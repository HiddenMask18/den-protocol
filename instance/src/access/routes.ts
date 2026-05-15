// Key delivery routes for subscriber and buyer access flows.
//
// One endpoint: POST /key
//
// A subscriber or buyer who has authenticated via /auth/verify sends this request to retrieve
// the content key(s) for a tier they are subscribed to or a listing they have purchased.
//
// Key delivery uses a two-party threshold split (spec §4.1):
//   instance_share — decrypted from the operational blob using the instance-derived key
//   creator_share  — fetched from the creator's independently-operated oracle
//
// Neither share alone is sufficient to derive content keys. The master secret is reconstructed
// transiently as: master_secret = instance_share XOR creator_share. Content keys are derived
// from master_secret, then master_secret and both shares are zeroed from memory immediately.
//
// The creator's oracle independently verifies on-chain entitlement before returning
// creator_share — it does not trust this instance's claims. A compelled hoster cannot
// forge entitlement proofs to extract creator_share from the oracle.
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
//   403  entitlement check failed or oracle denied the request
//   503  creator has not yet completed setup (no blob, no oracle URL)

import { Hono } from 'hono';
import { toHex } from 'viem';
import { requireAuth } from '../auth/middleware.ts';
import { getDb } from '../db/index.ts';
import { deriveCreatorBlobKey, decryptBlob } from '../crypto/blob.ts';
import { deriveKey } from '../crypto/derive.ts';
import { checkSubscriptionAccess, checkPurchaseAccess } from './gate.ts';
import { fetchCreatorShare, OracleError } from '../oracle/client.ts';

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

  // Retrieve the operational blob and oracle URL.
  // blob is nullable: NULL after a migration import before the creator re-uploads.
  // oracle_url is nullable: NULL for creators who haven't completed setup.
  type BlobRow = { blob: Uint8Array | null; oracle_url: string | null };
  const row = getDb()
    .query<BlobRow, [string]>(
      'SELECT blob, oracle_url FROM master_secret_blobs WHERE creator_proxy = ?',
    )
    .get(creator.toLowerCase());

  if (!row || !row.blob) {
    return c.json(
      { error: 'creator operational blob not available — creator has not completed setup' },
      503,
    );
  }
  if (!row.oracle_url) {
    return c.json(
      { error: 'creator oracle URL not configured — creator has not completed setup' },
      503,
    );
  }

  // Threshold key reconstruction:
  //   1. Decrypt operational blob → instance_share (32 bytes)
  //   2. Fetch creator_share from creator's oracle (oracle independently verifies entitlement)
  //   3. master_secret = instance_share XOR creator_share  (reconstructed transiently)
  //   4. Derive content keys from master_secret
  //   5. Zero all intermediate key material immediately

  let instanceShare: Uint8Array | undefined;
  let creatorShare: Uint8Array | undefined;
  let masterSecret: Uint8Array | undefined;

  try {
    // Step 1: decrypt operational blob → instance_share
    try {
      const { privKey } = deriveCreatorBlobKey(creator);
      instanceShare = await decryptBlob(row.blob, privKey);
    } catch {
      return c.json({ error: 'failed to decrypt operational blob' }, 500);
    }

    // Step 2: fetch creator_share from oracle
    const oracleRequest =
      type === 'subscription'
        ? ({
            type: 'subscription' as const,
            subscriberProxy: participantProxy,
            creatorProxy: creator,
            tierId: body.tierId!,
          })
        : ({
            type: 'purchase' as const,
            buyerProxy: participantProxy,
            creatorProxy: creator,
            listingId: body.listingId!,
          });

    try {
      creatorShare = await fetchCreatorShare(row.oracle_url, oracleRequest);
    } catch (err) {
      if (err instanceof OracleError && err.status === 403) {
        return c.json({ error: 'oracle denied request — entitlement not confirmed' }, 403);
      }
      return c.json(
        { error: `creator oracle unavailable: ${(err as Error).message}` },
        503,
      );
    }

    // Step 3: reconstruct master_secret = instance_share XOR creator_share
    masterSecret = new Uint8Array(32);
    for (let i = 0; i < 32; i++) {
      masterSecret[i] = instanceShare[i] ^ creatorShare[i];
    }

    // Step 4: derive one content key per path covered by the access grant.
    const keys: Record<string, string> = {};
    for (const path of gateResult.paths) {
      keys[path] = toHex(deriveKey(masterSecret, path));
    }

    // Step 5: mirror subscription state locally (spec §4.2).
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
    // Zero all intermediate key material regardless of success or failure.
    // The finally block runs even if a return statement is hit inside the try block.
    instanceShare?.fill(0);
    creatorShare?.fill(0);
    masterSecret?.fill(0);
  }
});
