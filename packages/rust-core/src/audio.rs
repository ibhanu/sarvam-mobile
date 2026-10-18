use base64::engine::general_purpose::STANDARD as BASE64_STD;
use base64::Engine;
use serde::{Deserialize, Serialize};

/// Target sample rate required by Sarvam Realtime STT (16 kHz).
pub const TARGET_SAMPLE_RATE: u32 = 16_000;

#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AudioLevel {
    pub rms: f64,
    pub peak: f64,
    pub db_fs: f64,
}

/// Resamples little-endian PCM16 audio (mono or stereo) to 16kHz mono linear-16 little-endian bytes.
pub fn resample_pcm16(
    input_bytes: &[u8],
    input_sample_rate: u32,
    channel_count: u16,
) -> Vec<u8> {
    if input_bytes.is_empty() || input_sample_rate == 0 || (channel_count != 1 && channel_count != 2) {
        return Vec::new();
    }

    let bytes_per_frame = 2 * (channel_count as usize);
    let num_frames = input_bytes.len() / bytes_per_frame;
    if num_frames == 0 {
        return Vec::new();
    }

    let mut mono_samples = Vec::with_capacity(num_frames);
    for i in 0..num_frames {
        let offset = i * bytes_per_frame;
        let left = i16::from_le_bytes([input_bytes[offset], input_bytes[offset + 1]]);
        if channel_count == 1 {
            mono_samples.push(left);
        } else {
            let right = i16::from_le_bytes([input_bytes[offset + 2], input_bytes[offset + 3]]);
            let mixed = ((left as i32) + (right as i32)) / 2;
            mono_samples.push(mixed as i16);
        }
    }

    if input_sample_rate == TARGET_SAMPLE_RATE {
        let mut out = Vec::with_capacity(num_frames * 2);
        for s in mono_samples {
            out.extend_from_slice(&s.to_le_bytes());
        }
        return out;
    }

    resample_mono_samples(&mono_samples, input_sample_rate)
}

/// Resamples little-endian Float32 audio (`[-1.0, 1.0]`, mono or stereo) to 16kHz mono linear-16 bytes.
pub fn resample_float32_bytes(
    input_bytes: &[u8],
    input_sample_rate: u32,
    channel_count: u16,
) -> Vec<u8> {
    if input_bytes.is_empty() || input_sample_rate == 0 || (channel_count != 1 && channel_count != 2) {
        return Vec::new();
    }

    let bytes_per_frame = 4 * (channel_count as usize);
    let num_frames = input_bytes.len() / bytes_per_frame;
    if num_frames == 0 {
        return Vec::new();
    }

    let mut mono_samples = Vec::with_capacity(num_frames);
    for i in 0..num_frames {
        let offset = i * bytes_per_frame;
        let left = f32::from_le_bytes([
            input_bytes[offset],
            input_bytes[offset + 1],
            input_bytes[offset + 2],
            input_bytes[offset + 3],
        ]);
        let mono_float = if channel_count == 1 {
            left
        } else {
            let right = f32::from_le_bytes([
                input_bytes[offset + 4],
                input_bytes[offset + 5],
                input_bytes[offset + 6],
                input_bytes[offset + 7],
            ]);
            (left + right) / 2.0
        };

        let clamped = mono_float.clamp(-1.0, 1.0);
        let scaled = (clamped * 32767.0).round() as i32;
        let short_val = scaled.clamp(i16::MIN as i32, i16::MAX as i32) as i16;
        mono_samples.push(short_val);
    }

    if input_sample_rate == TARGET_SAMPLE_RATE {
        let mut out = Vec::with_capacity(num_frames * 2);
        for s in mono_samples {
            out.extend_from_slice(&s.to_le_bytes());
        }
        return out;
    }

    resample_mono_samples(&mono_samples, input_sample_rate)
}

fn resample_mono_samples(mono_samples: &[i16], input_sample_rate: u32) -> Vec<u8> {
    let num_input = mono_samples.len();
    if num_input == 0 {
        return Vec::new();
    }

    let out_sample_count = (((num_input as u64) * (TARGET_SAMPLE_RATE as u64)
        + ((input_sample_rate / 2) as u64))
        / (input_sample_rate as u64)) as usize;

    let mut out = Vec::with_capacity(out_sample_count * 2);
    let ratio = (input_sample_rate as f64) / (TARGET_SAMPLE_RATE as f64);

    for i in 0..out_sample_count {
        let pos = (i as f64) * ratio;
        let idx = pos as usize;
        let frac = pos - (idx as f64);

        let s0 = mono_samples[idx.min(num_input - 1)] as f64;
        let s1 = mono_samples[(idx + 1).min(num_input - 1)] as f64;
        let interp = ((1.0 - frac) * s0 + frac * s1).round() as i32;
        let clamped = interp.clamp(i16::MIN as i32, i16::MAX as i32) as i16;
        out.extend_from_slice(&clamped.to_le_bytes());
    }

    out
}

/// Computes RMS, Peak amplitude (`0.0` to `1.0`), and dBFS (`-100.0` to `0.0`) from PCM16 audio bytes.
pub fn calculate_audio_levels(pcm16_bytes: &[u8]) -> AudioLevel {
    let num_samples = pcm16_bytes.len() / 2;
    if num_samples == 0 {
        return AudioLevel {
            rms: 0.0,
            peak: 0.0,
            db_fs: -100.0,
        };
    }

    let mut peak = 0.0_f64;
    let mut sum_squares = 0.0_f64;

    for i in 0..num_samples {
        let sample = i16::from_le_bytes([pcm16_bytes[i * 2], pcm16_bytes[i * 2 + 1]]);
        let normalized = ((sample as f64).abs() / 32768.0).min(1.0);
        if normalized > peak {
            peak = normalized;
        }
        sum_squares += normalized * normalized;
    }

    let rms = (sum_squares / (num_samples as f64)).sqrt().min(1.0);
    let db_fs = if rms > 0.00001 {
        (20.0 * rms.log10()).clamp(-100.0, 0.0)
    } else {
        -100.0
    };

    AudioLevel { rms, peak, db_fs }
}

/// Decodes a Base64 audio payload (such as `audios[0].audio` from TTS REST `/text-to-speech`) into raw bytes.
pub fn decode_base64_audio(base64_str: &str) -> Result<Vec<u8>, String> {
    BASE64_STD
        .decode(base64_str.trim().as_bytes())
        .map_err(|e| format!("Invalid Base64 audio payload: {e}"))
}
