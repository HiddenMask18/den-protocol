// Content routes — encrypted ciphertext download, plus the subscriber-facing content inventory.
//
// GET /content/:fingerprint        — download ciphertext (auth required for private content)
// GET /content/by-creator/:proxy   — list a creator's content for a tier the caller holds
//
// --- GET /content/:fingerprint ---
//
// Returns the raw ciphertext bytes for a given content fingerprint. Authentication is required
// but subscription entitlement is NOT re-checked here — that gate is enforced by POST /access/key,
// which delivers the content key only after verifying on-chain entitlement. Ciphertext without
// the corresponding key is cryptographically useless: serving it to any authenticated participant
// does not constitute an access breach.
//
// The fingerprint is the SHA-256 hash of the ciphertext, matching what is registered on-chain
// in DENContentRegistry. It is the stable content identifier shared between the instance and
// the on-chain registry.

import { Hono } from 'hono';
import { getDb } from '../db/index.ts';
import { reportRegistry } from '../chain/contracts.ts';
import { requireAuth } from '../auth/middleware.ts';
import { checkSubscriptionAccess } from '../access/gate.ts';

// Declares the context variables set by requireAuth so TypeScript knows their types on
// the routes that use it (the public download route below does its own inline auth).
type SessionEnv = {
  Variables: {
    proxy: string;
    wallet: string;
  };
};

export const contentRoutes = new Hono<SessionEnv>();

// Subscriber-facing content inventory for one creator + tier.
//
// GET /content/by-creator/:proxy?tierId=N   (requireAuth)
//
// Lets an authenticated Subscriber enumerate the content a Creator published to a tier they
// hold. GET /profile/:proxy (unauthenticated) deliberately exposes only public content and
// *warned* paywalled posts as teasers — an unwarned paywalled post is invisible there. Without
// this endpoint a subscribed viewer cannot discover those posts to request keys for, so the
// subscriber feed (DESIGN Flow 5, /feed) cannot be assembled.
//
// Entitlement is gated per-tier by the same checkSubscriptionAccess() used by POST /access/key:
// the caller must hold an active on-chain subscription to (:proxy, tierId) and the creator must
// have a signature-valid access grant for it. This route is the sibling of key delivery — same
// gate, same per-tier model — returning the content inventory instead of the keys.
//
// Returns metadata only (fingerprint, tierId, timestamp, warnings) — no ciphertext, no keys.
// Suspension is not re-checked here (that would cost a chain read per item); the per-fingerprint
// GET /content/:fingerprint download gate remains the enforcement point for suspended content.
//
// The response is an object envelope, not a bare array, so cursor pagination can be added later
// without a breaking change. v1 returns the full tier inventory with nextCursor: null.
contentRoutes.get('/by-creator/:proxy', requireAuth, async (c) => {
  const { proxy } = c.req.param();
  const tierId = c.req.query('tierId');

  if (!/^0x[0-9a-fA-F]{40}$/.test(proxy)) {
    return c.json({ error: 'proxy must be a 0x-prefixed 40-char hex Ethereum address' }, 400);
  }
  if (tierId === undefined) {
    return c.json({ error: 'tierId query parameter is required' }, 400);
  }

  // Parse before the chain call so a non-numeric tierId yields a 400, not a 500.
  let numericTierId: bigint;
  try {
    numericTierId = BigInt(tierId);
  } catch {
    return c.json({ error: 'tierId must be a numeric string' }, 400);
  }

  const participantProxy = c.get('proxy') as `0x${string}`;
  const creator = proxy as `0x${string}`;

  // Live on-chain entitlement check — identical gate to POST /access/key (spec §4.1).
  let gateResult;
  try {
    gateResult = await checkSubscriptionAccess(participantProxy, creator, numericTierId);
  } catch {
    return c.json({ error: 'failed to verify on-chain entitlement — check chain connectivity' }, 500);
  }
  if (!gateResult.ok) {
    return c.json({ error: gateResult.reason }, 403);
  }

  type Row = { fingerprint: string; tier_id: string; timestamp: number; warnings: string | null };
  const rows = getDb()
    .query<Row, [string, string]>(
      `SELECT fingerprint, tier_id, timestamp, warnings
       FROM content
       WHERE LOWER(creator_proxy) = LOWER(?) AND tier_id = ?
       ORDER BY timestamp DESC`,
    )
    .all(creator, numericTierId.toString());

  return c.json({
    content: rows.map((r) => ({
      fingerprint: r.fingerprint,
      tierId: r.tier_id,
      timestamp: r.timestamp,
      warnings: r.warnings ? (JSON.parse(r.warnings) as string[]) : null,
    })),
    nextCursor: null,
  });
});

contentRoutes.get('/:fingerprint', async (c) => {
  const { fingerprint } = c.req.param();

  // Validate fingerprint format: 0x + 64 hex chars (SHA-256 = 32 bytes)
  if (!/^0x[0-9a-fA-F]{64}$/.test(fingerprint)) {
    return c.json({ error: 'fingerprint must be a 0x-prefixed 64-char hex string (SHA-256)' }, 400);
  }

  // Spec §12.3: suspension is the mandatory first step for all violation claims.
  // Check on every content request — a suspended fingerprint must not be served.
  const suspended = await reportRegistry.read.isSuspended([fingerprint as `0x${string}`]);
  if (suspended) {
    return c.json({ error: 'content is suspended pending moderation review' }, 403);
  }

  type Row = { ciphertext: Uint8Array | null; is_reference: number; is_public: number };
  const row = getDb()
    .query<Row, [string]>('SELECT ciphertext, is_reference, is_public FROM content WHERE fingerprint = ?')
    .get(fingerprint);

  if (!row) {
    return c.json({ error: 'content not found on this instance' }, 404);
  }

  // Public content (spec §6.3) is served without authentication — the creator has explicitly
  // published the decryption key via PUT /creator/content/:fingerprint/visibility.
  // Private content requires a valid session token.
  if (!row.is_public) {
    const authHeader = c.req.header('Authorization');
    if (!authHeader?.startsWith('Bearer ')) {
      return c.json({ error: 'authentication required — include Authorization: Bearer <token> header' }, 401);
    }
    const token = authHeader.slice(7);
    type SessionRow = { expires_at: number };
    const session = getDb()
      .query<SessionRow, [string]>('SELECT expires_at FROM sessions WHERE token = ?')
      .get(token);
    if (!session) {
      return c.json({ error: 'invalid session token' }, 401);
    }
    if (Date.now() > session.expires_at) {
      getDb().run('DELETE FROM sessions WHERE token = ?', [token]);
      return c.json({ error: 'session expired — re-authenticate at /auth/challenge + /auth/verify' }, 401);
    }
  }

  // Migration references (is_reference=1) have no ciphertext locally — bytes live on IPFS.
  if (!row.ciphertext) {
    return c.json(
      { error: 'content is referenced but not yet available — ciphertext pending IPFS retrieval' },
      row.is_reference ? 503 : 404,
    );
  }

  // Wrap in new Uint8Array() to guarantee Uint8Array<ArrayBuffer> — required by Response BodyInit.
  return new Response(new Uint8Array(row.ciphertext), {
    headers: { 'Content-Type': 'application/octet-stream' },
  });
});
