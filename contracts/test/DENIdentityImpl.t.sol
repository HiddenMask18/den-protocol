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

    // Build the Ethereum-signed hash for an instance URL confirmation.
    function _urlConfirmHash(address proxyAddr, string memory url, uint256 nonce) internal pure returns (bytes32) {
        bytes32 structHash = keccak256(abi.encode("DEN-url-confirm", proxyAddr, url, nonce));
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
        DENIdentityImpl aliceProxy = _deployProxy(alice);
        DENIdentityImpl instanceProxy = _deployProxy(bob); // bob's proxy is the receiving instance

        string memory url = "https://den.example.com";
        uint256 nonce = aliceProxy.urlUpdateNonce();
        bytes32 h = _urlConfirmHash(address(aliceProxy), url, nonce);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(bobKey, h);

        vm.prank(alice);
        aliceProxy.updateInstanceURL(url, address(instanceProxy), _sig(v, r, s));
        assertEq(aliceProxy.instanceURL(), url);
        assertEq(aliceProxy.urlUpdateNonce(), nonce + 1);
    }

    function test_UpdateInstanceURLNonceIncrements() public {
        DENIdentityImpl aliceProxy = _deployProxy(alice);
        DENIdentityImpl instanceProxy = _deployProxy(bob);

        string memory url1 = "https://den1.example.com";
        string memory url2 = "https://den2.example.com";

        bytes32 h1 = _urlConfirmHash(address(aliceProxy), url1, 0);
        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(bobKey, h1);
        vm.prank(alice);
        aliceProxy.updateInstanceURL(url1, address(instanceProxy), _sig(v1, r1, s1));

        bytes32 h2 = _urlConfirmHash(address(aliceProxy), url2, 1);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(bobKey, h2);
        vm.prank(alice);
        aliceProxy.updateInstanceURL(url2, address(instanceProxy), _sig(v2, r2, s2));

        assertEq(aliceProxy.instanceURL(), url2);
        assertEq(aliceProxy.urlUpdateNonce(), 2);
    }

    function test_UpdateInstanceURLInvalidSigReverts() public {
        DENIdentityImpl aliceProxy = _deployProxy(alice);
        DENIdentityImpl instanceProxy = _deployProxy(bob);

        string memory url = "https://den.example.com";
        uint256 nonce = aliceProxy.urlUpdateNonce();
        bytes32 h = _urlConfirmHash(address(aliceProxy), url, nonce);
        // carol signs instead of bob (wrong instance wallet)
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(carolKey, h);

        vm.prank(alice);
        vm.expectRevert("Invalid instance signature");
        aliceProxy.updateInstanceURL(url, address(instanceProxy), _sig(v, r, s));
    }

    function test_UpdateInstanceURLOnlyPrimary() public {
        DENIdentityImpl proxy = _deployProxy(alice);
        DENIdentityImpl instanceProxy = _deployProxy(carol);

        string memory url = "https://den.example.com";
        bytes32 h = _urlConfirmHash(address(proxy), url, proxy.urlUpdateNonce());
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(carolKey, h);

        vm.prank(bob); // bob is not primary
        vm.expectRevert("Not primary wallet");
        proxy.updateInstanceURL(url, address(instanceProxy), _sig(v, r, s));
    }

    function test_ClearInstanceURLRequiresNoSig() public {
        DENIdentityImpl aliceProxy = _deployProxy(alice);
        DENIdentityImpl instanceProxy = _deployProxy(bob);

        string memory url = "https://den.example.com";
        bytes32 h = _urlConfirmHash(address(aliceProxy), url, aliceProxy.urlUpdateNonce());
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(bobKey, h);
        vm.prank(alice);
        aliceProxy.updateInstanceURL(url, address(instanceProxy), _sig(v, r, s));

        // Clear without countersig (empty url, zero address, empty sig)
        vm.prank(alice);
        aliceProxy.updateInstanceURL("", address(0), "");
        assertEq(aliceProxy.instanceURL(), "");
    }

    function test_UpdateInstanceURLEmitsEvent() public {
        DENIdentityImpl aliceProxy = _deployProxy(alice);
        DENIdentityImpl instanceProxy = _deployProxy(bob);

        string memory url = "https://den.example.com";
        bytes32 h = _urlConfirmHash(address(aliceProxy), url, aliceProxy.urlUpdateNonce());
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(bobKey, h);

        vm.prank(alice);
        vm.expectEmit(false, false, false, true);
        emit IDENParticipantIdentity.InstanceURLUpdated(url);
        aliceProxy.updateInstanceURL(url, address(instanceProxy), _sig(v, r, s));
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

    // --- Emergency wallet revocation (time-delayed, spec §2.5.5) ---

    function test_AnnounceAndExecuteRevocation() public {
        DENIdentityImpl proxy = _deployProxy(alice);
        vm.prank(alice);
        proxy.registerEmergencyWallet(bob);

        // Step 1: announce (starts delay)
        vm.prank(alice);
        proxy.announceEmergencyWalletRevocation(bob);

        (address pending, uint256 executeAfter) = proxy.pendingRevocation();
        assertEq(pending, bob);
        assertGt(executeAfter, block.timestamp);
        assertTrue(proxy.isEmergencyWallet(bob)); // still registered during delay

        // Step 2: wait out delay
        vm.warp(executeAfter);

        // Step 3: execute
        proxy.executeEmergencyWalletRevocation();
        assertFalse(proxy.isEmergencyWallet(bob));

        (address p2, uint256 e2) = proxy.pendingRevocation();
        assertEq(p2, address(0));
        assertEq(e2, 0);
    }

    function test_RevocationAnnouncedByEmergencyWallet() public {
        DENIdentityImpl proxy = _deployProxy(alice);
        vm.prank(alice);
        proxy.registerEmergencyWallet(bob);
        vm.prank(alice);
        proxy.registerEmergencyWallet(carol);

        // carol (emergency) announces revocation of bob
        vm.prank(carol);
        proxy.announceEmergencyWalletRevocation(bob);

        vm.warp(block.timestamp + proxy.WALLET_ROTATION_DELAY());
        proxy.executeEmergencyWalletRevocation();
        assertFalse(proxy.isEmergencyWallet(bob));
    }

    function test_RevocationCancelledByPrimary() public {
        DENIdentityImpl proxy = _deployProxy(alice);
        vm.prank(alice);
        proxy.registerEmergencyWallet(bob);

        vm.prank(alice);
        proxy.announceEmergencyWalletRevocation(bob);

        vm.prank(alice);
        proxy.cancelEmergencyWalletRevocation();

        (address pending,) = proxy.pendingRevocation();
        assertEq(pending, address(0));
        assertTrue(proxy.isEmergencyWallet(bob)); // not revoked
    }

    function test_RevocationCancelledByEmergencyWallet() public {
        DENIdentityImpl proxy = _deployProxy(alice);
        vm.prank(alice);
        proxy.registerEmergencyWallet(bob);
        vm.prank(alice);
        proxy.registerEmergencyWallet(carol);

        vm.prank(alice);
        proxy.announceEmergencyWalletRevocation(bob);

        // carol cancels
        vm.prank(carol);
        proxy.cancelEmergencyWalletRevocation();

        assertTrue(proxy.isEmergencyWallet(bob));
    }

    function test_RevocationExecuteBeforeDelayReverts() public {
        DENIdentityImpl proxy = _deployProxy(alice);
        vm.prank(alice);
        proxy.registerEmergencyWallet(bob);

        vm.prank(alice);
        proxy.announceEmergencyWalletRevocation(bob);

        vm.expectRevert("Delay not elapsed");
        proxy.executeEmergencyWalletRevocation();
    }

    function test_RevocationExecuteWithNoPendingReverts() public {
        DENIdentityImpl proxy = _deployProxy(alice);
        vm.expectRevert("No pending revocation");
        proxy.executeEmergencyWalletRevocation();
    }

    function test_RevocationAnnouncedNonEmergencyReverts() public {
        DENIdentityImpl proxy = _deployProxy(alice);
        vm.prank(alice);
        vm.expectRevert("Not emergency wallet");
        proxy.announceEmergencyWalletRevocation(carol); // carol is not an emergency wallet
    }

    function test_CannotDoubleAnnounceRevocation() public {
        DENIdentityImpl proxy = _deployProxy(alice);
        vm.prank(alice);
        proxy.registerEmergencyWallet(bob);

        vm.prank(alice);
        proxy.announceEmergencyWalletRevocation(bob);

        vm.prank(alice);
        vm.expectRevert("Revocation already pending");
        proxy.announceEmergencyWalletRevocation(bob);
    }

    function test_RevocationEmitsAnnounceEvent() public {
        DENIdentityImpl proxy = _deployProxy(alice);
        vm.prank(alice);
        proxy.registerEmergencyWallet(bob);

        uint256 expectedExecuteAfter = block.timestamp + proxy.WALLET_ROTATION_DELAY();
        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit IDENParticipantIdentity.EmergencyWalletRevocationAnnounced(alice, bob, expectedExecuteAfter);
        proxy.announceEmergencyWalletRevocation(bob);
    }

    function test_RevocationEmitsRevokedEventOnExecute() public {
        DENIdentityImpl proxy = _deployProxy(alice);
        vm.prank(alice);
        proxy.registerEmergencyWallet(bob);

        vm.prank(alice);
        proxy.announceEmergencyWalletRevocation(bob);
        vm.warp(block.timestamp + proxy.WALLET_ROTATION_DELAY());

        vm.expectEmit(true, false, false, false);
        emit IDENParticipantIdentity.EmergencyWalletRevoked(bob);
        proxy.executeEmergencyWalletRevocation();
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

    // Clean rotation requires the primary wallet as caller (spec §2.5.4 — dual-signature means
    // old+new wallets sign; the old wallet is the primary). Emergency wallets use
    // initiateCompromiseRotation for unilateral rotation.
    function test_EmergencyWalletCannotInitiateCleanRotation() public {
        DENIdentityImpl proxy = _deployProxy(alice);
        vm.prank(alice);
        proxy.registerEmergencyWallet(carol);

        uint256 nonce = proxy.rotationNonce();
        bytes32 h = _cleanRotationHash(address(proxy), nonce);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(bobKey, h);

        vm.prank(carol);
        vm.expectRevert("Not primary wallet");
        proxy.initiateCleanRotation(bob, _sig(v, r, s));
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

        // bob is not the primary wallet
        vm.prank(bob);
        vm.expectRevert("Not primary wallet");
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

    function test_PrimaryCanInitiateCompromiseRotation() public {
        DENIdentityImpl proxy = _deployProxy(alice);

        // Primary wallet (alice) can also announce a unilateral rotation (spec §2.5.4)
        vm.prank(alice);
        proxy.initiateCompromiseRotation(bob);

        (address pending,) = proxy.pendingRotation();
        assertEq(pending, bob);
    }

    function test_CompromiseRotationUnauthorizedReverts() public {
        DENIdentityImpl proxy = _deployProxy(alice);

        // carol is neither primary nor emergency — not authorized
        vm.prank(carol);
        vm.expectRevert("Not authorized");
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
        DENIdentityImpl aliceProxy = _deployProxy(alice);
        DENIdentityImpl instanceProxy = _deployProxy(carol);

        vm.prank(alice);
        aliceProxy.registerEmergencyWallet(bob);

        string memory url = "https://den.example.com";
        bytes32 h = _urlConfirmHash(address(aliceProxy), url, aliceProxy.urlUpdateNonce());
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(carolKey, h);
        vm.prank(alice);
        aliceProxy.updateInstanceURL(url, address(instanceProxy), _sig(v, r, s));

        DENIdentityImpl newImpl = new DENIdentityImpl();
        vm.prank(alice);
        aliceProxy.upgradeTo(address(newImpl));

        // All state preserved after upgrade
        assertEq(aliceProxy.primaryWallet(), alice);
        assertTrue(aliceProxy.isEmergencyWallet(bob));
        assertEq(aliceProxy.instanceURL(), url);
    }
}
