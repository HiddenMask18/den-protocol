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

Finally, register the operator wallet on-chain — a fresh anvil starts with no registrations, and
`GET /creator/url-signature` returns 503 until the operator has an identity proxy (see Operator
setup below). With the default anvil account 1 as your operator:

```bash
# IDENTITY_REGISTRY_ADDRESS = the value you pasted into .env
# The key below is Foundry's well-known anvil account 1 — public, valueless, LOCAL ONLY.
# Never use it (or any anvil default key) on a real network.
cast send $IDENTITY_REGISTRY_ADDRESS "register()" \
  --private-key 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d \
  --rpc-url http://localhost:8545
```

Re-run this after any fresh `anvil` restart (chain state, including registrations, is wiped).

### Base Sepolia / production

For a real deployment against Base Sepolia (testnet) or Base mainnet:

```bash
# Testnet
forge script script/Deploy.s.sol --rpc-url $BASE_SEPOLIA_RPC_URL --broadcast --verify

# Mainnet
forge script script/Deploy.s.sol --rpc-url $BASE_RPC_URL --broadcast --verify
```

Update `.env` with the deployed addresses and set `CHAIN=base` and `RPC_URL` to your RPC endpoint.

### Operator setup

The instance operator wallet must be a registered DEN participant. Call `DENIdentityRegistry.register()` with the operator wallet to deploy its identity proxy. Registration is also a prerequisite for `GET /creator/url-signature` — the operator proxy is the `receivingInstanceProxy` creators pass to `updateInstanceURL`.

Set `INSTANCE_PUBLIC_URL` to the instance's public base URL (no trailing slash). This is the URL creators record on-chain as their home instance; `GET /creator/url-signature` refuses to countersign anything else.

For each creator hosted, **the creator** calls `DENContentRegistry.setContentOperator(instanceOpProxy)` to authorize this instance's operator wallet. This is required before sunset notices can be issued and before `POST /hoster/claim` will succeed for that creator.

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

### Public discovery

Unauthenticated. No wallet, session, or account required (spec §6.5).

```
GET /profile/:proxy
→ {
    proxy:    "0x...",
    handle:   "alice" | null,
    bio:      "..." | null,
    tiers: [{ tierId, price, duration, token }],
    publicContent: [{
      fingerprint, tierId, timestamp,
      warnings: ["tag"] | null,
      contentKey: "0x..."    // 32-byte key — client decrypts ciphertext locally
    }],
    contentWarnings: [{ fingerprint, tierId, warnings: ["tag"] }]
  }
```

`tiers` is sourced from on-chain `TierSet` events (price in wei, duration in seconds, token is the ERC-20 address or `address(0)` for ETH). `publicContent` includes the decryption key so clients can fetch and decrypt the ciphertext from `GET /content/:fingerprint` without auth. `contentWarnings` covers paywalled posts — metadata only, no key.

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

**Instance URL countersignature**

To record this instance as their home instance on-chain, a creator calls `DENIdentityImpl.updateInstanceURL(url, receivingInstanceProxy, instanceSig)` — which requires the receiving instance's primary wallet to countersign `keccak256(abi.encode("DEN-url-confirm", creatorProxy, url, urlUpdateNonce))` as an EIP-191 personal message. This endpoint produces that signature:

```
GET /creator/url-signature
→ { url, receivingInstanceProxy, instanceSig, nonce }
```

The instance signs only its own configured `INSTANCE_PUBLIC_URL` (503 if unset), with the operator wallet (which must be a registered DEN participant — `receivingInstanceProxy` is its proxy). The nonce is read live from the creator's proxy contract, so a signature is valid for exactly one `updateInstanceURL` call. The client passes the three returned values straight through to the contract.

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

**Creator profile**

Sets the instance-stored bio displayed on the public profile. Optional — creators without a bio return `bio: null`.

```
PUT /creator/profile
Body: { bio: "..." | null }
→ { stored: true }
```

**Public content designation**

Marks a content item as publicly visible (accessible without a subscription) or reverts it to private. When marking public, the creator supplies the symmetric content key so the instance can include it in `GET /profile/:proxy`.

The key MUST be a fresh random per-post key generated client-side when the content was encrypted for public posting. It MUST NOT be a derivation-path key (`deriveKey(masterSecret, "tier:" + ...)`): private ciphertext is served to any authenticated participant and fingerprints are enumerable on-chain, so a published tier key would unlock every post in that tier for everyone. The instance stores the key as given and cannot verify how it was derived — key discipline is the client's responsibility.

