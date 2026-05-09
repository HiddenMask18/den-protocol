// Key delivery routes for subscriber and buyer access flows.
//
// One endpoint: POST /key
//
// A subscriber or buyer who has authenticated via /auth/verify sends this request to retrieve
// the content key(s) for a tier they are subscribed to or a listing they have purchased.
// The instance checks on-chain entitlement, decrypts the creator's master secret blob, derives
// the content key for each derivation path covered by the access grant, and returns them.
//
// The keys are ephemeral — derived on demand and never stored. The master secret is zeroed
// from memory immediately after derivation so it does not linger in garbage-collectable memory.
//
// Request body:
//   { type: "subscription", creatorProxy: "0x...", tierId: "1" }
//   { type: "purchase",     creatorProxy: "0x...", listingId: "42" }
//
// Response:
//   { keys: { "tier:1": "0xabc...", "tier:2": "0xdef..." } }
//   Keys are 32-byte values encoded as 0x-prefixed hex. Multiple entries appear when the access
//   grant covers multiple derivation paths (e.g. a tier 2 subscription that also grants tier 1).
//
// Error responses:
//   400  malformed or missing request fields
//   401  not authenticated (handled by requireAuth middleware before reaching this handler)
//   403  entitlement check failed (no active subscription, no purchase, no valid access grant)
//   503  creator has not yet uploaded their master secret blob to this instance

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
  // proxy is stored as a lowercase 0x-prefixed address by the auth middleware
  const participantProxy = c.get('proxy') as `0x${string}`;
  const creator = creatorProxy as `0x${string}`;

  // Check on-chain entitlement and retrieve the access grant derivation paths
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

  // Retrieve the creator's encrypted master secret blob
  type BlobRow = { blob: Uint8Array };
  const row = getDb()
    .query<BlobRow, [string]>('SELECT blob FROM master_secret_blobs WHERE creator_proxy = ?')
    .get(creator.toLowerCase());

  if (!row) {
    return c.json(
      { error: 'creator master secret not available on this instance — creator has not completed setup' },
      503,
    );
  }

  // Decrypt blob → plaintext master secret
  let masterSecret: Uint8Array;
  try {
    const { privKey } = deriveCreatorBlobKey(creator);
    masterSecret = await decryptBlob(row.blob, privKey);
  } catch {
    return c.json({ error: 'failed to decrypt master secret blob' }, 500);
  }

  // Derive one content key per path covered by the access grant.
  // Multiple paths appear when a tier grants access to lower tiers (superset model).
  const keys: Record<string, string> = {};
  try {
    for (const path of gateResult.paths) {
      keys[path] = toHex(deriveKey(masterSecret, path));
    }
  } finally {
    // Zero out the plaintext master secret immediately — do not leave it in GC-able memory.
    // The finally block ensures this runs even if deriveKey throws.
    masterSecret.fill(0);
  }

  return c.json({ keys });
});
