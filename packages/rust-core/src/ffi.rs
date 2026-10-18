use crate::audio::{calculate_audio_levels, decode_base64_audio, resample_float32_bytes, resample_pcm16};
use crate::auth::{SarvamCredentials, TokenCacheState};
use crate::environment::{format_user_agent, SarvamEnvironment};
use crate::errors::classify_http_error;
use crate::generated::{find_operation, SDK_VERSION, SPEC_VERSION};
use crate::realtime::{
    build_stt_ws_connection, build_tts_ws_connection, encode_stt_audio_frame,
    encode_tts_text_frame, parse_stt_ws_event, parse_tts_ws_event, validate_stt_sample_rate,
    SttRealtimeConfig, TtsStreamingConfig,
};
use crate::retry::{compute_backoff_ms, evaluate_retry, parse_retry_after_ms, RetryEvaluationInput};
use crate::sse::{parse_chat_sse_payload, parse_responses_sse_payload};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::ffi::{CStr, CString, c_char};
use std::slice;

#[derive(Debug, Deserialize)]
#[serde(tag = "op", rename_all = "camelCase")]
pub enum CoreCommand {
    #[serde(rename_all = "camelCase")]
    Version,
    #[serde(rename_all = "camelCase")]
    ResolveEnvironment {
        proxy_base_url: Option<String>,
    },
    #[serde(rename_all = "camelCase")]
    FormatUserAgent {
        platform: String,
        sdk_version: String,
        os_name: String,
        os_version: String,
        runtime: String,
    },
    #[serde(rename_all = "camelCase")]
    FindOperation {
        operation_id: String,
    },
    #[serde(rename_all = "camelCase")]
    ClassifyHttpError {
        status_code: u16,
        #[serde(default)]
        headers: BTreeMap<String, String>,
        #[serde(default)]
        raw_body: String,
        #[serde(default)]
        now_epoch_ms: i64,
    },
    #[serde(rename_all = "camelCase")]
    EvaluateRetry {
        input: RetryEvaluationInput,
    },
    #[serde(rename_all = "camelCase")]
    ParseRetryAfterMs {
        headers: BTreeMap<String, String>,
        #[serde(default)]
        now_epoch_ms: i64,
    },
    #[serde(rename_all = "camelCase")]
    ComputeBackoffMs {
        attempt: u32,
        base_backoff_ms: u64,
        max_backoff_ms: u64,
        random_factor: f64,
    },
    #[serde(rename_all = "camelCase")]
    ParseChatSse {
        raw_sse: String,
    },
    #[serde(rename_all = "camelCase")]
    ParseResponsesSse {
        raw_sse: String,
    },
    #[serde(rename_all = "camelCase")]
    ValidateSttSampleRate {
        sample_rate: u32,
    },
    #[serde(rename_all = "camelCase")]
    BuildSttWsConnection {
        environment: Option<SarvamEnvironment>,
        credentials: SarvamCredentials,
        config: SttRealtimeConfig,
    },
    #[serde(rename_all = "camelCase")]
    ParseSttWsEvent {
        raw_json: String,
    },
    #[serde(rename_all = "camelCase")]
    EncodeSttAudioFrame {
        pcm_bytes: Vec<u8>,
    },
    #[serde(rename_all = "camelCase")]
    BuildTtsWsConnection {
        environment: Option<SarvamEnvironment>,
        credentials: SarvamCredentials,
        config: TtsStreamingConfig,
    },
    #[serde(rename_all = "camelCase")]
    ParseTtsWsEvent {
        raw_json: String,
    },
    #[serde(rename_all = "camelCase")]
    EncodeTtsTextFrame {
        text: String,
    },
    #[serde(rename_all = "camelCase")]
    ResamplePcm16 {
        input_bytes: Vec<u8>,
        input_sample_rate: u32,
        channel_count: u16,
    },
    #[serde(rename_all = "camelCase")]
    ResampleFloat32Bytes {
        input_bytes: Vec<u8>,
        input_sample_rate: u32,
        channel_count: u16,
    },
    #[serde(rename_all = "camelCase")]
    CalculateAudioLevels {
        pcm16_bytes: Vec<u8>,
    },
    #[serde(rename_all = "camelCase")]
    DecodeBase64Audio {
        base64_str: String,
    },
    #[serde(rename_all = "camelCase")]
    CheckTokenProactiveRefresh {
        cached_token: Option<String>,
        expires_at_epoch_ms: Option<i64>,
        now_epoch_ms: i64,
    },
}

