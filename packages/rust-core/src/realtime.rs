use crate::auth::{SarvamCredentials, WsHandshakeAuth};
use crate::environment::SarvamEnvironment;
use crate::errors::{ClassifiedError, SarvamErrorKind};
use crate::generated::EnvironmentHost;
use base64::engine::general_purpose::STANDARD as BASE64_STD;
use base64::Engine;
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SttRealtimeConfig {
    pub language_code: String,
    pub model: Option<String>,
    pub sample_rate: Option<u32>,
    pub mode: Option<String>,
    pub encoding: Option<String>,
    pub return_timestamps: Option<bool>,
    pub endpointing: Option<u32>,
    pub threshold: Option<f64>,
    pub prefix_padding_ms: Option<u32>,
    pub silence_duration_ms: Option<u32>,
    pub min_speech_duration_ms: Option<u32>,
    pub prompt: Option<String>,
    pub keyterms: Option<Vec<String>>,
    pub use_subprotocol_auth: Option<bool>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WsConnectionSpec {
    pub url: String,
    pub headers: BTreeMap<String, String>,
    pub subprotocols: Vec<String>,
    pub initial_frames: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "camelCase")]
pub enum SttRealtimeEvent {
    #[serde(rename_all = "camelCase")]
    SessionBegin { session_id: String },
    #[serde(rename_all = "camelCase")]
    VadSpeechStart { timestamp_ms: Option<i64> },
    #[serde(rename_all = "camelCase")]
    VadSpeechEnd { timestamp_ms: Option<i64> },
    #[serde(rename_all = "camelCase")]
    TranscriptPartial {
        utterance_idx: Option<u32>,
        text: String,
        language: Option<String>,
    },
    #[serde(rename_all = "camelCase")]
    TranscriptFinal {
        utterance_idx: Option<u32>,
        text: String,
        language: Option<String>,
        language_confidence: Option<f64>,
        start_s: Option<f64>,
        end_s: Option<f64>,
    },
    #[serde(rename_all = "camelCase")]
    SessionEnd { duration_seconds: Option<f64> },
    #[serde(rename_all = "camelCase")]
    Error {
        code: Option<String>,
        message: String,
    },
    #[serde(rename_all = "camelCase")]
    Unknown { raw_json: String },
}

pub fn validate_stt_sample_rate(sample_rate: u32) -> Result<(), ClassifiedError> {
    if sample_rate == 16_000 || sample_rate == 8_000 {
        Ok(())
    } else {
        Err(ClassifiedError {
            error_type: SarvamErrorKind::BadRequestError,
            status_code: Some(400),
            code: Some("invalid_sample_rate".to_string()),
            message: format!(
                "Invalid sampleRate ({sample_rate}): sampleRate must be 16000 or 8000"
            ),
            request_id: None,
            retry_after_ms: None,
            raw_body: None,
            should_trigger_token_refresh: false,
            is_retryable_by_status: false,
        })
    }
}

pub fn build_stt_ws_connection(
    env: &SarvamEnvironment,
    creds: &SarvamCredentials,
    config: &SttRealtimeConfig,
) -> Result<WsConnectionSpec, ClassifiedError> {
    if let Some(sr) = config.sample_rate {
        validate_stt_sample_rate(sr)?;
    }

    let base_url = env.resolve_operation_url(EnvironmentHost::Ws, "/speech-to-text-realtime/ws");
    let mut query_parts = vec![format!("language_code={}", config.language_code)];
    if let Some(ref model) = config.model {
        query_parts.push(format!("model={model}"));
    }
    if let Some(sr) = config.sample_rate {
        query_parts.push(format!("sample_rate={sr}"));
    }
    if let Some(ref mode) = config.mode {
        query_parts.push(format!("mode={mode}"));
    }
    if let Some(ref enc) = config.encoding {
        query_parts.push(format!("encoding={enc}"));
    }
    if let Some(ts) = config.return_timestamps {
        query_parts.push(format!("return_timestamps={ts}"));
    }

    let url = format!("{base_url}?{}", query_parts.join("&"));
    let WsHandshakeAuth {
        headers,
        subprotocols,
    } = creds.to_ws_handshake(config.use_subprotocol_auth.unwrap_or(false));

    Ok(WsConnectionSpec {
        url,
        headers,
        subprotocols,
        initial_frames: Vec::new(),
    })
}

