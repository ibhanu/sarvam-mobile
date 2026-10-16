/**
 * Ephemeral Token Minting & Verification for Sarvam AI Mobile SDKs.
 * Uses standard Web Crypto API (crypto.subtle) - zero external dependencies,
 * compatible with Cloudflare Workers, WinterCG Edge, and Node.js 20+.
 */

export type SarvamScope =
  | 'stt'
  | 'tts'
  | 'text'
  | 'chat'
  | 'doc_ai'
  | 'dubbing'
  | (string & {});

export const DEFAULT_SCOPES: SarvamScope[] = [
  'stt',
  'tts',
  'text',
  'chat',
  'doc_ai',
  'dubbing',
];

export interface TokenPayload {
  sub: string;
  iat: number; // Unix epoch in seconds
  exp: number; // Unix epoch in seconds
  expiresAtEpochMs: number; // Unix epoch in milliseconds
  scopes: string[];
  jti?: string;
}

export interface MintTokenOptions {
  secret: string;
  sub?: string;
  scopes?: string[];
  ttlSeconds?: number; // default 900 (15 minutes)
}

export interface MintTokenResult {
  token: string;
  expiresAtEpochMs: number;
}

/**
 * Base64URL encode a byte array.
 */
export function base64UrlEncode(bytes: Uint8Array): string {
  let binary = '';
  const len = bytes.byteLength;
  for (let i = 0; i < len; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  return btoa(binary)
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');
}

/**
 * Base64URL decode a string into a byte array.
 */
export function base64UrlDecode(str: string): Uint8Array {
  let base64 = str.replace(/-/g, '+').replace(/_/g, '/');
  while (base64.length % 4 !== 0) {
    base64 += '=';
  }
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

function stringToBase64Url(str: string): string {
  return base64UrlEncode(new TextEncoder().encode(str));
}

function base64UrlToString(str: string): string {
  return new TextDecoder().decode(base64UrlDecode(str));
}

/**
 * Import an HMAC-SHA256 CryptoKey using Web Crypto API.
 */
async function getHmacKey(secret: string, usages: KeyUsage[]): Promise<CryptoKey> {
  const enc = new TextEncoder();
  return await crypto.subtle.importKey(
    'raw',
    enc.encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    usages
  );
}

/**
 * Mints an HMAC-SHA256 signed stateless short-lived ephemeral token.
 */
export async function createEphemeralToken(
  options: MintTokenOptions
): Promise<MintTokenResult> {
  const {
    secret,
    sub = 'mobile-client',
    scopes = DEFAULT_SCOPES,
    ttlSeconds = 900, // 15 minutes default
  } = options;

  if (!secret || typeof secret !== 'string') {
    throw new Error('Token secret must be a non-empty string');
  }

  const nowEpochMs = Date.now();
  const expiresAtEpochMs = nowEpochMs + ttlSeconds * 1000;
  const iat = Math.floor(nowEpochMs / 1000);
  const exp = Math.floor(expiresAtEpochMs / 1000);

  const header = { alg: 'HS256', typ: 'JWT' };
  const payload: TokenPayload = {
    sub,
    iat,
    exp,
    expiresAtEpochMs,
    scopes,
    jti: `tok_${nowEpochMs.toString(36)}_${Math.random().toString(36).slice(2, 9)}`,
  };

  const encodedHeader = stringToBase64Url(JSON.stringify(header));
  const encodedPayload = stringToBase64Url(JSON.stringify(payload));
  const signingInput = `${encodedHeader}.${encodedPayload}`;

  const key = await getHmacKey(secret, ['sign']);
  const signatureBuffer = await crypto.subtle.sign(
    'HMAC',
    key,
    new TextEncoder().encode(signingInput)
  );

  const encodedSignature = base64UrlEncode(new Uint8Array(signatureBuffer));
  const token = `${signingInput}.${encodedSignature}`;

  return { token, expiresAtEpochMs };
}

/**
 * Verifies an HMAC-SHA256 signed token and checks expiration.
 * Throws an Error if the signature is invalid, token is tampered, or token is expired.
 */
export async function verifyEphemeralToken(
  token: string,
  secret: string
): Promise<TokenPayload> {
  if (!token || typeof token !== 'string') {
    throw new Error('Token must be a non-empty string');
  }

  const parts = token.split('.');
  if (parts.length !== 3) {
    throw new Error('Malformed token structure: expected header.payload.signature');
  }

  const [encodedHeader, encodedPayload, encodedSignature] = parts;

  // 1. Verify HMAC-SHA256 signature
  const key = await getHmacKey(secret, ['verify']);
  const signingInputBytes = new TextEncoder().encode(`${encodedHeader}.${encodedPayload}`);

  let signatureBytes: Uint8Array;
  try {
    signatureBytes = base64UrlDecode(encodedSignature);
  } catch {
    throw new Error('Invalid signature encoding');
  }

  const isSignatureValid = await crypto.subtle.verify(
    'HMAC',
    key,
    signatureBytes as unknown as BufferSource,
    signingInputBytes as unknown as BufferSource
  );

  if (!isSignatureValid) {
    throw new Error('Invalid token signature');
  }

  // 2. Decode and validate payload JSON
  let payload: TokenPayload;
  try {
    payload = JSON.parse(base64UrlToString(encodedPayload));
  } catch {
    throw new Error('Invalid token payload encoding');
  }

  // 3. Expiration verification
  const nowEpochSeconds = Math.floor(Date.now() / 1000);
  if (payload.exp !== undefined && payload.exp < nowEpochSeconds) {
    throw new Error(`Token expired at ${new Date(payload.exp * 1000).toISOString()}`);
  }

  return payload;
}

/**
 * Checks whether the given token scopes allow access to the specified request path.
 */
export function isScopeAllowedForPath(scopes: string[], pathname: string): boolean {
  if (!scopes || !Array.isArray(scopes)) return false;
  if (scopes.includes('*') || scopes.includes('all')) return true;

  const path = pathname.startsWith('/') ? pathname : '/' + pathname;

  if (path.startsWith('/speech-to-text')) return scopes.includes('stt');
  if (path.startsWith('/text-to-speech') || path.startsWith('/voices')) return scopes.includes('tts');
  if (
    path.startsWith('/translate') ||
    path.startsWith('/transliterate') ||
    path.startsWith('/text-lid')
  ) {
    return scopes.includes('text');
  }
  if (
    path.startsWith('/v1/chat') ||
    path.startsWith('/v2/chat') ||
    path.startsWith('/v2/responses') ||
    path.startsWith('/models')
  ) {
    return scopes.includes('chat');
  }
  if (path.startsWith('/doc-ai')) return scopes.includes('doc_ai');
  if (path.startsWith('/dubbing')) return scopes.includes('dubbing');
  if (path.startsWith('/pronunciation-dictionaries')) {
    return scopes.includes('tts') || scopes.includes('text');
  }

  // Permissive fallback for unmapped endpoints
  return true;
}

/**
 * Canonical Sarvam error response generator matching SarvamError contract:
 * {
 *   "error": {
 *     "code": "invalid_api_key_error",
 *     "message": "...",
 *     "request_id": "req_..."
 *   }
 * }
 */
export function createCanonicalErrorResponse(
  status: number,
  code: string,
  message: string,
  extraHeaders: Record<string, string> = {}
): Response {
  const requestId = `req_${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 7)}`;
  const body = JSON.stringify({
    error: {
      code,
      message,
      request_id: requestId,
    },
  });

  return new Response(body, {
    status,
    headers: {
      'Content-Type': 'application/json',
      'x-request-id': requestId,
      ...extraHeaders,
    },
  });
}

/**
 * Convenience helper for HTTP 403 invalid_api_key_error response.
 */
export function createAuthErrorResponse(
  message = 'Invalid or expired token',
  extraHeaders: Record<string, string> = {}
): Response {
  return createCanonicalErrorResponse(403, 'invalid_api_key_error', message, extraHeaders);
}
