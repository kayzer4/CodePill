use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use std::sync::Arc;
use tokio::sync::RwLock;
use tracing::info;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProxyConfig {
    pub enabled: bool,
    pub current_url: String,
    pub proxy_type: String, // "socks5", "socks5h", "http", "https", "none"
    pub presets: Vec<ProxyPreset>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProxyPreset {
    pub name: String,
    pub url: String,
    pub proxy_type: String,
}

pub struct ProxyManager {
    config_path: PathBuf,
    state: Arc<RwLock<ProxyConfig>>,
}

impl ProxyManager {
    pub fn new() -> Self {
        let home = std::env::var("HOME").unwrap_or_else(|_| "/home/kayzer".into());
        let config_path = PathBuf::from(&home).join(".gemini/antigravity-cli/codepill_proxy.json");

        let default_socks = "socks5://pSWoJn:ngPTAv@196.16.2.168:9674".to_string();

        let initial_config = if config_path.exists() {
            if let Ok(content) = std::fs::read_to_string(&config_path) {
                serde_json::from_str::<ProxyConfig>(&content).unwrap_or_else(|_| {
                    Self::default_config(default_socks.clone())
                })
            } else {
                Self::default_config(default_socks.clone())
            }
        } else {
            Self::default_config(default_socks.clone())
        };

        Self {
            config_path,
            state: Arc::new(RwLock::new(initial_config)),
        }
    }

    fn default_config(default_url: String) -> ProxyConfig {
        ProxyConfig {
            enabled: true,
            current_url: default_url.clone(),
            proxy_type: Self::detect_type(&default_url),
            presets: vec![
                ProxyPreset {
                    name: "Default SOCKS5 Proxy".to_string(),
                    url: default_url,
                    proxy_type: "socks5".to_string(),
                },
                ProxyPreset {
                    name: "Local SOCKS5 (127.0.0.1:1080)".to_string(),
                    url: "socks5://127.0.0.1:1080".to_string(),
                    proxy_type: "socks5".to_string(),
                },
                ProxyPreset {
                    name: "Local HTTP Proxy (127.0.0.1:8080)".to_string(),
                    url: "http://127.0.0.1:8080".to_string(),
                    proxy_type: "http".to_string(),
                },
            ],
        }
    }

    pub fn detect_type(url: &str) -> String {
        let lower = url.to_lowercase();
        if lower.starts_with("socks5h://") {
            "socks5h".to_string()
        } else if lower.starts_with("socks5://") {
            "socks5".to_string()
        } else if lower.starts_with("https://") {
            "https".to_string()
        } else if lower.starts_with("http://") {
            "http".to_string()
        } else {
            "custom".to_string()
        }
    }

    pub async fn get_config(&self) -> ProxyConfig {
        self.state.read().await.clone()
    }

    pub async fn get_active_proxy_url(&self) -> Option<String> {
        let cfg = self.state.read().await;
        if cfg.enabled && !cfg.current_url.is_empty() {
            Some(cfg.current_url.clone())
        } else {
            None
        }
    }

    pub async fn set_proxy(&self, url: String, enabled: bool) -> Result<ProxyConfig> {
        let detected = Self::detect_type(&url);
        let mut cfg = self.state.write().await;
        cfg.current_url = url.clone();
        cfg.enabled = enabled;
        cfg.proxy_type = detected.clone();

        // Add to presets if not already there
        if !cfg.presets.iter().any(|p| p.url == url) && !url.is_empty() {
            cfg.presets.push(ProxyPreset {
                name: format!("{} ({})", detected.to_uppercase(), truncate(&url, 20)),
                url: url.clone(),
                proxy_type: detected,
            });
        }

        // Persist to disk
        if let Ok(json) = serde_json::to_string_pretty(&*cfg) {
            let _ = std::fs::write(&self.config_path, json);
        }

        info!("Updated proxy settings: enabled={}, url={}", enabled, cfg.current_url);
        Ok(cfg.clone())
    }

    /// Tests proxy connection by performing an HTTP request via the proxy
    pub async fn test_proxy(&self, test_url: Option<String>) -> Result<bool> {
        let cfg = self.state.read().await;
        let proxy_url = test_url.unwrap_or_else(|| cfg.current_url.clone());
        if proxy_url.is_empty() {
            return Ok(false);
        }

        // Run curl test with the proxy
        let status = tokio::process::Command::new("curl")
            .arg("-I")
            .arg("--connect-timeout")
            .arg("5")
            .arg("-x")
            .arg(&proxy_url)
            .arg("https://api.github.com")
            .output()
            .await?;

        Ok(status.status.success())
    }
}

fn truncate(s: &str, max_chars: usize) -> String {
    if s.chars().count() > max_chars {
        format!("{}…", s.chars().take(max_chars).collect::<String>())
    } else {
        s.to_string()
    }
}
