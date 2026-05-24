// Creator tooling routes — authenticated API for creators to set up their instance.
//
// All routes require a valid session (Authorization: Bearer <token>) obtained via /auth/verify.
// The session proxy is used as the creator proxy — a creator only ever manages their own data.
//
// Routes:
//   GET  /creator/blob-pubkey     Return the instance's per-creator ECIES public key
//   PUT  /creator/blob            Upload pre-encrypted master secret blobs (dual-blob model)
//   GET  /creator/blob            Check whether blob has been uploaded
//   GET  /creator/portability-blob  Return the wallet-encrypted portability blob for migration
//   POST /creator/content         Upload encrypted content; returns SHA-256 fingerprint
//   GET  /creator/content         List content metadata for this creator
//   POST /creator/grant           Publish a signed access grant declaration locally
//   GET  /creator/grant/:tierId   Retrieve a stored access grant
//
// Dual-blob model for master secrets:
//   The instance stores two ECIES blobs per creator:
//     operationalBlob   — encrypted to the instance's derived pubkey; instance decrypts at key
//                         delivery time. Creator cannot decrypt this.
//     portabilityBlob   — encrypted to the creator's wallet pubkey; creator decrypts for migration
//                         or recovery. Instance cannot decrypt this (spec §8.1).
//
//   The creator encrypts both blobs client-side before uploading. The instance NEVER receives the
//   plaintext master secret — it only receives ciphertext and verifies the operational blob
//   decrypts correctly (to confirm the right pubkey was used). The plaintext is zeroed immediately.
//
// On-chain writes (DENContentRegistry.registerContent, DENAccessGrant.publishGrant) are the
// creator's responsibility — the instance only reads on-chain state (publicClient is read-only).

import { Hono } from 'hono';
import { fromHex, toHex } from 'viem';
import { sha256 } from '@noble/hashes/sha256';
import { requireAuth } from '../auth/middleware.ts';
import { getDb } from '../db/index.ts';
import { decryptBlob, deriveCreatorBlobKey } from '../crypto/blob.ts';
import { getPrimaryWallet, getIsEmergencyWallet, governance, trustTier } from '../chain/contracts.ts';
import { getGrant, upsertGrant, verifyGrantSignature, type StoredGrant } from '../grants/store.ts';

type SessionEnv = {
  Variables: {
    proxy: string;
    wallet: string;
  };
};

export const creatorRoutes = new Hono<SessionEnv>();

// ─── Master secret blob ───────────────────────────────────────────────────────

// Returns the instance's derived secp256k1 public key for this creator.
// The creator encrypts their master secret to this key (using the ECIES scheme in blob.ts)
// before uploading the operational blob via PUT /creator/blob.
creatorRoutes.get('/blob-pubkey', requireAuth, (c) => {
  const proxy = c.get('proxy');
  const { pubKey } = deriveCreatorBlobKey(proxy);
  return c.json({ pubKey: toHex(pubKey) }); // 33-byte compressed key → 0x-prefixed 68-char hex
});

