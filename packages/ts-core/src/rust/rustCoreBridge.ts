import type { OperationKind } from '../generated/sarvamSpecGenerated.js';

export interface SarvamWasmExports {
  readonly memory: WebAssembly.Memory;
  sarvam_wasm_alloc(size: number): number;
  sarvam_wasm_dealloc(ptr: number, size: number): void;
  sarvam_wasm_invoke_json(ptr: number, len: number): bigint;
  sarvam_wasm_resample_pcm16(
    ptr: number,
    len: number,
    inputSampleRate: number,
    channelCount: number
  ): bigint;
}

export interface RustAudioLevel {
  readonly rms: number;
  readonly peak: number;
  readonly dbFs: number;
}

export interface RustClassifiedError {
  readonly type: string;
  readonly statusCode?: number;
  readonly code?: string;
  readonly message: string;
  readonly requestId?: string;
  readonly retryAfterMs?: number;
  readonly rawBody?: string;
  readonly shouldTriggerTokenRefresh: boolean;
  readonly isRetryableByStatus: boolean;
}

export type RustRetryDecision =
  | { readonly action: 'doNotRetry'; readonly reason: string }
  | { readonly action: 'refreshTokenAndRetryOnce' }
  | { readonly action: 'backoffAndRetry'; readonly delayMs: number };

export interface RustRetryEvaluationInput {
  readonly operationKind: OperationKind;
  readonly attempt: number;
  readonly maxRetries: number;
  readonly statusCode?: number;
  readonly headers?: Record<string, string>;
  readonly rawBody?: string;
  readonly isNetworkOrTimeoutError?: boolean;
  readonly isTimeoutError?: boolean;
  readonly isReplayableBody?: boolean;
  readonly hasIdempotencyKey?: boolean;
  readonly isTokenAuth?: boolean;
  readonly hasRefreshedToken?: boolean;
  readonly randomFactor?: number;
  readonly nowEpochMs?: number;
}

/**
 * Isomorphic WebAssembly bridge to the shared `sarvam_rust_core` binary
 * for TypeScript, Browser, and React Native (Hermes).
 */
export class SarvamRustCore {
  private readonly exports: SarvamWasmExports;
  private readonly encoder = new TextEncoder();
  private readonly decoder = new TextDecoder();

  public constructor(exports: SarvamWasmExports) {
    this.exports = exports;
  }

  /**
   * Instantiates `SarvamRustCore` from raw `.wasm` binary bytes (`Uint8Array` or `ArrayBuffer`).
   */
  public static async instantiate(wasmBinary: Uint8Array | ArrayBuffer): Promise<SarvamRustCore> {
    const result = (await WebAssembly.instantiate(
      wasmBinary as BufferSource,
      {}
    )) as unknown as WebAssembly.WebAssemblyInstantiatedSource | WebAssembly.Instance;
    const instance = 'instance' in result ? result.instance : result;
    return new SarvamRustCore(instance.exports as unknown as SarvamWasmExports);
  }

  /**
   * Invokes any command on the underlying Rust core engine via JSON dispatch.
   */
  public invoke<T>(command: Record<string, unknown>): T {
    const jsonBytes = this.encoder.encode(JSON.stringify(command));
    const inPtr = this.exports.sarvam_wasm_alloc(jsonBytes.byteLength);
    let packed: bigint;
    try {
      const memIn = new Uint8Array(this.exports.memory.buffer, inPtr, jsonBytes.byteLength);
      memIn.set(jsonBytes);
      packed = this.exports.sarvam_wasm_invoke_json(inPtr, jsonBytes.byteLength);
    } finally {
      this.exports.sarvam_wasm_dealloc(inPtr, jsonBytes.byteLength);
    }

    const outPtr = Number((packed >> 32n) & 0xffffffffn);
    const outLen = Number(packed & 0xffffffffn);
    let responseText: string;
    try {
      const memOut = new Uint8Array(this.exports.memory.buffer, outPtr, outLen);
      responseText = this.decoder.decode(memOut);
    } finally {
      this.exports.sarvam_wasm_dealloc(outPtr, outLen);
    }

    const parsed = JSON.parse(responseText) as
      | { status: 'ok'; data: T }
      | { status: 'err'; error: string };
    if (parsed.status === 'err') {
      throw new Error(parsed.error);
    }
    return parsed.data;
  }

