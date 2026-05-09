// Local access grant storage and off-chain signature verification.
//
// Access grants declare which derivation paths a subscription tier or shop item unlocks.
// They are creator-signed records stored both on-chain (DENAccessGrant contract) and locally
// in the access_grants table as part of the Creator's portable data set.
//
// This module has two responsibilities:
//
//   Storage — read/write the local access_grants table. Used by:
//     - Phase 3: creator publishes a new grant via the creator API
//     - Phase 4: receiving instance ingests grants from the Creator's portable data set
//
//   Signature verification — reimplements the DENAccessGrant signature scheme off-chain.
//     The spec requires signature verification at two mandatory points:
//       1. When accepting declarations during migration (Phase 4)
//       2. Before executing key derivation at any access request
//     For access requests, the on-chain verifyGrant() call in gate.ts is the primary check.
//     verifyGrantSignature() here is the off-chain counterpart, used for migration ingestion
//     and as a secondary verification layer.
//
// Declaration format:
//   The `declaration` column stores JSON: { "paths": ["tier:1"] } or { "paths": ["tier:1","tier:2"] }.
//   Paths are the strings passed to deriveKey() — what the grant actually unlocks.
//
// Signature scheme (matches DENAccessGrant.sol):
//   pathsHash  = keccak256(abi.encode(paths))
//   structHash = keccak256(abi.encode("DEN-access-grant", proxyAddress, tierId, pathsHash, version))
//   The creator signs structHash via personal_sign (EIP-191 prefix applied by their wallet).
//   Verification recovers the signer from the prefixed hash and checks it against the creator's wallet.

import { keccak256, encodeAbiParameters, recoverMessageAddress } from 'viem';
import { getDb } from '../db/index.ts';

export type StoredGrant = {
  creatorProxy: string;  // "0x..." lowercase
  tierId: string;        // decimal string, e.g. "1"
  declaration: string;   // JSON string: { paths: string[] }
  signature: string;     // "0x..." EIP-191 signature over structHash
  version: number;
};

// ─── Storage ──────────────────────────────────────────────────────────────────

export function getGrant(creatorProxy: string, tierId: string): StoredGrant | null {
  type Row = { creator_proxy: string; tier_id: string; declaration: string; signature: string; version: number };
  const row = getDb()
    .query<Row, [string, string]>(
      'SELECT creator_proxy, tier_id, declaration, signature, version FROM access_grants WHERE creator_proxy = ? AND tier_id = ?',
    )
    .get(creatorProxy.toLowerCase(), tierId);

  if (!row) return null;

  return {
    creatorProxy: row.creator_proxy,
    tierId: row.tier_id,
    declaration: row.declaration,
    signature: row.signature,
    version: row.version,
  };
}

export function upsertGrant(grant: StoredGrant): void {
  getDb().run(
    'INSERT OR REPLACE INTO access_grants (creator_proxy, tier_id, declaration, signature, version) VALUES (?, ?, ?, ?, ?)',
    [
      grant.creatorProxy.toLowerCase(),
      grant.tierId,
      grant.declaration,
      grant.signature,
      grant.version,
    ],
  );
}

// ─── Signature verification ───────────────────────────────────────────────────

// Verifies that grant.signature was produced by creatorPrimaryWallet over the grant's
// structured data, using the same scheme as the on-chain DENAccessGrant contract.
//
// Returns true if the recovered signer matches creatorPrimaryWallet, false otherwise.
// Throws if the signature or declaration are malformed.
export async function verifyGrantSignature(
  grant: StoredGrant,
  creatorPrimaryWallet: `0x${string}`,
): Promise<boolean> {
  let parsed: { paths: string[] };
  try {
    parsed = JSON.parse(grant.declaration);
  } catch {
    throw new Error('grant declaration is not valid JSON');
  }

  if (!Array.isArray(parsed.paths) || parsed.paths.some((p) => typeof p !== 'string')) {
    throw new Error('grant declaration must have a paths array of strings');
  }

  const paths = parsed.paths;
  const tierId = BigInt(grant.tierId);
  const version = BigInt(grant.version);
  const creatorProxy = grant.creatorProxy as `0x${string}`;

  // Step 1: pathsHash = keccak256(abi.encode(paths))
  const pathsHash = keccak256(
    encodeAbiParameters([{ type: 'string[]' }], [paths]),
  );

  // Step 2: structHash = keccak256(abi.encode("DEN-access-grant", proxy, tierId, pathsHash, version))
  const structHash = keccak256(
    encodeAbiParameters(
      [
        { type: 'string' },
        { type: 'address' },
        { type: 'uint256' },
        { type: 'bytes32' },
        { type: 'uint256' },
      ],
      ['DEN-access-grant', creatorProxy, tierId, pathsHash, version],
    ),
  );

  // Step 3: recover signer from EIP-191 prefixed structHash
  // { message: { raw: structHash } } tells viem to apply the \x19Ethereum Signed Message:\n32 prefix
  // to structHash — matching abi.encodePacked("\x19Ethereum Signed Message:\n32", structHash) on-chain
  const signer = await recoverMessageAddress({
    message: { raw: structHash as `0x${string}` },
    signature: grant.signature as `0x${string}`,
  });

  return signer.toLowerCase() === creatorPrimaryWallet.toLowerCase();
}
