// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/governance/DENGovernanceParams.sol";
import "../src/identity/DENIdentityImpl.sol";
import "../src/identity/DENIdentityRegistry.sol";
import "../src/subscription/DENSubscription.sol";
import "../src/content/DENContentRegistry.sol";
import "../src/content/DENAccessGrant.sol";
import "../src/purchase/DENPurchaseState.sol";
import "../src/compensation/DENHostCompensation.sol";
import "../src/reporting/DENReportRegistry.sol";
import "../src/trust/DENTrustTier.sol";
import "../src/interfaces/IDENHostCompensation.sol";

// Deploys all DEN protocol contracts and wires them together.
//
// Deployment order is determined by constructor dependencies:
//   DENGovernanceParams    (no deps — deployed first; all other contracts read from it)
//   DENIdentityImpl        (needs govParams)
//   DENIdentityRegistry    (needs impl)
//   DENSubscription        (needs registry)
//   DENContentRegistry     (needs registry + subscription)
//   DENAccessGrant         (needs registry)
//   DENPurchaseState       (needs registry)
//   DENHostCompensation    (needs registry + contentRegistry)
//   DENReportRegistry      (needs registry + subscription + purchaseState + contentRegistry)
//   DENTrustTier           (no constructor deps; wired below)
//
// Post-deployment wiring:
//   subscription.setGovernanceParams(govParams)
//   purchaseState.setGovernanceParams(govParams)
//   contentRegistry.setGovernanceParams(govParams)
//   reportRegistry.setGovernanceParams(govParams)
//   trustTier.setGovernanceParams(govParams)
//   compensation.setGovernanceParams(govParams)
//   registry.setGovernanceParams(govParams)
//   reportRegistry.setGovernance(govParams)          -- Option B governance path (spec §12.2)
//   govParams.setReportRegistry(reportRegistry)      -- enables resolveConflictedReport
//   subscription.setContentRegistry(contentRegistry) -- sunset gate
//   purchaseState.setContentRegistry(contentRegistry)
//   subscription.setCompensation(compensation)       -- protocol fee routing
//   purchaseState.setCompensation(compensation)
//   compensation.setSubscriptionContract(subscription)
//   compensation.setPurchaseContract(purchaseState)
//   compensation.setTokenRates(address(0), ethRates) -- initial ETH rates
//   subscription.setTrustTier(trustTier)
//   purchaseState.setTrustTier(trustTier)
//   trustTier.setSubscriptionContract(subscription)
//   trustTier.setPurchaseContract(purchaseState)
//   trustTier.setContentRegistry(contentRegistry)
//
// Usage:
//   # Dry-run against local anvil (no --broadcast)
//   forge script script/Deploy.s.sol --rpc-url http://localhost:8545
//
//   # Broadcast to anvil
//   forge script script/Deploy.s.sol --rpc-url http://localhost:8545 --broadcast
//
//   # Broadcast to Base mainnet (set DEPLOYER_PRIVATE_KEY in env)
//   forge script script/Deploy.s.sol --rpc-url $BASE_RPC_URL --broadcast --verify
//
// The deployer private key is read from the DEPLOYER_PRIVATE_KEY env var.
// For local anvil development, the default anvil key (account 0) is used as a fallback.

