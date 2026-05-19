// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/identity/DENIdentityImpl.sol";
import "../src/identity/DENIdentityRegistry.sol";
import "../src/subscription/DENSubscription.sol";
import "../src/content/DENContentRegistry.sol";
import "../src/content/DENAccessGrant.sol";
import "../src/purchase/DENPurchaseState.sol";

// Deploys all six DEN protocol contracts and wires them together.
//
// Deployment order is determined by constructor dependencies:
//   DENIdentityImpl        (no deps)
//   DENIdentityRegistry    (needs impl)
//   DENSubscription        (needs registry)
//   DENContentRegistry     (needs registry + subscription)
//   DENAccessGrant         (needs registry)
//   DENPurchaseState       (needs registry)
//
// After deployment, two one-time wiring calls connect DENContentRegistry
// to the contracts that need to check the sunset gate:
//   subscription.setContentRegistry(contentRegistry)
//   purchaseState.setContentRegistry(contentRegistry)
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

        // Post-deployment wiring: connect the content registry to the contracts that
        // gate on sunset state. Each is callable once only; there is no access control
        // (no deployer privilege is retained after this call).
        subscription.setContentRegistry(address(contentRegistry));
        purchaseState.setContentRegistry(address(contentRegistry));

        vm.stopBroadcast();

        deployed = DeployedAddresses({
            impl: address(impl),
            registry: address(registry),
            subscription: address(subscription),
            contentRegistry: address(contentRegistry),
            accessGrant: address(accessGrant),
            purchaseState: address(purchaseState)
        });

        console.log("\n=== DEN Protocol Deployment ===");
        console.log("IDENTITY_IMPL_ADDRESS     =", deployed.impl);
        console.log("IDENTITY_REGISTRY_ADDRESS =", deployed.registry);
        console.log("SUBSCRIPTION_ADDRESS      =", deployed.subscription);
        console.log("CONTENT_REGISTRY_ADDRESS  =", deployed.contentRegistry);
        console.log("ACCESS_GRANT_ADDRESS      =", deployed.accessGrant);
        console.log("PURCHASE_STATE_ADDRESS    =", deployed.purchaseState);
        console.log("\nPaste these into instance/.env to connect the off-chain layer.");
    }
}
