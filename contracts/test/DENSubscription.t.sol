// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/identity/DENIdentity.sol";
import "../src/subscription/DENSubscription.sol";

contract DENSubscriptionTest is Test {
    DENIdentity identity;
    DENSubscription subscription;

    address alice = makeAddr("alice");   // creator
    address bob = makeAddr("bob");       // subscriber
    address carol = makeAddr("carol");   // unregistered

    uint256 constant TIER_ID = 1;
    uint256 constant PRICE = 1 ether;
    uint256 constant DURATION = 30 days;

    function setUp() public {
        identity = new DENIdentity();
        subscription = new DENSubscription(address(identity));

        // register both parties
        vm.prank(alice);
        identity.register();

        vm.prank(bob);
        identity.register();

        // alice sets up a tier
        vm.prank(alice);
        subscription.setTier(TIER_ID, PRICE, DURATION);

        // give bob funds to subscribe with
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
        subscription.subscribe{value: PRICE}(alice, TIER_ID);
        assertTrue(subscription.isSubscribed(bob, alice, TIER_ID));
    }

    function test_UnregisteredSubscriberCannotSubscribe() public {
        vm.deal(carol, 10 ether);
        vm.prank(carol);
        vm.expectRevert("Subscriber not registered");
        subscription.subscribe{value: PRICE}(alice, TIER_ID);
    }

    function test_CannotSubscribeToUnregisteredCreator() public {
        vm.prank(bob);
        vm.expectRevert("Creator not registered");
        subscription.subscribe{value: PRICE}(carol, TIER_ID);
    }

    function test_CannotSubscribeToNonexistentTier() public {
        vm.prank(bob);
        vm.expectRevert("Tier does not exist");
        subscription.subscribe{value: PRICE}(alice, 99);
    }

    function test_IncorrectPaymentReverts() public {
        vm.prank(bob);
        vm.expectRevert("Incorrect payment amount");
        subscription.subscribe{value: 0.5 ether}(alice, TIER_ID);
    }

    // --- expiry and access ---

    function test_SubscriptionExpiresAfterDuration() public {
        vm.prank(bob);
        subscription.subscribe{value: PRICE}(alice, TIER_ID);

        vm.warp(block.timestamp + DURATION + 1);
        assertFalse(subscription.isSubscribed(bob, alice, TIER_ID));
    }

    function test_SubscriptionActiveBeforeExpiry() public {
        vm.prank(bob);
        subscription.subscribe{value: PRICE}(alice, TIER_ID);

        vm.warp(block.timestamp + DURATION - 1);
        assertTrue(subscription.isSubscribed(bob, alice, TIER_ID));
    }

    function test_ExpiryTimestampIsCorrect() public {
        uint256 start = block.timestamp;
        vm.prank(bob);
        subscription.subscribe{value: PRICE}(alice, TIER_ID);

        assertEq(subscription.getSubscriptionExpiry(bob, alice, TIER_ID), start + DURATION);
    }

    function test_UnsubscribedWalletIsNotSubscribed() public view {
        assertFalse(subscription.isSubscribed(bob, alice, TIER_ID));
    }

    // --- renewal extension ---

    function test_RenewalExtendsFromCurrentExpiry() public {
        uint256 start = block.timestamp;

        vm.prank(bob);
        subscription.subscribe{value: PRICE}(alice, TIER_ID);

        // renew halfway through
        vm.warp(start + DURATION / 2);

        vm.prank(bob);
        subscription.subscribe{value: PRICE}(alice, TIER_ID);

        // expiry should be original expiry + one more duration, not now + duration
        uint256 expectedExpiry = start + DURATION + DURATION;
        assertEq(subscription.getSubscriptionExpiry(bob, alice, TIER_ID), expectedExpiry);
    }

    function test_ExpiredSubscriptionRenewsFromNow() public {
        vm.prank(bob);
        subscription.subscribe{value: PRICE}(alice, TIER_ID);

        // let it expire
        vm.warp(block.timestamp + DURATION + 1);
        assertFalse(subscription.isSubscribed(bob, alice, TIER_ID));

        // resubscribe
        uint256 renewTime = block.timestamp;
        vm.prank(bob);
        subscription.subscribe{value: PRICE}(alice, TIER_ID);

        assertEq(subscription.getSubscriptionExpiry(bob, alice, TIER_ID), renewTime + DURATION);
        assertTrue(subscription.isSubscribed(bob, alice, TIER_ID));
    }

    // --- escrow ---

    function test_EscrowAccumulatesOnSubscription() public {
        vm.prank(bob);
        subscription.subscribe{value: PRICE}(alice, TIER_ID);
        assertEq(subscription.getEscrowBalance(alice), PRICE);
    }

    function test_EscrowAccumulatesAcrossMultipleSubscriptions() public {
        address dave = makeAddr("dave");
        vm.prank(dave);
        identity.register();
        vm.deal(dave, 10 ether);

        vm.prank(bob);
        subscription.subscribe{value: PRICE}(alice, TIER_ID);

        vm.prank(dave);
        subscription.subscribe{value: PRICE}(alice, TIER_ID);

        assertEq(subscription.getEscrowBalance(alice), PRICE * 2);
    }

    function test_CreatorCanWithdrawEscrow() public {
        vm.prank(bob);
        subscription.subscribe{value: PRICE}(alice, TIER_ID);

        uint256 balanceBefore = alice.balance;
        vm.prank(alice);
        subscription.withdraw();

        assertEq(alice.balance, balanceBefore + PRICE);
        assertEq(subscription.getEscrowBalance(alice), 0);
    }

    function test_WithdrawWithNothingReverts() public {
        vm.prank(alice);
        vm.expectRevert("Nothing to withdraw");
        subscription.withdraw();
    }

    function test_CannotWithdrawOthersEscrow() public {
        vm.prank(bob);
        subscription.subscribe{value: PRICE}(alice, TIER_ID);

        // bob tries to withdraw alice's escrow — he has nothing
        vm.prank(bob);
        vm.expectRevert("Nothing to withdraw");
        subscription.withdraw();
    }

    // --- events ---

    function test_EmitsSubscribedEvent() public {
        uint256 expectedExpiry = block.timestamp + DURATION;
        vm.prank(bob);
        vm.expectEmit(true, true, true, true);
        emit DENSubscription.Subscribed(bob, alice, TIER_ID, expectedExpiry);
        subscription.subscribe{value: PRICE}(alice, TIER_ID);
    }
}