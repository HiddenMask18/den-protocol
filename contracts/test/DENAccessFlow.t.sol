// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/identity/DENIdentityImpl.sol";
import "../src/identity/DENIdentityRegistry.sol";
import "../src/interfaces/IDENParticipantIdentity.sol";
import "../src/interfaces/IDENContentRegistry.sol";
import "../src/subscription/DENSubscription.sol";
import "../src/content/DENContentRegistry.sol";
import "../src/content/DENAccessGrant.sol";

// Integration test: exercises the complete on-chain access check an instance performs.
// Does not test individual contract logic (covered by unit tests). Tests that the three
// contracts compose correctly and that the full flow survives a creator wallet rotation.
contract DENAccessFlowTest is Test {
    DENIdentityImpl impl;
    DENIdentityRegistry registry;
    DENSubscription subscription;
    DENContentRegistry contentRegistry;
    DENAccessGrant accessGrant;

    uint256 aliceKey;
    address alice;
    uint256 bobKey;
    address bob;

    address aliceProxy;
    address bobProxy;

    uint256 constant TIER_ID = 1;
    uint256 constant PRICE = 1 ether;
    uint256 constant DURATION = 30 days;
    bytes32 constant FINGERPRINT = keccak256("encrypted-content-blob");

    function setUp() public {
        (alice, aliceKey) = makeAddrAndKey("alice");
        (bob, bobKey) = makeAddrAndKey("bob");

        impl = new DENIdentityImpl();
        registry = new DENIdentityRegistry(address(impl));
        subscription = new DENSubscription(address(registry));
        contentRegistry = new DENContentRegistry(address(registry), address(subscription));
        accessGrant = new DENAccessGrant(address(registry));
        subscription.setContentRegistry(address(contentRegistry));

        vm.prank(alice);
        registry.register();
        aliceProxy = registry.getProxy(alice);

        vm.prank(bob);
        registry.register();
        bobProxy = registry.getProxy(bob);

        vm.deal(bob, 10 ether);
    }

    function _signGrant(
        uint256 signerKey,
        address proxy,
        uint256 tierId,
        string[] memory paths,
        uint256 version
    ) internal pure returns (bytes memory) {
        bytes32 pathsHash = keccak256(abi.encode(paths));
        bytes32 structHash = keccak256(abi.encode("DEN-access-grant", proxy, tierId, pathsHash, version));
        bytes32 ethHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, ethHash);
        return abi.encodePacked(r, s, v);
    }

    function _rotateWallet(address proxy, address newWallet, uint256 newKey) internal {
        uint256 nonce = IDENParticipantIdentity(proxy).rotationNonce();
        bytes32 structHash = keccak256(abi.encode("DEN-clean-rotation", proxy, nonce));
        bytes32 ethHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(newKey, ethHash);
        address current = IDENParticipantIdentity(proxy).primaryWallet();
        vm.prank(current);
        IDENParticipantIdentity(proxy).initiateCleanRotation(newWallet, abi.encodePacked(r, s, v));
        vm.prank(newWallet);
        registry.syncWallet(proxy);
    }

    // The full happy path an instance walks through to grant access:
    //   1. creator sets up tier and content
    //   2. subscriber pays
    //   3. instance verifies subscription + access grant + content record
    function test_FullAccessCheckFlow() public {
        // --- Creator setup ---
        vm.prank(alice);
        subscription.setTier(TIER_ID, PRICE, DURATION);

        string[] memory paths = new string[](1);
        paths[0] = "tier:1";
        bytes memory sig = _signGrant(aliceKey, aliceProxy, TIER_ID, paths, 1);
        vm.prank(alice);
        accessGrant.publishGrant(TIER_ID, paths, sig);

        vm.prank(alice);
        contentRegistry.registerContent(FINGERPRINT, TIER_ID);

        // --- Subscriber pays ---
        vm.prank(bob);
        subscription.subscribe{value: PRICE}(aliceProxy, TIER_ID);

        // --- Instance access check (read-only, all three contracts) ---

        // Step 1: active subscription?
        assertTrue(subscription.isSubscribed(bobProxy, aliceProxy, TIER_ID));

        // Step 2: valid access grant for this tier?
        (bool valid, string[] memory returnedPaths) = accessGrant.verifyGrant(aliceProxy, TIER_ID);
        assertTrue(valid);
        assertEq(returnedPaths[0], "tier:1");

        // Step 3: content fingerprint belongs to this tier and is active?
        IDENContentRegistry.ContentRecord memory rec = contentRegistry.getContent(FINGERPRINT);
        assertEq(rec.tierId, TIER_ID);
        assertEq(rec.creatorProxy, aliceProxy);
        assertTrue(contentRegistry.isContentActive(FINGERPRINT));
    }

    // The same access check must pass after creator wallet rotation.
    function test_AccessCheckSurvivesCreatorWalletRotation() public {
        vm.prank(alice);
        subscription.setTier(TIER_ID, PRICE, DURATION);

        string[] memory paths = new string[](1);
        paths[0] = "tier:1";
        bytes memory sig = _signGrant(aliceKey, aliceProxy, TIER_ID, paths, 1);
        vm.prank(alice);
        accessGrant.publishGrant(TIER_ID, paths, sig);

        vm.prank(alice);
        contentRegistry.registerContent(FINGERPRINT, TIER_ID);

        vm.prank(bob);
        subscription.subscribe{value: PRICE}(aliceProxy, TIER_ID);

        // Creator rotates wallet
        (address alice2, uint256 alice2Key) = makeAddrAndKey("alice2");
        _rotateWallet(aliceProxy, alice2, alice2Key);

        // All three checks still pass — everything is keyed by aliceProxy, not alice's wallet
        assertTrue(subscription.isSubscribed(bobProxy, aliceProxy, TIER_ID));

        (bool valid, string[] memory returnedPaths) = accessGrant.verifyGrant(aliceProxy, TIER_ID);
        assertTrue(valid);
        assertEq(returnedPaths[0], "tier:1");

        IDENContentRegistry.ContentRecord memory rec = contentRegistry.getContent(FINGERPRINT);
        assertEq(rec.tierId, TIER_ID);
        assertTrue(contentRegistry.isContentActive(FINGERPRINT));

        // Creator's new wallet can also withdraw escrow
        uint256 balanceBefore = alice2.balance;
        vm.prank(alice2);
        subscription.withdraw();
        assertEq(alice2.balance, balanceBefore + PRICE);

        (alice2Key); // silence unused variable warning
    }

    // Access is denied once a subscription lapses.
    function test_AccessDeniedAfterSubscriptionLapse() public {
        vm.prank(alice);
        subscription.setTier(TIER_ID, PRICE, DURATION);

        string[] memory paths = new string[](1);
        paths[0] = "tier:1";
        bytes memory sig = _signGrant(aliceKey, aliceProxy, TIER_ID, paths, 1);
        vm.prank(alice);
        accessGrant.publishGrant(TIER_ID, paths, sig);

        vm.prank(alice);
        contentRegistry.registerContent(FINGERPRINT, TIER_ID);

        vm.prank(bob);
        subscription.subscribe{value: PRICE}(aliceProxy, TIER_ID);

        // Subscription lapses
        vm.warp(block.timestamp + DURATION + 1);

        // Subscription check fails; grant and content checks still pass (they are independent)
        assertFalse(subscription.isSubscribed(bobProxy, aliceProxy, TIER_ID));

        (bool valid,) = accessGrant.verifyGrant(aliceProxy, TIER_ID);
        assertTrue(valid); // grant is still published

        assertTrue(contentRegistry.isContentActive(FINGERPRINT)); // content still active
    }

    // Access is denied once the creator revokes the access grant.
    function test_AccessDeniedAfterGrantRevocation() public {
        vm.prank(alice);
        subscription.setTier(TIER_ID, PRICE, DURATION);

        string[] memory paths = new string[](1);
        paths[0] = "tier:1";
        bytes memory sig = _signGrant(aliceKey, aliceProxy, TIER_ID, paths, 1);
        vm.prank(alice);
        accessGrant.publishGrant(TIER_ID, paths, sig);

        vm.prank(alice);
        contentRegistry.registerContent(FINGERPRINT, TIER_ID);

        vm.prank(bob);
        subscription.subscribe{value: PRICE}(aliceProxy, TIER_ID);

        // Subscription is still active, but creator revokes the grant
        vm.prank(alice);
        accessGrant.revokeGrant(TIER_ID);

        assertTrue(subscription.isSubscribed(bobProxy, aliceProxy, TIER_ID));

        (bool valid,) = accessGrant.verifyGrant(aliceProxy, TIER_ID);
        assertFalse(valid); // gate fails here — no key derivation path available
    }
}
