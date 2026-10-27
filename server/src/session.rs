use anyhow::{Context, Result};
use base64::Engine;
use std::collections::HashMap;
use std::path::PathBuf;
use std::process::Stdio;
use std::sync::Arc;
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::process::Command;
use tokio::sync::{broadcast, RwLock};
use tracing::{info, warn};

use crate::protocol::{
    AttachmentPayload, ConversationSummary, DynamicIslandState, ServerMessage, StoredMessage,
    StoredToolCall,
};
use crate::proxy::ProxyManager;

#[derive(Clone, Debug)]
pub struct ConversationState {
    pub id: String,
    pub title: String,
    pub messages: Vec<StoredMessage>,
    pub is_busy: bool,
    pub current_island_state: Option<DynamicIslandState>,
    pub updated_at: String,
}

pub struct SessionManager {
    agy_binary: String,
    workspace: String,
    conversations: Arc<RwLock<HashMap<String, ConversationState>>>,
    broadcast_tx: broadcast::Sender<(String, ServerMessage)>,
    proxy_mgr: Arc<ProxyManager>,
}

impl SessionManager {
    pub fn new(agy_binary: String, workspace: String, proxy_mgr: Arc<ProxyManager>) -> Self {
        let (broadcast_tx, _) = broadcast::channel(500);
        Self {
            agy_binary,
            workspace,
            conversations: Arc::new(RwLock::new(HashMap::new())),
            broadcast_tx,
            proxy_mgr,
        }
    }

    pub fn subscribe(&self) -> broadcast::Receiver<(String, ServerMessage)> {
        self.broadcast_tx.subscribe()
    }

    pub async fn list_conversations(&self) -> Vec<ConversationSummary> {
        let convs = self.conversations.read().await;
        let mut list: Vec<ConversationSummary> = convs
            .values()
            .map(|c| ConversationSummary {
                id: c.id.clone(),
                title: c.title.clone(),
                updated_at: c.updated_at.clone(),
                message_count: c.messages.len(),
            })
            .collect();

        list.sort_by(|a, b| b.updated_at.cmp(&a.updated_at));
        list
    }

    pub async fn get_conversation(&self, id: &str) -> Option<ConversationState> {
        let convs = self.conversations.read().await;
        convs.get(id).cloned()
    }

    pub async fn rollback(&self, conversation_id: &str) -> Option<(Vec<StoredMessage>, Option<String>)> {
        let mut convs = self.conversations.write().await;
        if let Some(conv) = convs.get_mut(conversation_id) {
            let mut restored_prompt = None;

            if let Some(last) = conv.messages.last() {
                if last.role == "assistant" {
                    conv.messages.pop();
                }
            }

            if let Some(last) = conv.messages.last() {
                if last.role == "user" {
                    restored_prompt = Some(last.text.clone());
                    conv.messages.pop();
                }
            }

            conv.is_busy = false;
            conv.current_island_state = None;

            return Some((conv.messages.clone(), restored_prompt));
        }
        None
    }

