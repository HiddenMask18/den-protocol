// HTTP routes for the authentication flow.
//
// Two endpoints:
//
//   GET /auth/challenge?wallet=0x...
//     Returns a one-time nonce. The client signs this nonce with their wallet
//     private key using EIP-191 personal_sign (standard "sign message" in all wallets).
//
//   POST /auth/verify
//     Body: { wallet: "0x...", nonce: "...", signature: "0x..." }
//     Verifies the signature, confirms the wallet is registered in DEN, resolves
//     the wallet to its proxy address, and issues a 24-hour session token.
//
// After a successful /auth/verify, the client stores the sessionToken and sends it
// as "Authorization: Bearer <sessionToken>" on all subsequent requests.

import { Hono } from 'hono';
import { randomBytes } from 'crypto';
import { issueNonce } from './nonce.ts';
import { verifyAuth } from './verify.ts';
import { getDb } from '../db/index.ts';

export const authRoutes = new Hono();

const SESSION_TTL_MS = 24 * 60 * 60 * 1000;

authRoutes.get('/challenge', (c) => {
  const wallet = c.req.query('wallet');
  if (!wallet || !wallet.startsWith('0x')) {
    return c.json({ error: 'wallet query param required (0x-prefixed Ethereum address)' }, 400);
  }

  const nonce = issueNonce(wallet);
  return c.json({ nonce });
});

authRoutes.post('/verify', async (c) => {
  let body: { wallet?: string; nonce?: string; signature?: string };
  try {
    body = await c.req.json();
  } catch {
    return c.json({ error: 'request body must be valid JSON' }, 400);
  }

  if (!body.wallet || !body.nonce || !body.signature) {
    return c.json({ error: 'wallet, nonce, and signature fields are all required' }, 400);
  }

  const result = await verifyAuth(
    body.wallet as `0x${string}`,
    body.nonce,
    body.signature as `0x${string}`,
  );

  if (!result.ok) {
    return c.json({ error: result.reason }, 401);
  }

  // Issue a random 32-byte session token and persist it.
  const token = randomBytes(32).toString('hex');
  const now = Date.now();

  getDb().run(
    'INSERT OR REPLACE INTO sessions (token, proxy, wallet, created_at, expires_at) VALUES (?, ?, ?, ?, ?)',
    [token, result.proxy, result.wallet, now, now + SESSION_TTL_MS],
  );

  return c.json({ sessionToken: token, proxy: result.proxy });
});
