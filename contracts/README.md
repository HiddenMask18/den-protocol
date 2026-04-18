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

- `src/identity/` — DENIdentity implementation
- `src/subscription/` — DENSubscription with escrow
- `src/interfaces/` — IDENIdentity, IDENSubscription
- `test/` — test suite

## Foundry Commands

```bash
forge build
forge test
forge fmt
forge snapshot
anvil
```

See [Foundry docs](https://book.getfoundry.sh/) for full reference.