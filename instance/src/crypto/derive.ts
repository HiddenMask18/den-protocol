// Pure HKDF key derivation for DEN content keys.
//
// Takes a master secret and a derivation path and returns a 32-byte content key.
// The path namespace determines what the key unlocks:
//   "tier:" + tierId    — subscription content for that tier
//   "item:" + listingId — shop item or pack purchase content
//
// No salt is used so that derivation is deterministic — the same secret and path must
// always produce the same key regardless of when or where it runs. A random salt would
// break the ability for a subscriber to re-derive the same key across multiple sessions.
//
// Output is never stored. Callers must use the returned bytes immediately and discard.

import { hkdf } from '@noble/hashes/hkdf';
import { sha256 } from '@noble/hashes/sha256';

const encoder = new TextEncoder();

export function deriveKey(secret: Uint8Array, path: string): Uint8Array {
  return hkdf(sha256, secret, undefined, encoder.encode(path), 32);
}
