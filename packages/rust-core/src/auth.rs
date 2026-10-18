use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

///Proactive refresh buffer before token expiration (60 seconds in milliseconds).
pub const TOKEN_PROACTIVE_REFRESH_BUFFER_MS: i64 = 60_000;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "camelCase")]
pub enum SarvamCredentials {
    #[serde(rename_all = "camelCase")]
    SubscriptionKey { key: String },
    #[serde(rename_all = "camelCase")]
    BearerToken {
        token: String,
        expires_at_epoch_ms: Option<i64>,
    },
    #[serde(rename_all = "camelCase")]
    CustomHeaders { headers: BTreeMap<String, String> },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WsHandshakeAuth {
    pub headers: BTreeMap<String, String>,
    pub subprotocols: Vec<String>,
}

impl SarvamCredentials {
    pub fn to_rest_headers(&self) -> BTreeMap<String, String> {
        let mut map = BTreeMap::new();
        match self {
            SarvamCredentials::SubscriptionKey { key } => {
                map.insert("api-subscription-key".to_string(), key.clone());
            }
            SarvamCredentials::BearerToken { token, .. } => {
                map.insert("Authorization".to_string(), format!("Bearer {token}"));
            }
            SarvamCredentials::CustomHeaders { headers } => {
                for (k, v) in headers {
                    map.insert(k.clone(), v.clone());
                }
            }
        }
        map
    }

    pub fn to_ws_handshake(&self, use_subprotocol: bool) -> WsHandshakeAuth {
        let mut headers = BTreeMap::new();
        let mut subprotocols = Vec::new();

        match self {
            SarvamCredentials::SubscriptionKey { key } => {
                if use_subprotocol {
                    subprotocols.push(format!("api-subscription-key.{key}"));
                } else {
                    headers.insert("Api-Subscription-Key".to_string(), key.clone());
                }
            }
            SarvamCredentials::BearerToken { token, .. } => {
                if use_subprotocol {
                    subprotocols.push(format!("bearer.{token}"));
                } else {
                    headers.insert("Authorization".to_string(), format!("Bearer {token}"));
                }
            }
            SarvamCredentials::CustomHeaders {
                headers: custom, ..
            } => {
                for (k, v) in custom {
                    headers.insert(k.clone(), v.clone());
                }
            }
        }

        WsHandshakeAuth {
            headers,
            subprotocols,
        }
    }

    pub fn needs_proactive_refresh(&self, now_epoch_ms: i64) -> bool {
        match self {
            SarvamCredentials::BearerToken {
                expires_at_epoch_ms: Some(exp),
                ..
            } => now_epoch_ms + TOKEN_PROACTIVE_REFRESH_BUFFER_MS >= *exp,
            _ => false,
        }
    }
}

/// Manages cached bearer tokens, proactive 60s expiration checks, and invalidation.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TokenCacheState {
    pub cached_token: Option<String>,
    pub expires_at_epoch_ms: Option<i64>,
    pub refresh_count: u32,
}

impl TokenCacheState {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn store_token(&mut self, token: impl Into<String>, expires_at_epoch_ms: Option<i64>) {
        self.cached_token = Some(token.into());
        self.expires_at_epoch_ms = expires_at_epoch_ms;
        self.refresh_count += 1;
    }

    pub fn invalidate(&mut self) {
        self.cached_token = None;
        self.expires_at_epoch_ms = None;
    }

    pub fn is_valid_at(&self, now_epoch_ms: i64) -> bool {
        let Some(ref token) = self.cached_token else {
            return false;
        };
        if token.is_empty() {
            return false;
        }
        if let Some(exp) = self.expires_at_epoch_ms {
            now_epoch_ms + TOKEN_PROACTIVE_REFRESH_BUFFER_MS < exp
        } else {
            true
        }
    }

    pub fn current_credentials(&self, now_epoch_ms: i64) -> Option<SarvamCredentials> {
        if self.is_valid_at(now_epoch_ms) {
            self.cached_token
                .as_ref()
                .map(|t| SarvamCredentials::BearerToken {
                    token: t.clone(),
                    expires_at_epoch_ms: self.expires_at_epoch_ms,
                })
        } else {
            None
        }
    }
}
