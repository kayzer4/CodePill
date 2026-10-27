use anyhow::Result;
use std::path::PathBuf;
use std::sync::Arc;
use tokio::process::Command;
use tracing::info;

use crate::protocol::{AccountInfo, ModelInfo};
use crate::proxy::ProxyManager;

pub struct AccountManager {
    token_path: PathBuf,
    backup_path: PathBuf,
    agy_bin: String,
    proxy_mgr: Arc<ProxyManager>,
}

impl AccountManager {
    pub fn new(agy_bin: String, proxy_mgr: Arc<ProxyManager>) -> Self {
        let home = std::env::var("HOME").unwrap_or_else(|_| "/home/kayzer".into());
        let base = PathBuf::from(home).join(".gemini/antigravity-cli");
        let token_path = base.join("antigravity-oauth-token");
        let backup_path = base.join("antigravity-oauth-token.codepill.bak");

        Self {
            token_path,
            backup_path,
            agy_bin,
            proxy_mgr,
        }
    }

    pub fn get_account_info(&self) -> AccountInfo {
        if !self.token_path.exists() {
            return AccountInfo {
                logged_in: false,
                email: None,
                auth_method: None,
                expiry: None,
            };
        }

        match std::fs::read_to_string(&self.token_path) {
            Ok(content) => {
                if let Ok(val) = serde_json::from_str::<serde_json::Value>(&content) {
                    let email = val.get("id_token_email").and_then(|v| v.as_str()).map(String::from);
                    let auth_method = val.get("auth_method").and_then(|v| v.as_str()).map(String::from);
                    let expiry = val
                        .pointer("/token/expiry")
                        .and_then(|v| v.as_str())
                        .map(String::from);

                    AccountInfo {
                        logged_in: true,
                        email,
                        auth_method,
                        expiry,
                    }
                } else {
                    AccountInfo {
                        logged_in: false,
                        email: None,
                        auth_method: None,
                        expiry: None,
                    }
                }
            }
            Err(_) => AccountInfo {
                logged_in: false,
                email: None,
                auth_method: None,
                expiry: None,
            },
        }
    }

    pub fn logout(&self) -> Result<bool> {
        if self.token_path.exists() {
            // Backup token so we can easily restore or test login again
            std::fs::copy(&self.token_path, &self.backup_path)?;
            std::fs::remove_file(&self.token_path)?;
            info!("Account logged out (token safely backed up to .codepill.bak)");
            Ok(true)
        } else {
            Ok(false)
        }
    }

    pub fn login_restore(&self) -> Result<bool> {
        if self.backup_path.exists() {
            std::fs::copy(&self.backup_path, &self.token_path)?;
            info!("Account restored from backup token");
            Ok(true)
        } else {
            Ok(false)
        }
    }

    pub async fn get_usage(&self) -> Result<String> {
        let mut cmd = Command::new(&self.agy_bin);
        cmd.arg("-p")
            .arg("/usage")
            .arg("--output-format")
            .arg("text");

        if let Some(proxy) = self.proxy_mgr.get_active_proxy_url().await {
            cmd.env("HTTPS_PROXY", &proxy)
                .env("HTTP_PROXY", &proxy)
                .env("ALL_PROXY", &proxy);
        }

        let output = cmd.output().await?;
        let res = String::from_utf8_lossy(&output.stdout).to_string();
        Ok(res)
    }

    pub async fn get_credits(&self) -> Result<String> {
        let mut cmd = Command::new(&self.agy_bin);
        cmd.arg("-p")
            .arg("/credits")
            .arg("--output-format")
            .arg("text");

        if let Some(proxy) = self.proxy_mgr.get_active_proxy_url().await {
            cmd.env("HTTPS_PROXY", &proxy)
                .env("HTTP_PROXY", &proxy)
                .env("ALL_PROXY", &proxy);
        }

        let output = cmd.output().await?;
        let res = String::from_utf8_lossy(&output.stdout).to_string();
        Ok(res)
    }

    pub async fn get_models(&self) -> Result<Vec<ModelInfo>> {
        let mut cmd = Command::new(&self.agy_bin);
        cmd.arg("models");

        if let Some(proxy) = self.proxy_mgr.get_active_proxy_url().await {
            cmd.env("HTTPS_PROXY", &proxy)
                .env("HTTP_PROXY", &proxy)
                .env("ALL_PROXY", &proxy);
        }

        let output = cmd.output().await?;

        let text = String::from_utf8_lossy(&output.stdout);
        let mut models = Vec::new();

        for line in text.lines() {
            let line = line.trim();
            if line.is_empty() || line.starts_with('⠋') || line.starts_with('⠙') || line.contains("Fetching") {
                // Ignore spinner lines
                continue;
            }

            let parts: Vec<&str> = line.split_whitespace().collect();
            if !parts.is_empty() {
                let id = parts[0].to_string();
                let name = parts[1..].join(" ");
                models.push(ModelInfo { id, name });
            }
        }

        Ok(models)
    }
}
