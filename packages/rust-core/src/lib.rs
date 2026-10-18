pub mod audio;
pub mod auth;
pub mod environment;
pub mod errors;
pub mod ffi;
pub mod generated;
pub mod realtime;
pub mod retry;
pub mod sse;

#[cfg(test)]
mod tests {
    use crate::audio::{calculate_audio_levels, decode_base64_audio, resample_float32_bytes, resample_pcm16};
    use crate::auth::{SarvamCredentials, TokenCacheState};
    use crate::environment::{format_user_agent, SarvamEnvironment};
    use crate::errors::{classify_http_error, SarvamErrorKind};
    use crate::ffi::dispatch_command_json;
    use crate::generated::{find_operation, LanguageCode, OperationKind};
    use crate::realtime::{
        build_stt_ws_connection, build_tts_ws_connection, parse_stt_ws_event, parse_tts_ws_event,
        validate_stt_sample_rate, SttRealtimeConfig, SttRealtimeEvent, TtsStreamEvent,
        TtsStreamingConfig,
    };
    use crate::retry::{evaluate_retry, RetryDecision, RetryEvaluationInput};
    use crate::sse::{parse_chat_sse_payload, parse_responses_sse_payload};
    use std::collections::BTreeMap;

    #[test]
    fn test_environment_and_user_agent() {
        let prod = SarvamEnvironment::production();
        assert_eq!(prod.api_base_url, "https://api.sarvam.ai");
        assert_eq!(prod.dubbing_base_url, "https://api.sarvam.ai/dubbing");
        assert_eq!(prod.ws_base_url, "wss://api.sarvam.ai");

        let proxy = SarvamEnvironment::proxy("https://bff.myapp.com/sarvam/");
        assert_eq!(proxy.api_base_url, "https://bff.myapp.com/sarvam");
        assert_eq!(
            proxy.dubbing_base_url,
            "https://bff.myapp.com/sarvam/dubbing"
        );
        assert_eq!(proxy.ws_base_url, "wss://bff.myapp.com/sarvam");

        let ua = format_user_agent("kotlin", "0.2.0", "android", "15", "jvm/21");
        assert!(ua.contains("sarvam-kotlin/0.2.0"));
        assert!(ua.contains("rust-core/0.2.0"));
    }

    #[test]
    fn test_auth_and_token_cache() {
        let mut cache = TokenCacheState::new();
        assert!(!cache.is_valid_at(1_000));
        cache.store_token("tok_123", Some(100_000));
        // Valid at 30s (70s remaining > 60s buffer)
        assert!(cache.is_valid_at(30_000));
        // Proactive refresh triggered at 40s (60s remaining <= 60s buffer)
        assert!(!cache.is_valid_at(40_000));
        cache.invalidate();
        assert!(!cache.is_valid_at(10_000));
    }

    #[test]
    fn test_conformance_rest_auth_quirk_and_permission_denied() {
        let headers = BTreeMap::new();
        let body_403_invalid = r#"{"error":{"code":"invalid_api_key_error","message":"Invalid API key","request_id":"req_auth_403"}}"#;
        let err = classify_http_error(403, &headers, body_403_invalid, 0);
        assert_eq!(err.error_type, SarvamErrorKind::AuthenticationError);
        assert!(err.should_trigger_token_refresh);
        assert_eq!(err.request_id.as_deref(), Some("req_auth_403"));

        let body_403_tier = r#"{"error":{"code":"authentication_error","message":"Tier locked","request_id":"req_perm_403"}}"#;
        let perm = classify_http_error(403, &headers, body_403_tier, 0);
        assert_eq!(perm.error_type, SarvamErrorKind::PermissionDeniedError);
        assert!(!perm.should_trigger_token_refresh);
    }