// Accepts two pre-encrypted ECIES blobs from the creator:
//   operationalBlob   — encrypted to the instance's derived pubkey (from GET /creator/blob-pubkey)
//   portabilityBlob   — encrypted to the creator's own wallet secp256k1 pubkey
//
// The instance decrypts the operational blob to verify the creator used the correct pubkey,
// then immediately zeros the plaintext. The portability blob is stored as-is — the instance
// cannot decrypt it and does not attempt to.
creatorRoutes.put('/blob', requireAuth, async (c) => {
  let body: {
    operationalBlob?: string;
    portabilityBlob?: string;
    emergencyPortabilityBlob?: string;
    oracleUrl?: string;
  };
  try {
    body = await c.req.json();
  } catch {
    return c.json({ error: 'request body must be valid JSON' }, 400);
  }

  const { operationalBlob, portabilityBlob, emergencyPortabilityBlob, oracleUrl } = body;

  // Minimum valid ECIES blob: 33 (ephPub) + 12 (nonce) + 16 (authtag for empty plaintext) = 61 bytes
  // = 122 hex chars + 0x prefix = 124 chars total.
  function validateBlobHex(val: unknown, name: string): string | null {
    if (!val || typeof val !== 'string') return `${name} is required`;
    if (!val.startsWith('0x')) return `${name} must be a 0x-prefixed hex string`;
    if ((val.length - 2) % 2 !== 0) return `${name} has an odd number of hex characters`;
    if (val.length < 124) return `${name} is too short to be a valid ECIES blob (minimum 61 bytes)`;
    if (!/^[0-9a-fA-F]+$/.test(val.slice(2))) return `${name} contains non-hex characters`;
    return null;
  }

  const opErr = validateBlobHex(operationalBlob, 'operationalBlob');
  if (opErr) return c.json({ error: opErr }, 400);
  const portErr = validateBlobHex(portabilityBlob, 'portabilityBlob');
  if (portErr) return c.json({ error: portErr }, 400);
  // emergencyPortabilityBlob is optional — only provided when an emergency wallet is registered.
  if (emergencyPortabilityBlob !== undefined) {
    const emErr = validateBlobHex(emergencyPortabilityBlob, 'emergencyPortabilityBlob');
    if (emErr) return c.json({ error: emErr }, 400);
  }

  // oracleUrl is required — the creator must run an oracle holding their key share.
  if (!oracleUrl || typeof oracleUrl !== 'string') {
    return c.json({ error: 'oracleUrl is required (URL of the creator\'s key oracle)' }, 400);
  }
  try {
    const u = new URL(oracleUrl);
    if (u.protocol !== 'https:' && u.protocol !== 'http:') {
      return c.json({ error: 'oracleUrl must be an http or https URL' }, 400);
    }
  } catch {
    return c.json({ error: 'oracleUrl is not a valid URL' }, 400);
  }

  const proxy = c.get('proxy');
  const opBytes = fromHex(operationalBlob as `0x${string}`, 'bytes');
  const portBytes = fromHex(portabilityBlob as `0x${string}`, 'bytes');
  const emPortBytes = emergencyPortabilityBlob
    ? fromHex(emergencyPortabilityBlob as `0x${string}`, 'bytes')
    : null;

  // Verify the operational blob was encrypted to this creator's instance-derived key and
  // decrypts to exactly 32 bytes (the instance_share in the threshold split model).
  // The plaintext is zeroed immediately in the finally block.
  let instanceShare: Uint8Array | undefined;
  try {
    const { privKey } = deriveCreatorBlobKey(proxy);
    instanceShare = await decryptBlob(opBytes, privKey);
    if (instanceShare.length !== 32) {
      return c.json(
        { error: 'operationalBlob must decrypt to exactly 32 bytes (instance_share)' },
        400,
      );
    }
  } catch {
    return c.json(
      { error: 'operationalBlob failed decryption — it must be encrypted to the pubkey from GET /creator/blob-pubkey' },
      400,
    );
  } finally {
    instanceShare?.fill(0);
  }

  // If an emergency portability blob was provided, store it; otherwise preserve any existing one.
  // COALESCE(excluded.emergency_portability_blob, emergency_portability_blob) keeps the old value
  // when the incoming upload does not include one.
  getDb().run(
    `INSERT INTO master_secret_blobs
       (creator_proxy, blob, portability_blob, emergency_portability_blob, oracle_url, updated_at)
     VALUES (?, ?, ?, ?, ?, ?)
     ON CONFLICT(creator_proxy) DO UPDATE SET
       blob                       = excluded.blob,
       portability_blob           = excluded.portability_blob,
       emergency_portability_blob = COALESCE(excluded.emergency_portability_blob, emergency_portability_blob),
       oracle_url                 = excluded.oracle_url,
       updated_at                 = excluded.updated_at`,
    [proxy, opBytes, portBytes, emPortBytes, oracleUrl, Date.now()],
  );

  return c.json({ stored: true });
});

