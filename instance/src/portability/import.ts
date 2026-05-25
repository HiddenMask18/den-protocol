// Portable data set ingestion — import side of creator migration (spec §8.2).
//
// The receiving instance must:
//   1. Verify wallet signatures on ALL access grant declarations before accepting anything.
//      A single failing grant causes the entire import to be rejected (spec §8.2).
//   2. Store the portability blob (wallet-encrypted master secret).
//      The operational blob (instance-encrypted) is NOT set here — the creator
//      must re-upload it via PUT /creator/blob after the import completes.
//   3. Upsert all verified access grants into the local access_grants table.
//   4. Record content references (fingerprints + metadata) with is_reference=1.
//      Ciphertext is not included in the bundle; it lives on IPFS. The reference
//      lets the instance know what content belongs to this creator so it can
//      serve it once IPFS retrieval is implemented.
//
// Subscriber and buyer lists in the bundle are informational — on-chain state
// is authoritative and no DB writes are needed for them. Subscribers and buyers
// will authenticate normally; the on-chain gate handles entitlement.
//
// The entire write is wrapped in a SQLite transaction: all or nothing.
//
// After a successful import:
//   - GET /creator/blob returns { exists: false } — creator must upload operational blob
//   - GET /creator/portability-blob returns the imported wallet-encrypted blob
//   - GET /creator/grant/:tierId returns imported grants
//   - GET /content/:fingerprint returns 503 for referenced content (pending IPFS)
//   - POST /access/key works once the creator uploads the operational blob

import { fromHex } from 'viem';
import type { PortableDataBundle } from './export.ts';
import { getDb } from '../db/index.ts';
import { getPrimaryWallet } from '../chain/contracts.ts';
import { getGrant, verifyGrantSignature, upsertGrant, type StoredGrant } from '../grants/store.ts';

export class ImportValidationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'ImportValidationError';
  }
}

export type ImportResult = {
  grantsImported: number;
  contentReferencesImported: number;
  portabilityBlobStored: boolean;
};

export async function importPortableData(
  bundle: PortableDataBundle,
  creatorProxy: string,
): Promise<ImportResult> {
  // Resolve creator's current primary wallet from their identity contract.
  let primaryWallet: `0x${string}`;
  try {
    primaryWallet = await getPrimaryWallet(creatorProxy as `0x${string}`);
  } catch {
    throw new Error('failed to read primary wallet from chain — check chain connectivity');
  }

  // Verify ALL grant signatures before writing anything to the DB.
  // The spec requires rejection of any unsigned/unverifiable declaration (§8.2).
  for (const grant of bundle.accessGrants) {
    if (!grant.tierId || typeof grant.tierId !== 'string') {
      throw new ImportValidationError('grant is missing tierId');
    }
    if (!Array.isArray(grant.paths) || grant.paths.length === 0) {
      throw new ImportValidationError(`grant ${grant.tierId}: paths must be a non-empty array`);
    }
    if (!grant.signature || typeof grant.signature !== 'string' || !grant.signature.startsWith('0x')) {
      throw new ImportValidationError(`grant ${grant.tierId}: invalid signature format`);
    }
    if (typeof grant.version !== 'number' || !Number.isInteger(grant.version) || grant.version < 1) {
      throw new ImportValidationError(`grant ${grant.tierId}: version must be a positive integer`);
    }

    const stored: StoredGrant = {
      creatorProxy: creatorProxy.toLowerCase(),
      tierId: grant.tierId,
      declaration: JSON.stringify({ paths: grant.paths }),
      signature: grant.signature,
      version: grant.version,
    };

    let valid: boolean;
    try {
      valid = await verifyGrantSignature(stored, primaryWallet);
    } catch (err) {
      throw new ImportValidationError(
        `grant ${grant.tierId} has malformed signature: ${(err as Error).message}`,
      );
    }
    if (!valid) {
      throw new ImportValidationError(
        `grant ${grant.tierId} signature does not match creator's primary wallet — import rejected`,
      );
    }
  }

  // Parse portability blob bytes.
  let portBlobBytes: Uint8Array;
  try {
    portBlobBytes = fromHex(bundle.portabilityBlob as `0x${string}`, 'bytes');
  } catch {
    throw new ImportValidationError('portabilityBlob is not valid hex');
  }

  // Parse emergency portability blob bytes (optional — only present when creator has an emergency wallet).
  let emPortBlobBytes: Uint8Array | null = null;
  if (bundle.emergencyPortabilityBlob) {
    try {
      emPortBlobBytes = fromHex(bundle.emergencyPortabilityBlob as `0x${string}`, 'bytes');
    } catch {
      throw new ImportValidationError('emergencyPortabilityBlob is not valid hex');
    }
  }

  // Write everything atomically.
  const db = getDb();
  let grantsImported = 0;
  let contentReferencesImported = 0;

  const runImport = db.transaction(() => {
    // Store portability blobs. blob (operational) is NOT set — creator re-uploads after import
    // (re-encrypting master_secret to the new instance's derived key).
    // emergency_portability_blob uses COALESCE: preserve the existing value if the bundle omits it
    // (backwards-compatible with bundles exported before this field was added).
    // ON CONFLICT: preserve any existing operational blob and update everything else.
    db.run(
      `INSERT INTO master_secret_blobs
         (creator_proxy, blob, portability_blob, emergency_portability_blob, updated_at)
       VALUES (?, NULL, ?, ?, ?)
       ON CONFLICT(creator_proxy) DO UPDATE SET
         portability_blob           = excluded.portability_blob,
         emergency_portability_blob = COALESCE(excluded.emergency_portability_blob, emergency_portability_blob),
         updated_at                 = excluded.updated_at`,
      [creatorProxy.toLowerCase(), portBlobBytes, emPortBlobBytes, Date.now()],
    );

    // Upsert verified grants — skip if incoming version ≤ local version to prevent downgrade.
    for (const grant of bundle.accessGrants) {
      const existing = getGrant(creatorProxy.toLowerCase(), grant.tierId);
      if (existing && grant.version <= existing.version) {
        continue;
      }
      upsertGrant({
        creatorProxy: creatorProxy.toLowerCase(),
        tierId: grant.tierId,
        declaration: JSON.stringify({ paths: grant.paths }),
        signature: grant.signature,
        version: grant.version,
      });
      grantsImported++;
    }

    // Record content references — is_reference=1, ciphertext=NULL.
    // INSERT OR IGNORE: skip if fingerprint already present (content may have been
    // re-uploaded directly before the import, which takes precedence).
    for (const ref of bundle.contentReferences) {
      if (!ref.fingerprint || !ref.tierId || typeof ref.timestamp !== 'number') {
        continue;
      }
      const warnings = ref.warnings ? JSON.stringify(ref.warnings) : null;
      const result = db.run(
        `INSERT OR IGNORE INTO content
           (fingerprint, creator_proxy, tier_id, ciphertext, timestamp, warnings, is_reference)
         VALUES (?, ?, ?, NULL, ?, ?, 1)`,
        [ref.fingerprint, creatorProxy.toLowerCase(), ref.tierId, ref.timestamp, warnings],
      );
      contentReferencesImported += result.changes;
    }
  });

  runImport();

  return { grantsImported, contentReferencesImported, portabilityBlobStored: true };
}
