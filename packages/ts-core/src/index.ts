/**
 * @sarvam/core
 * Official TypeScript Core SDK for Sarvam AI Indic language models and speech services.
 * Pure TypeScript, zero Node.js built-ins.
 */

// Re-export generated specification constants and open enum types
export * from './generated/sarvamSpecGenerated.js';

// Environment
export * from './environment.js';

// Auth
export * from './auth.js';

// Errors
export * from './errors.js';

// Transport
export * from './transport/http.js';
export * from './transport/websocket.js';

// Middleware
export * from './middleware/types.js';
export * from './middleware/userAgent.js';
export * from './middleware/auth.js';
export * from './middleware/retry.js';
export * from './middleware/logging.js';

// Streaming
export * from './streaming/sse.js';

// Utilities
export * from './utils/base64.js';
export * from './utils/timing.js';

// Resources
export * from './resources/types.js';
export * from './resources/text.js';
export * from './resources/speechToText.js';
export * from './resources/textToSpeech.js';
export * from './resources/chat.js';
export * from './resources/responses.js';
export * from './resources/jobs.js';
export * from './resources/polling.js';
export * from './resources/other.js';

// Client
export * from './client.js';

export const VERSION = '0.1.0';
