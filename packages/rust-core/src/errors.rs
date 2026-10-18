use crate::retry::parse_retry_after_ms;
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum SarvamErrorKind {
    AuthenticationError,
    PermissionDeniedError,
    BadRequestError,
    NotFoundError,
    PayloadTooLargeError,
    UnprocessableEntityError,
    RateLimitError,
    ServerError,
    ConnectionError,
    TimeoutError,
    StreamError,
    RealtimeError,
    DecodingError,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ClassifiedError {
    #[serde(rename = "type")]
    pub error_type: SarvamErrorKind,
    pub status_code: Option<u16>,
    pub code: Option<String>,
    pub message: String,
    pub request_id: Option<String>,
    pub retry_after_ms: Option<u64>,
    pub raw_body: Option<String>,
    pub should_trigger_token_refresh: bool,
    pub is_retryable_by_status: bool,
}

#[derive(Debug, Deserialize)]
struct ErrorEnvelope {
    error: Option<ErrorDetail>,
    detail: Option< serde_json::Value>,
    message: Option<String>,
    code: Option<String>,
    request_id: Option<String>,
}

#[derive(Debug, Deserialize)]
struct ErrorDetail {
    code: Option<String>,
    message: Option<String>,
    request_id: Option<String>,
}

pub fn classify_http_error(
    status_code: u16,
    headers: &BTreeMap<String, String>,
    raw_body: &str,
    now_epoch_ms: i64,
) -> ClassifiedError {
    let mut code: Option<String> = None;
    let mut message: Option<String> = None;
    let mut request_id: Option<String> = None;

    // Case-insensitive header lookup for request_id
    for (k, v) in headers {
        let lower = k.to_ascii_lowercase();
        if lower == "x-request-id" || lower == "x-ms-request-id" || lower == "request-id" {
            request_id = Some(v.clone());
            break;
        }
    }

    if let Ok(parsed) = serde_json::from_str::<ErrorEnvelope>(raw_body) {
        if let Some(err) = parsed.error {
            code = err.code.or(code);
            message = err.message.or(message);
            request_id = err.request_id.or(request_id);
        }
        if code.is_none() {
            code = parsed.code;
        }
        if message.is_none() {
            message = parsed.message;
        }
        if message.is_none() {
            if let Some(serde_json::Value::String(s)) = parsed.detail {
                message = Some(s);
            }
        }
        if request_id.is_none() {
            request_id = parsed.request_id;
        }
    }

    let resolved_message = message.unwrap_or_else(|| {
        if raw_body.trim().is_empty() {
            format!("HTTP error {status_code}")
        } else {
            raw_body.to_string()
        }
    });

    let retry_after_ms = parse_retry_after_ms(headers, now_epoch_ms);
    let code_str = code.as_deref().unwrap_or("");

    let (error_type, should_trigger_token_refresh, is_retryable_by_status) = match status_code {
        401 => (SarvamErrorKind::AuthenticationError, true, false),
        403 => {
            if code_str == "invalid_api_key_error" {
                (SarvamErrorKind::AuthenticationError, true, false)
            } else {
                (SarvamErrorKind::PermissionDeniedError, false, false)
            }
        }
        400 => (SarvamErrorKind::BadRequestError, false, false),
        404 => (SarvamErrorKind::NotFoundError, false, false),
        413 => (SarvamErrorKind::PayloadTooLargeError, false, false),
        422 => (SarvamErrorKind::UnprocessableEntityError, false, false),
        429 => (SarvamErrorKind::RateLimitError, false, true),
        503 if code_str == "rate_limit_exceeded_error" => {
            (SarvamErrorKind::RateLimitError, false, true)
        }
        408 | 409 | 500 | 502 | 503 | 504 => (SarvamErrorKind::ServerError, false, true),
        _ if status_code >= 500 => (SarvamErrorKind::ServerError, false, true),
        _ => (SarvamErrorKind::BadRequestError, false, false),
    };

    ClassifiedError {
        error_type,
        status_code: Some(status_code),
        code,
        message: resolved_message,
        request_id,
        retry_after_ms,
        raw_body: if raw_body.is_empty() {
            None
        } else {
            Some(raw_body.to_string())
        },
        should_trigger_token_refresh,
        is_retryable_by_status,
    }
}
