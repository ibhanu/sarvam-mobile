/**
 * Pure JavaScript Base64 encoder and decoder.
 * Zero Node.js built-ins or external dependencies — safe for Hermes, React Native, and standard browsers.
 */

const B64_CHARS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

// Lookup table for decoding
const B64_LOOKUP = new Uint8Array(256);
for (let i = 0; i < 256; i++) {
  B64_LOOKUP[i] = 255; // default invalid marker
}
for (let i = 0; i < B64_CHARS.length; i++) {
  B64_LOOKUP[B64_CHARS.charCodeAt(i)] = i;
}
// Support URL-safe characters
B64_LOOKUP['-'.charCodeAt(0)] = 62;
B64_LOOKUP['_'.charCodeAt(0)] = 63;

/**
 * Decodes a Base64 string to a Uint8Array.
 */
export function base64ToBytes(base64: string): Uint8Array {
  // Strip whitespace
  const clean = base64.replace(/\s+/g, '');
  const len = clean.length;
  if (len === 0) {
    return new Uint8Array(0);
  }

  // Calculate padding
  let padding = 0;
  if (clean.endsWith('==')) {
    padding = 2;
  } else if (clean.endsWith('=')) {
    padding = 1;
  }

  const outputLen = Math.floor((len * 3) / 4) - padding;
  const bytes = new Uint8Array(outputLen);

  let byteIdx = 0;
  for (let i = 0; i < len; i += 4) {
    const c0 = B64_LOOKUP[clean.charCodeAt(i)] ?? 255;
    const c1 = B64_LOOKUP[clean.charCodeAt(i + 1)] ?? 255;
    const c2 = clean[i + 2] === '=' || clean[i + 2] === undefined ? 0 : (B64_LOOKUP[clean.charCodeAt(i + 2)] ?? 255);
    const c3 = clean[i + 3] === '=' || clean[i + 3] === undefined ? 0 : (B64_LOOKUP[clean.charCodeAt(i + 3)] ?? 255);

    if (c0 === 255 || c1 === 255 || c2 === 255 || c3 === 255) {
      throw new Error(`Invalid base64 character encountered during decoding`);
    }

    const triple = (c0 << 18) | (c1 << 12) | (c2 << 6) | c3;

    if (byteIdx < outputLen) {
      bytes[byteIdx++] = (triple >> 16) & 0xff;
    }
    if (byteIdx < outputLen) {
      bytes[byteIdx++] = (triple >> 8) & 0xff;
    }
    if (byteIdx < outputLen) {
      bytes[byteIdx++] = triple & 0xff;
    }
  }

  return bytes;
}

/**
 * Encodes a Uint8Array to a standard Base64 string.
 */
export function bytesToBase64(bytes: Uint8Array): string {
  const len = bytes.length;
  if (len === 0) {
    return '';
  }

  let result = '';
  let i = 0;

  for (; i + 2 < len; i += 3) {
    const b0 = bytes[i]!;
    const b1 = bytes[i + 1]!;
    const b2 = bytes[i + 2]!;

    const triple = (b0 << 16) | (b1 << 8) | b2;
    result +=
      B64_CHARS.charAt((triple >> 18) & 0x3f) +
      B64_CHARS.charAt((triple >> 12) & 0x3f) +
      B64_CHARS.charAt((triple >> 6) & 0x3f) +
      B64_CHARS.charAt(triple & 0x3f);
  }

  // Handle remaining 1 or 2 bytes
  if (i < len) {
    const b0 = bytes[i]!;
    if (i + 1 < len) {
      const b1 = bytes[i + 1]!;
      const triple = (b0 << 16) | (b1 << 8);
      result +=
        B64_CHARS.charAt((triple >> 18) & 0x3f) +
        B64_CHARS.charAt((triple >> 12) & 0x3f) +
        B64_CHARS.charAt((triple >> 6) & 0x3f) +
        '=';
    } else {
      const triple = b0 << 16;
      result +=
        B64_CHARS.charAt((triple >> 18) & 0x3f) +
        B64_CHARS.charAt((triple >> 12) & 0x3f) +
        '==';
    }
  }

  return result;
}

/**
 * Converts a hex string to Uint8Array.
 */
export function hexToBytes(hex: string): Uint8Array {
  const clean = hex.replace(/\s+/g, '');
  if (clean.length % 2 !== 0) {
    throw new Error('Hex string must have an even length');
  }
  const bytes = new Uint8Array(clean.length / 2);
  for (let i = 0; i < clean.length; i += 2) {
    bytes[i / 2] = parseInt(clean.substring(i, i + 2), 16);
  }
  return bytes;
}

/**
 * Converts a Uint8Array to a lowercase hex string.
 */
export function bytesToHex(bytes: Uint8Array): string {
  let hex = '';
  for (let i = 0; i < bytes.length; i++) {
    const b = bytes[i]!;
    hex += (b < 16 ? '0' : '') + b.toString(16);
  }
  return hex;
}
