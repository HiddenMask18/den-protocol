# DEN Instance

The off-chain hoster software for the DEN protocol. An instance stores encrypted content, derives content keys on demand, and gates access based on on-chain subscription and purchase state. It never holds plaintext content or unencrypted keys — only the participant with the right wallet can decrypt anything it stores.

See [`spec/den-spec.md`](../spec/den-spec.md) for the full protocol specification and [`spec/den-architecture.md`](../spec/den-architecture.md) for design rationale.

## Prerequisites

- [Bun](https://bun.sh) v1.0+
- [Foundry](https://getfoundry.sh) (for running a local `anvil` chain during development)

## Setup

```bash
# Install dependencies
bun install

# Copy the environment template and fill in your values
cp .env.example .env
```

The `.env` file needs contract addresses. For local development, deploy the contracts to a local anvil node first:

```bash
# From the repo root — start a local Ethereum node
anvil

# In a second terminal — deploy the contracts
cd contracts && forge script script/Deploy.s.sol --rpc-url http://localhost:8545 --broadcast
```

Then paste the deployed addresses into `.env`.

## Running

```bash
# Start the instance
bun run src/index.ts

# With live reload during development
bun --watch run src/index.ts
```

The server starts on `PORT` (default `3000`).

## API

All routes except `GET /auth/challenge` and `GET /creator/blob-pubkey` require a session token as a Bearer header: `Authorization: Bearer <sessionToken>`.

### Authentication

**1. Request a challenge nonce**
```
GET /auth/challenge?wallet=0x<address>
→ { nonce: "abc123..." }
```

**2. Sign and verify**

Sign the nonce string with your wallet using EIP-191 `personal_sign` (supported by all wallets and viem/ethers).
```
POST /auth/verify
Body: { wallet: "0x...", nonce: "abc123...", signature: "0x..." }
→ { sessionToken: "...", proxy: "0x..." }
```

Sessions expire after 24 hours. The returned `proxy` is the stable DEN identity — it doesn't change on wallet rotation.

---

### Creator tooling

These routes are called by a creator client to set up content on the instance. All require auth.

**Dual-blob master secret upload**

The master secret is never sent in plaintext. The creator encrypts it twice client-side, using ECIES (secp256k1 ECDH + HKDF-SHA256 + AES-256-GCM, wire format `[33: ephPub][12: nonce][N+16: ciphertext+tag]`):

```
# Step 1 — get the instance's per-creator public key
GET /creator/blob-pubkey
→ { pubKey: "0x02..." }   (33-byte compressed secp256k1 key, 0x-prefixed)

# Step 2 — upload both encrypted blobs
PUT /creator/blob
Body: {
  operationalBlob:  "0x...",   // master secret encrypted to instance pubKey above
  portabilityBlob:  "0x..."    // master secret encrypted to creator's wallet pubKey
}
→ { stored: true }

# Check upload status
GET /creator/blob
→ { exists: true }

# Retrieve portability blob for migration / backup
GET /creator/portability-blob
→ <raw bytes, Content-Type: application/octet-stream>
```

`operationalBlob` is verified by the instance (decrypted to confirm correct key was used). `portabilityBlob` is stored as-is — the instance cannot decrypt it.

**Content upload**

Creators encrypt content client-side before uploading. The instance computes the SHA-256 fingerprint of the ciphertext — this is the same value to register on-chain via `DENContentRegistry.registerContent(fingerprint, tierId)`.

```
POST /creator/content
Headers: X-Tier-Id: 1
         X-Warnings: ["violence"]   (optional JSON array)
Body: <raw ciphertext bytes, Content-Type: application/octet-stream>
→ { fingerprint: "0x..." }

GET /creator/content
→ [{ fingerprint, tierId, timestamp, warnings }]
```

**Access grant publication**

After publishing a grant on-chain via `DENAccessGrant.publishGrant(tierId, paths, signature)`, store it locally for the portable data set:

```
POST /creator/grant
Body: { tierId: "1", paths: ["tier:1"], signature: "0x...", version: 1 }
→ { stored: true }

GET /creator/grant/:tierId
→ { tierId, paths, version }
```

The signature must be the creator's EIP-191 signature over `keccak256(abi.encode("DEN-access-grant", proxy, tierId, pathsHash, version))`. Version must be `1` for new grants or `existing.version + 1` for updates.

**Portable data set export / import**

Exports everything needed to migrate to another instance or restore from backup. The export bundle is a JSON object containing the portability blob, all content records, and all grants.

```
GET /creator/export
→ {
    portabilityBlob: "0x...",
    content: [{ fingerprint, tierId, warnings, timestamp }],
    grants:  [{ tierId, paths, version, signature }]
  }

POST /creator/import
Body: { portabilityBlob: "0x...", content: [...], grants: [...] }
→ { imported: { content: N, grants: N } }
```

`portabilityBlob` is the creator-encrypted master secret blob (only the creator's wallet can decrypt it). Import is idempotent — duplicate fingerprints and tier IDs are skipped.

**Content deletion**

Remove a content record from the instance (e.g. after key rotation replaces a ciphertext):

```
DELETE /creator/content/:fingerprint
→ 204 No Content
```

---

### Hoster compensation

Callable only by the wallet matching `INSTANCE_OPERATOR_PRIVATE_KEY`. Computes and settles the hoster's resource claim against per-creator fee escrow on-chain (spec §7.2, §13.2).

```
POST /hoster/claim
Body: {
  creatorProxy:  "0x...",   // creator whose escrow to settle against
  storageGB:     12.5,      // declared storage consumed (GB)
  bandwidthGB:   80.0,      // declared bandwidth served (GB)
  instanceSize:  140        // creator_count + subscription_relationship_count for bracket selection
}
→ {
  txHash:        "0x...",
  hostedAmount:  "...",     // wei claimed by hoster
  surplusAmount: "..."      // wei returned to creator
}
```

The instance signs and broadcasts the `claimCompensation` transaction directly. Storage and bandwidth are declared by the hoster and recorded on-chain for community audit (declared-plus-auditable model per spec §7.3).

---

### Content download (subscriber/buyer)

```
GET /content/:fingerprint
→ <raw ciphertext bytes, Content-Type: application/octet-stream>
```

Auth required. Checks on-chain content lifecycle (must be Active or Archived) and moderation state (suspended content returns 403). No entitlement re-check — content key delivery (`POST /access/key`) already gates on live on-chain subscription/purchase state. Ciphertext is useless without the corresponding key.

---

### Key delivery (subscriber/buyer)

```
POST /access/key
Body: { type: "subscription", creatorProxy: "0x...", tierId: "1" }
   or { type: "purchase",     creatorProxy: "0x...", listingId: "42" }
→ { keys: { "tier:1": "0xabc...", "tier:2": "0xdef..." } }
```

The instance checks on-chain entitlement live (no caching), decrypts the creator's master secret blob, derives one 32-byte key per derivation path in the access grant, and returns them. Keys are HKDF-SHA256 outputs — the subscriber uses them to decrypt downloaded ciphertext locally.

## Project Structure

```
src/
├── chain/
│   ├── abis.ts         # ABI slices for all DEN contracts + identity impl
│   ├── client.ts       # viem publicClient (read-only chain connection)
│   ├── wallet.ts       # viem walletClient + operatorAccount (signs compensation txs)
│   └── contracts.ts    # Typed contract instances + getPrimaryWallet()
├── auth/
│   ├── nonce.ts        # In-memory challenge nonce store (5-min TTL, one-time use)
│   ├── verify.ts       # Signature verification + proxy resolution via identity registry
│   ├── middleware.ts   # Bearer token session validation for protected routes
│   └── routes.ts       # GET /auth/challenge, POST /auth/verify
├── crypto/
│   ├── derive.ts       # Pure HKDF-SHA256 key derivation (tier/item paths)
│   └── blob.ts         # Instance master key; per-creator ECIES keypair derivation + decrypt
├── grants/
│   └── store.ts        # Access grant DB CRUD + off-chain signature verification
├── access/
│   ├── gate.ts         # Live on-chain subscription/purchase entitlement checks
│   └── routes.ts       # POST /access/key — key delivery for subscribers and buyers
├── creator/
│   └── routes.ts       # Creator tooling: blob, content, and grant management (tier limits from chain)
├── content/
│   └── routes.ts       # GET /content/:fingerprint — lifecycle + suspension check, ciphertext download
├── hoster/
│   └── routes.ts       # POST /hoster/claim — operator-initiated compensation settlement
├── moderation/
│   └── routes.ts       # POST /moderation/report, POST /moderation/determine — report filing and determination
├── governance/
│   └── routes.ts       # GET /governance/params — live on-chain governance parameter snapshot
├── db/
│   └── index.ts        # SQLite init and schema (sessions, blobs, content, grants)
└── index.ts            # Entry point — Hono app, route registration
```

## Implementation Status

| Component | Status |
|---|---|
| Auth layer (wallet challenge/response, session tokens) | Done |
| Chain client + contract instances | Done |
| SQLite database setup | Done |
| Key derivation (HKDF, tier/item paths) | Done |
| ECIES master secret blob encrypt/decrypt | Done |
| Access grant store + off-chain signature verification | Done |
| Access gate (on-chain subscription/purchase checks) | Done |
| Subscriber/buyer content key delivery (`POST /access/key`) | Done |
| Creator master secret blob upload (dual-blob model) | Done |
| Content upload/download | Done |
| Creator content management API | Done |
| Access grant local publication | Done |
| Migration support (portable data set export/import) | Done |
| Key rotation (tier-by-tier re-encryption) | Done |
| Hoster compensation settlement (`POST /hoster/claim`) | Done |
| Moderation layer (report filing, determination, CSAM path) | Done |
| Creator trust tier enforcement (size + rate limits from chain) | Done |
| Governance parameter read endpoint (`GET /governance/params`) | Done |
