# DEN Protocol — Contracts

Reference implementation of DEN protocol smart contracts, built with [Foundry](https://getfoundry.sh/).

## Setup

```bash
# From repo root, initialize forge-std dependency first
git submodule update --init

# Then from this directory
forge build
forge test
```

## Structure

- `src/identity/` — DENIdentityProxy (ERC-1967), DENIdentityImpl, DENIdentityRegistry
- `src/subscription/` — DENSubscription (proxy-keyed tiers, escrow, sunset gate)
- `src/content/` — DENContentRegistry (fingerprint lifecycle), DENAccessGrant (signed tier→path declarations)
- `src/purchase/` — DENPurchaseState (permanent purchase records, escrow)
- `src/interfaces/` — interface definitions for all five contracts
- `test/` — 188-test suite covering all contracts

## Foundry Commands

```bash
forge build
forge test
forge fmt
forge snapshot
anvil
```

See [Foundry docs](https://book.getfoundry.sh/) for full reference.