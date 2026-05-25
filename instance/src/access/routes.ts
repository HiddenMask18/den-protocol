// Key delivery routes for subscriber and buyer access flows.
//
// One endpoint: POST /key
//
// A subscriber or buyer who has authenticated via /auth/verify sends this request to retrieve
// the content key(s) for a tier they are subscribed to or a listing they have purchased.
//
// Key delivery (spec §4.1):
//   1. Verify on-chain entitlement via the gate (subscription active or purchase recorded).
//   2. Decrypt the creator's operational blob using the instance-derived key → master_secret.
//   3. Derive one content key per path covered by the access grant using HKDF.
//   4. Zero master_secret immediately after derivation.
//
// The operational blob is ECIES-encrypted to an instance-derived keypair. The instance stores
// ciphertext only — master_secret is never persisted in plaintext.
//
// Request body:
//   { type: "subscription", creatorProxy: "0x...", tierId: "1" }
//   { type: "purchase",     creatorProxy: "0x...", listingId: "42" }
//
// Response:
//   { keys: { "tier:1": "0xabc...", "tier:2": "0xdef..." } }
//   Keys are 32-byte values encoded as 0x-prefixed hex. Multiple entries appear when the
//   access grant covers multiple derivation paths (e.g. tier 2 also grants tier 1).
//
// Error responses:
//   400  malformed or missing request fields
//   401  not authenticated (handled by requireAuth middleware before reaching this handler)
//   403  entitlement check failed
//   503  creator has not yet completed setup (no blob)

import { Hono } from 'hono';
import { toHex } from 'viem';
import { requireAuth } from '../auth/middleware.ts';
import { getDb } from '../db/index.ts';
import { deriveCreatorBlobKey, decryptBlob } from '../crypto/blob.ts';
import { deriveKey } from '../crypto/derive.ts';
import { checkSubscriptionAccess, checkPurchaseAccess } from './gate.ts';

// Declares the context variables set by requireAuth middleware so TypeScript knows their types.
type SessionEnv = {
  Variables: {
    proxy: string;
    wallet: string;
  };
};

export const accessRoutes = new Hono<SessionEnv>();

accessRoutes.post('/key', requireAuth, async (c) => {
  // Parse request body
  let body: { type?: string; creatorProxy?: string; tierId?: string; listingId?: string };
  try {
    body = await c.req.json();
  } catch {
    return c.json({ error: 'request body must be valid JSON' }, 400);
  }

  const { type, creatorProxy } = body;

  if (!creatorProxy || !creatorProxy.startsWith('0x')) {
    return c.json({ error: 'creatorProxy field is required (0x-prefixed Ethereum address)' }, 400);
  }
  if (type !== 'subscription' && type !== 'purchase') {
    return c.json({ error: 'type must be "subscription" or "purchase"' }, 400);
  }
  if (type === 'subscription' && !body.tierId) {
    return c.json({ error: 'tierId is required for subscription access' }, 400);
  }
  if (type === 'purchase' && !body.listingId) {
    return c.json({ error: 'listingId is required for purchase access' }, 400);
  }

  // Parse numeric IDs before the chain call so a non-numeric value produces a 400, not a 500.
  let numericId: bigint;
  try {
    numericId = BigInt(type === 'subscription' ? body.tierId! : body.listingId!);
  } catch {
    return c.json({ error: type === 'subscription' ? 'tierId must be a numeric string' : 'listingId must be a numeric string' }, 400);
  }

  // The authenticated participant's proxy — resolved from their wallet at login time.
  // This is the stable DEN identity used for all on-chain lookups.
  const participantProxy = c.get('proxy') as `0x${string}`;
  const creator = creatorProxy as `0x${string}`;

  // Check on-chain entitlement and verify the access grant signature (spec §4.1 MUST).
  let gateResult;
  try {
    if (type === 'subscription') {
      gateResult = await checkSubscriptionAccess(participantProxy, creator, numericId);
    } else {
      gateResult = await checkPurchaseAccess(participantProxy, creator, numericId);
    }
  } catch {
    return c.json({ error: 'failed to verify on-chain entitlement — check chain connectivity' }, 500);
  }

  if (!gateResult.ok) {
    return c.json({ error: gateResult.reason }, 403);
  }

  // Retrieve the operational blob.
  // blob is nullable: NULL after a migration import before the creator re-uploads.
  type BlobRow = { blob: Uint8Array | null };
  const row = getDb()
    .query<BlobRow, [string]>(
      'SELECT blob FROM master_secret_blobs WHERE creator_proxy = ?',
    )
    .get(creator.toLowerCase());

  if (!row || !row.blob) {
    return c.json(
      { error: 'creator operational blob not available — creator has not completed setup' },
      503,
    );
  }

  // Key delivery:
  //   1. Decrypt operational blob → master_secret (32 bytes)
  //   2. Derive one content key per path covered by the access grant
  //   3. Zero master_secret immediately

  let masterSecret: Uint8Array | undefined;

  try {
    try {
      const { privKey } = deriveCreatorBlobKey(creator);
      masterSecret = await decryptBlob(row.blob, privKey);
    } catch {
      return c.json({ error: 'failed to decrypt operational blob' }, 500);
    }

    const keys: Record<string, string> = {};
    for (const path of gateResult.paths) {
      keys[path] = toHex(deriveKey(masterSecret, path));
    }

    // Mirror subscription state locally (spec §4.2).
    if (type === 'subscription' && gateResult.expiry !== undefined) {
      getDb().run(
        `INSERT OR REPLACE INTO subscriber_state
           (subscriber_proxy, creator_proxy, tier_id, expiry, updated_at)
         VALUES (?, ?, ?, ?, ?)`,
        [
          participantProxy.toLowerCase(),
          creator.toLowerCase(),
          body.tierId!,
          Number(gateResult.expiry),
          Date.now(),
        ],
      );
    }

    return c.json({ keys });
  } finally {
    masterSecret?.fill(0);
  }
});
