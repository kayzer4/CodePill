use axum::{
    extract::Query,
    http::{header, StatusCode},
    response::Response,
    routing::{get, post},
    Extension, Json, Router,
};
use base64::prelude::*;
use clap::Parser;
use std::net::SocketAddr;
use std::sync::Arc;
use tower_http::cors::{Any, CorsLayer};
use tower_http::trace::TraceLayer;
use tracing::info;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

mod account;
mod protocol;
mod proxy;
mod session;
mod ws;

use account::AccountManager;
use protocol::{AccountInfo, ConversationSummary};
use proxy::{ProxyConfig, ProxyManager};
use session::SessionManager;
use ws::{ws_handler, AppState};

#[derive(Parser, Debug)]
#[command(name = "codepill-server")]
#[command(about = "CodePill backend server for Antigravity CLI and iOS Dynamic Island", long_about = None)]
struct Args {
    /// Host to bind on
    #[arg(short, long, default_value = "0.0.0.0")]
    bind: String,

    /// Port to listen on (inconspicuous default 44321)
    #[arg(short, long, default_value_t = 44321)]
    port: u16,

    /// Path to agy binary
    #[arg(long, default_value = "agy")]
    agy_bin: String,

    /// Default workspace directory
    #[arg(short, long, default_value = ".")]
    workspace: String,

    /// Initial Proxy URL (optional, e.g. socks5://host:port or http://host:port)
    #[arg(long)]
    proxy: Option<String>,
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

    let proxy_mgr = Arc::new(ProxyManager::new());
    if let Some(initial_proxy) = args.proxy {
        let _ = proxy_mgr.set_proxy(initial_proxy, true).await;
    }

    if let Some(active) = proxy_mgr.get_active_proxy_url().await {
        info!("🛡️ Active Proxy: {}", active);
    } else {
        info!("🌐 Running directly without proxy");
    }

    let session_mgr = Arc::new(SessionManager::new(
        args.agy_bin.clone(),
        workspace_str.clone(),
        Arc::clone(&proxy_mgr),
    ));
    let account_mgr = Arc::new(AccountManager::new(
        args.agy_bin.clone(),
        Arc::clone(&proxy_mgr),
    ));

    let app_state = AppState {
        session_mgr: Arc::clone(&session_mgr),
    };

    let cors = CorsLayer::new()
        .allow_origin(Any)
        .allow_methods(Any)
        .allow_headers(Any);

    let app = Router::new()
        .route("/health", get(health_check))
        .route("/ws", get(ws_handler))
        .route("/api/conversations", get(get_conversations))
        .route("/api/file", get(get_file_info))
        .route("/api/file/raw", get(get_file_raw))
        .route("/api/proxy", get(get_proxy).post(set_proxy))
        .route("/api/proxy/test", post(test_proxy))
        .route("/api/account", get(get_account))
        .route("/api/account/logout", post(logout_account))
        .route("/api/account/restore", post(restore_account))
        .route("/api/account/usage", get(get_usage))
        .route("/api/account/credits", get(get_credits))
        .route("/api/models", get(get_models))
        .layer(cors)
        .layer(TraceLayer::new_for_http())
        .layer(Extension(account_mgr))
        .layer(Extension(session_mgr))
        .layer(Extension(proxy_mgr))
        .with_state(app_state);

    let addr: SocketAddr = format!("{}:{}", args.bind, args.port).parse()?;
    info!("👂 Listening on http://{}", addr);
    info!("🔌 WebSocket endpoint: ws://{}/ws", addr);

    let listener = tokio::net::TcpListener::bind(addr).await?;
    axum::serve(listener, app.into_make_service_with_connect_info::<SocketAddr>()).await?;

    Ok(())
}

async fn health_check() -> Json<serde_json::Value> {
    Json(serde_json::json!({
        "status": "ok",
        "service": "codepill-server",
        "version": env!("CARGO_PKG_VERSION")
    }))
}

async fn get_conversations(
    Extension(session_mgr): Extension<Arc<SessionManager>>,
) -> Json<Vec<ConversationSummary>> {
    Json(session_mgr.list_conversations().await)
}

async fn get_proxy(
    Extension(proxy_mgr): Extension<Arc<ProxyManager>>,
) -> Json<ProxyConfig> {
    Json(proxy_mgr.get_config().await)
}

#[derive(serde::Deserialize)]
struct SetProxyRequest {
    url: String,
    enabled: bool,
}

async fn set_proxy(
    Extension(proxy_mgr): Extension<Arc<ProxyManager>>,
    Json(payload): Json<SetProxyRequest>,
) -> Json<serde_json::Value> {
    match proxy_mgr.set_proxy(payload.url, payload.enabled).await {
        Ok(cfg) => Json(serde_json::json!({ "success": true, "config": cfg })),
        Err(e) => Json(serde_json::json!({ "success": false, "error": e.to_string() })),
    }
}

