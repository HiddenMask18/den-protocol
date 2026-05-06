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
cd ../contracts && anvil

# In a second terminal — deploy the contracts (deployment scripts TBD)
forge script ... --rpc-url http://localhost:8545 --broadcast
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

### Authentication

All participant-specific routes require a session token obtained via the auth flow below.

**Step 1 — Request a challenge**
```
GET /auth/challenge?wallet=0x<address>
→ { nonce: "abc123..." }
```

**Step 2 — Sign the nonce and verify**

Sign the nonce string with your wallet using EIP-191 personal_sign (standard "sign message" supported by all wallets and libraries like viem/ethers).

```
POST /auth/verify
Body: { wallet: "0x...", nonce: "abc123...", signature: "0x..." }
→ { sessionToken: "...", proxy: "0x..." }
```

Include the session token as a Bearer token on all subsequent requests:
```
Authorization: Bearer <sessionToken>
```

Sessions expire after 24 hours. The returned `proxy` is the stable DEN identity address — it stays the same even if the wallet rotates.

## Project Structure

```
src/
├── chain/
│   ├── abis.ts       # ABI slices for the five DEN contracts
│   ├── client.ts     # viem publicClient (read-only chain connection)
│   └── contracts.ts  # Typed contract instances
├── auth/
│   ├── nonce.ts      # In-memory challenge nonce store (5-min TTL, one-time use)
│   ├── verify.ts     # Signature verification + proxy resolution via identity registry
│   ├── middleware.ts  # Bearer token session validation for protected routes
│   └── routes.ts     # GET /auth/challenge, POST /auth/verify
├── db/
│   └── index.ts      # SQLite init and schema (sessions, blobs, content, grants)
└── index.ts          # Entry point — Hono app, route registration
```

## Implementation Status

| Component | Status |
|---|---|
| Auth layer (wallet challenge/response, session tokens) | Done |
| Chain client + contract instances | Done |
| SQLite database setup | Done |
| Key derivation (HKDF, tier/item paths) | Planned |
| Access grant store + verification | Planned |
| Access gate (on-chain subscription/purchase checks) | Planned |
| Subscriber/buyer content key delivery | Planned |
| Master secret blob store | Planned |
| Content storage (ciphertext + IPFS pinning) | Planned |
| Creator content management API | Planned |
| Migration support (portable data set) | Planned |
| Hoster compensation | Planned (needs on-chain contracts) |
| Moderation layer | Planned (needs on-chain contracts) |
