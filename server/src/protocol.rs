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

/// Conversation summary item for list
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConversationSummary {
    pub id: String,
    pub title: String,
    pub updated_at: String,
    pub message_count: usize,
}

/// Attachment info
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AttachmentPayload {
    pub name: String,
    pub mime_type: String,
    pub base64_data: String,
}

/// Stored chat message on the server
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StoredMessage {
    pub id: String,
    pub role: String,
    pub text: String,
    #[serde(default)]
    pub tool_calls: Vec<StoredToolCall>,
    #[serde(default)]
    pub attachments: Vec<String>, // names or paths of saved attachments
    pub timestamp: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StoredToolCall {
    pub id: String,
    pub name: String,
    pub summary: String,
    pub parameters: Option<serde_json::Value>,
    pub output: Option<String>,
    pub is_running: bool,
    pub is_success: bool,
    pub duration_seconds: Option<f64>,
}

/// Messages sent from the iOS client to CodePill server
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", content = "payload")]
pub enum ClientMessage {
    /// Send a prompt to Antigravity
    #[serde(rename = "prompt")]
    Prompt {
        text: String,
        #[serde(default)]
        attachments: Vec<AttachmentPayload>,
        #[serde(default)]
        workspace: Option<String>,
        #[serde(default)]
        conversation_id: Option<String>,
        #[serde(default)]
        model: Option<String>,
    },

    /// Request sync/restore of a conversation state upon reconnect
    #[serde(rename = "sync")]
    Sync {
        conversation_id: Option<String>,
    },

    /// Rollback the conversation to before the last turn (rewind)
    #[serde(rename = "rollback")]
    Rollback {
        conversation_id: String,
    },

    /// List all known conversations
    #[serde(rename = "list_conversations")]
    ListConversations,

    /// Approve or reject a pending tool action
    #[serde(rename = "action_response")]
    ActionResponse {
        action_id: String,
        approved: bool,
    },

    /// Cancel the current ongoing turn
    #[serde(rename = "cancel")]
    Cancel,

    /// Delete a conversation
    #[serde(rename = "delete_conversation")]
    DeleteConversation {
        conversation_id: String,
    },

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
    pub status: String,
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
        parameters: Option<serde_json::Value>,
    },

    #[serde(rename = "tool_end")]
    ToolEnd {
        call_id: String,
        success: bool,
        output_preview: String,
        full_output: Option<String>,
        duration_seconds: Option<f64>,
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
        conversation_id: String,
        success: bool,
        summary: Option<String>,
    },

    #[serde(rename = "history_sync")]
    HistorySync {
        conversation_id: String,
        messages: Vec<StoredMessage>,
        is_busy: bool,
        island_state: Option<DynamicIslandState>,
    },

    #[serde(rename = "conversations_list")]
    ConversationsList {
        conversations: Vec<ConversationSummary>,
    },

    #[serde(rename = "rollback_completed")]
    RollbackCompleted {
        conversation_id: String,
        messages: Vec<StoredMessage>,
        restored_prompt: Option<String>,
    },

    #[serde(rename = "error")]
    Error {
        message: String,
    },
}
