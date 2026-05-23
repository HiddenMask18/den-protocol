// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/governance/DENGovernanceParams.sol";
import "../src/identity/DENIdentityImpl.sol";
import "../src/identity/DENIdentityRegistry.sol";
import "../src/subscription/DENSubscription.sol";
import "../src/content/DENContentRegistry.sol";
import "../src/purchase/DENPurchaseState.sol";
import "../src/compensation/DENHostCompensation.sol";
import "../src/reporting/DENReportRegistry.sol";
import "../src/trust/DENTrustTier.sol";
import "../src/interfaces/IDENReportRegistry.sol";

contract DENGovernanceParamsTest is Test {

    DENGovernanceParams govParams;
    DENIdentityImpl impl;
    DENIdentityRegistry registry;
    DENSubscription subscription;
    DENContentRegistry contentRegistry;
    DENPurchaseState purchaseState;
    DENHostCompensation compensation;
    DENReportRegistry reportRegistry;
    DENTrustTier trustTier;

    address owner;
    address alice;
    address bob;
    address aliceProxy;
    address bobProxy;

    function setUp() public {
        owner = address(this);
        alice = makeAddr("alice");
        bob   = makeAddr("bob");

        // Deploy governance params first — all contracts read from it.
        govParams       = new DENGovernanceParams();
        impl            = new DENIdentityImpl(address(govParams));
        registry        = new DENIdentityRegistry(address(impl));
        subscription    = new DENSubscription(address(registry));
        contentRegistry = new DENContentRegistry(address(registry), address(subscription));
        purchaseState   = new DENPurchaseState(address(registry));
        compensation    = new DENHostCompensation(address(registry), address(contentRegistry));
        reportRegistry  = new DENReportRegistry(
            address(registry),
            address(subscription),
            address(purchaseState),
            address(contentRegistry)
        );
        trustTier = new DENTrustTier();

        // Wire governance params into all contracts.
        registry.setGovernanceParams(address(govParams));
        subscription.setGovernanceParams(address(govParams));
        purchaseState.setGovernanceParams(address(govParams));
        contentRegistry.setGovernanceParams(address(govParams));
        reportRegistry.setGovernanceParams(address(govParams));
        trustTier.setGovernanceParams(address(govParams));
        compensation.setGovernanceParams(address(govParams));

        // Wire Option B governance path.
        reportRegistry.setGovernance(address(govParams));
        govParams.setReportRegistry(address(reportRegistry));

        // Wire remaining dependencies.
        subscription.setContentRegistry(address(contentRegistry));
        purchaseState.setContentRegistry(address(contentRegistry));
        subscription.setCompensation(address(compensation));
        purchaseState.setCompensation(address(compensation));
        compensation.setSubscriptionContract(address(subscription));
        compensation.setPurchaseContract(address(purchaseState));
        subscription.setTrustTier(address(trustTier));
        purchaseState.setTrustTier(address(trustTier));
        trustTier.setSubscriptionContract(address(subscription));
        trustTier.setPurchaseContract(address(purchaseState));
        trustTier.setContentRegistry(address(contentRegistry));

        vm.prank(alice); registry.register();
        vm.prank(bob);   registry.register();
        aliceProxy = registry.getProxy(alice);
        bobProxy   = registry.getProxy(bob);
    }

    // --- V1 default values ---

    function test_DefaultWalletRotationDelay() public view {
        assertEq(govParams.getWalletRotationDelay(), 3 days);
    }

    function test_DefaultRotationAnnouncementCooldown() public view {
        assertEq(govParams.getRotationAnnouncementCooldown(), 1 hours);
    }

    function test_DefaultHandleChangeAllowance() public view {
        assertEq(govParams.getHandleChangeAllowance(), 2);
    }

    function test_DefaultHandleChangePeriod() public view {
        assertEq(govParams.getHandleChangePeriod(), 30 days);
    }

    function test_DefaultHandleAliasRetentionWindow() public view {
        assertEq(govParams.getHandleAliasRetentionWindow(), 180 days);
    }

    function test_DefaultSubscriberProtectionWindow() public view {
        assertEq(govParams.getSubscriberProtectionWindow(), 30 days);
    }

    function test_DefaultCreatorResponseWindow() public view {
        assertEq(govParams.getCreatorResponseWindow(), 7 days);
    }

    function test_DefaultCsamSuspensionDuration() public view {
        assertEq(govParams.getCsamSuspensionDuration(), 30 days);
    }

    function test_DefaultTierThresholds() public view {
        assertEq(govParams.getTier1Threshold(), 10);
        assertEq(govParams.getTier2Threshold(), 50);
        assertEq(govParams.getTier3Threshold(), 200);
    }

    function test_DefaultFeeBps() public view {
        assertEq(govParams.getFeeBps(), 250);
    }

    function test_DefaultStorageCompensationLookback() public view {
        assertEq(govParams.getStorageCompensationLookback(), 90 days);
    }

    function test_DefaultInstanceSizeBrackets() public view {
        assertEq(govParams.getMicroMax(), 80);
        assertEq(govParams.getSmallMax(), 200);
        assertEq(govParams.getMediumMax(), 500);
    }

    function test_DefaultPostSizeLimits() public view {
        assertEq(govParams.getPostSizeLimit(0), 524_288_000);
        assertEq(govParams.getPostSizeLimit(1), 1_073_741_824);
        assertEq(govParams.getPostSizeLimit(2), 5_368_709_120);
        assertEq(govParams.getPostSizeLimit(3), 21_474_836_480);
    }

    function test_DefaultPostRateLimits() public view {
        assertEq(govParams.getPostRateLimit(0), 10);
        assertEq(govParams.getPostRateLimit(1), 30);
        assertEq(govParams.getPostRateLimit(2), 100);
        assertEq(govParams.getPostRateLimit(3), type(uint256).max);
    }

    function test_InvalidTierReverts() public {
        vm.expectRevert("Invalid tier");
        govParams.getPostSizeLimit(4);
        vm.expectRevert("Invalid tier");
        govParams.getPostRateLimit(4);
    }

    // --- Ownership ---

    function test_OwnerIsDeployer() public view {
        assertEq(govParams.owner(), owner);
    }

    function test_TransferOwnership() public {
        govParams.transferOwnership(alice);
        assertEq(govParams.owner(), alice);
    }

    function test_TransferOwnershipEmitsEvent() public {
        vm.expectEmit(true, true, false, false);
        emit DENGovernanceParams.OwnershipTransferred(owner, alice);
        govParams.transferOwnership(alice);
    }

    function test_TransferOwnershipZeroReverts() public {
        vm.expectRevert("Zero address");
        govParams.transferOwnership(address(0));
    }

    function test_NonOwnerCannotTransfer() public {
        vm.prank(alice);
        vm.expectRevert("Not owner");
        govParams.transferOwnership(alice);
    }

    // --- Parameter setters: access control ---

    function test_NonOwnerCannotSetWalletRotationDelay() public {
        vm.prank(alice);
        vm.expectRevert("Not owner");
        govParams.setWalletRotationDelay(1 days);
    }

    function test_NonOwnerCannotSetFeeBps() public {
        vm.prank(alice);
        vm.expectRevert("Not owner");
        govParams.setFeeBps(100);
    }

    // --- Parameter updates propagate to contracts ---

    function test_WalletRotationDelayPropagates() public {
        govParams.setWalletRotationDelay(7 days);

        // DENIdentityImpl reads from govParams immutable — WALLET_ROTATION_DELAY() reflects new value.
        // Deploy a proxy against this impl to test.
        DENIdentityImpl proxy = DENIdentityImpl(address(
            new DENIdentityImpl(address(govParams))
        ));
        // Can't call WALLET_ROTATION_DELAY on a non-initialized impl directly.
        // Instead verify via the govParams getter that the contract reads.
        assertEq(IDENGovernanceParams(impl.govParams()).getWalletRotationDelay(), 7 days);
    }

    function test_RotationAnnouncementCooldownPropagates() public {
        govParams.setRotationAnnouncementCooldown(2 hours);
        assertEq(govParams.getRotationAnnouncementCooldown(), 2 hours);
    }

    function test_HandleAliasRetentionPropagates() public {
        govParams.setHandleAliasRetentionWindow(90 days);
        assertEq(registry.HANDLE_ALIAS_RETENTION(), 90 days);
    }

    function test_HandleChangeAllowancePropagates() public {
        govParams.setHandleChangeAllowance(5);
        assertEq(registry.HANDLE_CHANGE_ALLOWANCE(), 5);
    }

    function test_HandleChangePeriodPropagates() public {
        govParams.setHandleChangePeriod(60 days);
        assertEq(registry.HANDLE_CHANGE_PERIOD(), 60 days);
    }

    function test_SubscriberProtectionWindowPropagates() public {
        govParams.setSubscriberProtectionWindow(45 days);
        assertEq(contentRegistry.SUBSCRIBER_PROTECTION_WINDOW(), 45 days);
    }

    function test_CsamSuspensionDurationPropagates() public {
        govParams.setCsamSuspensionDuration(60 days);
        assertEq(reportRegistry.CSAM_SUSPENSION_DURATION(), 60 days);
    }

    function test_CreatorResponseWindowPropagates() public {
        govParams.setCreatorResponseWindow(14 days);
        assertEq(reportRegistry.CREATOR_RESPONSE_WINDOW(), 14 days);
    }

    function test_TierThresholdsPropagateToTrustTier() public {
        govParams.setTierThresholds(20, 100, 500);
        assertEq(trustTier.TIER_1_THRESHOLD(), 20);
        assertEq(trustTier.TIER_2_THRESHOLD(), 100);
        assertEq(trustTier.TIER_3_THRESHOLD(), 500);
    }

    function test_FeeBpsPropagates() public {
        govParams.setFeeBps(200); // 2%
        assertEq(subscription.FEE_BPS(), 200);
        assertEq(purchaseState.FEE_BPS(), 200);
        assertEq(compensation.FEE_BPS(), 200);
    }

    function test_InstanceSizeBracketsPropagateToCompensation() public {
        govParams.setInstanceSizeBrackets(100, 300, 700);
        assertEq(compensation.MICRO_MAX(), 100);
        assertEq(compensation.SMALL_MAX(), 300);
        assertEq(compensation.MEDIUM_MAX(), 700);
    }

    // --- Validation on setters ---

    function test_SetFeeBpsAbove100PercentReverts() public {
        vm.expectRevert("Fee exceeds 100%");
        govParams.setFeeBps(10001);
    }

    function test_SetTierThresholdsInvalidOrderReverts() public {
        vm.expectRevert("Invalid threshold ordering");
        govParams.setTierThresholds(50, 10, 200); // tier1 >= tier2
    }

    function test_SetInstanceSizeBracketsInvalidOrderReverts() public {
        vm.expectRevert("Invalid bracket ordering");
        govParams.setInstanceSizeBrackets(200, 100, 500); // micro >= small
    }

    function test_SetSubscriptionExpiryGracePeriodAbove24hReverts() public {
        vm.expectRevert("Grace period exceeds 24h max (spec 13.4)");
        govParams.setSubscriptionExpiryGracePeriod(25 hours);
    }

    // --- Events ---

    function test_SetWalletRotationDelayEmitsEvent() public {
        vm.expectEmit(false, false, false, true);
        emit DENGovernanceParams.WalletRotationDelayUpdated(5 days);
        govParams.setWalletRotationDelay(5 days);
    }

    function test_SetFeeBpsEmitsEvent() public {
        vm.expectEmit(false, false, false, true);
        emit DENGovernanceParams.FeeBpsUpdated(300);
        govParams.setFeeBps(300);
    }

    function test_SetTierThresholdsEmitsEvent() public {
        vm.expectEmit(false, false, false, true);
        emit DENGovernanceParams.TierThresholdsUpdated(15, 75, 300);
        govParams.setTierThresholds(15, 75, 300);
    }

    // --- Tier threshold change affects getTier() ---

    function test_TierGraduationUsesUpdatedThresholds() public {
        // Lower thresholds so alice immediately graduates with fewer participants.
        govParams.setTierThresholds(1, 2, 3);

        // Simulate one qualifying subscription from bob to alice.
        vm.prank(alice);
        subscription.setTier(1, 0.01 ether, 30 days, address(0));
        vm.deal(bob, 1 ether);
        vm.prank(bob);
        subscription.subscribe{value: 0.01 ether}(aliceProxy, 1);

        // With threshold of 1, alice should now be at tier 1.
        assertEq(trustTier.getTier(aliceProxy), 1);
    }

    // --- feeBps change affects actual payment split ---

    function test_FeeBpsChangeAffectsSubscriptionFee() public {
        // Change fee to 5%.
        govParams.setFeeBps(500);

        vm.prank(alice);
        subscription.setTier(1, 1 ether, 30 days, address(0));

        vm.deal(bob, 10 ether);
        vm.prank(bob);
        subscription.subscribe{value: 1 ether}(aliceProxy, 1);

        // At 5% fee, creator escrow receives 0.95 ETH.
        assertEq(subscription.getEscrowBalance(aliceProxy, address(0)), 0.95 ether);
        // Fee pool receives 0.05 ETH.
        assertEq(compensation.getFeePool(aliceProxy, address(0)), 0.05 ether);
    }

    // --- CSAM suspension duration change affects reinstatement ---

    function test_CsamSuspensionDurationChangeAffectsReinstatement() public {
        // Reduce CSAM suspension to 1 day for test speed.
        govParams.setCsamSuspensionDuration(1 days);

        // Alice registers a listing and bob purchases it.
        vm.prank(alice);
        purchaseState.setListing(1, 0.01 ether, address(0));
        vm.deal(bob, 1 ether);
        vm.prank(bob);
        purchaseState.purchase{value: 0.01 ether}(aliceProxy, 1);

        // Alice registers content and bob files a CSAM report.
        bytes32 fp = keccak256("content1");
        vm.prank(alice);
        contentRegistry.setContentOperator(bobProxy); // bob is the operator for this test
        vm.prank(alice);
        IDENContentRegistry(address(contentRegistry)).registerContent(fp, 1);

        // bob files a report (as subscriber with purchase access — tierId = listingId = 1)
        bytes32 evidenceHash = keccak256("evidence");
        vm.prank(bob);
        reportRegistry.fileReport(fp, block.timestamp, IDENReportRegistry.ViolationCategory.CSAM, evidenceHash);

        uint256 reportId = 0;

        // Should revert before 1 day elapses.
        vm.expectRevert("Suspension period not elapsed");
        reportRegistry.reinstateAfterCsamExpiry(reportId);

        // After 1 day, reinstatement succeeds.
        vm.warp(block.timestamp + 1 days + 1);
        reportRegistry.reinstateAfterCsamExpiry(reportId);

        IDENReportRegistry.Report memory r = reportRegistry.getReport(reportId);
        assertEq(uint8(r.status), uint8(IDENReportRegistry.ReportStatus.Reinstated));
    }

    // --- setReportRegistry one-time setter ---

    function test_SetReportRegistryCannotBeCalledTwice() public {
        vm.expectRevert("Already set");
        govParams.setReportRegistry(address(reportRegistry));
    }

    function test_SetReportRegistryZeroReverts() public {
        DENGovernanceParams freshGov = new DENGovernanceParams();
        vm.expectRevert("Zero address");
        freshGov.setReportRegistry(address(0));
    }

    // --- setGovernanceParams one-time setters on other contracts ---

    function test_SetGovernanceParamsRegistryCannotBeCalledTwice() public {
        vm.expectRevert("Already set");
        registry.setGovernanceParams(address(govParams));
    }

    function test_SetGovernanceParamsSubscriptionCannotBeCalledTwice() public {
        vm.expectRevert("Already set");
        subscription.setGovernanceParams(address(govParams));
    }

    function test_SetGovernanceParamsTrustTierNonOwnerReverts() public {
        DENTrustTier freshTier = new DENTrustTier();
        vm.prank(alice);
        vm.expectRevert("Not owner");
        freshTier.setGovernanceParams(address(govParams));
    }

    // --- resolveConflictedReport ---

    function test_ResolveConflictedReportRequiresReportRegistrySet() public {
        DENGovernanceParams freshGov = new DENGovernanceParams();
        vm.expectRevert("Report registry not set");
        freshGov.resolveConflictedReport(0, IDENReportRegistry.ReportStatus.Dismissed);
    }

    function test_NonOwnerCannotResolveConflictedReport() public {
        vm.prank(alice);
        vm.expectRevert("Not owner");
        govParams.resolveConflictedReport(0, IDENReportRegistry.ReportStatus.Dismissed);
    }

    // --- Fallback behavior (contracts without govParams wired) ---

    function test_FallbackToDefaultsWhenGovParamsNotSet() public {
        // Deploy a fresh registry without wiring govParams.
        DENIdentityRegistry freshRegistry = new DENIdentityRegistry(address(impl));
        assertEq(freshRegistry.HANDLE_CHANGE_ALLOWANCE(), 2);
        assertEq(freshRegistry.HANDLE_CHANGE_PERIOD(), 30 days);
        assertEq(freshRegistry.HANDLE_ALIAS_RETENTION(), 180 days);
    }

    function test_FallbackContentRegistryDefault() public {
        DENContentRegistry fresh = new DENContentRegistry(address(registry), address(subscription));
        assertEq(fresh.SUBSCRIBER_PROTECTION_WINDOW(), 30 days);
    }

    function test_FallbackSubscriptionFeeBps() public {
        DENSubscription fresh = new DENSubscription(address(registry));
        assertEq(fresh.FEE_BPS(), 250);
    }
}
