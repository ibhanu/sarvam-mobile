use crate::generated::{
    EnvironmentHost, DEFAULT_API_BASE_URL, DEFAULT_DUBBING_BASE_URL, DEFAULT_WS_BASE_URL,
    SPEC_VERSION,
};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SarvamEnvironment {
    pub api_base_url: String,
    pub dubbing_base_url: String,
    pub ws_base_url: String,
}

impl Default for SarvamEnvironment {
    fn default() -> Self {
        Self::production()
    }
}

impl SarvamEnvironment {
    pub fn production() -> Self {
        Self {
            api_base_url: DEFAULT_API_BASE_URL.to_string(),
            dubbing_base_url: DEFAULT_DUBBING_BASE_URL.to_string(),
            ws_base_url: DEFAULT_WS_BASE_URL.to_string(),
        }
    }

    pub fn proxy(proxy_base_url: &str) -> Self {
        let trimmed = proxy_base_url.trim_end_matches('/');
        let ws_url = if let Some(rest) = trimmed.strip_prefix("https://") {
            format!("wss://{rest}")
        } else if let Some(rest) = trimmed.strip_prefix("http://") {
            format!("ws://{rest}")
        } else if trimmed.starts_with("wss://") || trimmed.starts_with("ws://") {
            trimmed.to_string()
        } else {
            format!("wss://{trimmed}")
        };

        Self {
            api_base_url: trimmed.to_string(),
            dubbing_base_url: format!("{trimmed}/dubbing"),
            ws_base_url: ws_url,
        }
    }

    pub fn resolve_base_url(&self, host: EnvironmentHost) -> &str {
        match host {
            EnvironmentHost::Api => &self.api_base_url,
            EnvironmentHost::Dubbing => &self.dubbing_base_url,
            EnvironmentHost::Ws => &self.ws_base_url,
        }
    }

    pub fn resolve_operation_url(&self, host: EnvironmentHost, path: &str) -> String {
        let base = self.resolve_base_url(host).trim_end_matches('/');
        let normalized_path = if path.starts_with('/') {
            path.to_string()
        } else {
            format!("/{path}")
        };
        format!("{base}{normalized_path}")
    }
}

pub fn format_user_agent(
    platform: &str,
    sdk_version: &str,
    os_name: &str,
    os_version: &str,
    runtime: &str,
) -> String {
    format!(
        "sarvam-{platform}/{sdk_version} (spec/{SPEC_VERSION}; {os_name}/{os_version}; {runtime}; rust-core/0.2.0)"
    )
}