#[derive(serde::Deserialize)]
struct TestProxyRequest {
    url: Option<String>,
}

async fn test_proxy(
    Extension(proxy_mgr): Extension<Arc<ProxyManager>>,
    Json(payload): Json<TestProxyRequest>,
) -> Json<serde_json::Value> {
    match proxy_mgr.test_proxy(payload.url).await {
        Ok(ok) => Json(serde_json::json!({ "success": ok, "reachable": ok })),
        Err(e) => Json(serde_json::json!({ "success": false, "error": e.to_string() })),
    }
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

#[derive(serde::Deserialize)]
struct FileQuery {
    path: String,
}

#[derive(serde::Serialize)]
struct FileInfoResponse {
    success: bool,
    path: String,
    filename: String,
    size: u64,
    is_binary: bool,
    content: Option<String>,
    error: Option<String>,
}

async fn get_file_info(
    Extension(session_mgr): Extension<Arc<SessionManager>>,
    Query(query): Query<FileQuery>,
) -> Json<FileInfoResponse> {
    let clean_path = query
        .path
        .trim_start_matches("file://")
        .split('#')
        .next()
        .unwrap_or(&query.path);

    let target_path = if std::path::Path::new(clean_path).is_absolute() {
        std::path::PathBuf::from(clean_path)
    } else {
        std::path::Path::new(session_mgr.workspace()).join(clean_path)
    };

    if !target_path.exists() {
        return Json(FileInfoResponse {
            success: false,
            path: clean_path.to_string(),
            filename: "".to_string(),
            size: 0,
            is_binary: false,
            content: None,
            error: Some(format!("File not found: {}", clean_path)),
        });
    }

    let filename = target_path
        .file_name()
        .map(|n| n.to_string_lossy().to_string())
        .unwrap_or_else(|| "file".to_string());

    match tokio::fs::read(&target_path).await {
        Ok(bytes) => {
            let size = bytes.len() as u64;
            match String::from_utf8(bytes.clone()) {
                Ok(text) => Json(FileInfoResponse {
                    success: true,
                    path: target_path.to_string_lossy().to_string(),
                    filename,
                    size,
                    is_binary: false,
                    content: Some(text),
                    error: None,
                }),
                Err(_) => Json(FileInfoResponse {
                    success: true,
                    path: target_path.to_string_lossy().to_string(),
                    filename,
                    size,
                    is_binary: true,
                    content: Some(BASE64_STANDARD.encode(&bytes)),
                    error: None,
                }),
            }
        }
        Err(e) => Json(FileInfoResponse {
            success: false,
            path: target_path.to_string_lossy().to_string(),
            filename,
            size: 0,
            is_binary: false,
            content: None,
            error: Some(e.to_string()),
        }),
    }
}

async fn get_file_raw(
    Extension(session_mgr): Extension<Arc<SessionManager>>,
    Query(query): Query<FileQuery>,
) -> Result<Response, (StatusCode, String)> {
    let clean_path = query
        .path
        .trim_start_matches("file://")
        .split('#')
        .next()
        .unwrap_or(&query.path);

    let target_path = if std::path::Path::new(clean_path).is_absolute() {
        std::path::PathBuf::from(clean_path)
    } else {
        std::path::Path::new(session_mgr.workspace()).join(clean_path)
    };

    if !target_path.exists() {
        return Err((
            StatusCode::NOT_FOUND,
            format!("File not found: {}", clean_path),
        ));
    }

    let bytes = tokio::fs::read(&target_path)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    let filename = target_path
        .file_name()
        .map(|n| n.to_string_lossy().to_string())
        .unwrap_or_else(|| "download".to_string());

    let ext = target_path
        .extension()
        .and_then(|s| s.to_str())
        .unwrap_or("")
        .to_lowercase();

    let content_type = match ext.as_str() {
        "swift" | "rs" | "py" | "js" | "ts" | "c" | "cpp" | "h" | "txt" | "md" | "toml"
        | "yaml" | "yml" | "json" | "sh" => "text/plain; charset=utf-8",
        "html" => "text/html; charset=utf-8",
        "png" => "image/png",
        "jpg" | "jpeg" => "image/jpeg",
        "gif" => "image/gif",
        "webp" => "image/webp",
        "pdf" => "application/pdf",
        _ => "application/octet-stream",
    };

    let response = Response::builder()
        .header(header::CONTENT_TYPE, content_type)
        .header(
            header::CONTENT_DISPOSITION,
            format!("inline; filename=\"{}\"", filename),
        )
        .body(axum::body::Body::from(bytes))
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    Ok(response)
}
