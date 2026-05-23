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
- `src/subscription/` — DENSubscription (proxy-keyed tiers, ETH + ERC-20 escrow, sunset gate)
- `src/content/` — DENContentRegistry (fingerprint lifecycle), DENAccessGrant (signed tier→path declarations)
- `src/purchase/` — DENPurchaseState (permanent purchase records, ETH + ERC-20 escrow)
- `src/compensation/` — DENHostCompensation (per-creator fee escrow, progressive bracket rates, hoster claim)
- `src/reporting/` — DENReportRegistry (protocol floor violation reports, CSAM LE hold path, governance-resolved conflicted reports)
- `src/trust/` — DENTrustTier (creator trust tier graduation via qualified inbound transactions)
- `src/governance/` — DENGovernanceParams (on-chain adjustable protocol parameters, spec §10/§13.4)
- `src/interfaces/` — interface definitions for all contracts
- `script/` — Deploy.s.sol: deploys all contracts in dependency order and wires post-deploy calls
- `test/` — 393-test suite covering all contracts

## Foundry Commands

```bash
forge build
forge test
forge fmt
forge snapshot
anvil
```

See [Foundry docs](https://book.getfoundry.sh/) for full reference.