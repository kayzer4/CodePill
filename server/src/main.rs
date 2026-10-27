use axum::{routing::get, Json, Router};
use clap::Parser;
use std::net::SocketAddr;
use std::sync::Arc;
use tower_http::cors::{Any, CorsLayer};
use tower_http::trace::TraceLayer;
use tracing::info;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

mod protocol;
mod session;
mod ws;

use session::SessionManager;
use ws::{ws_handler, AppState};

#[derive(Parser, Debug)]
#[command(name = "codepill-server")]
#[command(about = "CodePill backend server for Antigravity CLI and iOS Dynamic Island", long_about = None)]
struct Args {
    /// Host to bind on
    #[arg(short, long, default_value = "0.0.0.0")]
    bind: String,

    /// Port to listen on
    #[arg(short, long, default_value_t = 8080)]
    port: u16,

    /// Path to agy binary
    #[arg(long, default_value = "agy")]
    agy_bin: String,

    /// Default workspace directory
    #[arg(short, long, default_value = ".")]
    workspace: String,
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // Initialize logging
    tracing_subscriber::registry()
        .with(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "codepill_server=debug,tower_http=debug".into()),
        )
        .with(tracing_subscriber::fmt::layer())
        .init();

    let args = Args::parse();

    // Canonicalize workspace directory
    let workspace_path = std::fs::canonicalize(&args.workspace)
        .unwrap_or_else(|_| std::path::PathBuf::from(&args.workspace));
    let workspace_str = workspace_path.to_string_lossy().to_string();

    info!("🚀 CodePill Server starting...");
    info!("📁 Default Workspace: {}", workspace_str);
    info!("⚡ Antigravity CLI binary: {}", args.agy_bin);

    let session_mgr = Arc::new(SessionManager::new(args.agy_bin, workspace_str.clone()));
    let state = AppState { session_mgr };

    // Set up CORS
    let cors = CorsLayer::new()
        .allow_origin(Any)
        .allow_methods(Any)
        .allow_headers(Any);

    // Build routes
    let app = Router::new()
        .route("/health", get(health_check))
        .route("/ws", get(ws_handler))
        .layer(cors)
        .layer(TraceLayer::new_for_http())
        .with_state(state);

    let addr: SocketAddr = format!("{}:{}", args.bind, args.port).parse()?;
    info!("👂 Listening on http://{}", addr);
    info!("🔌 WebSocket endpoint: ws://{}/ws", addr);

    let listener = tokio::net::TcpListener::bind(addr).await?;
    axum::serve(listener, app).await?;

    Ok(())
}

async fn health_check() -> Json<serde_json::Value> {
    Json(serde_json::json!({
        "status": "ok",
        "service": "codepill-server",
        "version": env!("CARGO_PKG_VERSION")
    }))
}
