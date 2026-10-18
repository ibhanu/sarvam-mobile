use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SseRawEvent {
    pub event: Option<String>,
    pub data: String,
    pub id: Option<String>,
    pub retry: Option<u64>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ChatDelta {
    pub role: Option<String>,
    pub content: Option<String>,
    pub reasoning_content: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ChatChoiceChunk {
    pub index: u32,
    pub delta: ChatDelta,
    #[serde(alias = "finish_reason")]
    pub finish_reason: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ChatUsage {
    pub prompt_tokens: u32,
    pub completion_tokens: u32,
    pub total_tokens: u32,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ChatCompletionChunk {
    pub id: String,
    #[serde(default)]
    pub choices: Vec<ChatChoiceChunk>,
    pub usage: Option<ChatUsage>,
    pub first_delta_content: Option<String>,
}

impl ChatCompletionChunk {
    pub fn from_json(json_str: &str) -> Result<Self, String> {
        #[derive(Deserialize)]
        struct WireChunk {
            #[serde(default)]
            id: String,
            #[serde(default)]
            choices: Vec<ChatChoiceChunk>,
            usage: Option<ChatUsage>,
        }
        let wire: WireChunk =
            serde_json::from_str(json_str).map_err(|e| format!("Invalid ChatCompletionChunk: {e}"))?;
        let first_delta_content = wire
            .choices
            .first()
            .and_then(|c| c.delta.content.clone());
        Ok(Self {
            id: wire.id,
            choices: wire.choices,
            usage: wire.usage,
            first_delta_content,
        })
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ParsedChatSseStream {
    pub chunks: Vec<ChatCompletionChunk>,
    pub accumulated_content: String,
    pub final_usage: Option<ChatUsage>,
    pub terminated_on_done: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ResponsesSseEvent {
    pub event: String,
    pub data: serde_json::Value,
    pub is_terminal: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ParsedResponsesSseStream {
    pub events: Vec<ResponsesSseEvent>,
    pub terminated_on_event: Option<String>,
    pub final_response_status: Option<String>,
}

/// Incremental SSE parser handling arbitrary TCP chunk boundaries (`\n\n` and `\r\n\r\n`).
#[derive(Debug, Default, Clone)]
pub struct SseIncrementalParser {
    buffer: String,
}

impl SseIncrementalParser {
    pub fn new() -> Self {
        Self {
            buffer: String::new(),
        }
    }

    pub fn feed(&mut self, chunk_str: &str) -> Vec<SseRawEvent> {
        let normalized = chunk_str.replace("\r\n", "\n");
        self.buffer.push_str(&normalized);

        let mut out = Vec::new();
        while let Some(sep_idx) = self.buffer.find("\n\n") {
            let block = self.buffer[..sep_idx].to_string();
            self.buffer.drain(..sep_idx + 2);
            if let Some(ev) = parse_sse_block(&block) {
                out.push(ev);
            }
        }
        out
    }

    pub fn flush(&mut self) -> Vec<SseRawEvent> {
        let mut out = Vec::new();
        let remaining = self.buffer.trim().to_string();
        self.buffer.clear();
        if !remaining.is_empty() {
            if let Some(ev) = parse_sse_block(&remaining) {
                out.push(ev);
            }
        }
        out
    }
}

fn parse_sse_block(block: &str) -> Option<SseRawEvent> {
    let mut event: Option<String> = None;
    let mut data_lines: Vec<&str> = Vec::new();
    let mut id: Option<String> = None;
    let mut retry: Option<u64> = None;

    for line in block.lines() {
        if line.is_empty() || line.starts_with(':') {
            continue;
        }
        if let Some(rest) = line.strip_prefix("event:") {
            event = Some(rest.trim_start().to_string());
        } else if let Some(rest) = line.strip_prefix("data:") {
            data_lines.push(rest.strip_prefix(' ').unwrap_or(rest));
        } else if let Some(rest) = line.strip_prefix("id:") {
            id = Some(rest.trim_start().to_string());
        } else if let Some(rest) = line.strip_prefix("retry:") {
            if let Ok(r) = rest.trim().parse::<u64>() {
                retry = Some(r);
            }
        }
    }

    if data_lines.is_empty() && event.is_none() {
        return None;
    }

    Some(SseRawEvent {
        event,
        data: data_lines.join("\n"),
        id,
        retry,
    })
}

pub fn parse_chat_sse_payload(raw_sse: &str) -> Result<ParsedChatSseStream, String> {
    let mut parser = SseIncrementalParser::new();
    let mut raw_events = parser.feed(raw_sse);
    raw_events.extend(parser.flush());

    let mut chunks = Vec::new();
    let mut accumulated_content = String::new();
    let mut final_usage: Option<ChatUsage> = None;
    let mut terminated_on_done = false;

    for ev in raw_events {
        let trimmed = ev.data.trim();
        if trimmed.is_empty() {
            continue;
        }
        if trimmed == "[DONE]" {
            terminated_on_done = true;
            break;
        }
        let chunk = ChatCompletionChunk::from_json(trimmed)?;
        if let Some(ref text) = chunk.first_delta_content {
            accumulated_content.push_str(text);
        }
        if let Some(ref usage) = chunk.usage {
            final_usage = Some(usage.clone());
        }
        chunks.push(chunk);
    }

    Ok(ParsedChatSseStream {
        chunks,
        accumulated_content,
        final_usage,
        terminated_on_done,
    })
}

pub fn parse_responses_sse_payload(raw_sse: &str) -> Result<ParsedResponsesSseStream, String> {
    let mut parser = SseIncrementalParser::new();
    let mut raw_events = parser.feed(raw_sse);
    raw_events.extend(parser.flush());

    let mut events = Vec::new();
    let mut terminated_on_event = None;
    let mut final_response_status = None;

    for ev in raw_events {
        let trimmed = ev.data.trim();
        if trimmed.is_empty() || trimmed == "[DONE]" {
            continue;
        }
        let data: serde_json::Value = serde_json::from_str(trimmed)
            .map_err(|e| format!("Invalid Responses SSE JSON: {e}"))?;

        let event_name = ev
            .event
            .or_else(|| {
                data.get("type")
                    .and_then(|v| v.as_str())
                    .map(|s| s.to_string())
            })
            .unwrap_or_else(|| "message".to_string());

        let is_terminal = matches!(
            event_name.as_str(),
            "response.completed" | "response.failed" | "response.incomplete"
        );

        if is_terminal {
            terminated_on_event = Some(event_name.clone());
            final_response_status = data
                .get("response")
                .and_then(|r| r.get("status"))
                .and_then(|s| s.as_str())
                .map(|s| s.to_string());
        }

        events.push(ResponsesSseEvent {
            event: event_name,
            data,
            is_terminal,
        });

        if is_terminal {
            break;
        }
    }

    Ok(ParsedResponsesSseStream {
        events,
        terminated_on_event,
        final_response_status,
    })
}
