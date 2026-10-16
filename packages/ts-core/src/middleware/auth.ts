import { AuthProvider, SarvamCredentials } from '../auth.js';
import { AuthenticationError, createHttpError } from '../errors.js';
import { Middleware, NextHandler } from './types.js';
import { HttpRequest, HttpResponse } from '../transport/http.js';

function applyCredentials(headers: Record<string, string>, credentials: SarvamCredentials): Record<string, string> {
  const updated = { ...headers };
  switch (credentials.kind) {
    case 'subscriptionKey':
      updated['api-subscription-key'] = credentials.key;
      break;
    case 'bearerToken':
      updated['Authorization'] = `Bearer ${credentials.token}`;
      break;
    case 'customHeaders':
      for (const [k, v] of Object.entries(credentials.headers)) {
        updated[k] = v;
      }
      break;
  }
  return updated;
}

export function createAuthMiddleware(authProvider: AuthProvider): Middleware {
  return async (request: HttpRequest, next: NextHandler): Promise<HttpResponse> => {
    let credentials = await authProvider.getCredentials();
    const reqWithAuth: HttpRequest = {
      ...request,
      headers: applyCredentials(request.headers, credentials),
    };

    let response: HttpResponse;
    try {
      response = await next(reqWithAuth);
    } catch (err) {
      if (err instanceof AuthenticationError && authProvider.invalidate) {
        // Invalidate cached token and retry once
        authProvider.invalidate();
        credentials = await authProvider.getCredentials();
        const retriedReq: HttpRequest = {
          ...request,
          headers: applyCredentials(request.headers, credentials),
        };
        return await next(retriedReq);
      }
      throw err;
    }

    // If response status is 401 or (403 with invalid_api_key_error)
    if ((response.status === 401 || response.status === 403) && authProvider.invalidate) {
      const rawText = await response.text();
      const httpError = await createHttpError(response.status, rawText, (n) => response.headers.get(n));

      if (httpError instanceof AuthenticationError) {
        authProvider.invalidate();
        credentials = await authProvider.getCredentials();
        const retriedReq: HttpRequest = {
          ...request,
          headers: applyCredentials(request.headers, credentials),
        };
        return await next(retriedReq);
      }

      // If it wasn't AuthenticationError (e.g. PermissionDeniedError 403), reconstruct HttpResponse with the buffered body
      return {
        status: response.status,
        statusText: response.statusText,
        headers: response.headers,
        json: async <T = unknown>(): Promise<T> => JSON.parse(rawText) as T,
        text: async () => rawText,
        bytes: async () => new TextEncoder().encode(rawText),
        bodyStream: () => ({
          async *[Symbol.asyncIterator]() {
            yield new TextEncoder().encode(rawText);
          },
        }),
      };
    }

    return response;
  };
}