creatorRoutes.get('/blob', requireAuth, (c) => {
  const proxy = c.get('proxy');
  // Check that the operational blob (blob column) is present — not just the row.
  // After a migration import, the row exists but blob is NULL until the creator
  // re-uploads via PUT /creator/blob.
  const row = getDb()
    .query<{ blob: Uint8Array | null }, [string]>(
      'SELECT blob FROM master_secret_blobs WHERE creator_proxy = ?',
    )
    .get(proxy);
  return c.json({ exists: row !== null && row.blob !== null });
});

// Returns the portability blob for the authenticated wallet.
// Primary wallet → portability_blob (encrypted to primary wallet pubkey)
// Emergency wallet → emergency_portability_blob (encrypted to emergency wallet pubkey)
// The instance stores both but cannot decrypt either. Used for migration and recovery (spec §8.1).
creatorRoutes.get('/portability-blob', requireAuth, async (c) => {
  const proxy = c.get('proxy');
  const wallet = c.get('wallet') as `0x${string}`;

  type Row = { portability_blob: Uint8Array | null; emergency_portability_blob: Uint8Array | null };
  const row = getDb()
    .query<Row, [string]>(
      'SELECT portability_blob, emergency_portability_blob FROM master_secret_blobs WHERE creator_proxy = ?',
    )
    .get(proxy);

  if (!row) {
    return c.json({ error: 'portability blob not found — upload blobs via PUT /creator/blob' }, 404);
  }

  // Check if the authenticated wallet is an emergency wallet so we serve the right blob.
  let isEmergency = false;
  try {
    isEmergency = await getIsEmergencyWallet(proxy as `0x${string}`, wallet);
  } catch {
    return c.json({ error: 'failed to verify wallet role — check chain connectivity' }, 500);
  }

  if (isEmergency) {
    if (!row.emergency_portability_blob) {
      return c.json({ error: 'emergency portability blob not found — upload via PUT /creator/blob with emergencyPortabilityBlob' }, 404);
    }
    return new Response(new Uint8Array(row.emergency_portability_blob), {
      headers: { 'Content-Type': 'application/octet-stream' },
    });
  }

  if (!row.portability_blob) {
    return c.json({ error: 'portability blob not found — upload blobs via PUT /creator/blob' }, 404);
  }

  return new Response(new Uint8Array(row.portability_blob), {
    headers: { 'Content-Type': 'application/octet-stream' },
  });
});

// ─── Content ──────────────────────────────────────────────────────────────────

// Deletes a single content entry owned by the authenticated creator.
// Used to clean up orphaned old ciphertext rows after key rotation (spec §4.7):
// after re-encrypting all content for a tier and uploading new ciphertext (new fingerprints),
// the creator deletes the old rows so they do not appear in GET /creator/content listings.
//
// Returns 404 if the fingerprint is not found or does not belong to this creator.
// The caller is responsible for ensuring on-chain rotation is complete before calling this —
// the instance has no visibility into whether a given fingerprint is still active on-chain.
creatorRoutes.delete('/content/:fingerprint', requireAuth, (c) => {
  const proxy = c.get('proxy');
  const { fingerprint } = c.req.param();

  const row = getDb()
    .query<{ fingerprint: string }, [string, string]>(
      'SELECT fingerprint FROM content WHERE fingerprint = ? AND creator_proxy = ?',
    )
    .get(fingerprint, proxy);

  if (!row) {
    return c.json({ error: 'content not found' }, 404);
  }

  getDb().run('DELETE FROM content WHERE fingerprint = ? AND creator_proxy = ?', [fingerprint, proxy]);
  return new Response(null, { status: 204 });
});

const UINT256_MAX = (2n ** 256n) - 1n;

