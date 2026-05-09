# DEN — Decentralized Encrypted Network

Every creator platform that's tried to serve adult or "risky" content has followed the same path — starts permissive, grows, brings in Visa and Mastercard to scale, and then slowly capitulates to whatever those processors demand. Patreon, SubscribeStar, Fansly — same pattern, different timelines.

DEN is a protocol, not a platform. Payments route through self-custodial crypto wallets via smart contract — no payment processor sits in the middle with a kill switch. Content is end-to-end encrypted so instance operators store ciphertext they can't read, meaning there's nothing to scan and no backdoor to mandate. Creator identity, subscriber relationships, and content are portable by design — no instance can hold an audience hostage. The ecosystem is federated and community-governed, with no central treasury and no entity that can be pressured into compliance.

## How It Works

Creators hold a master secret that never leaves their control. Content is encrypted and stored on instances as ciphertext the operator cannot read. When a subscriber pays, their subscription state is recorded on-chain via smart contract. When they request content, the instance checks that on-chain state, derives a key transiently from the creator's master secret, and serves the decrypted content — nothing stored, nothing interceptable. No subscription state, no key, no access. The math decides, not a platform.

Instances are federated and independently operated. Creator identity, subscriber relationships, and content references are portable by design — a creator can migrate between instances without losing their audience. No instance can hold a creator hostage. No central entity exists to pressure into compliance.

## Current State

The protocol specification and architecture are complete. Implementation is underway in two layers:

**On-chain contracts** (`contracts/`) — complete. Five contracts covering identity (proxy-keyed, rotation-safe), subscriptions (escrow + expiry), content lifecycle (fingerprint registry, sunset flow), access grant declarations (signed tier→path mappings), and purchase state. 188 passing tests.

**Off-chain instance** (`instance/`) — Phase 2 of 4 complete. The auth layer, chain client, SQLite schema, ECIES blob encryption, HKDF key derivation, on-chain access gate, and subscriber/buyer key delivery endpoint are all implemented. Phase 3 (creator tooling — blob upload, content storage, grant publishing) is next.

## Contributing

Looking for 2-3 technical contributors, ideally with EVM/Solidity experience or the depth to pick it up. The work right now is pressure-testing the spec and building the first prototype. If you've read the architecture document and found something wrong or something missing, that's exactly the kind of engagement that's useful.

See [CONTRIBUTING.md](./CONTRIBUTING.md) for how to raise something.

After cloning, initialize the contract library dependency:
```bash
git submodule update --init
```

## Read First

- [MANIFESTO.md](./MANIFESTO.md) — why this exists and what it stands for
- [den-architecture.md](./spec/den-architecture.md) — architecture decisions and design rationale
- [den-spec.md](./spec/den-spec.md) — protocol specification v0.1-draft

## License

[AGPL-3.0](./LICENSE) — any fork run as a hosted service must open source its changes.