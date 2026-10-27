use axum::{
    routing::{get, post},
    Extension, Json, Router,
};
use clap::Parser;
use std::net::SocketAddr;
use std::sync::Arc;
use tower_http::cors::{Any, CorsLayer};
use tower_http::trace::TraceLayer;
use tracing::info;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

mod account;
mod protocol;
mod session;
mod ws;

use account::AccountManager;
use protocol::AccountInfo;
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
    tracing_subscriber::registry()
        .with(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "codepill_server=debug,tower_http=debug".into()),
        )
        .with(tracing_subscriber::fmt::layer())
        .init();

    let args = Args::parse();

    let workspace_path = std::fs::canonicalize(&args.workspace)
        .unwrap_or_else(|_| std::path::PathBuf::from(&args.workspace));
    let workspace_str = workspace_path.to_string_lossy().to_string();

    info!("🚀 CodePill Server starting...");
    info!("📁 Default Workspace: {}", workspace_str);
    info!("⚡ Antigravity CLI binary: {}", args.agy_bin);

    let session_mgr = Arc::new(SessionManager::new(args.agy_bin.clone(), workspace_str.clone()));
    let account_mgr = Arc::new(AccountManager::new(args.agy_bin.clone()));

    let app_state = AppState { session_mgr };

    let cors = CorsLayer::new()
        .allow_origin(Any)
        .allow_methods(Any)
        .allow_headers(Any);

    let app = Router::new()
        .route("/health", get(health_check))
        .route("/ws", get(ws_handler))
        .route("/api/account", get(get_account))
        .route("/api/account/logout", post(logout_account))
        .route("/api/account/restore", post(restore_account))
        .route("/api/account/usage", get(get_usage))
        .route("/api/account/credits", get(get_credits))
        .route("/api/models", get(get_models))
        .layer(cors)
        .layer(TraceLayer::new_for_http())
        .layer(Extension(account_mgr))
        .with_state(app_state);

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

async fn get_account(
    Extension(account): Extension<Arc<AccountManager>>,
) -> Json<AccountInfo> {
    Json(account.get_account_info())
}

async fn logout_account(
    Extension(account): Extension<Arc<AccountManager>>,
) -> Json<serde_json::Value> {
    match account.logout() {
        Ok(success) => Json(serde_json::json!({ "success": success, "status": "logged_out" })),
        Err(e) => Json(serde_json::json!({ "success": false, "error": e.to_string() })),
    }
}

async fn restore_account(
    Extension(account): Extension<Arc<AccountManager>>,
) -> Json<serde_json::Value> {
    match account.login_restore() {
        Ok(success) => Json(serde_json::json!({ "success": success, "status": "restored" })),
        Err(e) => Json(serde_json::json!({ "success": false, "error": e.to_string() })),
    }
}

async fn get_usage(
    Extension(account): Extension<Arc<AccountManager>>,
) -> Json<serde_json::Value> {
    match account.get_usage().await {
        Ok(output) => Json(serde_json::json!({ "raw": output })),
        Err(e) => Json(serde_json::json!({ "error": e.to_string() })),
    }
}

async fn get_credits(
    Extension(account): Extension<Arc<AccountManager>>,
) -> Json<serde_json::Value> {
    match account.get_credits().await {
        Ok(output) => Json(serde_json::json!({ "raw": output })),
        Err(e) => Json(serde_json::json!({ "error": e.to_string() })),
    }
}

async fn get_models(
    Extension(account): Extension<Arc<AccountManager>>,
) -> Json<serde_json::Value> {
    match account.get_models().await {
        Ok(models) => Json(serde_json::json!({ "models": models })),
        Err(e) => Json(serde_json::json!({ "error": e.to_string() })),
    }
}