  public version(): { rustCoreVersion: string; sdkVersion: string; specVersion: string } {
    return this.invoke({ op: 'version' });
  }

  public resolveEnvironment(proxyBaseUrl?: string): {
    apiBaseUrl: string;
    dubbingBaseUrl: string;
    wsBaseUrl: string;
  } {
    return this.invoke({ op: 'resolveEnvironment', proxyBaseUrl: proxyBaseUrl ?? null });
  }

  public classifyHttpError(
    statusCode: number,
    headers: Record<string, string>,
    rawBody: string,
    nowEpochMs = 0
  ): RustClassifiedError {
    return this.invoke({
      op: 'classifyHttpError',
      statusCode,
      headers,
      rawBody,
      nowEpochMs
    });
  }

  public evaluateRetry(input: RustRetryEvaluationInput): RustRetryDecision {
    return this.invoke({
      op: 'evaluateRetry',
      input: {
        operationKind: input.operationKind,
        attempt: input.attempt,
        maxRetries: input.maxRetries,
        statusCode: input.statusCode ?? null,
        headers: input.headers ?? {},
        rawBody: input.rawBody ?? '',
        isNetworkOrTimeoutError: input.isNetworkOrTimeoutError ?? false,
        isTimeoutError: input.isTimeoutError ?? false,
        isReplayableBody: input.isReplayableBody ?? true,
        hasIdempotencyKey: input.hasIdempotencyKey ?? false,
        isTokenAuth: input.isTokenAuth ?? false,
        hasRefreshedToken: input.hasRefreshedToken ?? false,
        randomFactor: input.randomFactor ?? 0.5,
        nowEpochMs: input.nowEpochMs ?? 0
      }
    });
  }

  public parseChatSse(rawSse: string): {
    chunks: Array<Record<string, unknown>>;
    accumulatedContent: string;
    finalUsage?: { prompt_tokens: number; completion_tokens: number; total_tokens: number };
    terminatedOnDone: boolean;
  } {
    return this.invoke({ op: 'parseChatSse', rawSse });
  }

  public parseResponsesSse(rawSse: string): {
    events: Array<{ event: string; data: Record<string, unknown>; isTerminal: boolean }>;
    terminatedOnEvent?: string;
    finalResponseStatus?: string;
  } {
    return this.invoke({ op: 'parseResponsesSse', rawSse });
  }

  public validateSttSampleRate(sampleRate: number): boolean {
    const res = this.invoke<{ valid: boolean }>({ op: 'validateSttSampleRate', sampleRate });
    return res.valid;
  }

  /**
   * High-throughput binary PCM16 resampler to 16kHz mono linear-16 LE executed directly in Wasm linear memory.
   */
  public resamplePcm16(
    inputBytes: Uint8Array,
    inputSampleRate: number,
    channelCount = 1
  ): Uint8Array {
    if (inputBytes.byteLength === 0) {
      return new Uint8Array(0);
    }
    const inPtr = this.exports.sarvam_wasm_alloc(inputBytes.byteLength);
    let packed: bigint;
    try {
      const memIn = new Uint8Array(this.exports.memory.buffer, inPtr, inputBytes.byteLength);
      memIn.set(inputBytes);
      packed = this.exports.sarvam_wasm_resample_pcm16(
        inPtr,
        inputBytes.byteLength,
        inputSampleRate,
        channelCount
      );
    } finally {
      this.exports.sarvam_wasm_dealloc(inPtr, inputBytes.byteLength);
    }

    if (packed === 0n) {
      return new Uint8Array(0);
    }

    const outPtr = Number((packed >> 32n) & 0xffffffffn);
    const outLen = Number(packed & 0xffffffffn);
    try {
      const memOut = new Uint8Array(this.exports.memory.buffer, outPtr, outLen);
      return new Uint8Array(memOut);
    } finally {
      this.exports.sarvam_wasm_dealloc(outPtr, outLen);
    }
  }

  public calculateAudioLevels(pcm16Bytes: Uint8Array): RustAudioLevel {
    return this.invoke({
      op: 'calculateAudioLevels',
      pcm16Bytes: Array.from(pcm16Bytes)
    });
  }
}
