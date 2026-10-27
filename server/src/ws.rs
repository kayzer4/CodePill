use axum::{
    extract::{
        ws::{Message, WebSocket, WebSocketUpgrade},
        State,
    },
    response::IntoResponse,
};
use futures_util::{SinkExt, StreamExt};
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
    State(state): State<AppState>,
) -> impl IntoResponse {
    ws.on_upgrade(|socket| handle_socket(socket, state))
}

async fn handle_socket(socket: WebSocket, state: AppState) {
    let (mut ws_sender, mut ws_receiver) = socket.split();
    let (out_tx, mut out_rx) = mpsc::channel::<ServerMessage>(100);

    info!("New iOS client connected via WebSocket");

    // Task forwarding server messages to WebSocket client
    let send_task = tokio::spawn(async move {
        while let Some(msg) = out_rx.recv().await {
            if let Ok(json) = serde_json::to_string(&msg) {
                if ws_sender.send(Message::Text(json.into())).await.is_err() {
                    break;
                }
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
                            workspace,
                            conversation_id,
                            ..
                        } => {
                            let mgr = Arc::clone(&state.session_mgr);
                            let tx = out_tx.clone();
                            tokio::spawn(async move {
                                if let Err(e) = mgr
                                    .start_turn(
                                        &text,
                                        conversation_id.as_deref(),
                                        workspace.as_deref(),
                                        tx.clone(),
                                    )
                                    .await
                                {
                                    error!("Turn error: {:?}", e);
                                    let _ = tx
                                        .send(ServerMessage::Error {
                                            message: e.to_string(),
                                        })
                                        .await;
                                }
                            });
                        }
                        ClientMessage::ActionResponse { action_id, approved } => {
                            info!("Action {} response: {}", action_id, approved);
                        }
                        ClientMessage::Cancel => {
                            info!("Cancel requested by client");
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