    #[test]
    fn test_conformance_retry_matrix() {
        // 1. JOB_CREATE on HTTP 500 without Idempotency-Key -> DoNotRetry
        let job_500 = evaluate_retry(&RetryEvaluationInput {
            operation_kind: OperationKind::JobCreate,
            attempt: 0,
            max_retries: 2,
            status_code: Some(500),
            headers: BTreeMap::new(),
            raw_body: r#"{"error":{"code":"internal_server_error","message":"Internal server error"}}"#.to_string(),
            is_network_or_timeout_error: false,
            is_timeout_error: false,
            is_replayable_body: true,
            has_idempotency_key: false,
            is_token_auth: false,
            has_refreshed_token: false,
            random_factor: 0.5,
            now_epoch_ms: 0,
        });
        assert!(matches!(job_500, RetryDecision::DoNotRetry { .. }));

        // 2. STATELESS_POST on 429 with retry-after-ms: 50 -> BackoffAndRetry { delay_ms: 50 }
        let mut rl_headers = BTreeMap::new();
        rl_headers.insert("retry-after-ms".to_string(), "50".to_string());
        let rl_429 = evaluate_retry(&RetryEvaluationInput {
            operation_kind: OperationKind::StatelessPost,
            attempt: 0,
            max_retries: 2,
            status_code: Some(429),
            headers: rl_headers,
            raw_body: String::new(),
            is_network_or_timeout_error: false,
            is_timeout_error: false,
            is_replayable_body: true,
            has_idempotency_key: false,
            is_token_auth: false,
            has_refreshed_token: false,
            random_factor: 0.5,
            now_epoch_ms: 0,
        });
        assert_eq!(rl_429, RetryDecision::BackoffAndRetry { delay_ms: 50 });

        // 3. TokenAuth on 403 invalid_api_key_error -> RefreshTokenAndRetryOnce
        let token_refresh = evaluate_retry(&RetryEvaluationInput {
            operation_kind: OperationKind::StatelessPost,
            attempt: 0,
            max_retries: 2,
            status_code: Some(403),
            headers: BTreeMap::new(),
            raw_body: r#"{"error":{"code":"invalid_api_key_error","message":"Bearer token expired"}}"#.to_string(),
            is_network_or_timeout_error: false,
            is_timeout_error: false,
            is_replayable_body: true,
            has_idempotency_key: false,
            is_token_auth: true,
            has_refreshed_token: false,
            random_factor: 0.5,
            now_epoch_ms: 0,
        });
        assert_eq!(token_refresh, RetryDecision::RefreshTokenAndRetryOnce);
    }

    #[test]
    fn test_conformance_sse_chat_and_responses() {
        let chat_v2_sse = "data: {\"id\":\"chatcmpl-1\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Namaste\"}}]}\n\ndata: {\"id\":\"chatcmpl-1\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\" world\"}}]}\n\ndata: {\"id\":\"chatcmpl-1\",\"choices\":[],\"usage\":{\"prompt_tokens\":8,\"completion_tokens\":2,\"total_tokens\":10}}\n\ndata: [DONE]\n";
        let parsed_chat = parse_chat_sse_payload(chat_v2_sse).unwrap();
        assert_eq!(parsed_chat.accumulated_content, "Namaste world");
        assert!(parsed_chat.terminated_on_done);
        assert_eq!(parsed_chat.chunks.len(), 3);
        assert_eq!(parsed_chat.chunks[2].choices.len(), 0);
        assert_eq!(parsed_chat.chunks[2].first_delta_content, None);
        assert_eq!(parsed_chat.final_usage.unwrap().total_tokens, 10);

        let responses_sse = "event: response.created\ndata: {\"id\":\"resp_001\",\"type\":\"response.created\"}\n\nevent: response.content_part.added\ndata: {\"id\":\"resp_001\",\"type\":\"response.content_part.added\",\"part\":{\"type\":\"text\",\"text\":\"Quantum computers use qubits.\"}}\n\nevent: response.completed\ndata: {\"id\":\"resp_001\",\"type\":\"response.completed\",\"response\":{\"status\":\"completed\"}}\n";
        let parsed_resp = parse_responses_sse_payload(responses_sse).unwrap();
        assert_eq!(
            parsed_resp.terminated_on_event.as_deref(),
            Some("response.completed")
        );
        assert_eq!(
            parsed_resp.final_response_status.as_deref(),
            Some("completed")
        );
    }