creatorRoutes.post('/content', requireAuth, async (c) => {
  const tierIdHeader = c.req.header('X-Tier-Id');
  if (!tierIdHeader) {
    return c.json({ error: 'X-Tier-Id header is required' }, 400);
  }

  let tierId: bigint;
  try {
    tierId = BigInt(tierIdHeader);
  } catch {
    return c.json({ error: 'X-Tier-Id must be a numeric string' }, 400);
  }

  // Optional content warnings: JSON array of strings
  let warnings: string | null = null;
  const warningsHeader = c.req.header('X-Warnings');
  if (warningsHeader) {
    let parsed: unknown;
    try {
      parsed = JSON.parse(warningsHeader);
    } catch {
      return c.json({ error: 'X-Warnings must be a valid JSON array of strings' }, 400);
    }
    if (!Array.isArray(parsed) || parsed.some((w) => typeof w !== 'string')) {
      return c.json({ error: 'X-Warnings must be a JSON array of strings' }, 400);
    }
    warnings = JSON.stringify(parsed);
  }

  const ciphertext = new Uint8Array(await c.req.arrayBuffer());
  if (ciphertext.length === 0) {
    return c.json({ error: 'request body must contain ciphertext bytes' }, 400);
  }

  const proxy = c.get('proxy');

  // Enforce trust tier limits (spec §9.1): file size and daily post rate.
  // Limits are read live from the governance contract so they respond to parameter updates
  // without requiring an instance redeploy (spec §10).
  let creatorTier: number;
  let maxFileSizeBytes: bigint;
  let maxPostRateRaw: bigint;
  try {
    creatorTier = await trustTier.read.getTier([proxy as `0x${string}`]);
    [maxFileSizeBytes, maxPostRateRaw] = await Promise.all([
      governance.read.getPostSizeLimit([creatorTier as 0 | 1 | 2 | 3]),
      governance.read.getPostRateLimit([creatorTier as 0 | 1 | 2 | 3]),
    ]);
  } catch {
    return c.json({ error: 'failed to read trust tier or limits from chain — check chain connectivity' }, 500);
  }

  // type(uint256).max is the sentinel for "no daily post limit" (tier 3, spec §13.4).
  const maxPostsPerDay = maxPostRateRaw === UINT256_MAX ? null : Number(maxPostRateRaw);

  if (BigInt(ciphertext.length) > maxFileSizeBytes) {
    return c.json(
      {
        error: `file exceeds tier ${creatorTier} maximum size of ${maxFileSizeBytes} bytes`,
        tier: creatorTier,
        maxFileSizeBytes: maxFileSizeBytes.toString(),
        receivedBytes: ciphertext.length,
      },
      413,
    );
  }

  if (maxPostsPerDay !== null) {
    const oneDayAgo = Date.now() - 24 * 60 * 60 * 1000;
    const { count } = getDb()
      .query<{ count: number }, [string, number]>(
        'SELECT COUNT(*) as count FROM content WHERE creator_proxy = ? AND timestamp >= ?',
      )
      .get(proxy, oneDayAgo)!;

    if (count >= maxPostsPerDay) {
      return c.json(
        {
          error: `post rate limit reached for tier ${creatorTier}: ${maxPostsPerDay} posts per day`,
          tier: creatorTier,
          maxPostsPerDay,
          postsToday: count,
        },
        429,
      );
    }
  }

  // Fingerprint is SHA-256 of the ciphertext bytes — matches what is registered on-chain
  // in DENContentRegistry via registerContent(fingerprint, tierId).
  const fingerprintBytes = sha256(ciphertext);
  const fingerprint = toHex(fingerprintBytes); // 0x-prefixed 66-char hex

  // Reject duplicate uploads — same ciphertext = same fingerprint.
  const existing = getDb()
    .query<{ fingerprint: string }, [string]>('SELECT fingerprint FROM content WHERE fingerprint = ?')
    .get(fingerprint);
  if (existing) {
    return c.json({ error: 'content with this fingerprint is already stored', fingerprint }, 409);
  }

  getDb().run(
    'INSERT INTO content (fingerprint, creator_proxy, tier_id, ciphertext, timestamp, warnings) VALUES (?, ?, ?, ?, ?, ?)',
    [fingerprint, proxy, tierId.toString(), ciphertext, Date.now(), warnings],
  );

  return c.json({ fingerprint });
});