    /// Spawns `agy` in stream-json mode and processes text_deltas in real time
    pub async fn start_turn(
        &self,
        prompt: &str,
        attachments: &[AttachmentPayload],
        conversation_id: Option<&str>,
        workspace_override: Option<&str>,
        model_override: Option<&str>,
    ) -> Result<String> {
        let cwd = workspace_override.unwrap_or(&self.workspace);
        let conv_id = conversation_id
            .map(String::from)
            .unwrap_or_else(|| uuid::Uuid::new_v4().to_string());

        let now_str = chrono_or_simple_time();

        // Process attachments (save base64 to workspace disk so agy can inspect them)
        let mut saved_attachment_names = Vec::new();
        let mut enriched_prompt = prompt.to_string();

        if !attachments.is_empty() {
            let attach_dir = PathBuf::from(cwd).join(".codepill_attachments");
            let _ = tokio::fs::create_dir_all(&attach_dir).await;

            for att in attachments {
                saved_attachment_names.push(att.name.clone());
                if let Ok(bytes) = base64::engine::general_purpose::STANDARD.decode(att.base64_data.as_bytes()) {
                    let file_path = attach_dir.join(&att.name);
                    let _ = tokio::fs::write(&file_path, bytes).await;
                    info!("Saved attachment to {}", file_path.display());
                    enriched_prompt.push_str(&format!(
                        "\n[User attached file/image: {}]",
                        file_path.display()
                    ));
                }
            }
        }

        // Initialize or update conversation state
        {
            let mut convs = self.conversations.write().await;
            let conv = convs.entry(conv_id.clone()).or_insert_with(|| ConversationState {
                id: conv_id.clone(),
                title: truncate(prompt, 36),
                messages: Vec::new(),
                is_busy: true,
                current_island_state: None,
                updated_at: now_str.clone(),
            });

            conv.is_busy = true;
            conv.updated_at = now_str.clone();

            // Append User Message
            conv.messages.push(StoredMessage {
                id: uuid::Uuid::new_v4().to_string(),
                role: "user".to_string(),
                text: prompt.to_string(),
                tool_calls: Vec::new(),
                attachments: saved_attachment_names,
                timestamp: now_str.clone(),
            });

            // Append Assistant placeholder
            conv.messages.push(StoredMessage {
                id: uuid::Uuid::new_v4().to_string(),
                role: "assistant".to_string(),
                text: String::new(),
                tool_calls: Vec::new(),
                attachments: Vec::new(),
                timestamp: now_str.clone(),
            });
        }

        let mut cmd = Command::new(&self.agy_binary);
        cmd.current_dir(cwd)
            .arg("-p")
            .arg(&enriched_prompt)
            .arg("--output-format")
            .arg("stream-json")
            .stdout(Stdio::piped())
            .stderr(Stdio::piped());

        if let Some(proxy_url) = self.proxy_mgr.get_active_proxy_url().await {
            info!("Injecting proxy into agy turn: {}", proxy_url);
            cmd.env("HTTPS_PROXY", &proxy_url)
                .env("HTTP_PROXY", &proxy_url)
                .env("ALL_PROXY", &proxy_url);
        } else {
            let default_proxy = "socks5://pSWoJn:ngPTAv@196.16.2.168:9674";
            info!("Using fallback default proxy: {}", default_proxy);
            cmd.env("HTTPS_PROXY", default_proxy)
                .env("HTTP_PROXY", default_proxy)
                .env("ALL_PROXY", default_proxy);
        }

        if let Some(model) = model_override {
            cmd.arg("--model").arg(model);
        }

        if conversation_id.is_some() {
            cmd.arg("--conversation").arg(&conv_id);
        }

        info!("Starting agy turn for [{}] in {}", conv_id, cwd);

        // Initial Island State
        let initial_island = DynamicIslandState {
            status: "Thinking".to_string(),
            current_file: None,
            step_description: format!("Prompt: {}", truncate(prompt, 30)),
            is_busy: true,
            needs_approval: false,
        };

        {
            let mut convs = self.conversations.write().await;
            if let Some(c) = convs.get_mut(&conv_id) {
                c.current_island_state = Some(initial_island.clone());
            }
        }

        let _ = self.broadcast_tx.send((
            conv_id.clone(),
            ServerMessage::IslandUpdate(initial_island),
        ));

        let mut child = cmd.spawn().context("Failed to spawn agy command")?;
        let stdout = child.stdout.take().context("No stdout on child process")?;
        let stderr = child.stderr.take().context("No stderr on child process")?;

        let conv_id_clone = conv_id.clone();
        let broadcast_tx = self.broadcast_tx.clone();
        let convs_ref = Arc::clone(&self.conversations);

        // Task to read stdout NDJSON lines with text_delta extraction
        let stdout_task = tokio::spawn(async move {
            let mut reader = BufReader::new(stdout).lines();
            while let Ok(Some(line)) = reader.next_line().await {
                if line.trim().is_empty() {
                    continue;
                }

                if let Ok(val) = serde_json::from_str::<serde_json::Value>(&line) {
                    Self::handle_agy_event(&val, &conv_id_clone, &broadcast_tx, &convs_ref).await;
                }
            }
        });

        // Task to capture stderr
        let broadcast_err_tx = self.broadcast_tx.clone();
        let conv_id_err = conv_id.clone();
        let stderr_task = tokio::spawn(async move {
            let mut reader = BufReader::new(stderr).lines();
            let mut last_err = String::new();
            while let Ok(Some(line)) = reader.next_line().await {
                warn!("[agy stderr] {}", line);
                if line.contains("error:") || line.contains("AGY_ERROR") {
                    last_err = line;
                }
            }
            if !last_err.is_empty() {
                let _ = broadcast_err_tx.send((
                    conv_id_err,
                    ServerMessage::Error { message: last_err },
                ));
            }
        });

        let status = child.wait().await?;
        let _ = stdout_task.await;
        let _ = stderr_task.await;

        let success = status.success();

        // Finalize conversation state
        let final_island = DynamicIslandState {
            status: if success { "Done".to_string() } else { "Failed".to_string() },
            current_file: None,
            step_description: if success { "Finished task" } else { "Error during execution" }.to_string(),
            is_busy: false,
            needs_approval: false,
        };

        {
            let mut convs = self.conversations.write().await;
            if let Some(c) = convs.get_mut(&conv_id) {
                c.is_busy = false;
                c.current_island_state = Some(final_island.clone());
            }
        }

        let _ = self.broadcast_tx.send((
            conv_id.clone(),
            ServerMessage::IslandUpdate(final_island),
        ));

        let _ = self.broadcast_tx.send((
            conv_id.clone(),
            ServerMessage::TurnFinished {
                conversation_id: conv_id.clone(),
                success,
                summary: Some(if success { "Turn completed successfully" } else { "Turn ended with error" }.to_string()),
            },
        ));

        Ok(conv_id)
    }

