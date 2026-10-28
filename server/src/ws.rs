use axum::{
    extract::{
        ws::{Message, WebSocket, WebSocketUpgrade},
        ConnectInfo, State,
    },
    response::IntoResponse,
};
use futures_util::{SinkExt, StreamExt};
use std::net::SocketAddr;
use std::sync::Arc;
use tokio::sync::mpsc;
use tracing::{error, info, warn};

use crate::protocol::{ClientMessage, ServerMessage};
use crate::session::SessionManager;

#[derive(Clone)]
pub struct AppState {
    pub session_mgr: Arc<SessionManager>,
}

pub async fn ws_handler(
    ws: WebSocketUpgrade,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    State(state): State<AppState>,
) -> impl IntoResponse {
    ws.max_message_size(256 * 1024 * 1024)
        .max_frame_size(64 * 1024 * 1024)
        .on_upgrade(move |socket| handle_socket(socket, state, addr))
}

async fn handle_socket(socket: WebSocket, state: AppState, addr: SocketAddr) {
    let (mut ws_sender, mut ws_receiver) = socket.split();
    let (direct_tx, mut direct_rx) = mpsc::channel::<ServerMessage>(100);

    let mut broadcast_rx = state.session_mgr.subscribe();

    info!("New iOS client connected via WebSocket from {}", addr);

    let active_conv_id = Arc::new(tokio::sync::RwLock::new(None::<String>));
    let active_conv_id_send = Arc::clone(&active_conv_id);

    // Task forwarding server messages to WebSocket client
    let send_task = tokio::spawn(async move {
        let mut ping_interval = tokio::time::interval(std::time::Duration::from_secs(10));
        loop {
            tokio::select! {
                _ = ping_interval.tick() => {
                    if ws_sender.send(Message::Ping(vec![].into())).await.is_err() {
                        break;
                    }
                }
                // Direct responses to this specific client
                Some(msg) = direct_rx.recv() => {
                    if let Ok(json) = serde_json::to_string(&msg) {
                        if ws_sender.send(Message::Text(json.into())).await.is_err() {
                            break;
                        }
                    }
                }
                // Broadcast events from background agent turns (filtered by active conversation)
                Ok((conv_id, msg)) = broadcast_rx.recv() => {
                    let current = active_conv_id_send.read().await;
                    if let Some(ref current_id) = *current {
                        if !conv_id.is_empty() && conv_id != *current_id {
                            // Strictly do not forward events of other conversations!
                            continue;
                        }
                    }
                    if let Ok(json) = serde_json::to_string(&msg) {
                        if ws_sender.send(Message::Text(json.into())).await.is_err() {
                            break;
                        }
                    }
                }
                else => break,
            }
        }
    });

    // Handle incoming client messages
    while let Some(Ok(msg)) = ws_receiver.next().await {
        match msg {
            Message::Text(text) => {
                match serde_json::from_str::<ClientMessage>(&text) {
                    Ok(client_msg) => match client_msg {
                        ClientMessage::Prompt {
                            text,
                            attachments,
                            workspace,
                            conversation_id,
                            model,
                        } => {
                            if let Some(ref cid) = conversation_id {
                                *active_conv_id.write().await = Some(cid.clone());
                            }
                            let mgr = Arc::clone(&state.session_mgr);
                            let direct = direct_tx.clone();
                            tokio::spawn(async move {
                                if let Err(e) = mgr
                                    .start_turn(
                                        &text,
                                        &attachments,
                                        conversation_id.as_deref(),
                                        workspace.as_deref(),
                                        model.as_deref(),
                                    )
                                    .await
                                {
                                    error!("Turn error: {:?}", e);
                                    let _ = direct
                                        .send(ServerMessage::Error {
                                            message: e.to_string(),
                                        })
                                        .await;
                                }
                            });
                        }
                        ClientMessage::Sync { conversation_id } => {
                            if let Some(ref cid) = conversation_id {
                                *active_conv_id.write().await = Some(cid.clone());
                            }
                            let target_id = if let Some(ref id) = conversation_id {
                                Some(id.clone())
                            } else {
                                let list = state.session_mgr.list_conversations().await;
                                list.first().map(|c| c.id.clone())
                            };

                            if let Some(id) = target_id {
                                if let Some(conv) = state.session_mgr.get_conversation(&id).await {
                                    // For mobile clients, limit initial sync to recent messages for instant load
                                    let sync_messages = if conv.messages.len() > 120 {
                                        conv.messages[conv.messages.len() - 120..].to_vec()
                                    } else {
                                        conv.messages
                                    };
                                    let _ = direct_tx
                                        .send(ServerMessage::HistorySync {
                                            conversation_id: conv.id,
                                            messages: sync_messages,
                                            is_busy: conv.is_busy,
                                            island_state: conv.current_island_state,
                                        })
                                        .await;
                                } else {
                                    let _ = direct_tx
                                        .send(ServerMessage::HistorySync {
                                            conversation_id: id,
                                            messages: vec![],
                                            is_busy: false,
                                            island_state: None,
                                        })
                                        .await;
                                }
                            }
                        }
                        ClientMessage::Rollback { conversation_id } => {
                            *active_conv_id.write().await = Some(conversation_id.clone());
                            if let Some((msgs, prompt)) = state.session_mgr.rollback(&conversation_id).await {
                                let _ = direct_tx
                                    .send(ServerMessage::RollbackCompleted {
                                        conversation_id,
                                        messages: msgs,
                                        restored_prompt: prompt,
                                    })
                                    .await;
                            }
                        }
                        ClientMessage::ListConversations => {
                            let list = state.session_mgr.list_conversations().await;
                            let _ = direct_tx
                                .send(ServerMessage::ConversationsList {
                                    conversations: list,
                                })
                                .await;
                        }
                        ClientMessage::DeleteConversation { conversation_id } => {
                            info!("Deleting conversation: {}", conversation_id);
                            state.session_mgr.delete_conversation(&conversation_id).await;
                            let list = state.session_mgr.list_conversations().await;
                            let _ = direct_tx
                                .send(ServerMessage::ConversationsList {
                                    conversations: list,
                                })
                                .await;
                        }
                        ClientMessage::RenameConversation { conversation_id, new_title } => {
                            info!("Renaming conversation {} to {}", conversation_id, new_title);
                            state.session_mgr.rename_conversation(&conversation_id, &new_title).await;
                            let list = state.session_mgr.list_conversations().await;
                            let _ = direct_tx
                                .send(ServerMessage::ConversationsList {
                                    conversations: list,
                                })
                                .await;
                        }
                        ClientMessage::ActionResponse { action_id, approved } => {
                            info!("Action {} response: {}", action_id, approved);
                        }
                        ClientMessage::Cancel => {
                            info!("Cancel requested by client");
                            let cid_opt = active_conv_id.read().await.clone();
                            if let Some(ref cid) = cid_opt {
                                state.session_mgr.cancel_turn(cid).await;
                            }
                        }
                        ClientMessage::RegisterLiveActivity {
                            activity_id,
                            push_token,
                        } => {
                            info!(
                                "Registered ActivityKit token for {}: {}",
                                activity_id, push_token
                            );
                        }
                    },
                    Err(e) => {
                        warn!("Failed to parse client message: {:?}", e);
                    }
                }
            }
            Message::Close(_) => {
                info!("Client closed connection");
                break;
            }
            Message::Ping(_) | Message::Pong(_) => {}
            _ => {}
        }
    }

    send_task.abort();
    info!("iOS client disconnected");
}
