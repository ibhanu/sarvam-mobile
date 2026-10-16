#!/usr/bin/env node
/* node:coverage disable */
import { createNodeProxyServer } from './node-server.js';
import { ProxyConfig } from './router.js';

const port = process.env.PORT ? parseInt(process.env.PORT, 10) : 3000;
const host = process.env.HOST || '0.0.0.0';

const apiKey = process.env.SARVAM_API_KEY || process.env.SARVAM_MASTER_KEY;
if (!apiKey) {
  console.error('Error: SARVAM_API_KEY or SARVAM_MASTER_KEY environment variable is required');
  process.exit(1);
}

const tokenSecret = process.env.BFF_TOKEN_SECRET || process.env.TOKEN_SECRET;
if (!tokenSecret) {
  console.error('Error: BFF_TOKEN_SECRET or TOKEN_SECRET environment variable is required');
  process.exit(1);
}

const config: ProxyConfig = {
  sarvamApiKey: apiKey,
  tokenSecret,
  upstreamApiBaseUrl: process.env.UPSTREAM_API_BASE_URL || 'https://api.sarvam.ai',
  upstreamDubbingBaseUrl: process.env.UPSTREAM_DUBBING_BASE_URL || 'https://api.sarvam.ai/dubbing',
  upstreamWsBaseUrl: process.env.UPSTREAM_WS_BASE_URL || 'wss://api.sarvam.ai',
  rateLimitRpm: process.env.RATE_LIMIT_RPM ? parseInt(process.env.RATE_LIMIT_RPM, 10) : 60,
  tokenTtlSeconds: process.env.TOKEN_TTL_SECONDS ? parseInt(process.env.TOKEN_TTL_SECONDS, 10) : 900,
};

const server = createNodeProxyServer(config);
server
  .start(port, host)
  .then(({ url, wsUrl }) => {
    console.log(`[Sarvam BFF Proxy] HTTP service listening at ${url}`);
    console.log(`[Sarvam BFF Proxy] WebSocket service listening at ${wsUrl}`);
  })
  .catch((err) => {
    console.error('Failed to start Sarvam BFF Proxy:', err);
    process.exit(1);
  });
