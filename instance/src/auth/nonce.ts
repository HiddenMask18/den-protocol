// In-memory nonce store for the authentication challenge-response flow.
//
// How the auth flow works:
//   1. Client requests a challenge: GET /auth/challenge?wallet=0x...
//   2. Instance generates a random nonce and stores it here (keyed by wallet address)
//   3. Client signs the nonce string with their wallet's private key
//   4. Client sends the wallet address + signature to POST /auth/verify
//   5. Instance calls consumeNonce() — which validates AND deletes the nonce
//   6. If the nonce is valid, the signature is verified against the wallet
//
// Why nonces expire (5-minute TTL):
//   A nonce that was requested but never used shouldn't sit in memory forever.
//   If a client abandons a login attempt, the nonce expires automatically.
//
// Why nonces are one-time-use (consumeNonce deletes on success):
//   A valid signature on a nonce could theoretically be replayed if the nonce persisted.
//   Deleting it after use means each signature can only authenticate once.
//
// Why in-memory (not SQLite):
//   Nonces are short-lived and only needed for the duration of a login attempt.
//   Storing them in the DB would add unnecessary I/O for data that's gone in 5 minutes.
//   If the instance restarts, all pending challenges are lost — clients just request a new one.

import { randomBytes } from 'crypto';

type NonceEntry = {
  nonce: string;
  expiresAt: number;
};

const store = new Map<string, NonceEntry>();

const NONCE_TTL_MS = 5 * 60 * 1000;

export function issueNonce(wallet: string): string {
  const nonce = randomBytes(32).toString('hex');
  store.set(wallet.toLowerCase(), {
    nonce,
    expiresAt: Date.now() + NONCE_TTL_MS,
  });
  return nonce;
}

// Validates and deletes the nonce in one operation. Returns true only if the nonce
// matches and hasn't expired. Any failure (missing, expired, wrong value) returns false.
export function consumeNonce(wallet: string, nonce: string): boolean {
  const key = wallet.toLowerCase();
  const entry = store.get(key);

  if (!entry) return false;

  if (Date.now() > entry.expiresAt) {
    store.delete(key);
    return false;
  }

  if (entry.nonce !== nonce) return false;

  store.delete(key); // one-time use
  return true;
}
