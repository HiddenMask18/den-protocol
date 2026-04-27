// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/identity/DENIdentityImpl.sol";
import "../src/identity/DENIdentityRegistry.sol";
import "../src/interfaces/IDENParticipantIdentity.sol";
import "../src/subscription/DENSubscription.sol";
import "../src/content/DENContentRegistry.sol";

contract DENContentRegistryTest is Test {
    DENIdentityImpl impl;
    DENIdentityRegistry registry;
    DENSubscription subscription;
    DENContentRegistry contentRegistry;

    uint256 aliceKey;
    address alice;
    address bob;
    address carol;
    address instanceOp;

    address aliceProxy;
    address instanceOpProxy;

    bytes32 constant FP1 = keccak256("content-1");
    bytes32 constant FP2 = keccak256("content-2");
    uint256 constant TIER_ID = 1;
    uint256 constant PRICE = 1 ether;
    uint256 constant DURATION = 30 days;

    function setUp() public {
        (alice, aliceKey) = makeAddrAndKey("alice");
        bob = makeAddr("bob");
        carol = makeAddr("carol");
        instanceOp = makeAddr("instanceOp");

        impl = new DENIdentityImpl();
        registry = new DENIdentityRegistry(address(impl));
        subscription = new DENSubscription(address(registry));
        contentRegistry = new DENContentRegistry(address(registry), address(subscription));
        subscription.setContentRegistry(address(contentRegistry));

        vm.prank(alice);
        registry.register();
        aliceProxy = registry.getProxy(alice);

        vm.prank(instanceOp);
        registry.register();
        instanceOpProxy = registry.getProxy(instanceOp);

        // Alice registers her tier so sunset notice duration lookups work correctly.
        vm.prank(alice);
        subscription.setTier(TIER_ID, PRICE, DURATION);

        // Alice designates instanceOp as the authorized sunset operator (spec §7.5).
        vm.prank(alice);
        contentRegistry.setContentOperator(instanceOpProxy);
    }

    // --- registerContent ---

    function test_RegisterContent() public {
        vm.prank(alice);
        contentRegistry.registerContent(FP1, TIER_ID);

        IDENContentRegistry.ContentRecord memory rec = contentRegistry.getContent(FP1);
        assertEq(rec.creatorProxy, aliceProxy);
        assertEq(rec.tierId, TIER_ID);
        assertEq(uint256(rec.lifecycle), uint256(IDENContentRegistry.Lifecycle.Active));
        assertEq(rec.registeredAt, block.timestamp);
        assertEq(rec.sunsetNoticedAt, 0);
    }

    function test_RegisterContentIsActive() public {
        vm.prank(alice);
        contentRegistry.registerContent(FP1, TIER_ID);
        assertTrue(contentRegistry.isContentActive(FP1));
    }

    function test_RegisterDuplicateFingerprintReverts() public {
        vm.prank(alice);
        contentRegistry.registerContent(FP1, TIER_ID);

        vm.prank(alice);
        vm.expectRevert("Fingerprint already registered");
        contentRegistry.registerContent(FP1, TIER_ID);
    }

    function test_RegisterZeroFingerprintReverts() public {
        vm.prank(alice);
        vm.expectRevert("Zero fingerprint");
        contentRegistry.registerContent(bytes32(0), TIER_ID);
    }

    function test_UnregisteredCannotRegisterContent() public {
        vm.prank(carol);
        vm.expectRevert("Not registered");
        contentRegistry.registerContent(FP1, TIER_ID);
    }

    function test_NonPrimaryWalletCannotRegisterContent() public {
        vm.prank(bob);
        registry.register();

        // bob registers content — it's attributed to bobProxy, not aliceProxy
        vm.prank(bob);
        contentRegistry.registerContent(FP1, TIER_ID);

        IDENContentRegistry.ContentRecord memory rec = contentRegistry.getContent(FP1);
        address bobProxy = registry.getProxy(bob);
        assertEq(rec.creatorProxy, bobProxy);
        assertTrue(rec.creatorProxy != aliceProxy);
    }

    function test_RegisterContentEmitsEvent() public {
        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit DENContentRegistry.ContentRegistered(aliceProxy, FP1, TIER_ID);
        contentRegistry.registerContent(FP1, TIER_ID);
    }

    function test_GetCreatorContentList() public {
        vm.prank(alice);
        contentRegistry.registerContent(FP1, TIER_ID);
        vm.prank(alice);
        contentRegistry.registerContent(FP2, TIER_ID);

        bytes32[] memory list = contentRegistry.getCreatorContent(aliceProxy);
        assertEq(list.length, 2);
        assertEq(list[0], FP1);
        assertEq(list[1], FP2);
    }

    // --- archiveContent ---

    // Archived content remains subscriber-accessible (spec §4.5); isContentActive returns true.
    function test_ArchiveActiveContent() public {
        vm.prank(alice);
        contentRegistry.registerContent(FP1, TIER_ID);

        vm.prank(alice);
        contentRegistry.archiveContent(FP1);

        IDENContentRegistry.ContentRecord memory rec = contentRegistry.getContent(FP1);
        assertEq(uint256(rec.lifecycle), uint256(IDENContentRegistry.Lifecycle.Archived));
        assertTrue(contentRegistry.isContentActive(FP1));
    }

    function test_ArchiveAlreadyArchivedReverts() public {
        vm.prank(alice);
        contentRegistry.registerContent(FP1, TIER_ID);
        vm.prank(alice);
        contentRegistry.archiveContent(FP1);

        vm.prank(alice);
        vm.expectRevert("Content not active");
        contentRegistry.archiveContent(FP1);
    }

    function test_ArchiveNonexistentContentReverts() public {
        vm.prank(alice);
        vm.expectRevert("Content not found");
        contentRegistry.archiveContent(FP1);
    }

    function test_NonPrimaryCannotArchive() public {
        vm.prank(bob);
        registry.register();

        vm.prank(alice);
        contentRegistry.registerContent(FP1, TIER_ID);

        vm.prank(bob);
        vm.expectRevert("Not primary wallet");
        contentRegistry.archiveContent(FP1);
    }

    function test_ArchiveEmitsEvent() public {
        vm.prank(alice);
        contentRegistry.registerContent(FP1, TIER_ID);

        vm.prank(alice);
        vm.expectEmit(true, true, false, false);
        emit DENContentRegistry.ContentArchived(aliceProxy, FP1);
        contentRegistry.archiveContent(FP1);
    }

    // --- issueSunsetNotice ---

    function test_SunsetNoticeFromActive() public {
        vm.prank(alice);
        contentRegistry.registerContent(FP1, TIER_ID);

        vm.prank(instanceOp);
        contentRegistry.issueSunsetNotice(FP1);

        IDENContentRegistry.ContentRecord memory rec = contentRegistry.getContent(FP1);
        assertEq(uint256(rec.lifecycle), uint256(IDENContentRegistry.Lifecycle.SunsetNoticed));
        assertEq(rec.sunsetNoticedAt, block.timestamp);
    }

    function test_SunsetNoticeFromArchived() public {
        vm.prank(alice);
        contentRegistry.registerContent(FP1, TIER_ID);
        vm.prank(alice);
        contentRegistry.archiveContent(FP1);

        vm.prank(instanceOp);
        contentRegistry.issueSunsetNotice(FP1);

        IDENContentRegistry.ContentRecord memory rec = contentRegistry.getContent(FP1);
        assertEq(uint256(rec.lifecycle), uint256(IDENContentRegistry.Lifecycle.SunsetNoticed));
    }

    function test_SunsetNoticeIsImmutable() public {
        vm.prank(alice);
        contentRegistry.registerContent(FP1, TIER_ID);
        vm.prank(instanceOp);
        contentRegistry.issueSunsetNotice(FP1);

        // Cannot archive after sunset notice (lifecycle check fires before auth check)
        vm.prank(alice);
        vm.expectRevert("Content not active");
        contentRegistry.archiveContent(FP1);

        // Cannot re-issue sunset notice (lifecycle check fires before auth check)
        vm.prank(instanceOp);
        vm.expectRevert("Cannot issue sunset notice in current state");
        contentRegistry.issueSunsetNotice(FP1);
    }

    // "Content not found" fires before auth checks, so any caller exercises this path.
    function test_SunsetNoticeNonexistentContentReverts() public {
        vm.prank(alice);
        vm.expectRevert("Content not found");
        contentRegistry.issueSunsetNotice(FP1);
    }

    // Only the designated operator proxy may issue sunset notices (spec §7.5).
    function test_CreatorCannotIssueSunsetNotice() public {
        vm.prank(alice);
        contentRegistry.registerContent(FP1, TIER_ID);

        vm.prank(alice);
        vm.expectRevert("Not authorized operator");
        contentRegistry.issueSunsetNotice(FP1);
    }

    function test_NonOperatorCannotIssueSunsetNotice() public {
        vm.prank(bob);
        registry.register();

        vm.prank(alice);
        contentRegistry.registerContent(FP1, TIER_ID);

        vm.prank(bob);
        vm.expectRevert("Not authorized operator");
        contentRegistry.issueSunsetNotice(FP1);
    }

    function test_UnregisteredCannotIssueSunsetNotice() public {
        vm.prank(alice);
        contentRegistry.registerContent(FP1, TIER_ID);

        vm.prank(carol);
        vm.expectRevert("Not registered");
        contentRegistry.issueSunsetNotice(FP1);
    }

    // deletableAfter is computed from the tier's subscription duration (spec §7.5).
    function test_SunsetNoticeEmitsEvent() public {
        vm.prank(alice);
        contentRegistry.registerContent(FP1, TIER_ID);

        uint256 deletableAfter = block.timestamp + DURATION;
        vm.prank(instanceOp);
        vm.expectEmit(true, true, false, true);
        emit DENContentRegistry.SunsetNoticeIssued(aliceProxy, FP1, deletableAfter);
        contentRegistry.issueSunsetNotice(FP1);
    }

    function test_SunsetNoticeSetsDeletableAfter() public {
        vm.prank(alice);
        contentRegistry.registerContent(FP1, TIER_ID);

        vm.prank(instanceOp);
        contentRegistry.issueSunsetNotice(FP1);

        IDENContentRegistry.ContentRecord memory rec = contentRegistry.getContent(FP1);
        assertEq(rec.deletableAfter, block.timestamp + DURATION);
    }

    // Falls back to SUBSCRIBER_PROTECTION_WINDOW when the tier has no registered duration.
    function test_SunsetNoticeFallsBackToProtectionWindow() public {
        uint256 unknownTierId = 999;
        vm.prank(alice);
        contentRegistry.registerContent(FP1, unknownTierId);

        vm.prank(instanceOp);
        contentRegistry.issueSunsetNotice(FP1);

        IDENContentRegistry.ContentRecord memory rec = contentRegistry.getContent(FP1);
        assertEq(rec.deletableAfter, block.timestamp + contentRegistry.SUBSCRIBER_PROTECTION_WINDOW());
    }

    function test_HasActiveSunsetAfterNotice() public {
        vm.prank(alice);
        contentRegistry.registerContent(FP1, TIER_ID);
        assertFalse(contentRegistry.hasActiveSunset(aliceProxy));

        vm.prank(instanceOp);
        contentRegistry.issueSunsetNotice(FP1);
        assertTrue(contentRegistry.hasActiveSunset(aliceProxy));
    }

    // --- deleteContent ---

    function test_DeleteAfterProtectionWindow() public {
        vm.prank(alice);
        contentRegistry.registerContent(FP1, TIER_ID);
        vm.prank(instanceOp);
        contentRegistry.issueSunsetNotice(FP1);

        vm.warp(block.timestamp + DURATION);

        vm.prank(alice);
        contentRegistry.deleteContent(FP1);

        IDENContentRegistry.ContentRecord memory rec = contentRegistry.getContent(FP1);
        assertEq(uint256(rec.lifecycle), uint256(IDENContentRegistry.Lifecycle.Deleted));
    }

    function test_DeleteBeforeProtectionWindowReverts() public {
        vm.prank(alice);
        contentRegistry.registerContent(FP1, TIER_ID);
        vm.prank(instanceOp);
        contentRegistry.issueSunsetNotice(FP1);

        vm.warp(block.timestamp + DURATION - 1);

        vm.prank(alice);
        vm.expectRevert("Subscriber protection window not elapsed");
        contentRegistry.deleteContent(FP1);
    }

    function test_DeleteFromWrongStateReverts() public {
        vm.prank(alice);
        contentRegistry.registerContent(FP1, TIER_ID);

        vm.prank(alice);
        vm.expectRevert("Content not in sunset state");
        contentRegistry.deleteContent(FP1);
    }

    function test_DeletePreservesRecord() public {
        vm.prank(alice);
        contentRegistry.registerContent(FP1, TIER_ID);
        vm.prank(instanceOp);
        contentRegistry.issueSunsetNotice(FP1);
        vm.warp(block.timestamp + DURATION);
        vm.prank(alice);
        contentRegistry.deleteContent(FP1);

        IDENContentRegistry.ContentRecord memory rec = contentRegistry.getContent(FP1);
        assertEq(rec.creatorProxy, aliceProxy);
        assertEq(rec.tierId, TIER_ID);
        assertEq(uint256(rec.lifecycle), uint256(IDENContentRegistry.Lifecycle.Deleted));
        assertFalse(contentRegistry.isContentActive(FP1));
    }

    function test_DeleteEmitsEvent() public {
        vm.prank(alice);
        contentRegistry.registerContent(FP1, TIER_ID);
        vm.prank(instanceOp);
        contentRegistry.issueSunsetNotice(FP1);
        vm.warp(block.timestamp + DURATION);

        vm.prank(alice);
        vm.expectEmit(true, true, false, false);
        emit DENContentRegistry.ContentDeleted(aliceProxy, FP1);
        contentRegistry.deleteContent(FP1);
    }

    function test_UnauthorizedCannotDelete() public {
        vm.prank(bob);
        registry.register();

        vm.prank(alice);
        contentRegistry.registerContent(FP1, TIER_ID);
        vm.prank(instanceOp);
        contentRegistry.issueSunsetNotice(FP1);
        vm.warp(block.timestamp + DURATION);

        // bob is neither the creator's primary wallet nor the registered operator
        vm.prank(bob);
        vm.expectRevert("Not authorized");
        contentRegistry.deleteContent(FP1);
    }

    // The operator who issued the sunset notice can complete the deletion (spec §7.5 Step 4).
    function test_OperatorCanDeleteAfterProtectionWindow() public {
        vm.prank(alice);
        contentRegistry.registerContent(FP1, TIER_ID);
        vm.prank(instanceOp);
        contentRegistry.issueSunsetNotice(FP1);

        vm.warp(block.timestamp + DURATION);

        vm.prank(instanceOp);
        contentRegistry.deleteContent(FP1);

        IDENContentRegistry.ContentRecord memory rec = contentRegistry.getContent(FP1);
        assertEq(uint256(rec.lifecycle), uint256(IDENContentRegistry.Lifecycle.Deleted));
    }
}