creatorRoutes.get('/content', requireAuth, (c) => {
  const proxy = c.get('proxy');
  type Row = { fingerprint: string; tier_id: string; timestamp: number; warnings: string | null };
  const rows = getDb()
    .query<Row, [string]>(
      'SELECT fingerprint, tier_id, timestamp, warnings FROM content WHERE creator_proxy = ? ORDER BY timestamp DESC',
    )
    .all(proxy);

  return c.json(
    rows.map((r) => ({
      fingerprint: r.fingerprint,
      tierId: r.tier_id,
      timestamp: r.timestamp,
      warnings: r.warnings ? JSON.parse(r.warnings) : null,
    })),
  );
});

// ─── Creator profile ──────────────────────────────────────────────────────────

// Sets the creator's public bio (spec §6.2 — creator description on public profile).
// The handle (pseudonymous name) lives on-chain; bio is instance-side.
// Upserts the creator_profile row — safe to call multiple times to update the bio.
creatorRoutes.put('/profile', requireAuth, async (c) => {
  let body: { bio?: unknown };
  try {
    body = await c.req.json();
  } catch {
    return c.json({ error: 'request body must be valid JSON' }, 400);
  }

  const { bio } = body;
  if (bio !== undefined && bio !== null && typeof bio !== 'string') {
    return c.json({ error: 'bio must be a string or null' }, 400);
  }

  const proxy = c.get('proxy');
  getDb().run(
    `INSERT INTO creator_profile (creator_proxy, bio, updated_at) VALUES (?, ?, ?)
     ON CONFLICT(creator_proxy) DO UPDATE SET bio = excluded.bio, updated_at = excluded.updated_at`,
    [proxy.toLowerCase(), typeof bio === 'string' ? bio : null, Date.now()],
  );

  return c.json({ stored: true });
});

// Marks a content item as publicly visible (spec §6.3) or reverts it to private.
// Public content is accessible without a subscription and its decryption key is returned
// in GET /profile/:proxy so any client can decrypt it.
//
// isPublic=true requires contentKey (0x-prefixed 64-char hex, the 32-byte symmetric key
// used to encrypt this content). The creator derives this from their master secret:
//   deriveKey(masterSecret, "tier:" + tierId) or "item:" + listingId
//
// isPublic=false clears the stored key and removes public access.
creatorRoutes.put('/content/:fingerprint/visibility', requireAuth, async (c) => {
  const proxy = c.get('proxy');
  const { fingerprint } = c.req.param();

  let body: { isPublic?: unknown; contentKey?: unknown };
  try {
    body = await c.req.json();
  } catch {
    return c.json({ error: 'request body must be valid JSON' }, 400);
  }

  const { isPublic, contentKey } = body;

  if (typeof isPublic !== 'boolean') {
    return c.json({ error: 'isPublic must be a boolean' }, 400);
  }

  const row = getDb()
    .query<{ fingerprint: string }, [string, string]>(
      'SELECT fingerprint FROM content WHERE fingerprint = ? AND LOWER(creator_proxy) = LOWER(?)',
    )
    .get(fingerprint, proxy);

  if (!row) {
    return c.json({ error: 'content not found' }, 404);
  }

  if (isPublic) {
    if (!contentKey || typeof contentKey !== 'string') {
      return c.json({ error: 'contentKey is required when marking content public' }, 400);
    }
    if (!/^0x[0-9a-fA-F]{64}$/.test(contentKey)) {
      return c.json({ error: 'contentKey must be a 0x-prefixed 64-char hex string (32 bytes)' }, 400);
    }
    const keyBytes = fromHex(contentKey as `0x${string}`, 'bytes');
    getDb().run(
      'UPDATE content SET is_public = 1, public_key = ? WHERE fingerprint = ?',
      [keyBytes, fingerprint],
    );
  } else {
    getDb().run(
      'UPDATE content SET is_public = 0, public_key = NULL WHERE fingerprint = ?',
      [fingerprint],
    );
  }

  return c.json({ stored: true });
});

