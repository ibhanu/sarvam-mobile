import { SarvamEnvironment } from './environment.js';

export type SarvamCredentials =
  | { readonly kind: 'subscriptionKey'; readonly key: string }
  | { readonly kind: 'bearerToken'; readonly token: string; readonly expiresAtEpochMs?: number }
  | { readonly kind: 'customHeaders'; readonly headers: Record<string, string> };

export interface AuthProvider {
  getCredentials(): Promise<SarvamCredentials>;
  invalidate?(): void;
}

/**
 * Static subscription key auth provider.
 */
export class ApiKeyAuth implements AuthProvider {
  private static warned = false;
  readonly key: string;

  constructor(apiKey: string) {
    if (!apiKey || typeof apiKey !== 'string' || apiKey.trim() === '') {
      throw new Error('ApiKeyAuth: API key must be a non-empty string');
    }
    this.key = apiKey.trim();

    // In mobile release builds (__DEV__ === false), emit a one-time warning
    if (!ApiKeyAuth.warned && (globalThis as Record<string, unknown>).__DEV__ === false) {
      ApiKeyAuth.warned = true;
      console.warn(
        '[@sarvam/core] Warning: Bundling static API keys into mobile release builds is insecure. ' +
          'Use TokenAuth or ProxyAuth in production mobile applications.'
      );
    }
  }

  async getCredentials(): Promise<SarvamCredentials> {
    return {
      kind: 'subscriptionKey',
      key: this.key,
    };
  }
}

export interface AuthToken {
  token: string;
  expiresAtEpochMs?: number;
}

export type TokenProvider = () => Promise<AuthToken | string>;

export interface TokenAuthOptions {
  /**
   * Pre-emptive refresh buffer in milliseconds before token expiration.
   * Defaults to 60,000 ms (60 seconds).
   */
  expiryBufferMs?: number;
}

/**
 * Ephemeral token authentication provider with in-memory caching,
 * proactive refresh, and single-flight deduplication.
 */
export class TokenAuth implements AuthProvider {
  private readonly tokenProvider: TokenProvider;
  private readonly expiryBufferMs: number;
  private cachedToken: AuthToken | null = null;
  private inFlightPromise: Promise<AuthToken> | null = null;

  constructor(tokenProvider: TokenProvider, options?: TokenAuthOptions) {
    if (typeof tokenProvider !== 'function') {
      throw new Error('TokenAuth: tokenProvider must be a function');
    }
    this.tokenProvider = tokenProvider;
    this.expiryBufferMs = options?.expiryBufferMs ?? 60_000;
  }

  invalidate(): void {
    this.cachedToken = null;
    this.inFlightPromise = null;
  }

  private isTokenValid(token: AuthToken): boolean {
    if (token.expiresAtEpochMs === undefined) {
      return true; // No expiration indicated
    }
    const now = Date.now();
    return now + this.expiryBufferMs < token.expiresAtEpochMs;
  }

  private async fetchToken(): Promise<AuthToken> {
    const raw = await this.tokenProvider();
    if (typeof raw === 'string') {
      return { token: raw };
    }
    if (!raw || typeof raw.token !== 'string') {
      throw new Error('TokenAuth: tokenProvider must return a string or an object with a string token');
    }
    return raw;
  }

  async getCredentials(): Promise<SarvamCredentials> {
    if (this.cachedToken && this.isTokenValid(this.cachedToken)) {
      return {
        kind: 'bearerToken',
        token: this.cachedToken.token,
        expiresAtEpochMs: this.cachedToken.expiresAtEpochMs,
      };
    }

    // Single-flight deduplication
    if (!this.inFlightPromise) {
      this.inFlightPromise = this.fetchToken()
        .then((fetched) => {
          this.cachedToken = fetched;
          this.inFlightPromise = null;
          return fetched;
        })
        .catch((err) => {
          this.inFlightPromise = null;
          throw err;
        });
    }

    const tokenObj = await this.inFlightPromise;
    return {
      kind: 'bearerToken',
      token: tokenObj.token,
      expiresAtEpochMs: tokenObj.expiresAtEpochMs,
    };
  }
}

export type CustomHeadersProvider =
  | (() => Promise<Record<string, string>> | Record<string, string>)
  | Record<string, string>;

/**
 * Proxy / BFF authentication provider for routing requests through a backend-for-frontend.
 */
export class ProxyAuth implements AuthProvider {
  readonly environment: SarvamEnvironment;
  private readonly headersProvider?: CustomHeadersProvider;

  constructor(proxyBaseUrl: string, headersProvider?: CustomHeadersProvider) {
    this.environment = SarvamEnvironment.proxy(proxyBaseUrl);
    this.headersProvider = headersProvider;
  }

  async getCredentials(): Promise<SarvamCredentials> {
    let headers: Record<string, string> = {};
    if (typeof this.headersProvider === 'function') {
      headers = await this.headersProvider();
    } else if (this.headersProvider) {
      headers = this.headersProvider;
    }
    return {
      kind: 'customHeaders',
      headers,
    };
  }
}
