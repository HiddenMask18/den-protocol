// Content download route — serves encrypted content ciphertext to authenticated participants.
//
// GET /content/:fingerprint
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
import { requireAuth } from '../auth/middleware.ts';
import { getDb } from '../db/index.ts';

type SessionEnv = {
  Variables: {
    proxy: string;
    wallet: string;
  };
};

export const contentRoutes = new Hono<SessionEnv>();

contentRoutes.get('/:fingerprint', requireAuth, (c) => {
  const { fingerprint } = c.req.param();

  // Validate fingerprint format: 0x + 64 hex chars (SHA-256 = 32 bytes)
  if (!/^0x[0-9a-fA-F]{64}$/.test(fingerprint)) {
    return c.json({ error: 'fingerprint must be a 0x-prefixed 64-char hex string (SHA-256)' }, 400);
  }

  type Row = { ciphertext: Uint8Array | null; is_reference: number };
  const row = getDb()
    .query<Row, [string]>('SELECT ciphertext, is_reference FROM content WHERE fingerprint = ?')
    .get(fingerprint);

  if (!row) {
    return c.json({ error: 'content not found on this instance' }, 404);
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
