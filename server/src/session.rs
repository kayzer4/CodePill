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

    pub fn workspace(&self) -> &str {
        &self.workspace
    }

    pub fn subscribe(&self) -> broadcast::Receiver<(String, ServerMessage)> {
        self.broadcast_tx.subscribe()
    }

    async fn fetch_antigravity_summaries() -> Vec<ConversationSummary> {
        let home = std::env::var("HOME").unwrap_or_else(|_| "/home/kayzer".to_string());
        let db_path = format!("{}/.gemini/antigravity-cli/conversation_summaries.db", home);
        if !std::path::Path::new(&db_path).exists() {
            return Vec::new();
        }

        let cmd = tokio::process::Command::new("sqlite3")
            .arg(&db_path)
            .arg("-json")
            .arg("SELECT conversation_id, title, step_count, last_modified_time FROM conversation_summaries ORDER BY last_modified_time DESC LIMIT 60;")
            .output()
            .await;

        if let Ok(out) = cmd {
            if out.status.success() {
                if let Ok(val) = serde_json::from_slice::<serde_json::Value>(&out.stdout) {
                    if let Some(arr) = val.as_array() {
                        return arr.iter().filter_map(|item| {
                            let id = item.get("conversation_id")?.as_str()?.to_string();
                            let title = item.get("title")?.as_str().unwrap_or("Session").to_string();
                            let steps = item.get("step_count")?.as_u64().unwrap_or(0) as usize;
                            let updated = item.get("last_modified_time")?.as_str().unwrap_or("").to_string();
                            Some(ConversationSummary {
                                id,
                                title: if title.is_empty() { "Session".to_string() } else { title },
                                updated_at: updated,
                                message_count: steps,
                            })
                        }).collect();
                    }
                }
            }
        }
        Vec::new()
    }

    async fn load_antigravity_transcript(conv_id: &str) -> Vec<StoredMessage> {
        let home = std::env::var("HOME").unwrap_or_else(|_| "/home/kayzer".to_string());
        let path = format!("{}/.gemini/antigravity-cli/brain/{}/.system_generated/logs/transcript.jsonl", home, conv_id);
        let full_path = format!("{}/.gemini/antigravity-cli/brain/{}/.system_generated/logs/transcript_full.jsonl", home, conv_id);

        let Ok(file) = tokio::fs::File::open(&path).await else {
            return Vec::new();
        };

        // Load full transcript lines indexed by step_index for truncation fallback
        let mut full_lines: std::collections::HashMap<u64, serde_json::Value> = std::collections::HashMap::new();
        if let Ok(full_file) = tokio::fs::File::open(&full_path).await {
            use tokio::io::AsyncBufReadExt;
            let mut full_reader = tokio::io::BufReader::new(full_file).lines();
            while let Ok(Some(line)) = full_reader.next_line().await {
                if let Ok(val) = serde_json::from_str::<serde_json::Value>(&line) {
                    if let Some(idx) = val.get("step_index").and_then(|v| v.as_u64()) {
                        full_lines.insert(idx, val);
                    }
                }
            }
        }

        use tokio::io::AsyncBufReadExt;
        let mut reader = tokio::io::BufReader::new(file).lines();
        let mut messages: Vec<StoredMessage> = Vec::new();
        let mut pending_tools: Vec<StoredToolCall> = Vec::new();

        while let Ok(Some(line)) = reader.next_line().await {
            if line.trim().is_empty() {
                continue;
            }

            let Ok(val) = serde_json::from_str::<serde_json::Value>(&line) else {
                continue;
            };

            let step_type = val.get("type").and_then(|v| v.as_str()).unwrap_or("");
            let created_at = val.get("created_at").and_then(|v| v.as_str()).unwrap_or("").to_string();

            match step_type {
                "USER_INPUT" => {
                    let raw_content = val.get("content").and_then(|v| v.as_str()).unwrap_or("");
                    let clean_text = if let Some(start) = raw_content.find("<USER_REQUEST>") {
                        let after_start = &raw_content[start + 14..];
                        if let Some(end) = after_start.find("</USER_REQUEST>") {
                            after_start[..end].trim().to_string()
                        } else {
                            raw_content.trim().to_string()
                        }
                    } else {
                        raw_content.trim().to_string()
                    };

                    if !clean_text.is_empty() {
                        messages.push(StoredMessage {
                            id: uuid::Uuid::new_v4().to_string(),
                            role: "user".to_string(),
                            text: clean_text,
                            tool_calls: Vec::new(),
                            attachments: Vec::new(),
                            timestamp: created_at,
                        });
                    }
                }
                "PLANNER_RESPONSE" => {
                    if let Some(tool_calls_arr) = val.get("tool_calls").and_then(|v| v.as_array()) {
                        for t in tool_calls_arr {
                            let name = t.get("name").and_then(|v| v.as_str()).unwrap_or("tool").to_string();
                            let args = t.get("args").cloned();
                            let summary = if let Some(ref a) = args {
                                if let Some(cmd) = a.get("CommandLine").and_then(|c| c.as_str()) {
                                    format!("Run: {}", truncate(cmd.trim_matches('"'), 30))
                                } else if let Some(p) = a.get("Path").and_then(|p| p.as_str()) {
                                    format!("File: {}", truncate(p.trim_matches('"'), 30))
                                } else {
                                    name.clone()
                                }
                            } else {
                                name.clone()
                            };

                            pending_tools.push(StoredToolCall {
                                id: uuid::Uuid::new_v4().to_string(),
                                name,
                                summary,
                                parameters: args,
                                output: None,
                                is_running: false,
                                is_success: true,
                                duration_seconds: None,
                            });
                        }
                    }

                    // Get content — fallback to transcript_full if truncated
                    let step_index = val.get("step_index").and_then(|v| v.as_u64());
                    let truncated = val.get("truncated_fields")
                        .and_then(|v| v.as_array())
                        .map(|arr| arr.iter().any(|f| f.as_str() == Some("content")))
                        .unwrap_or(false);

                    let content_opt = if truncated {
                        step_index
                            .and_then(|idx| full_lines.get(&idx))
                            .and_then(|fv| fv.get("content"))
                            .and_then(|v| v.as_str())
                            .map(|s| if s.len() > 50_000 { format!("{}… [truncated]", &s[..50_000]) } else { s.to_string() })
                    } else {
                        val.get("content").and_then(|v| v.as_str()).map(|s| s.to_string())
                    };

                    if let Some(content) = content_opt {
                        let tools = std::mem::take(&mut pending_tools);
                        messages.push(StoredMessage {
                            id: uuid::Uuid::new_v4().to_string(),
                            role: "assistant".to_string(),
                            text: content.to_string(),
                            tool_calls: tools,
                            attachments: Vec::new(),
                            timestamp: created_at,
                        });
                    }
                }
                "GENERIC" => {
                    // Get content — fallback to transcript_full if truncated
                    let step_index = val.get("step_index").and_then(|v| v.as_u64());
                    let truncated = val.get("truncated_fields")
                        .and_then(|v| v.as_array())
                        .map(|arr| arr.iter().any(|f| f.as_str() == Some("content")))
                        .unwrap_or(false);

                    let content_opt = if truncated {
                        step_index
                            .and_then(|idx| full_lines.get(&idx))
                            .and_then(|fv| fv.get("content"))
                            .and_then(|v| v.as_str())
                            .map(|s| if s.len() > 50_000 { format!("{}… [truncated]", &s[..50_000]) } else { s.to_string() })
                    } else {
                        val.get("content").and_then(|v| v.as_str()).map(|s| s.to_string())
                    };

                    if let Some(content) = content_opt {
                        if let Some(last_tool) = pending_tools.last_mut() {
                            let out = if content.len() > 20_000 {
                                format!("{}... [truncated for mobile]", &content[..20_000])
                            } else {
                                content.to_string()
                            };
                            last_tool.output = Some(out);
                        }
                    }
                }
                _ => {}
            }
        }

        if !pending_tools.is_empty() {
            let tools = std::mem::take(&mut pending_tools);
            messages.push(StoredMessage {
                id: uuid::Uuid::new_v4().to_string(),
                role: "assistant".to_string(),
                text: String::new(),
                tool_calls: tools,
                attachments: Vec::new(),
                timestamp: chrono_or_simple_time(),
            });
        }

        messages
    }

    pub async fn list_conversations(&self) -> Vec<ConversationSummary> {
        let mut map: HashMap<String, ConversationSummary> = HashMap::new();

        // 1. Sync directly from Antigravity CLI's SQLite database
        let historical = Self::fetch_antigravity_summaries().await;
        for h in historical {
            map.insert(h.id.clone(), h);
        }

        // 2. Overlay active in-memory conversations
        let convs = self.conversations.read().await;
        for c in convs.values() {
            map.insert(
                c.id.clone(),
                ConversationSummary {
                    id: c.id.clone(),
                    title: c.title.clone(),
                    updated_at: c.updated_at.clone(),
                    message_count: if c.messages.is_empty() {
                        map.get(&c.id).map(|existing| existing.message_count).unwrap_or(0)
                    } else {
                        c.messages.len()
                    },
                },
            );
        }

        let mut list: Vec<ConversationSummary> = map.into_values().collect();
        list.sort_by(|a, b| b.updated_at.cmp(&a.updated_at));
        list
    }

    pub async fn get_conversation(&self, id: &str) -> Option<ConversationState> {
        let msgs = Self::load_antigravity_transcript(id).await;

        let mut convs = self.conversations.write().await;
        if let Some(c) = convs.get_mut(id) {
            if !msgs.is_empty() && (!c.is_busy || c.messages.is_empty()) {
                c.messages = msgs;
            }
            return Some(c.clone());
        }

        if !msgs.is_empty() {
            let conv = convs.entry(id.to_string()).or_insert_with(|| ConversationState {
                id: id.to_string(),
                title: msgs.first().map(|m| truncate(&m.text, 30)).unwrap_or_else(|| "Session".to_string()),
                messages: msgs.clone(),
                updated_at: chrono_or_simple_time(),
                is_busy: false,
                current_island_state: None,
            });
            conv.messages = msgs;
            return Some(conv.clone());
        }

        convs.get(id).cloned()
    }

    pub async fn delete_conversation(&self, id: &str) {
        {
            let mut convs = self.conversations.write().await;
            convs.remove(id);
        }

        let home = std::env::var("HOME").unwrap_or_else(|_| "/home/kayzer".to_string());
        let db_path = format!("{}/.gemini/antigravity-cli/conversation_summaries.db", home);
        if std::path::Path::new(&db_path).exists() {
            let sql = format!("DELETE FROM conversation_summaries WHERE conversation_id = '{}';", id.replace('\'', ""));
            let _ = tokio::process::Command::new("sqlite3")
                .arg(&db_path)
                .arg(&sql)
                .output()
                .await;
        }

        let brain_path = format!("{}/.gemini/antigravity-cli/brain/{}", home, id);
        let _ = tokio::fs::remove_dir_all(&brain_path).await;
    }

    pub async fn rename_conversation(&self, id: &str, new_title: &str) {
        let home = std::env::var("HOME").unwrap_or_else(|_| "/home/kayzer".to_string());
        let db_path = format!("{}/.gemini/antigravity-cli/conversation_summaries.db", home);
        if std::path::Path::new(&db_path).exists() {
            let escaped_title = new_title.replace('\'', "''");
            let escaped_id = id.replace('\'', "");
            let sql = format!("UPDATE conversation_summaries SET title = '{}' WHERE conversation_id = '{}';", escaped_title, escaped_id);
            let _ = tokio::process::Command::new("sqlite3")
                .arg(&db_path)
                .arg(&sql)
                .output()
                .await;
        }
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
            .arg("--dangerously-skip-permissions")
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

        // Reload full transcript from brain on disk to ensure 100% sync
        let disk_messages = Self::load_antigravity_transcript(&conv_id).await;

        {
            let mut convs = self.conversations.write().await;
            if let Some(c) = convs.get_mut(&conv_id) {
                c.is_busy = false;
                c.current_island_state = Some(final_island.clone());
                if !disk_messages.is_empty() {
                    c.messages = disk_messages;
                }
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
                            let step_index = step.get("step_index").and_then(|i| i.as_u64()).unwrap_or(0);
                            let call_id = format!("{}-step-{}", conv_id, step_index);
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
                                        // Если последнее сообщение ассистента уже содержит текст,
                                        // создаем новое сообщение для следующей пачки инструментов!
                                        let needs_new_msg = match c.messages.last() {
                                            Some(m) => m.role != "assistant" || !m.text.trim().is_empty(),
                                            None => true,
                                        };
                                        if needs_new_msg {
                                            c.messages.push(StoredMessage {
                                                id: uuid::Uuid::new_v4().to_string(),
                                                role: "assistant".to_string(),
                                                text: String::new(),
                                                tool_calls: Vec::new(),
                                                attachments: Vec::new(),
                                                timestamp: chrono_or_simple_time(),
                                            });
                                        }
                                        if let Some(last) = c.messages.last_mut() {
                                            last.tool_calls.push(StoredToolCall {
                                                id: call_id.clone(),
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

                                let _ = tx.send((
                                    conv_id.to_string(),
                                    ServerMessage::IslandUpdate(island_state),
                                ));

                                let _ = tx.send((
                                    conv_id.to_string(),
                                    ServerMessage::ToolStart {
                                        call_id: call_id.clone(),
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
                                                let target_idx = last.tool_calls.iter().rposition(|t| t.id == call_id)
                                                    .unwrap_or_else(|| last.tool_calls.len().saturating_sub(1));
                                                if let Some(t) = last.tool_calls.get_mut(target_idx) {
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
                                        call_id: call_id.clone(),
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
                            // Проверяем: если последнее сообщение уже имеет другой текст (например промежуточный ответ),
                            // создаем для финального результата отдельное сообщение!
                            let needs_new_msg = match c.messages.last() {
                                Some(m) => m.role != "assistant" || !m.text.is_empty(),
                                None => true,
                            };
                            if needs_new_msg {
                                c.messages.push(StoredMessage {
                                    id: uuid::Uuid::new_v4().to_string(),
                                    role: "assistant".to_string(),
                                    text: response_text.to_string(),
                                    tool_calls: Vec::new(),
                                    attachments: Vec::new(),
                                    timestamp: chrono_or_simple_time(),
                                });
                            } else if let Some(last) = c.messages.last_mut() {
                                last.text = response_text.to_string();
                            }
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
