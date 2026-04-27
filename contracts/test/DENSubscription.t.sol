// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/identity/DENIdentityImpl.sol";
import "../src/identity/DENIdentityRegistry.sol";
import "../src/interfaces/IDENParticipantIdentity.sol";
import "../src/subscription/DENSubscription.sol";
import "../src/content/DENContentRegistry.sol";

contract DENSubscriptionTest is Test {
    DENIdentityImpl impl;
    DENIdentityRegistry registry;
    DENSubscription subscription;

    uint256 aliceKey;
    address alice;
    uint256 bobKey;
    address bob;
    address carol;

    address aliceProxy;
    address bobProxy;

    uint256 constant TIER_ID = 1;
    uint256 constant PRICE = 1 ether;
    uint256 constant DURATION = 30 days;

    function setUp() public {
        (alice, aliceKey) = makeAddrAndKey("alice");
        (bob, bobKey) = makeAddrAndKey("bob");
        carol = makeAddr("carol");

        impl = new DENIdentityImpl();
        registry = new DENIdentityRegistry(address(impl));
        subscription = new DENSubscription(address(registry));

        vm.prank(alice);
        registry.register();
        aliceProxy = registry.getProxy(alice);

        vm.prank(bob);
        registry.register();
        bobProxy = registry.getProxy(bob);

        vm.prank(alice);
        subscription.setTier(TIER_ID, PRICE, DURATION);

        vm.deal(bob, 10 ether);
    }

    // --- setTier ---

    function test_UnregisteredCannotSetTier() public {
        vm.prank(carol);
        vm.expectRevert("Not registered");
        subscription.setTier(TIER_ID, PRICE, DURATION);
    }

    function test_TierPriceMustBeNonzero() public {
        vm.prank(alice);
        vm.expectRevert("Price must be nonzero");
        subscription.setTier(2, 0, DURATION);
    }

    function test_TierDurationMustBeNonzero() public {
        vm.prank(alice);
        vm.expectRevert("Duration must be nonzero");
        subscription.setTier(2, PRICE, 0);
    }

    // --- subscribe ---

    function test_SubscribeSucceeds() public {
        vm.prank(bob);
        subscription.subscribe{value: PRICE}(aliceProxy, TIER_ID);
        assertTrue(subscription.isSubscribed(bobProxy, aliceProxy, TIER_ID));
    }

    function test_UnregisteredSubscriberCannotSubscribe() public {
        vm.deal(carol, 10 ether);
        vm.prank(carol);
        vm.expectRevert("Subscriber not registered");
        subscription.subscribe{value: PRICE}(aliceProxy, TIER_ID);
    }

    function test_CannotSubscribeToUnregisteredProxy() public {
        vm.prank(bob);
        vm.expectRevert("Creator proxy not registered");
        subscription.subscribe{value: PRICE}(carol, TIER_ID);
    }

    function test_CannotSubscribeToNonexistentTier() public {
        vm.prank(bob);
        vm.expectRevert("Tier does not exist");
        subscription.subscribe{value: PRICE}(aliceProxy, 99);
    }

    function test_IncorrectPaymentReverts() public {
        vm.prank(bob);
        vm.expectRevert("Incorrect payment amount");
        subscription.subscribe{value: 0.5 ether}(aliceProxy, TIER_ID);
    }

    // --- expiry and access ---

    function test_SubscriptionExpiresAfterDuration() public {
        vm.prank(bob);
        subscription.subscribe{value: PRICE}(aliceProxy, TIER_ID);

        vm.warp(block.timestamp + DURATION + 1);
        assertFalse(subscription.isSubscribed(bobProxy, aliceProxy, TIER_ID));
    }

    function test_SubscriptionActiveBeforeExpiry() public {
        vm.prank(bob);
        subscription.subscribe{value: PRICE}(aliceProxy, TIER_ID);

        vm.warp(block.timestamp + DURATION - 1);
        assertTrue(subscription.isSubscribed(bobProxy, aliceProxy, TIER_ID));
    }

    function test_ExpiryTimestampIsCorrect() public {
        uint256 start = block.timestamp;
        vm.prank(bob);
        subscription.subscribe{value: PRICE}(aliceProxy, TIER_ID);

        assertEq(subscription.getSubscriptionExpiry(bobProxy, aliceProxy, TIER_ID), start + DURATION);
    }

    function test_UnsubscribedProxyIsNotSubscribed() public view {
        assertFalse(subscription.isSubscribed(bobProxy, aliceProxy, TIER_ID));
    }

    // --- renewal extension ---

    function test_RenewalExtendsFromCurrentExpiry() public {
        uint256 start = block.timestamp;

        vm.prank(bob);
        subscription.subscribe{value: PRICE}(aliceProxy, TIER_ID);

        vm.warp(start + DURATION / 2);

        vm.prank(bob);
        subscription.subscribe{value: PRICE}(aliceProxy, TIER_ID);

        assertEq(subscription.getSubscriptionExpiry(bobProxy, aliceProxy, TIER_ID), start + DURATION + DURATION);
    }

    function test_ExpiredSubscriptionRenewsFromNow() public {
        vm.prank(bob);
        subscription.subscribe{value: PRICE}(aliceProxy, TIER_ID);

        vm.warp(block.timestamp + DURATION + 1);
        assertFalse(subscription.isSubscribed(bobProxy, aliceProxy, TIER_ID));

        uint256 renewTime = block.timestamp;
        vm.prank(bob);
        subscription.subscribe{value: PRICE}(aliceProxy, TIER_ID);

        assertEq(subscription.getSubscriptionExpiry(bobProxy, aliceProxy, TIER_ID), renewTime + DURATION);
        assertTrue(subscription.isSubscribed(bobProxy, aliceProxy, TIER_ID));
    }

    // --- escrow ---

    function test_EscrowAccumulatesOnSubscription() public {
        vm.prank(bob);
        subscription.subscribe{value: PRICE}(aliceProxy, TIER_ID);
        assertEq(subscription.getEscrowBalance(aliceProxy), PRICE);
    }

    function test_EscrowAccumulatesAcrossMultipleSubscriptions() public {
        address dave = makeAddr("dave");
        vm.prank(dave);
        registry.register();
        vm.deal(dave, 10 ether);

        vm.prank(bob);
        subscription.subscribe{value: PRICE}(aliceProxy, TIER_ID);

        vm.prank(dave);
        subscription.subscribe{value: PRICE}(aliceProxy, TIER_ID);

        assertEq(subscription.getEscrowBalance(aliceProxy), PRICE * 2);
    }

    function test_CreatorCanWithdrawEscrow() public {
        vm.prank(bob);
        subscription.subscribe{value: PRICE}(aliceProxy, TIER_ID);

        uint256 balanceBefore = alice.balance;
        vm.prank(alice);
        subscription.withdraw();

        assertEq(alice.balance, balanceBefore + PRICE);
        assertEq(subscription.getEscrowBalance(aliceProxy), 0);
    }

    function test_WithdrawWithNothingReverts() public {
        vm.prank(alice);
        vm.expectRevert("Nothing to withdraw");
        subscription.withdraw();
    }

    function test_CannotWithdrawOthersEscrow() public {
        vm.prank(bob);
        subscription.subscribe{value: PRICE}(aliceProxy, TIER_ID);

        vm.prank(bob);
        vm.expectRevert("Nothing to withdraw");
        subscription.withdraw();
    }

    function test_UnregisteredCannotWithdraw() public {
        vm.prank(carol);
        vm.expectRevert("Not registered");
        subscription.withdraw();
    }

    // --- events ---

    function test_EmitsSubscribedEvent() public {
        uint256 expectedExpiry = block.timestamp + DURATION;
        vm.prank(bob);
        vm.expectEmit(true, true, true, true);
        emit DENSubscription.Subscribed(bobProxy, aliceProxy, TIER_ID, expectedExpiry);
        subscription.subscribe{value: PRICE}(aliceProxy, TIER_ID);
    }

    // --- wallet rotation survival ---

    // Helper: perform a clean rotation for a proxy from oldKey to newWallet.
    function _rotateWallet(address proxy, uint256 oldKey, address newWallet, uint256 newKey) internal {
        uint256 nonce = IDENParticipantIdentity(proxy).rotationNonce();
        bytes32 structHash = keccak256(abi.encode("DEN-clean-rotation", proxy, nonce));
        bytes32 ethHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(newKey, ethHash);

        address oldWallet = IDENParticipantIdentity(proxy).primaryWallet();
        vm.prank(oldWallet);
        IDENParticipantIdentity(proxy).initiateCleanRotation(newWallet, abi.encodePacked(r, s, v));

        vm.prank(newWallet);
        registry.syncWallet(proxy);

        (oldKey); // silence unused variable warning
    }

    function test_SubscriptionSurvivesCreatorWalletRotation() public {
        // Bob subscribes to alice before rotation
        vm.prank(bob);
        subscription.subscribe{value: PRICE}(aliceProxy, TIER_ID);
        assertTrue(subscription.isSubscribed(bobProxy, aliceProxy, TIER_ID));

        // Alice rotates to alice2
        (address alice2, uint256 alice2Key) = makeAddrAndKey("alice2");
        _rotateWallet(aliceProxy, aliceKey, alice2, alice2Key);

        // Registry now points alice2 → aliceProxy; alice is deregistered
        assertFalse(registry.isRegistered(alice));
        assertTrue(registry.isRegistered(alice2));
        assertEq(registry.getProxy(alice2), aliceProxy);

        // Subscription is keyed by aliceProxy — unchanged by the rotation
        assertTrue(subscription.isSubscribed(bobProxy, aliceProxy, TIER_ID));
    }

    function test_WithdrawByNewWalletAfterCreatorRotation() public {
        vm.prank(bob);
        subscription.subscribe{value: PRICE}(aliceProxy, TIER_ID);

        (address alice2, uint256 alice2Key) = makeAddrAndKey("alice2");
        _rotateWallet(aliceProxy, aliceKey, alice2, alice2Key);

        // alice2 can withdraw the escrow that accumulated under aliceProxy
        uint256 balanceBefore = alice2.balance;
        vm.prank(alice2);
        subscription.withdraw();

        assertEq(alice2.balance, balanceBefore + PRICE);
        assertEq(subscription.getEscrowBalance(aliceProxy), 0);
    }

    // --- sunset gate ---

    // No new subscriptions after the creator has an active sunset notice (spec §5.6).
    function test_SubscribeBlockedAfterSunset() public {
        // Deploy content registry and wire it to the subscription contract.
        DENContentRegistry cr = new DENContentRegistry(address(registry), address(subscription));
        subscription.setContentRegistry(address(cr));

        // Register an operator and have alice designate it.
        address op = makeAddr("op");
        vm.prank(op);
        registry.register();
        address opProxy = registry.getProxy(op);
        vm.prank(alice);
        cr.setContentOperator(opProxy);

        // Register a content fingerprint so the operator can issue a sunset notice.
        bytes32 fp = keccak256("test-content");
        vm.prank(alice);
        cr.registerContent(fp, TIER_ID);

        vm.prank(op);
        cr.issueSunsetNotice(fp);

        // Bob cannot subscribe while sunset is active.
        vm.prank(bob);
        vm.expectRevert("Creator has active sunset notice");
        subscription.subscribe{value: PRICE}(aliceProxy, TIER_ID);
    }

    function test_SubscriptionSurvivesSubscriberWalletRotation() public {
        vm.prank(bob);
        subscription.subscribe{value: PRICE}(aliceProxy, TIER_ID);
        assertTrue(subscription.isSubscribed(bobProxy, aliceProxy, TIER_ID));

        // Bob rotates to bob2
        (address bob2, uint256 bob2Key) = makeAddrAndKey("bob2");
        _rotateWallet(bobProxy, bobKey, bob2, bob2Key);

        assertFalse(registry.isRegistered(bob));
        assertTrue(registry.isRegistered(bob2));
        assertEq(registry.getProxy(bob2), bobProxy);

        // Subscription is keyed by bobProxy — unchanged by the rotation.
        // Instance would call: getProxy(bob2) → bobProxy → isSubscribed(bobProxy, aliceProxy, tierId)
        assertTrue(subscription.isSubscribed(bobProxy, aliceProxy, TIER_ID));
    }
}
