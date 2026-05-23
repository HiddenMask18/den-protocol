// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "./mocks/MockGovParams.sol";
import "../src/identity/DENIdentityImpl.sol";
import "../src/identity/DENIdentityRegistry.sol";
import "../src/subscription/DENSubscription.sol";
import "../src/purchase/DENPurchaseState.sol";
import "../src/content/DENContentRegistry.sol";
import "../src/reporting/DENReportRegistry.sol";
import "../src/interfaces/IDENReportRegistry.sol";

contract DENReportRegistryTest is Test {
    DENIdentityImpl      impl;
    DENIdentityRegistry  registry;
    DENSubscription      subscription;
    DENPurchaseState     purchaseState;
    DENContentRegistry   contentRegistry;
    DENReportRegistry    reportRegistry;

    address alice;       // creator
    address bob;         // subscriber / reporter
    address carol;       // registered but not subscribed
    address instanceOp;  // content operator

    address aliceProxy;
    address bobProxy;
    address carolProxy;
    address instanceOpProxy;

    bytes32 constant FP1 = keccak256("content-1");
    bytes32 constant FP2 = keccak256("content-2");
    uint256 constant TIER_ID = 1;
    uint256 constant PRICE   = 1 ether;
    uint256 constant DURATION = 30 days;

    bytes32 constant EVIDENCE = keccak256("evidence-hash");

    function setUp() public {
        alice      = makeAddr("alice");
        bob        = makeAddr("bob");
        carol      = makeAddr("carol");
        instanceOp = makeAddr("instanceOp");

        impl             = new DENIdentityImpl(address(new MockGovParams()));
        registry         = new DENIdentityRegistry(address(impl));
        subscription     = new DENSubscription(address(registry));
        purchaseState    = new DENPurchaseState(address(registry));
        contentRegistry  = new DENContentRegistry(address(registry), address(subscription));
        reportRegistry   = new DENReportRegistry(address(registry), address(subscription), address(purchaseState), address(contentRegistry));

        subscription.setContentRegistry(address(contentRegistry));

        vm.prank(alice);      registry.register();
        vm.prank(bob);        registry.register();
        vm.prank(carol);      registry.register();
        vm.prank(instanceOp); registry.register();

        aliceProxy      = registry.getProxy(alice);
        bobProxy        = registry.getProxy(bob);
        carolProxy      = registry.getProxy(carol);
        instanceOpProxy = registry.getProxy(instanceOp);

        vm.prank(alice);
        subscription.setTier(TIER_ID, PRICE, DURATION, address(0));

        vm.prank(alice);
        contentRegistry.setContentOperator(instanceOpProxy);

        vm.prank(alice);
        contentRegistry.registerContent(FP1, TIER_ID);

        // Bob subscribes — he has plaintext access and can file valid reports.
        vm.deal(bob, 10 ether);
        vm.prank(bob);
        subscription.subscribe{value: PRICE}(aliceProxy, TIER_ID);
    }

    // --- fileReport ---

    function test_FileReportHappyPath() public {
        vm.prank(bob);
        uint256 id = reportRegistry.fileReport(FP1, block.timestamp, IDENReportRegistry.ViolationCategory.NON_CONSENT, EVIDENCE);
        assertEq(id, 0);
        assertEq(reportRegistry.getReportCount(), 1);

        IDENReportRegistry.Report memory r = reportRegistry.getReport(0);
        assertEq(r.fingerprint, FP1);
        assertEq(r.reporterProxy, bobProxy);
        assertEq(uint256(r.category), uint256(IDENReportRegistry.ViolationCategory.NON_CONSENT));
        assertEq(uint256(r.status), uint256(IDENReportRegistry.ReportStatus.Active));
        assertFalse(r.operatorConflict);
    }

    function test_ContentSuspendedAfterFirstReport() public {
        assertFalse(reportRegistry.isSuspended(FP1));
        vm.prank(bob);
        reportRegistry.fileReport(FP1, block.timestamp, IDENReportRegistry.ViolationCategory.NON_CONSENT, EVIDENCE);
        assertTrue(reportRegistry.isSuspended(FP1));
    }

    function test_ReportFiledEmitsEvents() public {
        vm.prank(bob);
        vm.expectEmit(true, true, false, false);
        emit IDENReportRegistry.ContentSuspended(FP1, 0);
        vm.expectEmit(true, true, true, true);
        emit IDENReportRegistry.ReportFiled(0, FP1, bobProxy, IDENReportRegistry.ViolationCategory.NON_CONSENT, false);
        reportRegistry.fileReport(FP1, block.timestamp, IDENReportRegistry.ViolationCategory.NON_CONSENT, EVIDENCE);
    }

    function test_SecondReportDoesNotReEmitSuspended() public {
        address dave = makeAddr("dave");
        vm.prank(dave); registry.register();
        vm.deal(dave, 1 ether);
        vm.prank(dave);
        subscription.subscribe{value: PRICE}(aliceProxy, TIER_ID);

        vm.prank(bob);
        reportRegistry.fileReport(FP1, block.timestamp, IDENReportRegistry.ViolationCategory.NON_CONSENT, EVIDENCE);

        // Second report — ContentSuspended should NOT fire again
        vm.recordLogs();
        vm.prank(dave);
        reportRegistry.fileReport(FP1, block.timestamp, IDENReportRegistry.ViolationCategory.NON_CONSENT, EVIDENCE);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            assertNotEq(logs[i].topics[0], IDENReportRegistry.ContentSuspended.selector);
        }

        assertEq(reportRegistry.getReportCount(), 2);
    }

    function test_UnregisteredCannotReport() public {
        address stranger = makeAddr("stranger");
        vm.prank(stranger);
        vm.expectRevert("Not registered");
        reportRegistry.fileReport(FP1, block.timestamp, IDENReportRegistry.ViolationCategory.NON_CONSENT, EVIDENCE);
    }

    function test_UnsubscribedCannotReport() public {
        // Carol is registered but never subscribed — expiry == 0
        vm.prank(carol);
        vm.expectRevert("No verified access at claimed access time");
        reportRegistry.fileReport(FP1, block.timestamp, IDENReportRegistry.ViolationCategory.NON_CONSENT, EVIDENCE);
    }

    function test_FutureAccessTimestampReverts() public {
        vm.prank(bob);
        vm.expectRevert("Invalid access timestamp");
        reportRegistry.fileReport(FP1, block.timestamp + 1, IDENReportRegistry.ViolationCategory.NON_CONSENT, EVIDENCE);
    }

    function test_ZeroAccessTimestampReverts() public {
        vm.prank(bob);
        vm.expectRevert("Invalid access timestamp");
        reportRegistry.fileReport(FP1, 0, IDENReportRegistry.ViolationCategory.NON_CONSENT, EVIDENCE);
    }

    function test_ZeroEvidenceHashReverts() public {
        vm.prank(bob);
        vm.expectRevert("Missing evidence hash");
        reportRegistry.fileReport(FP1, block.timestamp, IDENReportRegistry.ViolationCategory.NON_CONSENT, bytes32(0));
    }

    function test_NonexistentFingerprintReverts() public {
        vm.prank(bob);
        vm.expectRevert("Content not found");
        reportRegistry.fileReport(keccak256("unknown"), block.timestamp, IDENReportRegistry.ViolationCategory.NON_CONSENT, EVIDENCE);
    }

    function test_DeletedContentNotReportable() public {
        vm.prank(instanceOp);
        contentRegistry.issueSunsetNotice(FP1);
        vm.warp(block.timestamp + DURATION);
        vm.prank(alice);
        contentRegistry.deleteContent(FP1);

        vm.prank(bob);
        vm.expectRevert("Content not reportable");
        reportRegistry.fileReport(FP1, block.timestamp - 1, IDENReportRegistry.ViolationCategory.NON_CONSENT, EVIDENCE);
    }

    function test_SunsetNoticedContentNotReportable() public {
        vm.prank(instanceOp);
        contentRegistry.issueSunsetNotice(FP1);

        vm.prank(bob);
        vm.expectRevert("Content not reportable");
        reportRegistry.fileReport(FP1, block.timestamp, IDENReportRegistry.ViolationCategory.NON_CONSENT, EVIDENCE);
    }

    function test_ArchivedContentIsReportable() public {
        vm.prank(alice);
        contentRegistry.archiveContent(FP1);

        vm.prank(bob);
        uint256 id = reportRegistry.fileReport(FP1, block.timestamp, IDENReportRegistry.ViolationCategory.NON_CONSENT, EVIDENCE);
        assertEq(uint256(reportRegistry.getReport(id).status), uint256(IDENReportRegistry.ReportStatus.Active));
    }

    function test_SubscriptionExpiryBeforeAccessTimestampReverts() public {
        // Bob's expiry is block.timestamp + DURATION. Reporting with a future accessTimestamp
        // that is within his subscription is fine; a past timestamp beyond expiry is not possible
        // here. Instead, test a subscriber who let their sub lapse then tries to report.
        address eve = makeAddr("eve");
        vm.prank(eve); registry.register();
        vm.deal(eve, 1 ether);
        vm.prank(eve);
        subscription.subscribe{value: PRICE}(aliceProxy, TIER_ID); // expiry = block.timestamp + DURATION

        // Warp past expiry
        vm.warp(block.timestamp + DURATION + 1);
        // Eve's subscription is expired. She claims she accessed at a timestamp AFTER her expiry.
        vm.prank(eve);
        vm.expectRevert("No verified access at claimed access time");
        reportRegistry.fileReport(
            FP1,
            block.timestamp,  // after her expiry
            IDENReportRegistry.ViolationCategory.NON_CONSENT,
            EVIDENCE
        );
    }

    // --- Operator conflict ---

    function test_OperatorConflictAutoDetected() public {
        // instanceOp subscribes with their operator wallet — auto-detectable conflict (spec §12.2)
        vm.deal(instanceOp, 1 ether);
        vm.prank(instanceOp);
        subscription.subscribe{value: PRICE}(aliceProxy, TIER_ID);

        vm.prank(instanceOp);
        uint256 id = reportRegistry.fileReport(FP1, block.timestamp, IDENReportRegistry.ViolationCategory.NON_CONSENT, EVIDENCE);
        assertTrue(reportRegistry.getReport(id).operatorConflict);
    }

    function test_NormalReporterHasNoConflict() public {
        vm.prank(bob);
        uint256 id = reportRegistry.fileReport(FP1, block.timestamp, IDENReportRegistry.ViolationCategory.NON_CONSENT, EVIDENCE);
        assertFalse(reportRegistry.getReport(id).operatorConflict);
    }

    // --- determineReport: non-CSAM ---

    function test_DetermineUpheld() public {
        vm.prank(bob);
        uint256 id = reportRegistry.fileReport(FP1, block.timestamp, IDENReportRegistry.ViolationCategory.NON_CONSENT, EVIDENCE);

        vm.prank(instanceOp);
        reportRegistry.determineReport(id, IDENReportRegistry.ReportStatus.Upheld);

        assertEq(uint256(reportRegistry.getReport(id).status), uint256(IDENReportRegistry.ReportStatus.Upheld));
        // Permanent suspension — content stays suspended even after the active count drops to zero
        assertTrue(reportRegistry.isSuspended(FP1));
    }

    function test_DetermineUpheldEmitsEvents() public {
        vm.prank(bob);
        uint256 id = reportRegistry.fileReport(FP1, block.timestamp, IDENReportRegistry.ViolationCategory.NON_CONSENT, EVIDENCE);

        vm.prank(instanceOp);
        vm.expectEmit(true, false, false, true);
        emit IDENReportRegistry.ReportDetermined(id, IDENReportRegistry.ReportStatus.Upheld);
        reportRegistry.determineReport(id, IDENReportRegistry.ReportStatus.Upheld);
    }

    function test_DetermineDismissed() public {
        vm.prank(bob);
        uint256 id = reportRegistry.fileReport(FP1, block.timestamp, IDENReportRegistry.ViolationCategory.NON_CONSENT, EVIDENCE);

        vm.prank(instanceOp);
        reportRegistry.determineReport(id, IDENReportRegistry.ReportStatus.Dismissed);

        assertEq(uint256(reportRegistry.getReport(id).status), uint256(IDENReportRegistry.ReportStatus.Dismissed));
        assertFalse(reportRegistry.isSuspended(FP1));
    }

    function test_DetermineDismissedEmitsReinstate() public {
        vm.prank(bob);
        uint256 id = reportRegistry.fileReport(FP1, block.timestamp, IDENReportRegistry.ViolationCategory.NON_CONSENT, EVIDENCE);

        vm.prank(instanceOp);
        vm.expectEmit(true, true, false, false);
        emit IDENReportRegistry.ContentReinstated(FP1, id);
        reportRegistry.determineReport(id, IDENReportRegistry.ReportStatus.Dismissed);
    }

    function test_DetermineFalseReport() public {
        vm.prank(bob);
        uint256 id = reportRegistry.fileReport(FP1, block.timestamp, IDENReportRegistry.ViolationCategory.NON_CONSENT, EVIDENCE);

        vm.prank(instanceOp);
        reportRegistry.determineReport(id, IDENReportRegistry.ReportStatus.FalseReport);

        assertEq(uint256(reportRegistry.getReport(id).status), uint256(IDENReportRegistry.ReportStatus.FalseReport));
        assertFalse(reportRegistry.isSuspended(FP1));
        assertEq(reportRegistry.getFalseReportCount(bobProxy), 1);
    }

    function test_FalseReportFlaggedEvent() public {
        vm.prank(bob);
        uint256 id = reportRegistry.fileReport(FP1, block.timestamp, IDENReportRegistry.ViolationCategory.NON_CONSENT, EVIDENCE);

        vm.prank(instanceOp);
        vm.expectEmit(true, true, false, true);
        emit IDENReportRegistry.FalseReportFlagged(id, bobProxy, 1);
        reportRegistry.determineReport(id, IDENReportRegistry.ReportStatus.FalseReport);
    }

    function test_FalseReportCountAccumulates() public {
        vm.prank(alice);
        contentRegistry.registerContent(FP2, TIER_ID);

        vm.prank(bob);
        uint256 id1 = reportRegistry.fileReport(FP1, block.timestamp, IDENReportRegistry.ViolationCategory.NON_CONSENT, EVIDENCE);
        vm.prank(bob);
        uint256 id2 = reportRegistry.fileReport(FP2, block.timestamp, IDENReportRegistry.ViolationCategory.NON_CONSENT, EVIDENCE);

        vm.prank(instanceOp);
        reportRegistry.determineReport(id1, IDENReportRegistry.ReportStatus.FalseReport);
        vm.prank(instanceOp);
        reportRegistry.determineReport(id2, IDENReportRegistry.ReportStatus.FalseReport);

        assertEq(reportRegistry.getFalseReportCount(bobProxy), 2);
    }

    function test_NonOperatorCannotDetermine() public {
        vm.prank(bob);
        uint256 id = reportRegistry.fileReport(FP1, block.timestamp, IDENReportRegistry.ViolationCategory.NON_CONSENT, EVIDENCE);

        vm.prank(carol);
        vm.expectRevert("Not content operator");
        reportRegistry.determineReport(id, IDENReportRegistry.ReportStatus.Dismissed);
    }

    function test_UnregisteredCannotDetermine() public {
        vm.prank(bob);
        uint256 id = reportRegistry.fileReport(FP1, block.timestamp, IDENReportRegistry.ViolationCategory.NON_CONSENT, EVIDENCE);

        address stranger = makeAddr("stranger");
        vm.prank(stranger);
        vm.expectRevert("Not registered");
        reportRegistry.determineReport(id, IDENReportRegistry.ReportStatus.Dismissed);
    }

    function test_CannotDetermineAlreadyDeterminedReport() public {
        vm.prank(bob);
        uint256 id = reportRegistry.fileReport(FP1, block.timestamp, IDENReportRegistry.ViolationCategory.NON_CONSENT, EVIDENCE);
        vm.prank(instanceOp);
        reportRegistry.determineReport(id, IDENReportRegistry.ReportStatus.Dismissed);

        vm.prank(instanceOp);
        vm.expectRevert("Report not active");
        reportRegistry.determineReport(id, IDENReportRegistry.ReportStatus.Dismissed);
    }

    // --- Operator-conflicted reports ---

    function test_ConflictedReportGovernanceNotSetReverts() public {
        vm.deal(instanceOp, 1 ether);
        vm.prank(instanceOp);
        subscription.subscribe{value: PRICE}(aliceProxy, TIER_ID);

        vm.prank(instanceOp);
        uint256 id = reportRegistry.fileReport(FP1, block.timestamp, IDENReportRegistry.ViolationCategory.NON_CONSENT, EVIDENCE);

        vm.prank(instanceOp);
        vm.expectRevert("Conflicted report requires governance: not yet configured");
        reportRegistry.determineReport(id, IDENReportRegistry.ReportStatus.Dismissed);
    }

    function test_ConflictedReportOperatorCannotDetermineEvenWithGovernanceSet() public {
        vm.deal(instanceOp, 1 ether);
        vm.prank(instanceOp);
        subscription.subscribe{value: PRICE}(aliceProxy, TIER_ID);

        vm.prank(instanceOp);
        uint256 id = reportRegistry.fileReport(FP1, block.timestamp, IDENReportRegistry.ViolationCategory.NON_CONSENT, EVIDENCE);

        address governance = makeAddr("governance");
        reportRegistry.setGovernance(governance);

        // Operator (not governance) cannot determine conflicted report
        vm.prank(instanceOp);
        vm.expectRevert("Conflicted reports require governance resolution");
        reportRegistry.determineReport(id, IDENReportRegistry.ReportStatus.Dismissed);
    }

    function test_GovernanceCanDetermineConflictedReport() public {
        vm.deal(instanceOp, 1 ether);
        vm.prank(instanceOp);
        subscription.subscribe{value: PRICE}(aliceProxy, TIER_ID);

        vm.prank(instanceOp);
        uint256 id = reportRegistry.fileReport(FP1, block.timestamp, IDENReportRegistry.ViolationCategory.NON_CONSENT, EVIDENCE);

        address governance = makeAddr("governance");
        reportRegistry.setGovernance(governance);

        vm.prank(governance);
        reportRegistry.determineReport(id, IDENReportRegistry.ReportStatus.Dismissed);

        assertEq(uint256(reportRegistry.getReport(id).status), uint256(IDENReportRegistry.ReportStatus.Dismissed));
        assertFalse(reportRegistry.isSuspended(FP1));
    }

    // --- Multi-report suspension logic ---

    function test_AllReportsDismissedReinstates() public {
        address dave = makeAddr("dave");
        vm.prank(dave); registry.register();
        vm.deal(dave, 1 ether);
        vm.prank(dave);
        subscription.subscribe{value: PRICE}(aliceProxy, TIER_ID);

        vm.prank(bob);
        uint256 id1 = reportRegistry.fileReport(FP1, block.timestamp, IDENReportRegistry.ViolationCategory.NON_CONSENT, EVIDENCE);
        vm.prank(dave);
        uint256 id2 = reportRegistry.fileReport(FP1, block.timestamp, IDENReportRegistry.ViolationCategory.NON_CONSENT, EVIDENCE);
        assertTrue(reportRegistry.isSuspended(FP1));

        // Dismiss first — still suspended (second is active)
        vm.prank(instanceOp);
        reportRegistry.determineReport(id1, IDENReportRegistry.ReportStatus.Dismissed);
        assertTrue(reportRegistry.isSuspended(FP1));

        // Dismiss second — now reinstated
        vm.prank(instanceOp);
        reportRegistry.determineReport(id2, IDENReportRegistry.ReportStatus.Dismissed);
        assertFalse(reportRegistry.isSuspended(FP1));
    }

    function test_UpheldPreventsReinstatementEvenIfOthersDissmissed() public {
        address dave = makeAddr("dave");
        vm.prank(dave); registry.register();
        vm.deal(dave, 1 ether);
        vm.prank(dave);
        subscription.subscribe{value: PRICE}(aliceProxy, TIER_ID);

        vm.prank(bob);
        uint256 id1 = reportRegistry.fileReport(FP1, block.timestamp, IDENReportRegistry.ViolationCategory.NON_CONSENT, EVIDENCE);
        vm.prank(dave);
        uint256 id2 = reportRegistry.fileReport(FP1, block.timestamp, IDENReportRegistry.ViolationCategory.NON_CONSENT, EVIDENCE);

        vm.prank(instanceOp);
        reportRegistry.determineReport(id1, IDENReportRegistry.ReportStatus.Upheld);
        vm.prank(instanceOp);
        reportRegistry.determineReport(id2, IDENReportRegistry.ReportStatus.Dismissed);

        // Permanently suspended — upheld report wins
        assertTrue(reportRegistry.isSuspended(FP1));
    }

    // --- CSAM path ---

    function test_CsamReportAutoSuspends() public {
        vm.prank(bob);
        reportRegistry.fileReport(FP1, block.timestamp, IDENReportRegistry.ViolationCategory.CSAM, EVIDENCE);
        assertTrue(reportRegistry.isSuspended(FP1));
    }

    function test_CsamCannotBeDismissed() public {
        vm.prank(bob);
        uint256 id = reportRegistry.fileReport(FP1, block.timestamp, IDENReportRegistry.ViolationCategory.CSAM, EVIDENCE);

        vm.prank(instanceOp);
        vm.expectRevert("CSAM reports cannot be internally adjudicated: use reinstateAfterCsamExpiry or setLawEnforcementHold");
        reportRegistry.determineReport(id, IDENReportRegistry.ReportStatus.Dismissed);
    }

    function test_CsamCannotBeFalseReported() public {
        vm.prank(bob);
        uint256 id = reportRegistry.fileReport(FP1, block.timestamp, IDENReportRegistry.ViolationCategory.CSAM, EVIDENCE);

        vm.prank(instanceOp);
        vm.expectRevert("CSAM reports cannot be internally adjudicated: use reinstateAfterCsamExpiry or setLawEnforcementHold");
        reportRegistry.determineReport(id, IDENReportRegistry.ReportStatus.FalseReport);
    }

    function test_CsamCannotBeUpheld() public {
        // Spec §12.5: CSAM cannot be internally adjudicated at all — Upheld is equally prohibited.
        vm.prank(bob);
        uint256 id = reportRegistry.fileReport(FP1, block.timestamp, IDENReportRegistry.ViolationCategory.CSAM, EVIDENCE);

        vm.prank(instanceOp);
        vm.expectRevert("CSAM reports cannot be internally adjudicated: use reinstateAfterCsamExpiry or setLawEnforcementHold");
        reportRegistry.determineReport(id, IDENReportRegistry.ReportStatus.Upheld);

        // Status stays Active; content remains suspended via the active report count.
        assertEq(uint256(reportRegistry.getReport(id).status), uint256(IDENReportRegistry.ReportStatus.Active));
        assertTrue(reportRegistry.isSuspended(FP1));
    }

    function test_ReporterClaimsAccessBeforeSubscriptionStartReverts() public {
        // Spec §12.2: reporter must have had plaintext access at the claimed timestamp.
        // Warp to t=100 before subscribing — subscription start is recorded as t=100.
        vm.warp(100);
        address eve = makeAddr("eve");
        vm.prank(eve); registry.register();
        vm.deal(eve, PRICE);
        vm.prank(eve); subscription.subscribe{value: PRICE}(aliceProxy, TIER_ID);

        // Eve claims she accessed content at t=50 — before her subscription started at t=100.
        vm.prank(eve);
        vm.expectRevert("No verified access at claimed access time");
        reportRegistry.fileReport(FP1, 50, IDENReportRegistry.ViolationCategory.NON_CONSENT, EVIDENCE);
    }

    function test_BuyerCanFileReport() public {
        // Spec §12.2: buyers have legitimate plaintext access via purchase records.
        vm.prank(alice); purchaseState.setListing(TIER_ID, PRICE, address(0));
        vm.prank(alice); contentRegistry.registerContent(FP2, TIER_ID);

        address dave = makeAddr("dave");
        vm.prank(dave); registry.register();
        vm.deal(dave, PRICE);
        vm.prank(dave); purchaseState.purchase{value: PRICE}(aliceProxy, TIER_ID);

        vm.prank(dave);
        uint256 id = reportRegistry.fileReport(FP2, block.timestamp, IDENReportRegistry.ViolationCategory.NON_CONSENT, EVIDENCE);
        assertEq(uint256(reportRegistry.getReport(id).status), uint256(IDENReportRegistry.ReportStatus.Active));
    }

    function test_BuyerCannotClaimAccessBeforePurchase() public {
        // Buyer's access starts at purchasedAt; claiming an earlier timestamp is not valid.
        vm.warp(100);
        vm.prank(alice); purchaseState.setListing(TIER_ID, PRICE, address(0));
        vm.prank(alice); contentRegistry.registerContent(FP2, TIER_ID);

        address dave = makeAddr("dave");
        vm.prank(dave); registry.register();
        vm.deal(dave, PRICE);
        vm.prank(dave); purchaseState.purchase{value: PRICE}(aliceProxy, TIER_ID); // purchasedAt = 100

        // Dave claims access at t=50 — before his purchase at t=100.
        vm.prank(dave);
        vm.expectRevert("No verified access at claimed access time");
        reportRegistry.fileReport(FP2, 50, IDENReportRegistry.ViolationCategory.NON_CONSENT, EVIDENCE);
    }

    function test_CsamReinstatementAfterExpiry() public {
        vm.prank(bob);
        uint256 id = reportRegistry.fileReport(FP1, block.timestamp, IDENReportRegistry.ViolationCategory.CSAM, EVIDENCE);

        vm.warp(block.timestamp + reportRegistry.CSAM_SUSPENSION_DURATION());

        reportRegistry.reinstateAfterCsamExpiry(id);

        assertEq(uint256(reportRegistry.getReport(id).status), uint256(IDENReportRegistry.ReportStatus.Reinstated));
        assertFalse(reportRegistry.isSuspended(FP1));
    }

    function test_CsamReinstatementPermissionless() public {
        vm.prank(bob);
        uint256 id = reportRegistry.fileReport(FP1, block.timestamp, IDENReportRegistry.ViolationCategory.CSAM, EVIDENCE);
        vm.warp(block.timestamp + reportRegistry.CSAM_SUSPENSION_DURATION());

        // alice (the creator) can trigger reinstatement — permissionless so operator cannot block by inaction
        vm.prank(alice);
        reportRegistry.reinstateAfterCsamExpiry(id);
        assertFalse(reportRegistry.isSuspended(FP1));
    }

    function test_CsamReinstatementBeforeDurationReverts() public {
        vm.prank(bob);
        uint256 id = reportRegistry.fileReport(FP1, block.timestamp, IDENReportRegistry.ViolationCategory.CSAM, EVIDENCE);

        vm.warp(block.timestamp + reportRegistry.CSAM_SUSPENSION_DURATION() - 1);
        vm.expectRevert("Suspension period not elapsed");
        reportRegistry.reinstateAfterCsamExpiry(id);
    }

    function test_CsamReinstatementBlockedByLeHold() public {
        vm.prank(bob);
        uint256 id = reportRegistry.fileReport(FP1, block.timestamp, IDENReportRegistry.ViolationCategory.CSAM, EVIDENCE);

        vm.prank(instanceOp);
        reportRegistry.setLawEnforcementHold(id);

        vm.warp(block.timestamp + reportRegistry.CSAM_SUSPENSION_DURATION());
        vm.expectRevert("Law enforcement hold active");
        reportRegistry.reinstateAfterCsamExpiry(id);
    }

    function test_ReinstatementOnNonCsamReverts() public {
        vm.prank(bob);
        uint256 id = reportRegistry.fileReport(FP1, block.timestamp, IDENReportRegistry.ViolationCategory.NON_CONSENT, EVIDENCE);

        vm.warp(block.timestamp + reportRegistry.CSAM_SUSPENSION_DURATION());
        vm.expectRevert("Not a CSAM report");
        reportRegistry.reinstateAfterCsamExpiry(id);
    }

    // --- Law enforcement hold ---

    function test_SetAndRemoveLeHold() public {
        vm.prank(bob);
        uint256 id = reportRegistry.fileReport(FP1, block.timestamp, IDENReportRegistry.ViolationCategory.CSAM, EVIDENCE);

        assertFalse(reportRegistry.hasLawEnforcementHold(id));

        vm.prank(instanceOp);
        reportRegistry.setLawEnforcementHold(id);
        assertTrue(reportRegistry.hasLawEnforcementHold(id));

        vm.prank(instanceOp);
        reportRegistry.removeLawEnforcementHold(id);
        assertFalse(reportRegistry.hasLawEnforcementHold(id));
    }

    function test_LeHoldOnlyForCsam() public {
        vm.prank(bob);
        uint256 id = reportRegistry.fileReport(FP1, block.timestamp, IDENReportRegistry.ViolationCategory.NON_CONSENT, EVIDENCE);

        vm.prank(instanceOp);
        vm.expectRevert("LE hold only applies to CSAM reports");
        reportRegistry.setLawEnforcementHold(id);
    }

    function test_LeHoldOnlyByContentOperator() public {
        vm.prank(bob);
        uint256 id = reportRegistry.fileReport(FP1, block.timestamp, IDENReportRegistry.ViolationCategory.CSAM, EVIDENCE);

        vm.prank(carol);
        vm.expectRevert("Not content operator");
        reportRegistry.setLawEnforcementHold(id);
    }

    function test_LeHoldEmitsEvents() public {
        vm.prank(bob);
        uint256 id = reportRegistry.fileReport(FP1, block.timestamp, IDENReportRegistry.ViolationCategory.CSAM, EVIDENCE);

        vm.prank(instanceOp);
        vm.expectEmit(true, false, false, false);
        emit IDENReportRegistry.LawEnforcementHoldSet(id);
        reportRegistry.setLawEnforcementHold(id);

        vm.prank(instanceOp);
        vm.expectEmit(true, false, false, false);
        emit IDENReportRegistry.LawEnforcementHoldRemoved(id);
        reportRegistry.removeLawEnforcementHold(id);
    }

    function test_AfterLeHoldRemovedReinstatementWorks() public {
        vm.prank(bob);
        uint256 id = reportRegistry.fileReport(FP1, block.timestamp, IDENReportRegistry.ViolationCategory.CSAM, EVIDENCE);

        vm.prank(instanceOp);
        reportRegistry.setLawEnforcementHold(id);

        vm.warp(block.timestamp + reportRegistry.CSAM_SUSPENSION_DURATION());

        vm.prank(instanceOp);
        reportRegistry.removeLawEnforcementHold(id);

        reportRegistry.reinstateAfterCsamExpiry(id);
        assertFalse(reportRegistry.isSuspended(FP1));
    }

    // --- setGovernance ---

    function test_SetGovernanceOnlyOwner() public {
        address governance = makeAddr("governance");
        vm.prank(alice);
        vm.expectRevert("Not owner");
        reportRegistry.setGovernance(governance);
    }

    function test_SetGovernanceOnlyOnce() public {
        address governance = makeAddr("governance");
        reportRegistry.setGovernance(governance);

        vm.expectRevert("Already set");
        reportRegistry.setGovernance(makeAddr("governance2"));
    }

    function test_SetGovernanceRejectsZeroAddress() public {
        vm.expectRevert("Zero address");
        reportRegistry.setGovernance(address(0));
    }

    // --- Views ---

    function test_GetReportsByFingerprint() public {
        vm.prank(bob);
        reportRegistry.fileReport(FP1, block.timestamp, IDENReportRegistry.ViolationCategory.NON_CONSENT, EVIDENCE);

        address dave = makeAddr("dave");
        vm.prank(dave); registry.register();
        vm.deal(dave, 1 ether);
        vm.prank(dave);
        subscription.subscribe{value: PRICE}(aliceProxy, TIER_ID);
        vm.prank(dave);
        reportRegistry.fileReport(FP1, block.timestamp, IDENReportRegistry.ViolationCategory.NON_CONSENT, EVIDENCE);

        uint256[] memory ids = reportRegistry.getReportsByFingerprint(FP1);
        assertEq(ids.length, 2);
        assertEq(ids[0], 0);
        assertEq(ids[1], 1);
    }

    function test_GetReportNotFoundReverts() public {
        vm.expectRevert("Report not found");
        reportRegistry.getReport(99);
    }
}
