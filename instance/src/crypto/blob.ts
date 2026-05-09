// Instance master key management and ECIES encryption for master secret blobs.
//
// Architecture (B+ model):
//   The instance holds one INSTANCE_MASTER_KEY (32-byte hex in env). Per-creator blob keys
//   are derived deterministically from it using HKDF, so a DB leak alone is useless — an
//   attacker needs both the DB and the instance master key to decrypt any blob.
//
//   Each creator's master secret is stored in master_secret_blobs.blob as ECIES ciphertext
//   encrypted to the creator's derived public key. The instance decrypts on demand at key
//   derivation time and never holds the plaintext longer than one request.
//
// ECIES scheme:
//   Key agreement : secp256k1 ECDH (ephemeral sender key × recipient key)
//   KDF           : HKDF-SHA256 (shared secret → 32-byte AES key; ephemeral pubkey as salt)
//   Encryption    : AES-256-GCM (Web Crypto API, available in Bun without any import)
//   Domain tag    : "den-blob-v1" as HKDF info — binds derived key to this protocol and version
//
// Wire format (bytes):
//   [0..33)  compressed ephemeral secp256k1 public key (33 bytes)
//   [33..45) AES-GCM nonce / IV (12 bytes)
//   [45..)   AES-GCM ciphertext with 16-byte auth tag appended (N + 16 bytes)
//
// The auth tag is part of the ciphertext slice — crypto.subtle.decrypt expects it there and
// will throw if it does not match, catching both tampering and accidental corruption.

import { secp256k1 } from '@noble/curves/secp256k1';
import { hkdf } from '@noble/hashes/hkdf';
import { sha256 } from '@noble/hashes/sha256';

// ─── Instance master key ─────────────────────────────────────────────────────

let _instanceMasterKey: Uint8Array | null = null;

export function loadInstanceMasterKey(): void {
  const raw = process.env.INSTANCE_MASTER_KEY;
  if (!raw) {
    throw new Error(
      'INSTANCE_MASTER_KEY is not set. ' +
      'Generate one with: openssl rand -hex 32',
    );
  }
  if (!/^[0-9a-fA-F]{64}$/.test(raw)) {
    throw new Error(
      'INSTANCE_MASTER_KEY must be exactly 64 hex characters (32 bytes). ' +
      'Generate one with: openssl rand -hex 32',
    );
  }
  _instanceMasterKey = hexToBytes(raw);
}

export function getInstanceMasterKey(): Uint8Array {
  if (!_instanceMasterKey) {
    throw new Error('Instance master key not loaded — call loadInstanceMasterKey() at startup');
  }
  return _instanceMasterKey;
}

// ─── Per-creator blob key derivation ─────────────────────────────────────────

// Derives a deterministic secp256k1 keypair for a specific creator's blob.
// The private key is derived from the instance master key using HKDF so that:
//   - Different creators get different keys (no cross-creator decryption)
//   - The derivation is reproducible at runtime without storing per-creator keys
//
// The returned privKey is a Uint8Array for use with secp256k1 operations.
// The returned pubKey is the compressed 33-byte public key given to creators for encryption.
export function deriveCreatorBlobKey(creatorProxy: string): { privKey: Uint8Array; pubKey: Uint8Array } {
  const info = new TextEncoder().encode('creator-blob-key:' + creatorProxy.toLowerCase());
  const privKey = hkdf(sha256, getInstanceMasterKey(), undefined, info, 32);
  const pubKey = secp256k1.getPublicKey(privKey, true); // compressed = 33 bytes
  return { privKey, pubKey };
}

// ─── ECIES encrypt / decrypt ──────────────────────────────────────────────────

// Encrypts plaintext to a secp256k1 recipient public key.
// Used by Phase 3 creator tooling when a creator uploads their master secret.
export async function encryptBlob(
  plaintext: Uint8Array,
  recipientPubKey: Uint8Array,
): Promise<Uint8Array> {
  // Ephemeral keypair — new for every encryption so blobs are unlinkable
  const ephemeralPriv = secp256k1.utils.randomPrivateKey();
  const ephemeralPub = secp256k1.getPublicKey(ephemeralPriv, true); // 33 bytes compressed

  // ECDH: shared secret from ephemeral private key × recipient public key
  // getSharedSecret returns a 33-byte compressed point; slice(1) extracts the 32-byte x-coordinate
  const rawShared = secp256k1.getSharedSecret(ephemeralPriv, recipientPubKey);
  const encKey = deriveEncKey(rawShared.slice(1), ephemeralPub);

  const nonce = crypto.getRandomValues(new Uint8Array(12));
  const aesKey = await importAesKey(encKey);
  // Wrap in new Uint8Array() to guarantee Uint8Array<ArrayBuffer> — required by crypto.subtle
  const ciphertext = new Uint8Array(
    await crypto.subtle.encrypt({ name: 'AES-GCM', iv: new Uint8Array(nonce) }, aesKey, new Uint8Array(plaintext)),
  );

  // Concatenate wire format
  const out = new Uint8Array(33 + 12 + ciphertext.length);
  out.set(ephemeralPub, 0);
  out.set(nonce, 33);
  out.set(ciphertext, 45);
  return out;
}

// Decrypts a blob produced by encryptBlob using the recipient's private key.
// Throws if the blob is malformed, truncated, or the auth tag does not match.
export async function decryptBlob(
  blob: Uint8Array,
  recipientPrivKey: Uint8Array,
): Promise<Uint8Array> {
  if (blob.length < 45 + 16) {
    // 33 (pubkey) + 12 (nonce) + 16 (min ciphertext: empty plaintext + auth tag)
    throw new Error('blob is too short to be a valid ECIES ciphertext');
  }

  const ephemeralPub = blob.slice(0, 33);
  const nonce = blob.slice(33, 45);
  const ciphertext = blob.slice(45);

  // getSharedSecret returns a 33-byte compressed point; slice(1) extracts the 32-byte x-coordinate
  const rawShared = secp256k1.getSharedSecret(recipientPrivKey, ephemeralPub);
  const encKey = deriveEncKey(rawShared.slice(1), ephemeralPub);

  const aesKey = await importAesKey(encKey);
  return new Uint8Array(
    await crypto.subtle.decrypt({ name: 'AES-GCM', iv: new Uint8Array(nonce) }, aesKey, new Uint8Array(ciphertext)),
  );
  // crypto.subtle.decrypt throws DOMException if auth tag fails — tampered or corrupted blob
}

// ─── Internal helpers ─────────────────────────────────────────────────────────

// Derives the 32-byte AES key from the ECDH shared secret.
// The ephemeral public key is used as HKDF salt to bind the derived key to this specific
// key exchange — two different ephemeral keys over the same recipient always produce
// different AES keys even if the ECDH output were somehow identical.
function deriveEncKey(sharedSecret: Uint8Array, ephemeralPub: Uint8Array): Uint8Array {
  return hkdf(sha256, sharedSecret, ephemeralPub, new TextEncoder().encode('den-blob-v1'), 32);
}

async function importAesKey(keyBytes: Uint8Array): Promise<CryptoKey> {
  return crypto.subtle.importKey('raw', new Uint8Array(keyBytes), { name: 'AES-GCM' }, false, ['encrypt', 'decrypt']);
}

function hexToBytes(hex: string): Uint8Array {
  const bytes = new Uint8Array(hex.length / 2);
  for (let i = 0; i < bytes.length; i++) {
    bytes[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  }
  return bytes;
}