```
PUT /creator/content/:fingerprint/visibility
Body: { isPublic: true,  contentKey: "0x<64 hex chars>" }
   or { isPublic: false }
→ { stored: true }
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

### Content listing (subscriber)

Enumerates a creator's content for one tier the caller is subscribed to. `GET /profile/:proxy` (unauthenticated) only exposes public content and *warned* paywalled posts — an unwarned paywalled post is invisible there, so a subscribed viewer needs this endpoint to discover what to request keys for. This is the data source for the subscriber feed.

```
GET /content/by-creator/:proxy?tierId=1
→ {
    content: [{
      fingerprint, tierId,
      timestamp,                  // Unix ms, newest first
      warnings: ["tag"] | null
    }],
    nextCursor: null              // reserved for future pagination; always null in v1
  }
```

Auth required. Entitlement is gated per-tier by the same live on-chain check as `POST /access/key` — the caller must hold an active subscription to `(proxy, tierId)` and the creator must have a signature-valid access grant for it, else `403`. Metadata only — no ciphertext, no keys. Suspension is not re-checked here (the per-fingerprint download gate enforces it). The response is an object envelope so cursor pagination can be added without a breaking change.

---

### Key delivery (subscriber/buyer)

```
POST /access/key
Body: { type: "subscription", creatorProxy: "0x...", tierId: "1" }
   or { type: "purchase",     creatorProxy: "0x...", listingId: "42" }
→ { keys: { "tier:1": "0xabc...", "tier:2": "0xdef..." } }
```

The instance checks on-chain entitlement live (no caching), decrypts the creator's master secret blob, derives one 32-byte key per derivation path in the access grant, and returns them. Keys are HKDF-SHA256 outputs — the subscriber uses them to decrypt downloaded ciphertext locally.

---

### Moderation

The protocol floor violation reporting layer (spec §12). Suspension state is checked on-chain — suspended content returns 403 from `GET /content/:fingerprint`.

**Report evidence submission (subscriber)**

Before calling `fileReport` on-chain, a subscriber optionally submits evidence to the instance. The instance stores it and returns a hash the subscriber includes in the on-chain call.

```
POST /moderation/report
Body: { evidence: "<base64 bytes>" }
→ { evidenceHash: "0x...", reportRegistryAddress: "0x..." }
```

The subscriber then calls `DENReportRegistry.fileReport(contentProxy, fingerprint, violationType, evidenceHash)` with their own wallet. The instance cannot relay this — the contract checks `msg.sender`.

**Report inspection (unauthenticated)**

```
GET /moderation/report/:id
→ { reportId, contentProxy, fingerprint, reporter, violationType,
    status, evidenceHash, determinedAt, isLawEnforcementHold }
```

**Creator report discovery (creator auth required)**

Returns all active reports against the authenticated creator's content, including off-chain evidence bytes and the response window from governance.

```
GET /moderation/creator/reports
→ {
    creatorResponseWindowSeconds: "...",
    reports: [{
      reportId, fingerprint, reporter, violationType, status,
      evidenceHash, evidence: "<base64>" | null,
      determinedAt, isLawEnforcementHold
    }]
  }
```

**Operator determination (operator only)**

```
POST /moderation/report/:id/determine
Body: { outcome: "Upheld" | "Dismissed" | "FalseReport" }
→ { txHash: "0x..." }
```

Operator-conflicted reports (where the reporter is the content operator) cannot be determined here — the contract reverts. Those require governance to resolve (spec §12.2).

**Law enforcement hold (operator only)**

```
POST   /moderation/report/:id/le-hold    → { txHash }   // set LE hold (CSAM path)
DELETE /moderation/report/:id/le-hold    → { txHash }   // remove LE hold
```

**Reinstatement after CSAM expiry (any authenticated participant)**

```
POST /moderation/report/:id/reinstate
→ { txHash: "0x..." }
```

Permissionless on-chain after the CSAM suspension duration elapses — the operator cannot block it.

---

### Governance

Read-only snapshot of all live on-chain governance parameters (spec §10). Unauthenticated.

```
GET /governance/params
→ {
    identity:     { wallet_rotation_delay, rotation_announcement_cooldown,
                    handle_change_allowance, handle_change_period, handle_alias_retention_window },
    content:      { subscriber_protection_window, sunset_window_duration },
    compensation: { storage_compensation_lookback,
                    instance_size_brackets: { micro_max, small_max, medium_max } },
    trust_tiers:  { thresholds: { tier_1, tier_2, tier_3 }, lookback_window,
                    post_size_limits: { tier_0, tier_1, tier_2, tier_3 },
                    post_rate_limits: { tier_0, tier_1, tier_2, tier_3 } },
    reporting:    { creator_response_window, csam_suspension_duration },
    fees:         { protocol_fee_bps },
    misc:         { inactivity_grace_period, batch_settlement_interval,
                    subscription_expiry_grace_period, resolver_cache_ttl }
  }
```

All numeric values are strings (BigInt serialization). `lookback_window` returns `"all-time"` when 0. `post_rate_limits.tier_3` returns `"unlimited"` when unbounded.

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
│   └── routes.ts       # GET /content/:fingerprint download + GET /content/by-creator/:proxy listing
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