    #[test]
    fn test_conformance_ws_stt_and_tts() {
        assert!(validate_stt_sample_rate(16_000).is_ok());
        assert!(validate_stt_sample_rate(8_000).is_ok());
        assert!(validate_stt_sample_rate(44_100).is_err());

        let env = SarvamEnvironment::production();
        let creds = SarvamCredentials::SubscriptionKey {
            key: "test-api-key".to_string(),
        };
        let stt_conn = build_stt_ws_connection(
            &env,
            &creds,
            &SttRealtimeConfig {
                language_code: LanguageCode::HI_IN.to_string(),
                model: Some("saaras:v3-realtime".to_string()),
                sample_rate: Some(16_000),
                mode: None,
                encoding: None,
                return_timestamps: None,
                endpointing: None,
                threshold: None,
                prefix_padding_ms: None,
                silence_duration_ms: None,
                min_speech_duration_ms: None,
                prompt: None,
                keyterms: None,
                use_subprotocol_auth: Some(true),
            },
        )
        .unwrap();
        assert_eq!(
            stt_conn.subprotocols,
            vec!["api-subscription-key.test-api-key".to_string()]
        );

        let ev = parse_stt_ws_event(
            r#"{"event":"transcript_final","utterance_idx":0,"text":"नमस्ते!","language":"hi-IN","language_confidence":0.99}"#,
        );
        match ev {
            SttRealtimeEvent::TranscriptFinal { text, language, .. } => {
                assert_eq!(text, "नमस्ते!");
                assert_eq!(language.as_deref(), Some("hi-IN"));
            }
            _ => panic!("Expected TranscriptFinal"),
        }

        let tts_conn = build_tts_ws_connection(
            &env,
            &creds,
            &TtsStreamingConfig {
                language_code: "hi-IN".to_string(),
                speaker: "simran_en_customer".to_string(),
                model: Some("bulbul:v4-flash".to_string()),
                speech_sample_rate: Some(22050),
                output_audio_codec: Some("mp3".to_string()),
                use_subprotocol_auth: Some(false),
            },
        );
        assert_eq!(tts_conn.initial_frames.len(), 1);
        let tts_audio = parse_tts_ws_event(
            r#"{"type":"audio","data":{"audio":"UklGRiQAAABXQVZFZm10IBAAAAABAAEAQB8AAEAfAAABAAgAZGF0YQAAAAA="}}"#,
        );
        match tts_audio {
            TtsStreamEvent::AudioChunk { audio_bytes, .. } => {
                assert_eq!(audio_bytes.len(), 44);
                assert_eq!(&audio_bytes[0..4], b"RIFF");
                assert_eq!(&audio_bytes[8..12], b"WAVE");
            }
            _ => panic!("Expected AudioChunk"),
        }
    }

    #[test]
    fn test_audio_dsp_resampler_and_levels() {
        // 48kHz mono -> 16kHz mono (3:1 decimation)
        let mut pcm_48k = Vec::new();
        for i in 0..480 {
            let sample: i16 = if i % 2 == 0 { 16384 } else { -16384 };
            pcm_48k.extend_from_slice(&sample.to_le_bytes());
        }
        let pcm_16k = resample_pcm16(&pcm_48k, 48_000, 1);
        assert_eq!(pcm_16k.len(), 160 * 2);

        let levels = calculate_audio_levels(&pcm_16k);
        assert!(levels.peak > 0.49 && levels.peak <= 0.51);
        assert!(levels.rms > 0.49 && levels.rms <= 0.51);
        assert!(levels.db_fs < 0.0 && levels.db_fs > -10.0);

        // Float32 stereo 32kHz -> 16kHz mono
        let mut f32_stereo = Vec::new();
        for _ in 0..320 {
            f32_stereo.extend_from_slice(&0.5_f32.to_le_bytes());
            f32_stereo.extend_from_slice(&0.5_f32.to_le_bytes());
        }
        let resampled_f32 = resample_float32_bytes(&f32_stereo, 32_000, 2);
        assert_eq!(resampled_f32.len(), 160 * 2);

        let wav = decode_base64_audio("UklGRiQAAABXQVZFZm10IBAAAAABAAEAQB8AAEAfAAABAAgAZGF0YQAAAAA=").unwrap();
        assert_eq!(wav.len(), 44);

        let op = find_operation("text.translate").unwrap();
        assert_eq!(op.path, "/translate");

        let resp_json = dispatch_command_json(r#"{"op":"version"}"#);
        assert!(resp_json.contains("\"status\":\"ok\""));
    }
}
