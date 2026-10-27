use serde::{Deserialize, Serialize};

/// Account info response
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AccountInfo {
    pub logged_in: bool,
    pub email: Option<String>,
    pub auth_method: Option<String>,
    pub expiry: Option<String>,
}

/// Model info
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ModelInfo {
    pub id: String,
    pub name: String,
}

/// Messages sent from the iOS client to CodePill server
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", content = "payload")]
pub enum ClientMessage {
    /// Send a prompt or instruction to Antigravity
    #[serde(rename = "prompt")]
    Prompt {
        text: String,
        #[serde(default)]
        workspace: Option<String>,
        #[serde(default)]
        conversation_id: Option<String>,
        #[serde(default)]
        model: Option<String>,
    },

    /// Approve or reject a pending tool action / edit
    #[serde(rename = "action_response")]
    ActionResponse {
        action_id: String,
        approved: bool,
    },

    /// Cancel the current ongoing turn
    #[serde(rename = "cancel")]
    Cancel,

    /// Register APNs Live Activity push token for Dynamic Island
    #[serde(rename = "register_live_activity")]
    RegisterLiveActivity {
        activity_id: String,
        push_token: String,
    },
}

/// Dynamic Island State for ActivityKit
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DynamicIslandState {
    pub status: String,          // e.g. "Thinking", "Writing code", "Running tests", "Waiting"
    pub current_file: Option<String>,
    pub step_description: String,
    pub is_busy: bool,
    pub needs_approval: bool,
}

/// Messages sent from CodePill server to the iOS client
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", content = "payload")]
pub enum ServerMessage {
    #[serde(rename = "session_started")]
    SessionStarted {
        session_id: String,
        conversation_id: Option<String>,
        workspace: String,
    },

    #[serde(rename = "token_chunk")]
    TokenChunk {
        text: String,
    },

    #[serde(rename = "thought_chunk")]
    ThoughtChunk {
        text: String,
    },

    #[serde(rename = "tool_start")]
    ToolStart {
        call_id: String,
        tool_name: String,
        summary: String,
    },

    #[serde(rename = "tool_end")]
    ToolEnd {
        call_id: String,
        success: bool,
        output_preview: String,
    },

    #[serde(rename = "island_update")]
    IslandUpdate(DynamicIslandState),

    #[serde(rename = "approval_request")]
    ApprovalRequest {
        action_id: String,
        tool_name: String,
        details: String,
        diff: Option<String>,
    },

    #[serde(rename = "turn_finished")]
    TurnFinished {
        success: bool,
        summary: Option<String>,
    },

    #[serde(rename = "error")]
    Error {
        message: String,
    },
}
