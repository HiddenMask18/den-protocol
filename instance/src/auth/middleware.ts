// Session validation middleware for protected routes.
//
// Once a participant authenticates via /auth/verify, they receive a session token.
// They include this token as a Bearer token on every subsequent request:
//
//   Authorization: Bearer <token>
//
// This middleware checks the token against the sessions table, validates it hasn't expired,
// and makes the session's proxy and wallet available to route handlers via Hono context:
//
//   const proxy = c.get('proxy')   // the stable DEN identity
//   const wallet = c.get('wallet') // the wallet that authenticated this session
//
// All routes that touch participant-specific data should use this middleware.

import type { Context, Next } from 'hono';
import { getDb } from '../db/index.ts';

type SessionRow = {
  proxy: string;
  wallet: string;
  expires_at: number;
};

export async function requireAuth(c: Context, next: Next): Promise<Response | void> {
  const authHeader = c.req.header('Authorization');
  if (!authHeader?.startsWith('Bearer ')) {
    return c.json({ error: 'authentication required — include Authorization: Bearer <token> header' }, 401);
  }

  const token = authHeader.slice(7);

  const session = getDb()
    .query<SessionRow, [string]>('SELECT proxy, wallet, expires_at FROM sessions WHERE token = ?')
    .get(token);

  if (!session) {
    return c.json({ error: 'invalid session token' }, 401);
  }

  if (Date.now() > session.expires_at) {
    // Clean up expired session immediately rather than waiting for a sweep.
    getDb().run('DELETE FROM sessions WHERE token = ?', [token]);
    return c.json({ error: 'session expired — re-authenticate at /auth/challenge + /auth/verify' }, 401);
  }

  c.set('proxy', session.proxy);
  c.set('wallet', session.wallet);

  await next();
}