#[derive(Debug, Serialize)]
#[serde(tag = "status", rename_all = "camelCase")]
pub enum CoreResponse<T: Serialize> {
    Ok { data: T },
    Err { error: String, details: Option<serde_json::Value> },
}

pub fn dispatch_command_json(command_json: &str) -> String {
    let parsed: Result<CoreCommand, _> = serde_json::from_str(command_json);
    let cmd = match parsed {
        Ok(c) => c,
        Err(e) => {
            return serde_json::json!({
                "status": "err",
                "error": format!("Invalid command JSON: {e}")
            })
            .to_string();
        }
    };

    match cmd {
        CoreCommand::Version => serde_json::json!({
            "status": "ok",
            "data": {
                "rustCoreVersion": "0.2.0",
                "sdkVersion": SDK_VERSION,
                "specVersion": SPEC_VERSION
            }
        })
        .to_string(),

        CoreCommand::ResolveEnvironment { proxy_base_url } => {
            let env = match proxy_base_url {
                Some(ref url) => SarvamEnvironment::proxy(url),
                None => SarvamEnvironment::production(),
            };
            serde_json::json!({ "status": "ok", "data": env }).to_string()
        }

        CoreCommand::FormatUserAgent {
            platform,
            sdk_version,
            os_name,
            os_version,
            runtime,
        } => {
            let ua = format_user_agent(&platform, &sdk_version, &os_name, &os_version, &runtime);
            serde_json::json!({ "status": "ok", "data": { "userAgent": ua } }).to_string()
        }

        CoreCommand::FindOperation { operation_id } => match find_operation(&operation_id) {
            Some(spec) => serde_json::json!({ "status": "ok", "data": spec }).to_string(),
            None => serde_json::json!({
                "status": "err",
                "error": format!("Operation not found: {operation_id}")
            })
            .to_string(),
        },

        CoreCommand::ClassifyHttpError {
            status_code,
            headers,
            raw_body,
            now_epoch_ms,
        } => {
            let classified = classify_http_error(status_code, &headers, &raw_body, now_epoch_ms);
            serde_json::json!({ "status": "ok", "data": classified }).to_string()
        }

        CoreCommand::EvaluateRetry { input } => {
            let decision = evaluate_retry(&input);
            serde_json::json!({ "status": "ok", "data": decision }).to_string()
        }

        CoreCommand::ParseRetryAfterMs {
            headers,
            now_epoch_ms,
        } => {
            let ms = parse_retry_after_ms(&headers, now_epoch_ms);
            serde_json::json!({ "status": "ok", "data": { "retryAfterMs": ms } }).to_string()
        }

        CoreCommand::ComputeBackoffMs {
            attempt,
            base_backoff_ms,
            max_backoff_ms,
            random_factor,
        } => {
            let delay_ms =
                compute_backoff_ms(attempt, base_backoff_ms, max_backoff_ms, random_factor);
            serde_json::json!({ "status": "ok", "data": { "delayMs": delay_ms } }).to_string()
        }

        CoreCommand::ParseChatSse { raw_sse } => match parse_chat_sse_payload(&raw_sse) {
            Ok(res) => serde_json::json!({ "status": "ok", "data": res }).to_string(),
            Err(e) => serde_json::json!({ "status": "err", "error": e }).to_string(),
        },

        CoreCommand::ParseResponsesSse { raw_sse } => match parse_responses_sse_payload(&raw_sse) {
            Ok(res) => serde_json::json!({ "status": "ok", "data": res }).to_string(),
            Err(e) => serde_json::json!({ "status": "err", "error": e }).to_string(),
        },

        CoreCommand::ValidateSttSampleRate { sample_rate } => {
            match validate_stt_sample_rate(sample_rate) {
                Ok(()) => serde_json::json!({ "status": "ok", "data": { "valid": true } }).to_string(),
                Err(classified) => serde_json::json!({
                    "status": "err",
                    "error": classified.message,
                    "details": classified
                })
                .to_string(),
            }
        }

        CoreCommand::BuildSttWsConnection {
            environment,
            credentials,
            config,
        } => {
            let env = environment.unwrap_or_default();
            match build_stt_ws_connection(&env, &credentials, &config) {
                Ok(spec) => serde_json::json!({ "status": "ok", "data": spec }).to_string(),
                Err(classified) => serde_json::json!({
                    "status": "err",
                    "error": classified.message,
                    "details": classified
                })
                .to_string(),
            }
        }

        CoreCommand::ParseSttWsEvent { raw_json } => {
            let ev = parse_stt_ws_event(&raw_json);
            serde_json::json!({ "status": "ok", "data": ev }).to_string()
        }

        CoreCommand::EncodeSttAudioFrame { pcm_bytes } => {
            let frame = encode_stt_audio_frame(&pcm_bytes);
            serde_json::json!({ "status": "ok", "data": { "frame": frame } }).to_string()
        }

        CoreCommand::BuildTtsWsConnection {
            environment,
            credentials,
            config,
        } => {
            let env = environment.unwrap_or_default();
            let spec = build_tts_ws_connection(&env, &credentials, &config);
            serde_json::json!({ "status": "ok", "data": spec }).to_string()
        }

        CoreCommand::ParseTtsWsEvent { raw_json } => {
            let ev = parse_tts_ws_event(&raw_json);
            serde_json::json!({ "status": "ok", "data": ev }).to_string()
        }

        CoreCommand::EncodeTtsTextFrame { text } => {
            let frame = encode_tts_text_frame(&text);
            serde_json::json!({ "status": "ok", "data": { "frame": frame } }).to_string()
        }

        CoreCommand::ResamplePcm16 {
            input_bytes,
            input_sample_rate,
            channel_count,
        } => {
            let out = resample_pcm16(&input_bytes, input_sample_rate, channel_count);
            serde_json::json!({ "status": "ok", "data": { "pcm16Bytes": out } }).to_string()
        }

        CoreCommand::ResampleFloat32Bytes {
            input_bytes,
            input_sample_rate,
            channel_count,
        } => {
            let out = resample_float32_bytes(&input_bytes, input_sample_rate, channel_count);
            serde_json::json!({ "status": "ok", "data": { "pcm16Bytes": out } }).to_string()
        }

        CoreCommand::CalculateAudioLevels { pcm16_bytes } => {
            let levels = calculate_audio_levels(&pcm16_bytes);
            serde_json::json!({ "status": "ok", "data": levels }).to_string()
        }

        CoreCommand::DecodeBase64Audio { base64_str } => match decode_base64_audio(&base64_str) {
            Ok(bytes) => serde_json::json!({
                "status": "ok",
                "data": {
                    "byteLength": bytes.len(),
                    "bytes": bytes
                }
            })
            .to_string(),
            Err(e) => serde_json::json!({ "status": "err", "error": e }).to_string(),
        },

        CoreCommand::CheckTokenProactiveRefresh {
            cached_token,
            expires_at_epoch_ms,
            now_epoch_ms,
        } => {
            let state = TokenCacheState {
                cached_token,
                expires_at_epoch_ms,
                refresh_count: 0,
            };
            let valid = state.is_valid_at(now_epoch_ms);
            serde_json::json!({
                "status": "ok",
                "data": {
                    "isValid": valid,
                    "needsRefresh": !valid
                }
            })
            .to_string()
        }
    }
}