// ─── Access grants ────────────────────────────────────────────────────────────

creatorRoutes.post('/grant', requireAuth, async (c) => {
  let body: { tierId?: string; paths?: unknown; signature?: string; version?: unknown };
  try {
    body = await c.req.json();
  } catch {
    return c.json({ error: 'request body must be valid JSON' }, 400);
  }

  const { tierId, paths, signature, version } = body;

  if (!tierId || typeof tierId !== 'string') {
    return c.json({ error: 'tierId field is required (numeric string)' }, 400);
  }
  try {
    BigInt(tierId);
  } catch {
    return c.json({ error: 'tierId must be a numeric string' }, 400);
  }

  if (!Array.isArray(paths) || paths.length === 0 || paths.some((p) => typeof p !== 'string' || !p)) {
    return c.json({ error: 'paths must be a non-empty array of non-empty strings' }, 400);
  }

  // Spec §4.1: derivation paths are "tier:<id>" for subscription tiers or "item:<id>" for shop items.
  const validPath = /^(tier|item):\d+$/;
  if (!paths.every((p) => validPath.test(p as string))) {
    return c.json({ error: 'each path must be "tier:<id>" or "item:<id>" (e.g. "tier:1", "item:42")' }, 400);
  }

  if (!signature || typeof signature !== 'string' || !signature.startsWith('0x')) {
    return c.json({ error: 'signature must be a 0x-prefixed hex string' }, 400);
  }

  if (typeof version !== 'number' || !Number.isInteger(version) || version < 1) {
    return c.json({ error: 'version must be a positive integer' }, 400);
  }

  const proxy = c.get('proxy');

  // Version must be 1 for a new grant, or existing.version + 1 for an update.
  const existing = getGrant(proxy, tierId);
  const expectedVersion = existing ? existing.version + 1 : 1;
  if (version !== expectedVersion) {
    return c.json(
      { error: `version must be ${expectedVersion} (got ${version})` },
      409,
    );
  }

  // Fetch the creator's current primary wallet from their proxy contract for signature verification.
  let primaryWallet: `0x${string}`;
  try {
    primaryWallet = await getPrimaryWallet(proxy as `0x${string}`);
  } catch {
    return c.json({ error: 'failed to read primary wallet from chain — check chain connectivity' }, 500);
  }

  const grant: StoredGrant = {
    creatorProxy: proxy,
    tierId,
    declaration: JSON.stringify({ paths }),
    signature,
    version,
  };

  let valid: boolean;
  try {
    valid = await verifyGrantSignature(grant, primaryWallet);
  } catch (err) {
    return c.json({ error: `grant signature verification error: ${(err as Error).message}` }, 400);
  }

  if (!valid) {
    return c.json({ error: 'grant signature does not match primary wallet' }, 403);
  }

  upsertGrant(grant);

  return c.json({ stored: true });
});

creatorRoutes.get('/grant/:tierId', requireAuth, (c) => {
  const proxy = c.get('proxy');
  const { tierId } = c.req.param();

  const grant = getGrant(proxy, tierId);
  if (!grant) {
    return c.json({ error: 'grant not found' }, 404);
  }

  const parsed = JSON.parse(grant.declaration) as { paths: string[] };
  return c.json({ tierId: grant.tierId, paths: parsed.paths, version: grant.version });
});
