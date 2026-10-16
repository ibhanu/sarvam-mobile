#!/usr/bin/env node

import { createMockServer } from './server.js';

function parsePort(): number {
  const args = process.argv.slice(2);
  const portIdx = args.indexOf('--port');
  if (portIdx !== -1 && args[portIdx + 1]) {
    return parseInt(args[portIdx + 1], 10);
  }
  if (process.env.PORT) {
    return parseInt(process.env.PORT, 10);
  }
  return 8080;
}

async function main() {
  const port = parsePort();
  const server = createMockServer({
    port,
    debug: true,
  });

  await server.start();
  console.log(`[Sarvam Mock Server] Listening on ${server.url} (ws: ${server.wsUrl})`);
  console.log(`[Sarvam Mock Server] Press Ctrl+C to stop.`);

  const shutdown = async () => {
    console.log('\n[Sarvam Mock Server] Shutting down...');
    await server.stop();
    process.exit(0);
  };

  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);
}

main().catch((err) => {
  console.error('[Sarvam Mock Server] Failed to start:', err);
  process.exit(1);
});