// ============================================================================
// C-ABI Exports (Swift, Dart FFI, C/C++, React Native JSI)
// ============================================================================

fn to_c_string(s: String) -> *mut c_char {
    CString::new(s)
        .unwrap_or_else(|_| CString::new(r#"{"status":"err","error":"NUL byte"}"#).unwrap())
        .into_raw()
}

fn from_c_str(ptr: *const c_char) -> Option<String> {
    if ptr.is_null() {
        return None;
    }
    unsafe { CStr::from_ptr(ptr).to_str().ok().map(|s| s.to_string()) }
}

/// Returns the version metadata of `libsarvam_rust_core` as a C string.
/// Caller must free with `sarvam_rust_free_string`.
#[no_mangle]
pub extern "C" fn sarvam_rust_version() -> *mut c_char {
    to_c_string(dispatch_command_json(r#"{"op":"version"}"#))
}

/// Invokes any command on `libsarvam_rust_core` via JSON-encoded `CoreCommand` and returns a JSON `CoreResponse`.
/// Caller must free the returned string with `sarvam_rust_free_string`.
#[no_mangle]
pub extern "C" fn sarvam_rust_invoke_json(command_json: *const c_char) -> *mut c_char {
    let Some(cmd_str) = from_c_str(command_json) else {
        return to_c_string(r#"{"status":"err","error":"Null command_json pointer"}"#.to_string());
    };
    to_c_string(dispatch_command_json(&cmd_str))
}

/// Zero-JSON-overhead binary PCM16 resampler to 16kHz mono linear-16 LE.
/// Writes `[out_len, out_cap]` as two `u64` values into `out_meta_u64_pair`.
/// Caller must free the returned buffer with `sarvam_rust_free_bytes(ptr, out_len, out_cap)`.
#[no_mangle]
pub extern "C" fn sarvam_rust_resample_pcm16(
    input_ptr: *const u8,
    input_len: usize,
    input_sample_rate: u32,
    channel_count: u16,
    out_meta_u64_pair: *mut u64,
) -> *mut u8 {
    if input_ptr.is_null() || input_len == 0 {
        if !out_meta_u64_pair.is_null() {
            unsafe {
                let meta = slice::from_raw_parts_mut(out_meta_u64_pair, 2);
                meta[0] = 0;
                meta[1] = 0;
            }
        }
        return std::ptr::null_mut();
    }

    let input_slice = unsafe { slice::from_raw_parts(input_ptr, input_len) };
    let mut resampled = resample_pcm16(input_slice, input_sample_rate, channel_count);
    resampled.shrink_to_fit();

    let ptr = resampled.as_mut_ptr();
    let len = resampled.len();
    let cap = resampled.capacity();
    std::mem::forget(resampled);

    if !out_meta_u64_pair.is_null() {
        unsafe {
            let meta = slice::from_raw_parts_mut(out_meta_u64_pair, 2);
            meta[0] = len as u64;
            meta[1] = cap as u64;
        }
    }
    ptr
}

/// Allocates `size` bytes in Rust heap memory for FFI callers (e.g. Dart `dart:ffi` without `package:ffi`).
/// Caller must free with `sarvam_rust_dealloc(ptr, size)`.
#[no_mangle]
pub extern "C" fn sarvam_rust_alloc(size: usize) -> *mut u8 {
    if size == 0 {
        return std::ptr::null_mut();
    }
    let mut buf = vec![0u8; size];
    buf.shrink_to_fit();
    let ptr = buf.as_mut_ptr();
    std::mem::forget(buf);
    ptr
}

/// Frees a buffer allocated by `sarvam_rust_alloc(size)`.
#[no_mangle]
pub extern "C" fn sarvam_rust_dealloc(ptr: *mut u8, size: usize) {
    if !ptr.is_null() && size > 0 {
        unsafe {
            let _ = Vec::from_raw_parts(ptr, size, size);
        }
    }
}

/// Invokes a UTF-8 JSON command from raw `(input_ptr, input_len)` bytes and writes `[out_len, out_cap]`
/// as two `u64` values into `out_meta_u64_pair` (which must point to at least 2 `u64`s / 16 bytes).
/// Caller must free the returned pointer with `sarvam_rust_free_bytes(ptr, out_len, out_cap)`.
#[no_mangle]
pub extern "C" fn sarvam_rust_invoke_bytes(
    input_ptr: *const u8,
    input_len: usize,
    out_meta_u64_pair: *mut u64,
) -> *mut u8 {
    let cmd_str = if input_ptr.is_null() || input_len == 0 {
        ""
    } else {
        let slice = unsafe { slice::from_raw_parts(input_ptr, input_len) };
        std::str::from_utf8(slice).unwrap_or("")
    };

    let response = dispatch_command_json(cmd_str);
    let mut bytes = response.into_bytes();
    bytes.shrink_to_fit();

    let ptr = bytes.as_mut_ptr();
    let len = bytes.len();
    let cap = bytes.capacity();
    std::mem::forget(bytes);

    if !out_meta_u64_pair.is_null() {
        unsafe {
            let meta = slice::from_raw_parts_mut(out_meta_u64_pair, 2);
            meta[0] = len as u64;
            meta[1] = cap as u64;
        }
    }
    ptr
}

/// Frees a C string returned by `sarvam_rust_*`.
#[no_mangle]
pub extern "C" fn sarvam_rust_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe {
            let _ = CString::from_raw(ptr);
        }
    }
}

/// Frees a byte buffer returned by `sarvam_rust_resample_pcm16` or `sarvam_rust_invoke_bytes`.
#[no_mangle]
pub extern "C" fn sarvam_rust_free_bytes(ptr: *mut u8, len: usize, cap: usize) {
    if !ptr.is_null() && cap > 0 {
        unsafe {
            let _ = Vec::from_raw_parts(ptr, len, cap);
        }
    }
}

// ============================================================================
// WebAssembly Exports (TypeScript / Web / React Native)
// ============================================================================

#[no_mangle]
pub extern "C" fn sarvam_wasm_alloc(size: usize) -> *mut u8 {
    let mut buf = Vec::with_capacity(size);
    let ptr = buf.as_mut_ptr();
    std::mem::forget(buf);
    ptr
}

#[no_mangle]
pub extern "C" fn sarvam_wasm_dealloc(ptr: *mut u8, size: usize) {
    if !ptr.is_null() && size > 0 {
        unsafe {
            let _ = Vec::from_raw_parts(ptr, 0, size);
        }
    }
}

/// Executes a UTF-8 JSON command at `(ptr, len)` in Wasm linear memory and returns a packed `u64`:
/// high 32 bits = pointer to UTF-8 JSON response, low 32 bits = byte length (allocated with capacity == length).
#[no_mangle]
pub extern "C" fn sarvam_wasm_invoke_json(ptr: *const u8, len: usize) -> u64 {
    let input_str = if ptr.is_null() || len == 0 {
        ""
    } else {
        let slice = unsafe { slice::from_raw_parts(ptr, len) };
        std::str::from_utf8(slice).unwrap_or("")
    };
    let response = dispatch_command_json(input_str);
    let mut bytes = response.into_bytes();
    bytes.shrink_to_fit();
    let out_ptr = bytes.as_mut_ptr() as usize as u64;
    let out_len = bytes.len() as u64;
    std::mem::forget(bytes);
    (out_ptr << 32) | (out_len & 0xFFFF_FFFF)
}

/// Fast binary PCM16 resampler in Wasm linear memory. Returns packed `u64` (`(out_ptr << 32) | out_len`).
#[no_mangle]
pub extern "C" fn sarvam_wasm_resample_pcm16(
    ptr: *const u8,
    len: usize,
    input_sample_rate: u32,
    channel_count: u32,
) -> u64 {
    if ptr.is_null() || len == 0 {
        return 0;
    }
    let slice = unsafe { slice::from_raw_parts(ptr, len) };
    let mut out = resample_pcm16(slice, input_sample_rate, channel_count as u16);
    out.shrink_to_fit();
    let out_ptr = out.as_mut_ptr() as usize as u64;
    let out_len = out.len() as u64;
    std::mem::forget(out);
    (out_ptr << 32) | (out_len & 0xFFFF_FFFF)
}

// ============================================================================
// Direct JNI Exports for Android / Kotlin (`ai.sarvam.rust.SarvamRustBridge`)
// Zero third-party JNI/JNA crate dependencies required!
// ============================================================================

#[cfg(not(target_arch = "wasm32"))]
mod jni_bridge {
    use super::*;
    use std::ffi::c_void;

    type JniEnv = *mut *const JniNativeInterface;
    type JObject = *mut c_void;
    type JClass = *mut c_void;
    type JString = *mut c_void;
    type JByteArray = *mut c_void;
    type JBoolean = u8;
    type JInt = i32;
    type JSize = i32;

    #[repr(C)]
    pub struct JniNativeInterface {
        reserved: [*const c_void; 167],
        new_string_utf: unsafe extern "system" fn(env: JniEnv, utf: *const c_char) -> JString,
        get_string_utf_length: unsafe extern "system" fn(env: JniEnv, string: JString) -> JSize,
        get_string_utf_chars: unsafe extern "system" fn(
            env: JniEnv,
            string: JString,
            is_copy: *mut JBoolean,
        ) -> *const c_char,
        release_string_utf_chars:
            unsafe extern "system" fn(env: JniEnv, string: JString, chars: *const c_char),
        get_array_length: unsafe extern "system" fn(env: JniEnv, array: JObject) -> JSize,
        new_object_array: *const c_void,
        get_object_array_element: *const c_void,
        set_object_array_element: *const c_void,
        new_boolean_array: *const c_void,
        new_byte_array: unsafe extern "system" fn(env: JniEnv, len: JSize) -> JByteArray,
        new_char_array: *const c_void,
        new_short_array: *const c_void,
        new_int_array: *const c_void,
        new_long_array: *const c_void,
        new_float_array: *const c_void,
        new_double_array: *const c_void,
        get_boolean_array_elements: *const c_void,
        get_byte_array_elements: unsafe extern "system" fn(
            env: JniEnv,
            array: JByteArray,
            is_copy: *mut JBoolean,
        ) -> *mut i8,
        get_char_array_elements: *const c_void,
        get_short_array_elements: *const c_void,
        get_int_array_elements: *const c_void,
        get_long_array_elements: *const c_void,
        get_float_array_elements: *const c_void,
        get_double_array_elements: *const c_void,
        release_boolean_array_elements: *const c_void,
        release_byte_array_elements: unsafe extern "system" fn(
            env: JniEnv,
            array: JByteArray,
            elems: *mut i8,
            mode: JInt,
        ),
        release_char_array_elements: *const c_void,
        release_short_array_elements: *const c_void,
        release_int_array_elements: *const c_void,
        release_long_array_elements: *const c_void,
        release_float_array_elements: *const c_void,
        release_double_array_elements: *const c_void,
        get_boolean_array_region: *const c_void,
        get_byte_array_region: *const c_void,
        get_char_array_region: *const c_void,
        get_short_array_region: *const c_void,
        get_int_array_region: *const c_void,
        get_long_array_region: *const c_void,
        get_float_array_region: *const c_void,
        get_double_array_region: *const c_void,
        set_boolean_array_region: *const c_void,
        set_byte_array_region: unsafe extern "system" fn(
            env: JniEnv,
            array: JByteArray,
            start: JSize,
            len: JSize,
            buf: *const i8,
        ),
    }

    #[no_mangle]
    pub unsafe extern "system" fn Java_ai_sarvam_rust_SarvamRustBridge_nativeInvokeJson(
        env: JniEnv,
        _class: JClass,
        command_json: JString,
    ) -> JString {
        let iface = &**env;
        if command_json.is_null() {
            let err_c = CString::new(r#"{"status":"err","error":"Null commandJson"}"#).unwrap();
            return (iface.new_string_utf)(env, err_c.as_ptr());
        }

        let chars = (iface.get_string_utf_chars)(env, command_json, std::ptr::null_mut());
        let input = if chars.is_null() {
            String::new()
        } else {
            let s = CStr::from_ptr(chars).to_string_lossy().into_owned();
            (iface.release_string_utf_chars)(env, command_json, chars);
            s
        };

        let response = dispatch_command_json(&input);
        let c_resp = CString::new(response).unwrap_or_else(|_| {
            CString::new(r#"{"status":"err","error":"NUL byte in response"}"#).unwrap()
        });
        (iface.new_string_utf)(env, c_resp.as_ptr())
    }

    #[no_mangle]
    pub unsafe extern "system" fn Java_ai_sarvam_rust_SarvamRustBridge_nativeResamplePcm16(
        env: JniEnv,
        _class: JClass,
        input_bytes: JByteArray,
        input_sample_rate: JInt,
        channel_count: JInt,
    ) -> JByteArray {
        let iface = &**env;
        if input_bytes.is_null() {
            return (iface.new_byte_array)(env, 0);
        }

        let len = (iface.get_array_length)(env, input_bytes);
        if len <= 0 {
            return (iface.new_byte_array)(env, 0);
        }

        let elems = (iface.get_byte_array_elements)(env, input_bytes, std::ptr::null_mut());
        if elems.is_null() {
            return (iface.new_byte_array)(env, 0);
        }

        let slice = slice::from_raw_parts(elems as *const u8, len as usize);
        let resampled = resample_pcm16(slice, input_sample_rate as u32, channel_count as u16);
        // JNI_ABORT = 2 (do not copy back changes to input array)
        (iface.release_byte_array_elements)(env, input_bytes, elems, 2);

        let out_arr = (iface.new_byte_array)(env, resampled.len() as JSize);
        if !out_arr.is_null() && !resampled.is_empty() {
            (iface.set_byte_array_region)(
                env,
                out_arr,
                0,
                resampled.len() as JSize,
                resampled.as_ptr() as *const i8,
            );
        }
        out_arr
    }
}
