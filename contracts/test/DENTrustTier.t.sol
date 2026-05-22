// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/identity/DENIdentityImpl.sol";
import "../src/identity/DENIdentityRegistry.sol";
import "../src/subscription/DENSubscription.sol";
import "../src/content/DENContentRegistry.sol";
import "../src/purchase/DENPurchaseState.sol";
import "../src/trust/DENTrustTier.sol";
import "../src/interfaces/IDENTrustTier.sol";

contract DENTrustTierTest is Test {

    DENIdentityImpl impl;
    DENIdentityRegistry registry;
    DENSubscription subscription;
    DENContentRegistry contentRegistry;
    DENPurchaseState purchaseState;
    DENTrustTier trustTier;

    address alice;
    address bob;
    address carol;
    address operator;

    address aliceProxy;
    address bobProxy;
    address carolProxy;
    address operatorProxy;

    uint256 constant TIER_ID    = 1;
    uint256 constant LISTING_ID = 1;
    uint256 constant PRICE      = 0.1 ether;
    uint256 constant DURATION   = 30 days;

    function setUp() public {
        alice    = makeAddr("alice");
        bob      = makeAddr("bob");
        carol    = makeAddr("carol");
        operator = makeAddr("operator");

        impl            = new DENIdentityImpl();
        registry        = new DENIdentityRegistry(address(impl));
        subscription    = new DENSubscription(address(registry));
        contentRegistry = new DENContentRegistry(address(registry), address(subscription));
        purchaseState   = new DENPurchaseState(address(registry));
        trustTier       = new DENTrustTier();

        vm.prank(alice);    registry.register();
        vm.prank(bob);      registry.register();
        vm.prank(carol);    registry.register();
        vm.prank(operator); registry.register();

        aliceProxy    = registry.getProxy(alice);
        bobProxy      = registry.getProxy(bob);
        carolProxy    = registry.getProxy(carol);
        operatorProxy = registry.getProxy(operator);

        // Wire contracts.
        subscription.setContentRegistry(address(contentRegistry));
        purchaseState.setContentRegistry(address(contentRegistry));
        subscription.setTrustTier(address(trustTier));
        purchaseState.setTrustTier(address(trustTier));
        trustTier.setSubscriptionContract(address(subscription));
        trustTier.setPurchaseContract(address(purchaseState));
        trustTier.setContentRegistry(address(contentRegistry));

        // Alice sets up a subscription tier and a shop listing.
        vm.prank(alice); subscription.setTier(TIER_ID, PRICE, DURATION, address(0));
        vm.prank(alice); purchaseState.setListing(LISTING_ID, PRICE, address(0));

        vm.deal(bob, 100 ether);
        vm.deal(carol, 100 ether);
        vm.deal(operator, 100 ether);
    }

    // --- Baseline ---

    function test_NewCreatorStartsAtTierZero() public view {
        assertEq(trustTier.getTier(aliceProxy), 0);
        assertEq(trustTier.getQualifiedCount(aliceProxy), 0);
    }

    // --- Subscription-driven graduation ---

    function test_SubscriptionIncrementsCount() public {
        vm.prank(bob);
        subscription.subscribe{value: PRICE}(aliceProxy, TIER_ID);

        assertEq(trustTier.getQualifiedCount(aliceProxy), 1);
        assertEq(trustTier.getTier(aliceProxy), 0); // still below tier 1 threshold
    }

    function test_TierOneAfterTenDistinctSubscribers() public {
        _fundAndSubscribe(aliceProxy, 10);

        assertEq(trustTier.getQualifiedCount(aliceProxy), 10);
        assertEq(trustTier.getTier(aliceProxy), 1);
    }

    function test_TierTwoAfterFiftyDistinctSubscribers() public {
        _fundAndSubscribe(aliceProxy, 50);

        assertEq(trustTier.getQualifiedCount(aliceProxy), 50);
        assertEq(trustTier.getTier(aliceProxy), 2);
    }

    function test_TierThreeAfterTwoHundredDistinctSubscribers() public {
        _fundAndSubscribe(aliceProxy, 200);

        assertEq(trustTier.getQualifiedCount(aliceProxy), 200);
        assertEq(trustTier.getTier(aliceProxy), 3);
    }

    // --- Purchase-driven graduation ---

    function test_PurchaseIncrementsCount() public {
        vm.prank(bob);
        purchaseState.purchase{value: PRICE}(aliceProxy, LISTING_ID);

        assertEq(trustTier.getQualifiedCount(aliceProxy), 1);
    }

    function test_SubscriptionAndPurchaseBothContribute() public {
        // Bob subscribes — counts once.
        vm.prank(bob);
        subscription.subscribe{value: PRICE}(aliceProxy, TIER_ID);

        // Carol purchases — counts once.
        vm.prank(carol);
        purchaseState.purchase{value: PRICE}(aliceProxy, LISTING_ID);

        assertEq(trustTier.getQualifiedCount(aliceProxy), 2);
    }

    // --- De-duplication ---

    function test_RenewalFromSameSubscriberDoesNotInflateCount() public {
        vm.prank(bob);
        subscription.subscribe{value: PRICE}(aliceProxy, TIER_ID);

        // Skip to expiry, re-subscribe.
        vm.warp(block.timestamp + DURATION + 1);
        vm.prank(bob);
        subscription.subscribe{value: PRICE}(aliceProxy, TIER_ID);

        // Only counted once — same participant proxy.
        assertEq(trustTier.getQualifiedCount(aliceProxy), 1);
    }

    function test_SameParticipantSubscribeAndPurchaseCountsOnce() public {
        vm.prank(bob);
        subscription.subscribe{value: PRICE}(aliceProxy, TIER_ID);

        vm.prank(bob);
        purchaseState.purchase{value: PRICE}(aliceProxy, LISTING_ID);

        // Bob is the same participant proxy — only counted once across both actions.
        assertEq(trustTier.getQualifiedCount(aliceProxy), 1);
    }

    // --- Self-transaction exclusion (spec §9.3) ---

    function test_SelfSubscriptionExcluded() public {
        // Alice subscribes to her own tier — self-transaction.
        vm.prank(alice); vm.deal(alice, 1 ether);
        subscription.subscribe{value: PRICE}(aliceProxy, TIER_ID);

        assertEq(trustTier.getQualifiedCount(aliceProxy), 0);
        assertEq(trustTier.getTier(aliceProxy), 0);
    }

    function test_SelfPurchaseExcluded() public {
        vm.prank(alice); vm.deal(alice, 1 ether);
        purchaseState.purchase{value: PRICE}(aliceProxy, LISTING_ID);

        assertEq(trustTier.getQualifiedCount(aliceProxy), 0);
    }

    // --- Content operator exclusion (spec §9.3) ---

    function test_ContentOperatorSubscriptionExcluded() public {
        // Alice registers operator as her content operator.
        vm.prank(alice);
        contentRegistry.setContentOperator(operatorProxy);

        // Operator subscribes to alice — should be excluded.
        vm.prank(operator);
        subscription.subscribe{value: PRICE}(aliceProxy, TIER_ID);

        assertEq(trustTier.getQualifiedCount(aliceProxy), 0);
    }

    function test_ContentOperatorPurchaseExcluded() public {
        vm.prank(alice);
        contentRegistry.setContentOperator(operatorProxy);

        vm.prank(operator);
        purchaseState.purchase{value: PRICE}(aliceProxy, LISTING_ID);

        assertEq(trustTier.getQualifiedCount(aliceProxy), 0);
    }

    function test_ThirdPartyNotOperatorIsNotExcluded() public {
        vm.prank(alice);
        contentRegistry.setContentOperator(operatorProxy);

        // Bob is not the operator — subscription counts.
        vm.prank(bob);
        subscription.subscribe{value: PRICE}(aliceProxy, TIER_ID);

        assertEq(trustTier.getQualifiedCount(aliceProxy), 1);
    }

    function test_OperatorExclusionDoesNotApplyToOtherCreators() public {
        // Operator is alice's content operator, but carol's content is not managed by anyone.
        vm.prank(alice);
        contentRegistry.setContentOperator(operatorProxy);

        // Carol sets up a tier; operator subscribes to carol (not alice).
        vm.prank(carol);
        subscription.setTier(TIER_ID, PRICE, DURATION, address(0));
        vm.prank(operator);
        subscription.subscribe{value: PRICE}(carolProxy, TIER_ID);

        // Counts toward carol's tier — operator is only excluded for alice's content.
        assertEq(trustTier.getQualifiedCount(carolProxy), 1);
        assertEq(trustTier.getQualifiedCount(aliceProxy), 0);
    }

    // --- Unauthorized direct calls ---

    function test_RevertOnDirectCallNotFromAuthorizedContract() public {
        vm.expectRevert("Unauthorized");
        trustTier.recordTransaction(aliceProxy, bobProxy);
    }

    function test_RevertOnDirectCallFromRandomAddress() public {
        vm.prank(bob);
        vm.expectRevert("Unauthorized");
        trustTier.recordTransaction(aliceProxy, carolProxy);
    }

    // --- Tier graduation is independent per creator ---

    function test_GraduationIsPerCreator() public {
        // Bob subscribes to alice.
        vm.prank(bob);
        subscription.subscribe{value: PRICE}(aliceProxy, TIER_ID);

        // Carol sets a tier; bob subscribes to carol too.
        vm.prank(carol);
        subscription.setTier(TIER_ID, PRICE, DURATION, address(0));
        vm.prank(bob);
        subscription.subscribe{value: PRICE}(carolProxy, TIER_ID);

        assertEq(trustTier.getQualifiedCount(aliceProxy), 1);
        assertEq(trustTier.getQualifiedCount(carolProxy), 1);
    }

    // --- Wiring guards ---

    function test_RevertSetSubscriptionContractTwice() public {
        DENTrustTier fresh = new DENTrustTier();
        fresh.setSubscriptionContract(address(subscription));
        vm.expectRevert("Already set");
        fresh.setSubscriptionContract(address(subscription));
    }

    function test_RevertSetPurchaseContractTwice() public {
        DENTrustTier fresh = new DENTrustTier();
        fresh.setPurchaseContract(address(purchaseState));
        vm.expectRevert("Already set");
        fresh.setPurchaseContract(address(purchaseState));
    }

    function test_RevertSetContentRegistryTwice() public {
        DENTrustTier fresh = new DENTrustTier();
        fresh.setContentRegistry(address(contentRegistry));
        vm.expectRevert("Already set");
        fresh.setContentRegistry(address(contentRegistry));
    }

    function test_RevertWiringFromNonOwner() public {
        DENTrustTier fresh = new DENTrustTier();
        vm.prank(bob);
        vm.expectRevert("Not owner");
        fresh.setSubscriptionContract(address(subscription));
    }

    function test_RevertSetTrustTierTwiceOnSubscription() public {
        vm.expectRevert("Already set");
        subscription.setTrustTier(address(trustTier));
    }

    function test_RevertSetTrustTierTwiceOnPurchaseState() public {
        vm.expectRevert("Already set");
        purchaseState.setTrustTier(address(trustTier));
    }

    // --- No-op when trust tier not wired ---

    function test_SubscriptionWorksWithoutTrustTierWired() public {
        DENSubscription bare = new DENSubscription(address(registry));
        bare.setContentRegistry(address(contentRegistry));
        vm.prank(alice);
        bare.setTier(TIER_ID, PRICE, DURATION, address(0));
        vm.prank(bob);
        bare.subscribe{value: PRICE}(aliceProxy, TIER_ID);
        // No revert — trust tier is optional.
        assertTrue(bare.isSubscribed(bobProxy, aliceProxy, TIER_ID));
    }

    function test_PurchaseWorksWithoutTrustTierWired() public {
        DENPurchaseState bare = new DENPurchaseState(address(registry));
        bare.setContentRegistry(address(contentRegistry));
        vm.prank(alice);
        bare.setListing(LISTING_ID, PRICE, address(0));
        vm.prank(bob);
        bare.purchase{value: PRICE}(aliceProxy, LISTING_ID);
        assertTrue(bare.hasPurchased(bobProxy, aliceProxy, LISTING_ID));
    }

    // --- Threshold boundary conditions ---

    function test_TierOneBoundaryNineSubscribers() public {
        _fundAndSubscribe(aliceProxy, 9);
        assertEq(trustTier.getTier(aliceProxy), 0);
    }

    function test_TierTwoBoundaryFortyNineSubscribers() public {
        _fundAndSubscribe(aliceProxy, 49);
        assertEq(trustTier.getTier(aliceProxy), 1);
    }

    function test_TierThreeBoundaryOneNinetyNineSubscribers() public {
        _fundAndSubscribe(aliceProxy, 199);
        assertEq(trustTier.getTier(aliceProxy), 2);
    }

    // --- TransactionQualified event ---

    function test_EmitsTransactionQualifiedOnFirstSubscription() public {
        vm.expectEmit(true, true, false, true);
        emit IDENTrustTier.TransactionQualified(aliceProxy, bobProxy, 1);
        vm.prank(bob);
        subscription.subscribe{value: PRICE}(aliceProxy, TIER_ID);
    }

    function test_NoEventOnRenewal() public {
        vm.prank(bob);
        subscription.subscribe{value: PRICE}(aliceProxy, TIER_ID);

        vm.warp(block.timestamp + DURATION + 1);

        // No TransactionQualified event should be emitted for the renewal.
        vm.recordLogs();
        vm.prank(bob);
        subscription.subscribe{value: PRICE}(aliceProxy, TIER_ID);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 sig = keccak256("TransactionQualified(address,address,uint256)");
        for (uint i = 0; i < logs.length; i++) {
            assertNotEq(logs[i].topics[0], sig, "Unexpected TransactionQualified on renewal");
        }
    }

    // --- Helpers ---

    // Creates `n` distinct named subscribers, funds them, and has each subscribe to `creatorProxy`.
    function _fundAndSubscribe(address creatorProxy, uint256 n) internal {
        for (uint256 i = 0; i < n; i++) {
            address sub = makeAddr(string(abi.encodePacked("sub", vm.toString(i))));
            vm.prank(sub);
            registry.register();
            vm.deal(sub, PRICE);
            vm.prank(sub);
            subscription.subscribe{value: PRICE}(creatorProxy, TIER_ID);
        }
    }
}
