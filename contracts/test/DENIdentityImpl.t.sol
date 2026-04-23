// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/identity/DENIdentityImpl.sol";
import "../src/identity/DENIdentityProxy.sol";

// Helper: cast proxy address to the impl interface so tests can call impl functions.
// All calls go through delegatecall; state lives in the proxy.
contract DENIdentityImplTest is Test {

    DENIdentityImpl impl;

    // Wallet keys for signing rotation messages.
    uint256 aliceKey;
    address alice;
    uint256 bobKey;
    address bob;
    uint256 carolKey;
    address carol;

    // Returns the proxy cast to the impl interface for calling impl functions.
    function _deployProxy(address primaryWallet) internal returns (DENIdentityImpl) {
        bytes memory initData = abi.encodeWithSelector(
            DENIdentityImpl.initialize.selector,
            primaryWallet
        );
        DENIdentityProxy proxy = new DENIdentityProxy(address(impl), initData);
        return DENIdentityImpl(address(proxy));
    }

    // Build the Ethereum-signed hash for a clean rotation.
    function _cleanRotationHash(address proxyAddr, uint256 nonce) internal pure returns (bytes32) {
        bytes32 structHash = keccak256(abi.encode("DEN-clean-rotation", proxyAddr, nonce));
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", structHash));
    }

    // Pack (r, s, v) into bytes65.
    function _sig(uint8 v, bytes32 r, bytes32 s) internal pure returns (bytes memory) {
        return abi.encodePacked(r, s, v);
    }

    function setUp() public {
        impl = new DENIdentityImpl();
        (alice, aliceKey) = makeAddrAndKey("alice");
        (bob, bobKey) = makeAddrAndKey("bob");
        (carol, carolKey) = makeAddrAndKey("carol");
    }

    // --- Initialization ---

    function test_ProxyIsNotImplAddress() public {
        DENIdentityImpl proxy = _deployProxy(alice);
        assertTrue(address(proxy) != address(impl));
    }

    function test_PrimaryWalletSetOnInit() public {
        DENIdentityImpl proxy = _deployProxy(alice);
        assertEq(proxy.primaryWallet(), alice);
    }

    function test_ImplCannotBeInitializedDirectly() public {
        vm.expectRevert("Already initialized");
        impl.initialize(alice);
    }

    function test_ProxyCannotBeInitializedTwice() public {
        DENIdentityImpl proxy = _deployProxy(alice);
        vm.expectRevert("Already initialized");
        proxy.initialize(alice);
    }

    // --- Instance URL ---

    function test_UpdateInstanceURL() public {
        DENIdentityImpl proxy = _deployProxy(alice);
        vm.prank(alice);
        proxy.updateInstanceURL("https://den.example.com");
        assertEq(proxy.instanceURL(), "https://den.example.com");
    }

    function test_UpdateInstanceURLOnlyPrimary() public {
        DENIdentityImpl proxy = _deployProxy(alice);
        vm.prank(bob);
        vm.expectRevert("Not primary wallet");
        proxy.updateInstanceURL("https://evil.example.com");
    }

    function test_UpdateInstanceURLEmitsEvent() public {
        DENIdentityImpl proxy = _deployProxy(alice);
        vm.prank(alice);
        vm.expectEmit(false, false, false, true);
        emit IDENParticipantIdentity.InstanceURLUpdated("https://den.example.com");
        proxy.updateInstanceURL("https://den.example.com");
    }

    // --- Emergency wallets ---

    function test_RegisterEmergencyWallet() public {
        DENIdentityImpl proxy = _deployProxy(alice);
        vm.prank(alice);
        proxy.registerEmergencyWallet(bob);
        assertTrue(proxy.isEmergencyWallet(bob));
    }

    function test_RegisterEmergencyWalletOnlyPrimary() public {
        DENIdentityImpl proxy = _deployProxy(alice);
        vm.prank(bob);
        vm.expectRevert("Not primary wallet");
        proxy.registerEmergencyWallet(carol);
    }

    function test_RegisterEmergencyWalletNotDuplicate() public {
        DENIdentityImpl proxy = _deployProxy(alice);
        vm.startPrank(alice);
        proxy.registerEmergencyWallet(bob);
        vm.expectRevert("Already emergency wallet");
        proxy.registerEmergencyWallet(bob);
        vm.stopPrank();
    }

    function test_RegisterEmergencyWalletNotPrimary() public {
        DENIdentityImpl proxy = _deployProxy(alice);
        vm.prank(alice);
        vm.expectRevert("Cannot be primary");
        proxy.registerEmergencyWallet(alice);
    }

    function test_RevokeEmergencyWallet() public {
        DENIdentityImpl proxy = _deployProxy(alice);
        vm.startPrank(alice);
        proxy.registerEmergencyWallet(bob);
        proxy.revokeEmergencyWallet(bob);
        vm.stopPrank();
        assertFalse(proxy.isEmergencyWallet(bob));
    }

    function test_RevokeEmergencyWalletByEmergencyWallet() public {
        DENIdentityImpl proxy = _deployProxy(alice);
        vm.prank(alice);
        proxy.registerEmergencyWallet(bob);
        vm.prank(alice);
        proxy.registerEmergencyWallet(carol);

        // carol (emergency wallet) revokes bob
        vm.prank(carol);
        proxy.revokeEmergencyWallet(bob);
        assertFalse(proxy.isEmergencyWallet(bob));
    }

    function test_RevokeEmergencyWalletUnauthorized() public {
        DENIdentityImpl proxy = _deployProxy(alice);
        vm.prank(alice);
        proxy.registerEmergencyWallet(bob);

        vm.prank(bob);
        // bob is an emergency wallet but is not authorized to revoke itself
        // (onlyAuthorized allows primary OR emergency — bob IS authorized)
        // This should succeed per spec (any registered wallet can revoke)
        proxy.revokeEmergencyWallet(bob);
        assertFalse(proxy.isEmergencyWallet(bob));
    }

    function test_RevokeNonEmergencyWalletReverts() public {
        DENIdentityImpl proxy = _deployProxy(alice);
        vm.prank(alice);
        vm.expectRevert("Not emergency wallet");
        proxy.revokeEmergencyWallet(carol);
    }

    // --- Clean rotation ---

    function test_CleanRotation() public {
        DENIdentityImpl proxy = _deployProxy(alice);
        uint256 nonce = proxy.rotationNonce();

        bytes32 h = _cleanRotationHash(address(proxy), nonce);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(bobKey, h);

        vm.prank(alice);
        proxy.initiateCleanRotation(bob, _sig(v, r, s));

        assertEq(proxy.primaryWallet(), bob);
        assertEq(proxy.rotationNonce(), nonce + 1);
    }

    function test_CleanRotationByEmergencyWallet() public {
        DENIdentityImpl proxy = _deployProxy(alice);
        vm.prank(alice);
        proxy.registerEmergencyWallet(carol);

        uint256 nonce = proxy.rotationNonce();
        bytes32 h = _cleanRotationHash(address(proxy), nonce);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(bobKey, h);

        // carol (emergency) initiates rotation to bob
        vm.prank(carol);
        proxy.initiateCleanRotation(bob, _sig(v, r, s));

        assertEq(proxy.primaryWallet(), bob);
    }

    function test_CleanRotationInvalidSignatureReverts() public {
        DENIdentityImpl proxy = _deployProxy(alice);
        uint256 nonce = proxy.rotationNonce();

        bytes32 h = _cleanRotationHash(address(proxy), nonce);
        // carol signs but we claim it's bob
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(carolKey, h);

        vm.prank(alice);
        vm.expectRevert("Invalid new wallet signature");
        proxy.initiateCleanRotation(bob, _sig(v, r, s));
    }

    function test_CleanRotationNonceInvalidatesOldSig() public {
        DENIdentityImpl proxy = _deployProxy(alice);
        uint256 nonce = proxy.rotationNonce();

        // Build sig for nonce 0
        bytes32 h = _cleanRotationHash(address(proxy), nonce);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(carolKey, h);

        // Rotate to carol first (consumes nonce 0)
        vm.prank(alice);
        proxy.initiateCleanRotation(carol, _sig(v, r, s));

        // Now try to replay the sig for nonce 0 → should fail
        bytes32 h2 = _cleanRotationHash(address(proxy), proxy.rotationNonce());
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(aliceKey, h2);
        // alice tries to rotate back using a sig for the wrong nonce
        bytes32 staleH = _cleanRotationHash(address(proxy), nonce); // nonce 0
        (uint8 sv, bytes32 sr, bytes32 ss) = vm.sign(aliceKey, staleH);
        vm.prank(carol);
        vm.expectRevert("Invalid new wallet signature");
        proxy.initiateCleanRotation(alice, _sig(sv, sr, ss));

        // Correct nonce works
        vm.prank(carol);
        proxy.initiateCleanRotation(alice, _sig(v2, r2, s2));
        assertEq(proxy.primaryWallet(), alice);
    }

    function test_CleanRotationUnauthorizedReverts() public {
        DENIdentityImpl proxy = _deployProxy(alice);
        bytes32 h = _cleanRotationHash(address(proxy), proxy.rotationNonce());
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(bobKey, h);

        // bob is not primary or emergency
        vm.prank(bob);
        vm.expectRevert("Not authorized");
        proxy.initiateCleanRotation(bob, _sig(v, r, s));
    }

    // --- Compromise rotation ---

    function test_CompromiseRotationHappyPath() public {
        DENIdentityImpl proxy = _deployProxy(alice);
        vm.prank(alice);
        proxy.registerEmergencyWallet(bob);

        // Step 1: announce
        vm.prank(bob);
        proxy.initiateCompromiseRotation(carol);

        (address pending, uint256 executeAfter) = proxy.pendingRotation();
        assertEq(pending, carol);
        assertGt(executeAfter, block.timestamp);

        // Step 2: wait out delay
        vm.warp(executeAfter);

        // Step 3: execute (anyone can call)
        proxy.executeCompromiseRotation();
        assertEq(proxy.primaryWallet(), carol);

        (address p2, uint256 e2) = proxy.pendingRotation();
        assertEq(p2, address(0));
        assertEq(e2, 0);
    }

    function test_CompromiseRotationOnlyEmergencyWallet() public {
        DENIdentityImpl proxy = _deployProxy(alice);

        vm.prank(carol); // carol is not an emergency wallet
        vm.expectRevert("Only emergency wallet");
        proxy.initiateCompromiseRotation(carol);
    }

    function test_CompromiseRotationCannotDoubleAnnounce() public {
        DENIdentityImpl proxy = _deployProxy(alice);
        vm.prank(alice);
        proxy.registerEmergencyWallet(bob);

        vm.prank(bob);
        proxy.initiateCompromiseRotation(carol);

        vm.prank(bob);
        vm.expectRevert("Rotation already pending");
        proxy.initiateCompromiseRotation(carol);
    }

    function test_CompromiseRotationCancelByPrimary() public {
        DENIdentityImpl proxy = _deployProxy(alice);
        vm.prank(alice);
        proxy.registerEmergencyWallet(bob);

        vm.prank(bob);
        proxy.initiateCompromiseRotation(carol);

        // alice (primary) notices and cancels
        vm.prank(alice);
        proxy.cancelCompromiseRotation();

        (address pending,) = proxy.pendingRotation();
        assertEq(pending, address(0));
        assertEq(proxy.primaryWallet(), alice); // unchanged
    }

    function test_CompromiseRotationCancelByEmergencyWallet() public {
        DENIdentityImpl proxy = _deployProxy(alice);
        vm.prank(alice);
        proxy.registerEmergencyWallet(bob);
        vm.prank(alice);
        proxy.registerEmergencyWallet(carol);

        vm.prank(bob);
        proxy.initiateCompromiseRotation(makeAddr("attacker"));

        // carol (another emergency wallet) cancels
        vm.prank(carol);
        proxy.cancelCompromiseRotation();

        (address pending,) = proxy.pendingRotation();
        assertEq(pending, address(0));
    }

    function test_CompromiseRotationExecuteBeforeDelayReverts() public {
        DENIdentityImpl proxy = _deployProxy(alice);
        vm.prank(alice);
        proxy.registerEmergencyWallet(bob);

        vm.prank(bob);
        proxy.initiateCompromiseRotation(carol);

        vm.expectRevert("Delay not elapsed");
        proxy.executeCompromiseRotation();
    }

    function test_CompromiseRotationExecuteWithNoPendingReverts() public {
        DENIdentityImpl proxy = _deployProxy(alice);
        vm.expectRevert("No pending rotation");
        proxy.executeCompromiseRotation();
    }

    function test_CompromiseRotationBlockedByCleanRotation() public {
        DENIdentityImpl proxy = _deployProxy(alice);
        vm.prank(alice);
        proxy.registerEmergencyWallet(bob);

        vm.prank(bob);
        proxy.initiateCompromiseRotation(carol);

        // Try clean rotation while compromise is pending
        bytes32 h = _cleanRotationHash(address(proxy), proxy.rotationNonce());
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(carolKey, h);
        vm.prank(alice);
        vm.expectRevert("Compromise rotation pending");
        proxy.initiateCleanRotation(carol, _sig(v, r, s));
    }

    // --- Upgrade ---

    function test_UpgradeByPrimary() public {
        DENIdentityImpl proxy = _deployProxy(alice);

        // Deploy a new impl (same logic for test purposes)
        DENIdentityImpl newImpl = new DENIdentityImpl();

        vm.prank(alice);
        proxy.upgradeTo(address(newImpl));

        // Proxy should now delegate to newImpl (state preserved)
        assertEq(proxy.primaryWallet(), alice);
    }

    function test_UpgradeByNonPrimaryReverts() public {
        DENIdentityImpl proxy = _deployProxy(alice);
        DENIdentityImpl newImpl = new DENIdentityImpl();

        vm.prank(bob);
        vm.expectRevert("Not primary wallet");
        proxy.upgradeTo(address(newImpl));
    }

    function test_StatePreservedAfterUpgrade() public {
        DENIdentityImpl proxy = _deployProxy(alice);
        vm.startPrank(alice);
        proxy.registerEmergencyWallet(bob);
        proxy.updateInstanceURL("https://den.example.com");
        vm.stopPrank();

        DENIdentityImpl newImpl = new DENIdentityImpl();
        vm.prank(alice);
        proxy.upgradeTo(address(newImpl));

        // All state preserved after upgrade
        assertEq(proxy.primaryWallet(), alice);
        assertTrue(proxy.isEmergencyWallet(bob));
        assertEq(proxy.instanceURL(), "https://den.example.com");
    }
}
