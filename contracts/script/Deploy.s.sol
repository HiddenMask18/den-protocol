// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/identity/DENIdentityImpl.sol";
import "../src/identity/DENIdentityRegistry.sol";
import "../src/subscription/DENSubscription.sol";
import "../src/content/DENContentRegistry.sol";
import "../src/content/DENAccessGrant.sol";
import "../src/purchase/DENPurchaseState.sol";
import "../src/compensation/DENHostCompensation.sol";
import "../src/reporting/DENReportRegistry.sol";
import "../src/interfaces/IDENHostCompensation.sol";

// Deploys all DEN protocol contracts and wires them together.
//
// Deployment order is determined by constructor dependencies:
//   DENIdentityImpl        (no deps)
//   DENIdentityRegistry    (needs impl)
//   DENSubscription        (needs registry)
//   DENContentRegistry     (needs registry + subscription)
//   DENAccessGrant         (needs registry)
//   DENPurchaseState       (needs registry)
//   DENHostCompensation    (needs registry + contentRegistry)
//
// Post-deployment wiring:
//   subscription.setContentRegistry(contentRegistry)   — sunset gate
//   purchaseState.setContentRegistry(contentRegistry)  — sunset gate
//   subscription.setCompensation(compensation)          — protocol fee routing
//   purchaseState.setCompensation(compensation)         — protocol fee routing
//   compensation.setSubscriptionContract(subscription)  — authorize depositor
//   compensation.setPurchaseContract(purchaseState)     — authorize depositor
//   compensation.setTokenRates(address(0), ethRates)    — initial ETH rates
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
        address impl;
        address registry;
        address subscription;
        address contentRegistry;
        address accessGrant;
        address purchaseState;
        address compensation;
        address reportRegistry;
    }

    function run() external returns (DeployedAddresses memory deployed) {
        uint256 deployerKey = vm.envOr("DEPLOYER_PRIVATE_KEY", ANVIL_DEFAULT_KEY);
        address deployer = vm.addr(deployerKey);

        console.log("Deployer:", deployer);
        console.log("Chain ID:", block.chainid);

        vm.startBroadcast(deployerKey);

        // 1. Logic contract for identity proxies — deployed once, shared by all participants.
        //    Constructor sets _initialized = 1 to prevent direct re-initialization.
        DENIdentityImpl impl = new DENIdentityImpl();

        // 2. Registry — deploys per-participant ERC-1967 proxies on register().
        DENIdentityRegistry registry = new DENIdentityRegistry(address(impl));

        // 3. Subscription — proxy-keyed tiers and escrow. Needs registry for proxy lookups.
        DENSubscription subscription = new DENSubscription(address(registry));

        // 4. Content registry — fingerprint lifecycle. Needs subscription to check active
        //    subscriber count when a sunset notice is issued (spec §7.5).
        DENContentRegistry contentRegistry = new DENContentRegistry(
            address(registry),
            address(subscription)
        );

        // 5. Access grant — signed tier→derivation-path declarations with replay protection.
        DENAccessGrant accessGrant = new DENAccessGrant(address(registry));

        // 6. Purchase state — permanent purchase records for shop items and packs.
        DENPurchaseState purchaseState = new DENPurchaseState(address(registry));

        // 7. Host compensation — per-creator escrow, protocol fee collection, hoster resource claims.
        DENHostCompensation compensation = new DENHostCompensation(
            address(registry),
            address(contentRegistry)
        );

        // 8. Report registry — protocol floor violation reporting, suspension, CSAM LE referral path.
        //    setGovernance() is NOT called here — the governance contract does not exist in V1.
        //    Operator-conflicted reports will remain unresolvable until governance is deployed and wired.
        DENReportRegistry reportRegistry = new DENReportRegistry(
            address(registry),
            address(subscription),
            address(purchaseState),
            address(contentRegistry)
        );

        // Post-deployment wiring.

        // Sunset gate: subscription and purchase contracts check active sunset before accepting payment.
        subscription.setContentRegistry(address(contentRegistry));
        purchaseState.setContentRegistry(address(contentRegistry));

        // Protocol fee routing: subscription and purchase contracts split 2.5% into per-creator escrow.
        subscription.setCompensation(address(compensation));
        purchaseState.setCompensation(address(compensation));

        // Authorize depositors: only these two contracts may call depositFee.
        compensation.setSubscriptionContract(address(subscription));
        compensation.setPurchaseContract(address(purchaseState));

        // Initial progressive rate table for ETH (address(0)), spec §13.4.
        // Rates in wei per declared GB, calibrated at approximately $2000/ETH.
        // Governance parameters — update via setTokenRates as ETH price changes.
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
            impl: address(impl),
            registry: address(registry),
            subscription: address(subscription),
            contentRegistry: address(contentRegistry),
            accessGrant: address(accessGrant),
            purchaseState: address(purchaseState),
            compensation: address(compensation),
            reportRegistry: address(reportRegistry)
        });

        console.log("\n=== DEN Protocol Deployment ===");
        console.log("IDENTITY_IMPL_ADDRESS     =", deployed.impl);
        console.log("IDENTITY_REGISTRY_ADDRESS =", deployed.registry);
        console.log("SUBSCRIPTION_ADDRESS      =", deployed.subscription);
        console.log("CONTENT_REGISTRY_ADDRESS  =", deployed.contentRegistry);
        console.log("ACCESS_GRANT_ADDRESS      =", deployed.accessGrant);
        console.log("PURCHASE_STATE_ADDRESS    =", deployed.purchaseState);
        console.log("COMPENSATION_ADDRESS      =", deployed.compensation);
        console.log("REPORT_REGISTRY_ADDRESS   =", deployed.reportRegistry);
        console.log("\nPaste these into instance/.env to connect the off-chain layer.");
        console.log("Note: call reportRegistry.setGovernance(addr) once the governance contract is deployed.");
    }
}