contract DeployDEN is Script {
    // Default anvil account 0 private key — safe to use only against local anvil.
    uint256 constant ANVIL_DEFAULT_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    struct DeployedAddresses {
        address govParams;
        address impl;
        address registry;
        address subscription;
        address contentRegistry;
        address accessGrant;
        address purchaseState;
        address compensation;
        address reportRegistry;
        address trustTier;
    }

    function run() external returns (DeployedAddresses memory deployed) {
        uint256 deployerKey = vm.envOr("DEPLOYER_PRIVATE_KEY", ANVIL_DEFAULT_KEY);
        address deployer = vm.addr(deployerKey);

        console.log("Deployer:", deployer);
        console.log("Chain ID:", block.chainid);

        vm.startBroadcast(deployerKey);

        // 1. Governance parameter store — deployed first; all other contracts read from it.
        //    Initialises with V1 defaults (spec §13.4). Owner is the deployer.
        //    During bootstrap phase, deployer acts as founding maintainer (spec §10.3).
        DENGovernanceParams govParams = new DENGovernanceParams();

        // 2. Logic contract for identity proxies — needs govParams as immutable.
        //    Constructor embeds govParams in bytecode; all proxies delegating to this impl
        //    share the same governance parameter source.
        DENIdentityImpl impl = new DENIdentityImpl(address(govParams));

        // 3. Registry — deploys per-participant ERC-1967 proxies on register().
        DENIdentityRegistry registry = new DENIdentityRegistry(address(impl));

        // 4. Subscription — proxy-keyed tiers and escrow. Needs registry for proxy lookups.
        DENSubscription subscription = new DENSubscription(address(registry));

        // 5. Content registry — fingerprint lifecycle. Needs subscription to check active
        //    subscriber count when a sunset notice is issued (spec §7.5).
        DENContentRegistry contentRegistry = new DENContentRegistry(
            address(registry),
            address(subscription)
        );

        // 6. Access grant — signed tier→derivation-path declarations with replay protection.
        DENAccessGrant accessGrant = new DENAccessGrant(address(registry));

        // 7. Purchase state — permanent purchase records for shop items and packs.
        DENPurchaseState purchaseState = new DENPurchaseState(address(registry));

        // 8. Host compensation — per-creator escrow, protocol fee collection, hoster resource claims.
        DENHostCompensation compensation = new DENHostCompensation(
            address(registry),
            address(contentRegistry)
        );

        // 9. Report registry — protocol floor violation reporting, suspension, CSAM LE referral path.
        DENReportRegistry reportRegistry = new DENReportRegistry(
            address(registry),
            address(subscription),
            address(purchaseState),
            address(contentRegistry)
        );

        // 10. Trust tier — tracks distinct qualified participant counts for creator tier graduation.
        DENTrustTier trustTier = new DENTrustTier();

        // --- Post-deployment wiring ---

        // Wire governance params into all contracts that read governance parameters.
        // DENIdentityImpl already has govParams as an immutable (set at construction).
        registry.setGovernanceParams(address(govParams));
        subscription.setGovernanceParams(address(govParams));
        purchaseState.setGovernanceParams(address(govParams));
        contentRegistry.setGovernanceParams(address(govParams));
        reportRegistry.setGovernanceParams(address(govParams));
        trustTier.setGovernanceParams(address(govParams));
        compensation.setGovernanceParams(address(govParams));

        // Wire Option B governance path for operator-conflicted reports (spec §12.2).
        // DENReportRegistry.determineReport requires msg.sender == _governance for conflicted reports.
        // DENGovernanceParams.resolveConflictedReport() forwards calls as this contract address.
        reportRegistry.setGovernance(address(govParams));
        govParams.setReportRegistry(address(reportRegistry));

        // Sunset gate: subscription and purchase contracts check active sunset before accepting payment.
        subscription.setContentRegistry(address(contentRegistry));
        purchaseState.setContentRegistry(address(contentRegistry));

        // Protocol fee routing: subscription and purchase contracts split fee into per-creator escrow.
        subscription.setCompensation(address(compensation));
        purchaseState.setCompensation(address(compensation));

        // Authorize depositors: only these two contracts may call depositFee.
        compensation.setSubscriptionContract(address(subscription));
        compensation.setPurchaseContract(address(purchaseState));

        // Trust tier wiring: subscription and purchase contracts call recordTransaction on each payment.
        // Content registry wiring enables operator self-exclusion check (spec §9.3).
        subscription.setTrustTier(address(trustTier));
        purchaseState.setTrustTier(address(trustTier));
        trustTier.setSubscriptionContract(address(subscription));
        trustTier.setPurchaseContract(address(purchaseState));
        trustTier.setContentRegistry(address(contentRegistry));

        // Initial progressive rate table for ETH (address(0)), spec §13.4.
        // Rates in wei per declared GB, calibrated at approximately $2000/ETH.
        // Adjustable by governance via setTokenRates as ETH price changes.
        //   Micro  (<80):   storage $0.60/GB = 3e14 wei, bandwidth $0.80/GB = 4e14 wei
        //   Small  (80–200): storage $0.45/GB = 2.25e14 wei, bandwidth $0.60/GB = 3e14 wei
        //   Medium (200–500): storage $0.30/GB = 1.5e14 wei, bandwidth $0.40/GB = 2e14 wei
        //   Large  (500+):  storage $0.46/GB = 2.3e14 wei, bandwidth $0.69/GB = 3.45e14 wei
        IDENHostCompensation.BracketRates[4] memory ethRates;
        ethRates[0] = IDENHostCompensation.BracketRates({storageRatePerGB: 3e14,      bandwidthRatePerGB: 4e14});
        ethRates[1] = IDENHostCompensation.BracketRates({storageRatePerGB: 225000000000000, bandwidthRatePerGB: 3e14});
        ethRates[2] = IDENHostCompensation.BracketRates({storageRatePerGB: 15e13,     bandwidthRatePerGB: 2e14});
        ethRates[3] = IDENHostCompensation.BracketRates({storageRatePerGB: 23e13,     bandwidthRatePerGB: 345000000000000});
        compensation.setTokenRates(address(0), ethRates);

        vm.stopBroadcast();

        deployed = DeployedAddresses({
            govParams:       address(govParams),
            impl:            address(impl),
            registry:        address(registry),
            subscription:    address(subscription),
            contentRegistry: address(contentRegistry),
            accessGrant:     address(accessGrant),
            purchaseState:   address(purchaseState),
            compensation:    address(compensation),
            reportRegistry:  address(reportRegistry),
            trustTier:       address(trustTier)
        });

        console.log("\n=== DEN Protocol Deployment ===");
        console.log("GOVERNANCE_ADDRESS        =", deployed.govParams);
        console.log("IDENTITY_IMPL_ADDRESS     =", deployed.impl);
        console.log("IDENTITY_REGISTRY_ADDRESS =", deployed.registry);
        console.log("SUBSCRIPTION_ADDRESS      =", deployed.subscription);
        console.log("CONTENT_REGISTRY_ADDRESS  =", deployed.contentRegistry);
        console.log("ACCESS_GRANT_ADDRESS      =", deployed.accessGrant);
        console.log("PURCHASE_STATE_ADDRESS    =", deployed.purchaseState);
        console.log("COMPENSATION_ADDRESS      =", deployed.compensation);
        console.log("REPORT_REGISTRY_ADDRESS   =", deployed.reportRegistry);
        console.log("TRUST_TIER_ADDRESS        =", deployed.trustTier);
        console.log("\nPaste these into instance/.env to connect the off-chain layer.");
    }
}
