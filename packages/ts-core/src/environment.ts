import {
  DEFAULT_API_BASE_URL,
  DEFAULT_DUBBING_BASE_URL,
  DEFAULT_WS_BASE_URL,
} from './generated/sarvamSpecGenerated.js';

export interface SarvamEnvironment {
  readonly apiBaseUrl: string;
  readonly dubbingBaseUrl: string;
  readonly wsBaseUrl: string;
}

function normalizeUrl(url: string): string {
  return url.replace(/\/+$/, '');
}

function deriveWsUrl(httpUrl: string): string {
  const clean = normalizeUrl(httpUrl);
  if (clean.startsWith('https://')) {
    return 'wss://' + clean.slice('https://'.length);
  }
  if (clean.startsWith('http://')) {
    return 'ws://' + clean.slice('http://'.length);
  }
  if (clean.startsWith('wss://') || clean.startsWith('ws://')) {
    return clean;
  }
  return `wss://${clean}`;
}

export const SarvamEnvironment = {
  production: {
    apiBaseUrl: DEFAULT_API_BASE_URL,
    dubbingBaseUrl: DEFAULT_DUBBING_BASE_URL,
    wsBaseUrl: DEFAULT_WS_BASE_URL,
  } as const satisfies SarvamEnvironment,

  proxy(baseUrl: string): SarvamEnvironment {
    const clean = normalizeUrl(baseUrl);
    return {
      apiBaseUrl: clean,
      dubbingBaseUrl: `${clean}/dubbing`,
      wsBaseUrl: deriveWsUrl(clean),
    };
  },

  custom(options: {
    apiBaseUrl: string;
    dubbingBaseUrl?: string;
    wsBaseUrl?: string;
  }): SarvamEnvironment {
    const apiBaseUrl = normalizeUrl(options.apiBaseUrl);
    return {
      apiBaseUrl,
      dubbingBaseUrl: options.dubbingBaseUrl
        ? normalizeUrl(options.dubbingBaseUrl)
        : `${apiBaseUrl}/dubbing`,
      wsBaseUrl: options.wsBaseUrl ? normalizeUrl(options.wsBaseUrl) : deriveWsUrl(apiBaseUrl),
    };
  },
};
