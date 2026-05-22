// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/identity/DENIdentityImpl.sol";
import "../src/identity/DENIdentityRegistry.sol";

contract DENIdentityRegistryTest is Test {

    DENIdentityImpl impl;
    DENIdentityRegistry registry;

    uint256 aliceKey;
    address alice;
    uint256 bobKey;
    address bob;
    address carol;

    function setUp() public {
        (alice, aliceKey) = makeAddrAndKey("alice");
        (bob, bobKey) = makeAddrAndKey("bob");
        carol = makeAddr("carol");

        impl = new DENIdentityImpl();
        registry = new DENIdentityRegistry(address(impl));
    }

    // --- Registration ---

    function test_RegisterDeploysProxy() public {
        vm.prank(alice);
        registry.register();

        address proxy = registry.getProxy(alice);
        assertTrue(proxy != address(0));
        assertTrue(proxy != alice);
    }

    function test_RegisteredWalletIsRegistered() public {
        vm.prank(alice);
        registry.register();
        assertTrue(registry.isRegistered(alice));
    }

    function test_UnregisteredWalletIsNotRegistered() public view {
        assertFalse(registry.isRegistered(alice));
    }

    function test_RegisterTwiceReverts() public {
        vm.prank(alice);
        registry.register();

        vm.prank(alice);
        vm.expectRevert("Already registered");
        registry.register();
    }

    function test_TwoWalletsGetDifferentProxies() public {
        vm.prank(alice);
        registry.register();
        vm.prank(bob);
        registry.register();

        assertTrue(registry.getProxy(alice) != registry.getProxy(bob));
    }

    function test_ProxyPrimaryWalletMatchesRegistrant() public {
        vm.prank(alice);
        registry.register();

        address proxy = registry.getProxy(alice);
        assertEq(IDENParticipantIdentity(proxy).primaryWallet(), alice);
    }

    function test_GetIdentityAddressMatchesGetProxy() public {
        vm.prank(alice);
        registry.register();
        assertEq(registry.getIdentityAddress(alice), registry.getProxy(alice));
    }

    function test_RegisterEmitsEvent() public {
        vm.prank(alice);
        vm.expectEmit(true, false, false, false);
        emit DENIdentityRegistry.Registered(alice, address(0)); // proxy addr unknown ahead of time
        registry.register();
    }

    // --- Handle management ---

    function test_SetHandle() public {
        vm.prank(alice);
        registry.register();

        vm.prank(alice);
        registry.setHandle("vixenart");

        address proxy = registry.getProxy(alice);
        assertEq(registry.handleOf(proxy), "vixenart");
        assertEq(registry.resolve("vixenart"), proxy);
    }

    function test_SetHandleUnregisteredReverts() public {
        vm.prank(alice);
        vm.expectRevert("Not registered");
        registry.setHandle("vixenart");
    }

    function test_SetHandleEmptyReverts() public {
        vm.prank(alice);
        registry.register();

        vm.prank(alice);
        vm.expectRevert("Empty handle");
        registry.setHandle("");
    }

    function test_SetHandleTakenReverts() public {
        vm.prank(alice);
        registry.register();
        vm.prank(alice);
        registry.setHandle("vixenart");

        vm.prank(bob);
        registry.register();
        vm.prank(bob);
        vm.expectRevert("Handle taken");
        registry.setHandle("vixenart");
    }

    function test_ChangeHandle() public {
        vm.prank(alice);
        registry.register();
        address proxy = registry.getProxy(alice);

        vm.prank(alice);
        registry.setHandle("vixenart");

        vm.prank(alice);
        registry.setHandle("vixenart_new");

        assertEq(registry.handleOf(proxy), "vixenart_new");
        assertEq(registry.resolve("vixenart_new"), proxy);
    }

    function test_OldHandleResolvesAsAliasAfterChange() public {
        vm.prank(alice);
        registry.register();
        address proxy = registry.getProxy(alice);

        vm.prank(alice);
        registry.setHandle("vixenart");

        vm.prank(alice);
        registry.setHandle("vixenart_new");

        // Old handle still resolves within retention window
        assertEq(registry.resolve("vixenart"), proxy);
    }

    function test_OldHandleExpiredAfterRetentionWindow() public {
        vm.prank(alice);
        registry.register();

        vm.prank(alice);
        registry.setHandle("vixenart");

        vm.prank(alice);
        registry.setHandle("vixenart_new");

        // Fast-forward past retention window
        vm.warp(block.timestamp + registry.HANDLE_ALIAS_RETENTION() + 1);

        // Old handle no longer resolves
        assertEq(registry.resolve("vixenart"), address(0));
    }

    function test_ExpiredAliasHandleCanBeRegisteredByOther() public {
        vm.prank(alice);
        registry.register();
        vm.prank(alice);
        registry.setHandle("vixenart");
        vm.prank(alice);
        registry.setHandle("vixenart_new");

        vm.warp(block.timestamp + registry.HANDLE_ALIAS_RETENTION() + 1);

        vm.prank(bob);
        registry.register();
        vm.prank(bob);
        registry.setHandle("vixenart"); // now available
        assertEq(registry.resolve("vixenart"), registry.getProxy(bob));
    }

    function test_SetHandleByNonPrimaryReverts() public {
        vm.prank(alice);
        registry.register();

        // bob tries to set handle for alice's registration slot (bob's own slot is empty)
        vm.prank(bob);
        vm.expectRevert("Not registered");
        registry.setHandle("stolen_handle");
    }

    function test_ResolveUnknownHandleReturnsZero() public view {
        assertEq(registry.resolve("nobody"), address(0));
    }

    // --- Wallet sync after rotation ---

    function test_SyncWalletAfterCleanRotation() public {
        vm.prank(alice);
        registry.register();
        address proxy = registry.getProxy(alice);

        // Perform clean rotation in impl (bob signs consent)
        uint256 nonce = IDENParticipantIdentity(proxy).rotationNonce();
        bytes32 structHash = keccak256(abi.encode("DEN-clean-rotation", proxy, nonce));
        bytes32 ethHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(bobKey, ethHash);

        vm.prank(alice);
        IDENParticipantIdentity(proxy).initiateCleanRotation(bob, abi.encodePacked(r, s, v));

        // Registry still points to alice (not yet synced)
        assertEq(registry.getProxy(alice), proxy);
        assertFalse(registry.isRegistered(bob));

        // Bob syncs the registry
        vm.prank(bob);
        registry.syncWallet(proxy);

        // Now bob is registered, alice is not
        assertFalse(registry.isRegistered(alice));
        assertTrue(registry.isRegistered(bob));
        assertEq(registry.getProxy(bob), proxy);
    }

    function test_SyncWalletUnknownProxyReverts() public {
        vm.prank(alice);
        vm.expectRevert("Unknown proxy");
        registry.syncWallet(makeAddr("unknown"));
    }

    function test_SyncWalletNotPrimaryReverts() public {
        vm.prank(alice);
        registry.register();
        address proxy = registry.getProxy(alice);

        // carol tries to sync without being primary
        vm.prank(carol);
        vm.expectRevert("Not primary wallet");
        registry.syncWallet(proxy);
    }

    function test_SyncWalletUnchangedReverts() public {
        vm.prank(alice);
        registry.register();
        address proxy = registry.getProxy(alice);

        // alice is still primary, no rotation happened
        vm.prank(alice);
        vm.expectRevert("Wallet unchanged");
        registry.syncWallet(proxy);
    }

    function test_SyncWalletNewWalletAlreadyRegisteredReverts() public {
        // alice and bob are both independently registered
        vm.prank(alice);
        registry.register();
        vm.prank(bob);
        registry.register();

        address aliceProxy = registry.getProxy(alice);

        // alice rotates primary wallet to bob in the proxy
        uint256 nonce = IDENParticipantIdentity(aliceProxy).rotationNonce();
        bytes32 structHash = keccak256(abi.encode("DEN-clean-rotation", aliceProxy, nonce));
        bytes32 ethHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(bobKey, ethHash);

        vm.prank(alice);
        IDENParticipantIdentity(aliceProxy).initiateCleanRotation(bob, abi.encodePacked(r, s, v));

        // bob tries to sync — but bob is already registered independently
        vm.prank(bob);
        vm.expectRevert("New wallet already registered");
        registry.syncWallet(aliceProxy);
    }

    function test_SyncWalletAfterCompromiseRotation() public {
        vm.prank(alice);
        registry.register();
        address proxy = registry.getProxy(alice);

        // alice registers carol as emergency wallet
        vm.prank(alice);
        IDENParticipantIdentity(proxy).registerEmergencyWallet(carol);

        // alice loses access to primary wallet; carol initiates compromise rotation to bob
        vm.prank(carol);
        IDENParticipantIdentity(proxy).initiateCompromiseRotation(bob);

        (, uint256 executeAfter) = IDENParticipantIdentity(proxy).pendingRotation();
        vm.warp(executeAfter);
        IDENParticipantIdentity(proxy).executeCompromiseRotation();

        assertEq(IDENParticipantIdentity(proxy).primaryWallet(), bob);

        // bob syncs the registry
        vm.prank(bob);
        registry.syncWallet(proxy);

        assertFalse(registry.isRegistered(alice));
        assertTrue(registry.isRegistered(bob));
        assertEq(registry.getProxy(bob), proxy);
    }

    function test_HandleResolvesCorrectlyAfterWalletSync() public {
        vm.prank(alice);
        registry.register();
        address proxy = registry.getProxy(alice);

        vm.prank(alice);
        registry.setHandle("vixenart");

        // Rotate to bob and sync registry
        uint256 nonce = IDENParticipantIdentity(proxy).rotationNonce();
        bytes32 structHash = keccak256(abi.encode("DEN-clean-rotation", proxy, nonce));
        bytes32 ethHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(bobKey, ethHash);

        vm.prank(alice);
        IDENParticipantIdentity(proxy).initiateCleanRotation(bob, abi.encodePacked(r, s, v));

        vm.prank(bob);
        registry.syncWallet(proxy);

        // Handle still resolves to the same proxy after wallet sync
        assertEq(registry.resolve("vixenart"), proxy);
        assertEq(registry.handleOf(proxy), "vixenart");

        // Bob (new primary) can also update the handle
        vm.prank(bob);
        registry.setHandle("vixenart_v2");
        assertEq(registry.resolve("vixenart_v2"), proxy);
        assertEq(registry.resolve("vixenart"), proxy); // old handle still aliases
    }

    // --- Handle change rate limiting (spec §2.5.9, §13.4) ---

    // Initial handle set is not a "change" and is never rate-limited.
    function test_InitialHandleSetNotRateLimited() public {
        vm.prank(alice);
        registry.register();

        vm.prank(alice);
        registry.setHandle("vixenart"); // must succeed — not a change
        assertEq(registry.handleOf(registry.getProxy(alice)), "vixenart");
    }

    // Up to HANDLE_CHANGE_ALLOWANCE changes per period are permitted.
    function test_HandleChangesWithinAllowanceSucceed() public {
        vm.prank(alice);
        registry.register();
        vm.startPrank(alice);
        registry.setHandle("handle_v1");
        registry.setHandle("handle_v2"); // change 1
        registry.setHandle("handle_v3"); // change 2 — at allowance limit
        vm.stopPrank();
        assertEq(registry.handleOf(registry.getProxy(alice)), "handle_v3");
    }

    // A change beyond the allowance reverts.
    function test_HandleChangeExceedingAllowanceReverts() public {
        vm.prank(alice);
        registry.register();
        vm.startPrank(alice);
        registry.setHandle("handle_v1");
        registry.setHandle("handle_v2"); // change 1
        registry.setHandle("handle_v3"); // change 2 — at limit
        vm.expectRevert("Handle change allowance exceeded");
        registry.setHandle("handle_v4"); // change 3 — over limit
        vm.stopPrank();
    }

    // After HANDLE_CHANGE_PERIOD elapses the allowance resets for the next period.
    function test_HandleChangeAllowanceResetsAfterPeriod() public {
        vm.prank(alice);
        registry.register();
        vm.startPrank(alice);
        registry.setHandle("handle_v1");
        registry.setHandle("handle_v2"); // change 1
        registry.setHandle("handle_v3"); // change 2 — at limit
        vm.stopPrank();

        vm.warp(block.timestamp + registry.HANDLE_CHANGE_PERIOD());

        vm.prank(alice);
        registry.setHandle("handle_v4"); // new period — must succeed
        assertEq(registry.handleOf(registry.getProxy(alice)), "handle_v4");
    }

    // handleChangeInfo returns stored count and period start.
    // Period start is set lazily when a change triggers a period reset (block.timestamp >= periodStart + period).
    // In the default Foundry environment (block.timestamp=1) the reset branch never fires on first change,
    // so periodStart stays 0. In production it is set to block.timestamp on the first period-reset change.
    function test_HandleChangeInfoUpdates() public {
        vm.prank(alice);
        registry.register();
        address proxy = registry.getProxy(alice);

        (uint256 count0, uint256 start0) = registry.handleChangeInfo(proxy);
        assertEq(count0, 0);
        assertEq(start0, 0);

        vm.prank(alice);
        registry.setHandle("handle_v1"); // initial set — not a change, not tracked
        (uint256 count1, uint256 start1) = registry.handleChangeInfo(proxy);
        assertEq(count1, 0);
        assertEq(start1, 0);

        vm.prank(alice);
        registry.setHandle("handle_v2"); // change 1
        (uint256 count2,) = registry.handleChangeInfo(proxy);
        assertEq(count2, 1);

        vm.prank(alice);
        registry.setHandle("handle_v3"); // change 2
        (uint256 count3,) = registry.handleChangeInfo(proxy);
        assertEq(count3, 2);

        // After period expires, a new change triggers reset: count returns to 1, periodStart is set.
        vm.warp(block.timestamp + registry.HANDLE_CHANGE_PERIOD());
        vm.prank(alice);
        registry.setHandle("handle_v4"); // first change of the new period
        (uint256 count4, uint256 start4) = registry.handleChangeInfo(proxy);
        assertEq(count4, 1);
        assertGt(start4, 0); // period start was recorded at the reset timestamp
    }

    // Rate limit is keyed on proxy, not wallet — a wallet rotation does not reset the count.
    function test_HandleChangeRateLimitKeyedOnProxy() public {
        vm.prank(alice);
        registry.register();
        address proxy = registry.getProxy(alice);

        vm.startPrank(alice);
        registry.setHandle("handle_v1");
        registry.setHandle("handle_v2"); // change 1
        registry.setHandle("handle_v3"); // change 2 — at limit
        vm.stopPrank();

        // Rotate to bob
        uint256 nonce = IDENParticipantIdentity(proxy).rotationNonce();
        bytes32 structHash = keccak256(abi.encode("DEN-clean-rotation", proxy, nonce));
        bytes32 ethHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(bobKey, ethHash);
        vm.prank(alice);
        IDENParticipantIdentity(proxy).initiateCleanRotation(bob, abi.encodePacked(r, s, v));
        vm.prank(bob);
        registry.syncWallet(proxy);

        // Bob is now primary — but the rate limit count is on the proxy, not the wallet
        vm.prank(bob);
        vm.expectRevert("Handle change allowance exceeded");
        registry.setHandle("handle_v4");
    }

    // --- IDENIdentity compatibility (used by DENSubscription) ---

    function test_IsRegisteredCompatWithSubscription() public {
        vm.prank(alice);
        registry.register();
        // DENSubscription checks isRegistered() — must return true after register()
        assertTrue(registry.isRegistered(alice));
        assertFalse(registry.isRegistered(bob));
    }

    // --- isRegisteredProxy ---

    function test_IsRegisteredProxy_AfterRegister() public {
        vm.prank(alice);
        registry.register();
        address proxy = registry.getProxy(alice);
        assertTrue(registry.isRegisteredProxy(proxy));
    }

    function test_IsRegisteredProxy_UnknownAddress() public {
        assertFalse(registry.isRegisteredProxy(makeAddr("unknown")));
    }

    // BUG-09: A proxy must be able to reclaim its own old handle during the alias retention
    // window. Before the fix, the alias check did not exempt the owning proxy, so returning
    // to a previous handle would revert with "Handle reserved as alias by another participant".

    function test_ProxyCanReclaimOwnHandleDuringAliasWindow() public {
        vm.prank(alice);
        registry.register();
        address proxy = registry.getProxy(alice);

        vm.prank(alice);
        registry.setHandle("vixenart");

        vm.prank(alice);
        registry.setHandle("vixenart_new");

        // Within the alias retention window, alice can switch back to "vixenart".
        vm.prank(alice);
        registry.setHandle("vixenart");
        assertEq(registry.handleOf(proxy), "vixenart");
    }

    function test_OtherProxyCannotUseActiveAlias() public {
        vm.prank(alice);
        registry.register();

        vm.prank(alice);
        registry.setHandle("vixenart");

        vm.prank(alice);
        registry.setHandle("vixenart_new");

        // "vixenart" is alice's active alias — bob cannot claim it within the retention window.
        vm.prank(bob);
        registry.register();

        vm.prank(bob);
        vm.expectRevert("Handle reserved as alias by another participant");
        registry.setHandle("vixenart");
    }

    function test_IsRegisteredProxy_StaysValidAfterWalletSync() public {
        vm.prank(alice);
        registry.register();
        address proxy = registry.getProxy(alice);

        // Clean rotation: alice → bob
        uint256 nonce = IDENParticipantIdentity(proxy).rotationNonce();
        bytes32 structHash = keccak256(abi.encode("DEN-clean-rotation", proxy, nonce));
        bytes32 ethHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(bobKey, ethHash);

        vm.prank(alice);
        IDENParticipantIdentity(proxy).initiateCleanRotation(bob, abi.encodePacked(r, s, v));

        vm.prank(bob);
        registry.syncWallet(proxy);

        // Proxy is still a registered proxy after wallet rotation
        assertTrue(registry.isRegisteredProxy(proxy));
    }
}
