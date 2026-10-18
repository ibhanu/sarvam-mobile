use crate::errors::{classify_http_error, SarvamErrorKind};
use crate::generated::OperationKind;
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

pub const DEFAULT_MAX_RETRIES: u32 = 2;
pub const DEFAULT_BASE_BACKOFF_MS: u64 = 500;
pub const DEFAULT_MAX_BACKOFF_MS: u64 = 8_000;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "action", rename_all = "camelCase")]
pub enum RetryDecision {
    #[serde(rename_all = "camelCase")]
    DoNotRetry { reason: String },
    #[serde(rename_all = "camelCase")]
    RefreshTokenAndRetryOnce,
    #[serde(rename_all = "camelCase")]
    BackoffAndRetry { delay_ms: u64 },
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RetryEvaluationInput {
    pub operation_kind: OperationKind,
    pub attempt: u32,
    pub max_retries: u32,
    pub status_code: Option<u16>,
    pub headers: BTreeMap<String, String>,
    pub raw_body: String,
    pub is_network_or_timeout_error: bool,
    pub is_timeout_error: bool,
    pub is_replayable_body: bool,
    pub has_idempotency_key: bool,
    pub is_token_auth: bool,
    pub has_refreshed_token: bool,
    pub random_factor: f64,
    pub now_epoch_ms: i64,
}

/// Parses retry-after delay in milliseconds according to Section 5.1 precedence:
/// 1. `retry-after-ms` (integer ms)
/// 2. `Retry-After` (integer seconds * 1000)
/// 3. `X-RateLimit-Reset` (Unix epoch seconds delta)
pub fn parse_retry_after_ms(headers: &BTreeMap<String, String>, now_epoch_ms: i64) -> Option<u64> {
    let mut retry_after_ms_val: Option<String> = None;
    let mut retry_after_val: Option<String> = None;
    let mut ratelimit_reset_val: Option<String> = None;

    for (k, v) in headers {
        match k.to_ascii_lowercase().as_str() {
            "retry-after-ms" => retry_after_ms_val = Some(v.trim().to_string()),
            "retry-after" => retry_after_val = Some(v.trim().to_string()),
            "x-ratelimit-reset" => ratelimit_reset_val = Some(v.trim().to_string()),
            _ => {}
        }
    }

    if let Some(ms_str) = retry_after_ms_val {
        if let Ok(ms) = ms_str.parse::<u64>() {
            return Some(ms);
        }
    }

    if let Some(sec_str) = retry_after_val {
        if let Ok(secs) = sec_str.parse::<u64>() {
            return Some(secs.saturating_mul(1_000));
        }
    }

    if let Some(reset_str) = ratelimit_reset_val {
        if let Ok(epoch_secs) = reset_str.parse::<i64>() {
            let target_ms = epoch_secs.saturating_mul(1_000);
            let delta = target_ms - now_epoch_ms;
            if delta > 0 {
                return Some(delta as u64);
            }
            return Some(0);
        }
    }

    None
}

/// Computes full-jitter exponential backoff in milliseconds:
/// `ceiling = min(max_backoff_ms, base_backoff_ms * 2^attempt)`
/// `sleep = random_factor * ceiling` (where `random_factor` is in `[0.0, 1.0]`).
pub fn compute_backoff_ms(
    attempt: u32,
    base_backoff_ms: u64,
    max_backoff_ms: u64,
    random_factor: f64,
) -> u64 {
    let shift = attempt.min(16);
    let exp = base_backoff_ms.saturating_mul(1u64 << shift);
    let ceiling = exp.min(max_backoff_ms);
    let clamped_rand = random_factor.clamp(0.0, 1.0);
    ((ceiling as f64) * clamped_rand).round() as u64
}

pub fn evaluate_retry(input: &RetryEvaluationInput) -> RetryDecision {
    // 1. Check TokenAuth single-retry on AuthenticationError (HTTP 401 or 403 invalid_api_key_error)
    if let Some(status) = input.status_code {
        let classified = classify_http_error(
            status,
            &input.headers,
            &input.raw_body,
            input.now_epoch_ms,
        );

        if classified.error_type == SarvamErrorKind::AuthenticationError {
            if input.is_token_auth && !input.has_refreshed_token {
                return RetryDecision::RefreshTokenAndRetryOnce;
            }
            return RetryDecision::DoNotRetry {
                reason: "AuthenticationError does not retry via backoff".to_string(),
            };
        }
    }

    // 2. Check max retries budget (attempt is 0-indexed: 0 = initial attempt, 1 = 1st retry, etc.)
    if input.attempt >= input.max_retries {
        return RetryDecision::DoNotRetry {
            reason: "Max retries exhausted".to_string(),
        };
    }

    let retry_after = parse_retry_after_ms(&input.headers, input.now_epoch_ms);
    let compute_delay = || -> u64 {
        retry_after.unwrap_or_else(|| {
            compute_backoff_ms(
                input.attempt,
                DEFAULT_BASE_BACKOFF_MS,
                DEFAULT_MAX_BACKOFF_MS,
                input.random_factor,
            )
        })
    };

    // 3. Network / Timeout error classification by OperationKind
    if input.is_network_or_timeout_error {
        let allowed = match input.operation_kind {
            OperationKind::Idempotent => true,
            OperationKind::StatelessPost => !input.is_timeout_error,
            OperationKind::MultipartCompute => false,
            OperationKind::JobCreate => input.has_idempotency_key && !input.is_timeout_error,
        };
        return if allowed {
            RetryDecision::BackoffAndRetry {
                delay_ms: compute_delay(),
            }
        } else {
            RetryDecision::DoNotRetry {
                reason: format!(
                    "Network/timeout error not retryable for {:?}",
                    input.operation_kind
                ),
            }
        };
    }

    // 4. HTTP Status Code classification by OperationKind (Section 5.2 Safe Retry Matrix)
    let Some(status) = input.status_code else {
        return RetryDecision::DoNotRetry {
            reason: "No status code or network error".to_string(),
        };
    };

    let should_retry_status = match input.operation_kind {
        OperationKind::Idempotent => {
            matches!(status, 408 | 409 | 429 | 500 | 502 | 503 | 504)
        }
        OperationKind::StatelessPost => {
            matches!(status, 408 | 409 | 429 | 500 | 502 | 503 | 504)
        }
        OperationKind::MultipartCompute => {
            input.is_replayable_body && matches!(status, 429 | 503)
        }
        OperationKind::JobCreate => {
            if status == 429 {
                true
            } else if input.has_idempotency_key {
                matches!(status, 408 | 409 | 500 | 502 | 503 | 504)
            } else {
                false
            }
        }
    };

    if should_retry_status {
        RetryDecision::BackoffAndRetry {
            delay_ms: compute_delay(),
        }
    } else {
        RetryDecision::DoNotRetry {
            reason: format!(
                "HTTP {status} is not retryable for {:?}",
                input.operation_kind
            ),
        }
    }
}
