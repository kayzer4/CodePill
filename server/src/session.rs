use anyhow::{Context, Result};
use std::process::Stdio;
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::process::Command;
use tokio::sync::mpsc;
use tracing::{info, warn};

use crate::protocol::{DynamicIslandState, ServerMessage};

pub struct SessionManager {
    agy_binary: String,
    workspace: String,
}

impl SessionManager {
    pub fn new(agy_binary: String, workspace: String) -> Self {
        Self {
            agy_binary,
            workspace,
        }
    }

    /// Spawns `agy` in stream-json mode and pipes output events into `out_tx`
    pub async fn start_turn(
        &self,
        prompt: &str,
        conversation_id: Option<&str>,
        workspace_override: Option<&str>,
        out_tx: mpsc::Sender<ServerMessage>,
    ) -> Result<()> {
        let cwd = workspace_override.unwrap_or(&self.workspace);

        let mut cmd = Command::new(&self.agy_binary);
        cmd.current_dir(cwd)
            .arg("-p")
            .arg(prompt)
            .arg("--output-format")
            .arg("stream-json")
            .stdout(Stdio::piped())
            .stderr(Stdio::piped());

        if let Some(conv_id) = conversation_id {
            cmd.arg("--conversation").arg(conv_id);
        }

        info!("Starting agy turn in {}", cwd);

        // Notify client of initial busy state
        let _ = out_tx
            .send(ServerMessage::IslandUpdate(DynamicIslandState {
                status: "Thinking".to_string(),
                current_file: None,
                step_description: format!("Prompt: {}", truncate(prompt, 30)),
                is_busy: true,
                needs_approval: false,
            }))
            .await;

        let mut child = cmd.spawn().context("Failed to spawn agy command")?;

        let stdout = child.stdout.take().context("No stdout on child process")?;
        let stderr = child.stderr.take().context("No stderr on child process")?;

        let out_tx_clone = out_tx.clone();

        // Task to read stdout NDJSON lines
        let stdout_task = tokio::spawn(async move {
            let mut reader = BufReader::new(stdout).lines();
            while let Ok(Some(line)) = reader.next_line().await {
                if line.trim().is_empty() {
                    continue;
                }

                if let Ok(val) = serde_json::from_str::<serde_json::Value>(&line) {
                    Self::handle_agy_event(&val, &out_tx_clone).await;
                }
            }
        });

        // Task to log stderr
        let stderr_task = tokio::spawn(async move {
            let mut reader = BufReader::new(stderr).lines();
            while let Ok(Some(line)) = reader.next_line().await {
                warn!("[agy stderr] {}", line);
            }
        });

        let status = child.wait().await?;
        let _ = stdout_task.await;
        let _ = stderr_task.await;

        let success = status.success();

        // Send final Dynamic Island update
        let _ = out_tx
            .send(ServerMessage::IslandUpdate(DynamicIslandState {
                status: if success { "Done".to_string() } else { "Failed".to_string() },
                current_file: None,
                step_description: if success { "Finished task" } else { "Command error" }.to_string(),
                is_busy: false,
                needs_approval: false,
            }))
            .await;

        let _ = out_tx
            .send(ServerMessage::TurnFinished {
                success,
                summary: Some(if success { "Turn completed successfully" } else { "Turn ended with error" }.to_string()),
            })
            .await;

        Ok(())
    }

    async fn handle_agy_event(val: &serde_json::Value, tx: &mpsc::Sender<ServerMessage>) {
        let event_type = val.get("event").and_then(|v| v.as_str()).unwrap_or("");

        match event_type {
            "init" => {
                let conv_id = val.get("conversation_id").and_then(|v| v.as_str()).map(String::from);
                let cwd = val
                    .pointer("/init/cwd")
                    .and_then(|v| v.as_str())
                    .unwrap_or("")
                    .to_string();

                let _ = tx
                    .send(ServerMessage::SessionStarted {
                        session_id: uuid::Uuid::new_v4().to_string(),
                        conversation_id: conv_id,
                        workspace: cwd,
                    })
                    .await;
            }
            "step_update" => {
                if let Some(step) = val.get("step_update") {
                    let step_type = step.get("step_type").and_then(|v| v.as_str()).unwrap_or("");
                    let state = step.get("state").and_then(|v| v.as_str()).unwrap_or("");

                    match step_type {
                        "tool" => {
                            let tool_name = step.get("tool_name").and_then(|v| v.as_str()).unwrap_or("unknown");
                            let tool_info = step.get("tool_info");

                            if state == "ACTIVE" {
                                let desc = match tool_name {
                                    "write_to_file" | "replace_file_content" => {
                                        let path = tool_info
                                            .and_then(|i| i.pointer("/parameters/Path"))
                                            .and_then(|p| p.as_str())
                                            .and_then(|p| p.split('/').last())
                                            .unwrap_or("file");
                                        format!("Editing {}", path)
                                    }
                                    "run_command" => {
                                        let cmd = tool_info
                                            .and_then(|i| i.pointer("/parameters/CommandLine"))
                                            .and_then(|c| c.as_str())
                                            .unwrap_or("bash");
                                        format!("Run: {}", truncate(cmd, 25))
                                    }
                                    "search_web" => "Searching web".to_string(),
                                    other => format!("Tool: {}", other),
                                };

                                let file_name = tool_info
                                    .and_then(|i| i.pointer("/parameters/Path"))
                                    .and_then(|p| p.as_str())
                                    .and_then(|p| p.split('/').last())
                                    .map(String::from);

                                // Update Dynamic Island
                                let _ = tx
                                    .send(ServerMessage::IslandUpdate(DynamicIslandState {
                                        status: "Running tool".to_string(),
                                        current_file: file_name,
                                        step_description: desc.clone(),
                                        is_busy: true,
                                        needs_approval: false,
                                    }))
                                    .await;

                                let _ = tx
                                    .send(ServerMessage::ToolStart {
                                        call_id: uuid::Uuid::new_v4().to_string(),
                                        tool_name: tool_name.to_string(),
                                        summary: desc,
                                    })
                                    .await;
                            } else if state == "DONE" {
                                let output = tool_info
                                    .and_then(|i| i.get("output"))
                                    .and_then(|o| o.as_str())
                                    .unwrap_or("")
                                    .to_string();

                                let _ = tx
                                    .send(ServerMessage::ToolEnd {
                                        call_id: "".to_string(),
                                        success: true,
                                        output_preview: truncate(&output, 100),
                                    })
                                    .await;
                            }
                        }
                        "agent_response" => {
                            let _ = tx
                                .send(ServerMessage::IslandUpdate(DynamicIslandState {
                                    status: "Thinking".to_string(),
                                    current_file: None,
                                    step_description: "Generating solution...".to_string(),
                                    is_busy: true,
                                    needs_approval: false,
                                }))
                                .await;
                        }
                        _ => {}
                    }
                }
            }
            "result" => {
                if let Some(res) = val.get("result") {
                    let response_text = res.get("response").and_then(|v| v.as_str()).unwrap_or("");
                    if !response_text.is_empty() {
                        let _ = tx
                            .send(ServerMessage::TokenChunk {
                                text: response_text.to_string(),
                            })
                            .await;
                    }
                }
            }
            _ => {}
        }
    }
}

fn truncate(s: &str, max_chars: usize) -> String {
    if s.chars().count() > max_chars {
        format!("{}…", s.chars().take(max_chars).collect::<String>())
    } else {
        s.to_string()
    }
}