pub fn encode_stt_audio_frame(pcm_bytes: &[u8]) -> String {
    let b64 = BASE64_STD.encode(pcm_bytes);
    serde_json::json!({
        "event": "audio_input",
        "audio": b64
    })
    .to_string()
}

pub fn encode_stt_flush_frame() -> String {
    r#"{"event":"flush"}"#.to_string()
}

pub fn encode_stt_ping_frame() -> String {
    r#"{"event":"ping"}"#.to_string()
}

pub fn encode_stt_end_frame() -> String {
    r#"{"event":"end"}"#.to_string()
}

pub fn parse_stt_ws_event(raw_json: &str) -> SttRealtimeEvent {
    let Ok(val) = serde_json::from_str::<serde_json::Value>(raw_json) else {
        return SttRealtimeEvent::Unknown {
            raw_json: raw_json.to_string(),
        };
    };

    let event_type = val
        .get("event")
        .or_else(|| val.get("type"))
        .and_then(|v| v.as_str())
        .unwrap_or("");

    match event_type {
        "session_begin" => SttRealtimeEvent::SessionBegin {
            session_id: val
                .get("session_id")
                .and_then(|v| v.as_str())
                .unwrap_or_default()
                .to_string(),
        },
        "vad_speech_start" | "speech_start" => SttRealtimeEvent::VadSpeechStart {
            timestamp_ms: val.get("timestamp_ms").and_then(|v| v.as_i64()),
        },
        "vad_speech_end" | "speech_end" => SttRealtimeEvent::VadSpeechEnd {
            timestamp_ms: val.get("timestamp_ms").and_then(|v| v.as_i64()),
        },
        "transcript_partial" => SttRealtimeEvent::TranscriptPartial {
            utterance_idx: val
                .get("utterance_idx")
                .and_then(|v| v.as_u64())
                .map(|v| v as u32),
            text: val
                .get("text")
                .or_else(|| val.get("transcript"))
                .and_then(|v| v.as_str())
                .unwrap_or_default()
                .to_string(),
            language: val
                .get("language")
                .or_else(|| val.get("language_code"))
                .and_then(|v| v.as_str())
                .map(|s| s.to_string()),
        },
        "transcript_final" | "transcript" => SttRealtimeEvent::TranscriptFinal {
            utterance_idx: val
                .get("utterance_idx")
                .and_then(|v| v.as_u64())
                .map(|v| v as u32),
            text: val
                .get("text")
                .or_else(|| val.get("transcript"))
                .and_then(|v| v.as_str())
                .unwrap_or_default()
                .to_string(),
            language: val
                .get("language")
                .or_else(|| val.get("language_code"))
                .and_then(|v| v.as_str())
                .map(|s| s.to_string()),
            language_confidence: val.get("language_confidence").and_then(|v| v.as_f64()),
            start_s: val.get("start_s").and_then(|v| v.as_f64()),
            end_s: val.get("end_s").and_then(|v| v.as_f64()),
        },
        "session_end" => SttRealtimeEvent::SessionEnd {
            duration_seconds: val.get("duration_seconds").and_then(|v| v.as_f64()),
        },
        "error" => SttRealtimeEvent::Error {
            code: val
                .get("code")
                .and_then(|v| v.as_str())
                .map(|s| s.to_string()),
            message: val
                .get("message")
                .and_then(|v| v.as_str())
                .unwrap_or("Unknown STT realtime error")
                .to_string(),
        },
        _ => SttRealtimeEvent::Unknown {
            raw_json: raw_json.to_string(),
        },
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TtsStreamingConfig {
    pub language_code: String,
    pub speaker: String,
    pub model: Option<String>,
    pub speech_sample_rate: Option<u32>,
    pub output_audio_codec: Option<String>,
    pub use_subprotocol_auth: Option<bool>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "camelCase")]
pub enum TtsStreamEvent {
    #[serde(rename_all = "camelCase")]
    AudioChunk {
        audio_base64: String,
        audio_bytes: Vec<u8>,
        content_type: Option<String>,
        request_id: Option<String>,
    },
    #[serde(rename_all = "camelCase")]
    Completed { request_id: Option<String> },
    #[serde(rename_all = "camelCase")]
    Error {
        message: String,
        code: Option<String>,
    },
    #[serde(rename_all = "camelCase")]
    Unknown { raw_json: String },
}

pub fn build_tts_ws_connection(
    env: &SarvamEnvironment,
    creds: &SarvamCredentials,
    config: &TtsStreamingConfig,
) -> WsConnectionSpec {
    let model = config.model.as_deref().unwrap_or("bulbul:v4-flash");
    let base_url = env.resolve_operation_url(EnvironmentHost::Ws, "/text-to-speech/ws");
    let url = format!("{base_url}?model={model}&send_completion_event=true");

    let WsHandshakeAuth {
        headers,
        subprotocols,
    } = creds.to_ws_handshake(config.use_subprotocol_auth.unwrap_or(false));

    let mut data_obj = serde_json::Map::new();
    data_obj.insert(
        "language_code".to_string(),
        serde_json::Value::String(config.language_code.clone()),
    );
    data_obj.insert(
        "speaker".to_string(),
        serde_json::Value::String(config.speaker.clone()),
    );
    data_obj.insert(
        "model".to_string(),
        serde_json::Value::String(model.to_string()),
    );
    if let Some(sr) = config.speech_sample_rate {
        data_obj.insert(
            "speech_sample_rate".to_string(),
            serde_json::Value::Number(sr.into()),
        );
    }
    if let Some(ref codec) = config.output_audio_codec {
        data_obj.insert(
            "output_audio_codec".to_string(),
            serde_json::Value::String(codec.clone()),
        );
    }

    let initial_config_frame = serde_json::json!({
        "type": "config",
        "data": data_obj
    })
    .to_string();

    WsConnectionSpec {
        url,
        headers,
        subprotocols,
        initial_frames: vec![initial_config_frame],
    }
}

pub fn encode_tts_text_frame(text: &str) -> String {
    serde_json::json!({
        "type": "text",
        "data": {
            "text": text
        }
    })
    .to_string()
}

pub fn encode_tts_flush_frame() -> String {
    r#"{"type":"flush"}"#.to_string()
}

pub fn parse_tts_ws_event(raw_json: &str) -> TtsStreamEvent {
    let Ok(val) = serde_json::from_str::<serde_json::Value>(raw_json) else {
        return TtsStreamEvent::Unknown {
            raw_json: raw_json.to_string(),
        };
    };

    let msg_type = val.get("type").and_then(|v| v.as_str()).unwrap_or("");
    let data = val.get("data");

    match msg_type {
        "audio" => {
            let b64 = data
                .and_then(|d| d.get("audio"))
                .and_then(|v| v.as_str())
                .unwrap_or_default()
                .to_string();
            let decoded = BASE64_STD.decode(b64.as_bytes()).unwrap_or_default();
            let content_type = data
                .and_then(|d| d.get("content_type"))
                .and_then(|v| v.as_str())
                .map(|s| s.to_string());
            let request_id = data
                .and_then(|d| d.get("request_id"))
                .or_else(|| val.get("request_id"))
                .and_then(|v| v.as_str())
                .map(|s| s.to_string());

            TtsStreamEvent::AudioChunk {
                audio_base64: b64,
                audio_bytes: decoded,
                content_type,
                request_id,
            }
        }
        "event" => {
            let ev_name = data
                .and_then(|d| d.get("event").or_else(|| d.get("event_type")))
                .and_then(|v| v.as_str())
                .unwrap_or("");
            if ev_name == "final" || ev_name == "completion" {
                let request_id = data
                    .and_then(|d| d.get("request_id"))
                    .or_else(|| val.get("request_id"))
                    .and_then(|v| v.as_str())
                    .map(|s| s.to_string());
                TtsStreamEvent::Completed { request_id }
            } else {
                TtsStreamEvent::Unknown {
                    raw_json: raw_json.to_string(),
                }
            }
        }
        "error" => {
            let message = data
                .and_then(|d| d.get("message"))
                .or_else(|| val.get("message"))
                .and_then(|v| v.as_str())
                .unwrap_or("Unknown TTS WebSocket error")
                .to_string();
            let code = data
                .and_then(|d| d.get("code"))
                .or_else(|| val.get("code"))
                .and_then(|v| v.as_str())
                .map(|s| s.to_string());
            TtsStreamEvent::Error { message, code }
        }
        _ => TtsStreamEvent::Unknown {
            raw_json: raw_json.to_string(),
        },
    }
}