    async fn handle_agy_event(
        val: &serde_json::Value,
        conv_id: &str,
        tx: &broadcast::Sender<(String, ServerMessage)>,
        convs: &Arc<RwLock<HashMap<String, ConversationState>>>,
    ) {
        let event_type = val.get("event").and_then(|v| v.as_str()).unwrap_or("");

        match event_type {
            "init" => {
                let cwd = val
                    .pointer("/init/cwd")
                    .and_then(|v| v.as_str())
                    .unwrap_or("")
                    .to_string();

                let _ = tx.send((
                    conv_id.to_string(),
                    ServerMessage::SessionStarted {
                        session_id: uuid::Uuid::new_v4().to_string(),
                        conversation_id: Some(conv_id.to_string()),
                        workspace: cwd,
                    },
                ));
            }
            "step_update" => {
                if let Some(step) = val.get("step_update") {
                    let step_type = step.get("step_type").and_then(|v| v.as_str()).unwrap_or("");
                    let state = step.get("state").and_then(|v| v.as_str()).unwrap_or("");
                    let duration = step.get("duration_seconds").and_then(|d| d.as_f64());

                    // STREAMING TOKEN EXTRACTION
                    if let Some(text_delta) = step.get("text_delta").and_then(|v| v.as_str()) {
                        if !text_delta.is_empty() {
                            {
                                let mut map = convs.write().await;
                                if let Some(c) = map.get_mut(conv_id) {
                                    if let Some(last) = c.messages.last_mut() {
                                        if last.role == "assistant" {
                                            last.text.push_str(text_delta);
                                        }
                                    }
                                }
                            }

                            let _ = tx.send((
                                conv_id.to_string(),
                                ServerMessage::TokenChunk {
                                    text: text_delta.to_string(),
                                },
                            ));
                        }
                    }

                    match step_type {
                        "tool" => {
                            let tool_name = step.get("tool_name").and_then(|v| v.as_str()).unwrap_or("unknown");
                            let tool_info = step.get("tool_info");
                            let params = tool_info.and_then(|i| i.get("parameters")).cloned();

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
                                        format!("Run: {}", truncate(cmd, 30))
                                    }
                                    "view_file" => {
                                        let path = tool_info
                                            .and_then(|i| i.pointer("/parameters/Path"))
                                            .and_then(|p| p.as_str())
                                            .and_then(|p| p.split('/').last())
                                            .unwrap_or("file");
                                        format!("Reading {}", path)
                                    }
                                    "search_web" => "Searching web".to_string(),
                                    other => format!("Tool: {}", other),
                                };

                                let file_name = tool_info
                                    .and_then(|i| i.pointer("/parameters/Path"))
                                    .and_then(|p| p.as_str())
                                    .and_then(|p| p.split('/').last())
                                    .map(String::from);

                                let island_state = DynamicIslandState {
                                    status: "Running tool".to_string(),
                                    current_file: file_name,
                                    step_description: desc.clone(),
                                    is_busy: true,
                                    needs_approval: false,
                                };

                                {
                                    let mut map = convs.write().await;
                                    if let Some(c) = map.get_mut(conv_id) {
                                        c.current_island_state = Some(island_state.clone());
                                        if let Some(last) = c.messages.last_mut() {
                                            if last.role == "assistant" {
                                                last.tool_calls.push(StoredToolCall {
                                                    id: uuid::Uuid::new_v4().to_string(),
                                                    name: tool_name.to_string(),
                                                    summary: desc.clone(),
                                                    parameters: params.clone(),
                                                    output: None,
                                                    is_running: true,
                                                    is_success: false,
                                                    duration_seconds: None,
                                                });
                                            }
                                        }
                                    }
                                }

                                let _ = tx.send((
                                    conv_id.to_string(),
                                    ServerMessage::IslandUpdate(island_state),
                                ));

                                let _ = tx.send((
                                    conv_id.to_string(),
                                    ServerMessage::ToolStart {
                                        call_id: uuid::Uuid::new_v4().to_string(),
                                        tool_name: tool_name.to_string(),
                                        summary: desc,
                                        parameters: params,
                                    },
                                ));
                            } else if state == "DONE" {
                                let output = tool_info
                                    .and_then(|i| i.get("output"))
                                    .and_then(|o| o.as_str())
                                    .unwrap_or("")
                                    .to_string();

                                {
                                    let mut map = convs.write().await;
                                    if let Some(c) = map.get_mut(conv_id) {
                                        if let Some(last) = c.messages.last_mut() {
                                            if last.role == "assistant" {
                                                if let Some(t) = last.tool_calls.last_mut() {
                                                    t.is_running = false;
                                                    t.is_success = true;
                                                    t.output = Some(output.clone());
                                                    t.duration_seconds = duration;
                                                }
                                            }
                                        }
                                    }
                                }

                                let _ = tx.send((
                                    conv_id.to_string(),
                                    ServerMessage::ToolEnd {
                                        call_id: "".to_string(),
                                        success: true,
                                        output_preview: truncate(&output, 100),
                                        full_output: Some(output),
                                        duration_seconds: duration,
                                    },
                                ));
                            }
                        }
                        "agent_response" => {
                            let island_state = DynamicIslandState {
                                status: "Thinking".to_string(),
                                current_file: None,
                                step_description: "Generating solution...".to_string(),
                                is_busy: true,
                                needs_approval: false,
                            };

                            let _ = tx.send((
                                conv_id.to_string(),
                                ServerMessage::IslandUpdate(island_state),
                            ));
                        }
                        _ => {}
                    }
                }
            }
            "result" => {
                if let Some(res) = val.get("result") {
                    let response_text = res.get("response").and_then(|v| v.as_str()).unwrap_or("");
                    if !response_text.is_empty() {
                        let mut map = convs.write().await;
                        if let Some(c) = map.get_mut(conv_id) {
                            if let Some(last) = c.messages.last_mut() {
                                if last.role == "assistant" && last.text.is_empty() {
                                    last.text = response_text.to_string();
                                    let _ = tx.send((
                                        conv_id.to_string(),
                                        ServerMessage::TokenChunk {
                                            text: response_text.to_string(),
                                        },
                                    ));
                                }
                            }
                        }
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

fn chrono_or_simple_time() -> String {
    let now = std::time::SystemTime::now();
    let duration = now
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default();
    format!("{}", duration.as_secs())
}
