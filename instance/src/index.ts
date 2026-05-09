// DEN instance — entry point.
//
// Startup order matters:
//   1. initDb() — creates the SQLite file and all tables if they don't exist yet.
//      Everything that follows depends on the DB being ready.
//   2. Route registration — all route modules import getDb() which requires initDb()
//      to have been called first.
//   3. Export the Hono app — Bun's HTTP server picks this up automatically.
//
// To run locally:
//   cp .env.example .env   (fill in contract addresses and RPC_URL)
//   bun run src/index.ts
//
// For live-reload during development:
//   bun --watch run src/index.ts

import { Hono } from 'hono';
import { initDb } from './db/index.ts';
import { loadInstanceMasterKey } from './crypto/blob.ts';
import { authRoutes } from './auth/routes.ts';
import { accessRoutes } from './access/routes.ts';

initDb();
loadInstanceMasterKey();

const app = new Hono();

app.route('/auth', authRoutes);
app.route('/access', accessRoutes);

app.onError((err, c) => {
  console.error('[error]', err);
  return c.json({ error: 'internal server error' }, 500);
});

const port = Number(process.env.PORT ?? 3000);
console.log(`DEN instance listening on port ${port}`);

export default { port, fetch: app.fetch };
