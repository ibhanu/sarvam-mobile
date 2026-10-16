import {
  SARVAM_SDK_VERSION,
  SARVAM_SPEC_VERSION,
} from '../generated/sarvamSpecGenerated.js';
import { Middleware, NextHandler } from './types.js';
import { HttpRequest, HttpResponse } from '../transport/http.js';

export interface UserAgentMiddlewareOptions {
  customPrefix?: string;
  osInfo?: string;
  runtimeInfo?: string;
}

export function createUserAgentMiddleware(options?: UserAgentMiddlewareOptions): Middleware {
  const prefix = options?.customPrefix ?? `sarvam-ts-core/${SARVAM_SDK_VERSION}`;
  const spec = `spec/${SARVAM_SPEC_VERSION}`;
  const os = options?.osInfo ?? 'js';
  const runtime = options?.runtimeInfo ?? 'node';
  const userAgentString = `${prefix} (${spec}; ${os}; ${runtime})`;

  return async (request: HttpRequest, next: NextHandler): Promise<HttpResponse> => {
    const updatedHeaders: Record<string, string> = {
      ...request.headers,
      'User-Agent': userAgentString,
      'X-Sarvam-SDK-Version': SARVAM_SDK_VERSION,
    };

    return next({
      ...request,
      headers: updatedHeaders,
    });
  };
}
