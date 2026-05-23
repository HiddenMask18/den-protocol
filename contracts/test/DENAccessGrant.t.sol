// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "./mocks/MockGovParams.sol";
import "../src/identity/DENIdentityImpl.sol";
import "../src/identity/DENIdentityRegistry.sol";
import "../src/interfaces/IDENParticipantIdentity.sol";
import "../src/content/DENAccessGrant.sol";

contract DENAccessGrantTest is Test {
    DENIdentityImpl impl;
    DENIdentityRegistry registry;
    DENAccessGrant accessGrant;

    uint256 aliceKey;
    address alice;
    uint256 bobKey;
    address bob;
    address carol;

    address aliceProxy;

    uint256 constant TIER_ID = 1;
    string[] paths1;
    string[] paths2;

    function setUp() public {
        (alice, aliceKey) = makeAddrAndKey("alice");
        (bob, bobKey) = makeAddrAndKey("bob");
        carol = makeAddr("carol");

        impl = new DENIdentityImpl(address(new MockGovParams()));
        registry = new DENIdentityRegistry(address(impl));
        accessGrant = new DENAccessGrant(address(registry));

        vm.prank(alice);
        registry.register();
        aliceProxy = registry.getProxy(alice);

        paths1.push("tier:1");
        paths2.push("tier:1");
        paths2.push("tier:2");
    }

    // Build the signature the creator must produce before calling publishGrant.
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

    // --- publishGrant ---

    function test_PublishGrantStoresPaths() public {
        bytes memory sig = _signGrant(aliceKey, aliceProxy, TIER_ID, paths1, 1);
        vm.prank(alice);
        accessGrant.publishGrant(TIER_ID, paths1, sig);

        IDENAccessGrant.AccessGrant memory grant = accessGrant.getGrant(aliceProxy, TIER_ID);
        assertTrue(grant.exists);
        assertEq(grant.version, 1);
        assertEq(grant.derivationPaths.length, 1);
        assertEq(grant.derivationPaths[0], "tier:1");
        // Signature stored alongside declaration for portable data set verification (spec §4.1).
        assertEq(grant.signature.length, 65);
    }

    function test_PublishGrantVersionIncrementsOnUpdate() public {
        bytes memory sig1 = _signGrant(aliceKey, aliceProxy, TIER_ID, paths1, 1);
        vm.prank(alice);
        accessGrant.publishGrant(TIER_ID, paths1, sig1);

        bytes memory sig2 = _signGrant(aliceKey, aliceProxy, TIER_ID, paths2, 2);
        vm.prank(alice);
        accessGrant.publishGrant(TIER_ID, paths2, sig2);

        IDENAccessGrant.AccessGrant memory grant = accessGrant.getGrant(aliceProxy, TIER_ID);
        assertEq(grant.version, 2);
        assertEq(grant.derivationPaths.length, 2);
        assertEq(grant.derivationPaths[1], "tier:2");
        assertEq(grant.signature.length, 65);
    }

    function test_PublishGrantEmitsEvent() public {
        bytes memory sig = _signGrant(aliceKey, aliceProxy, TIER_ID, paths1, 1);
        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit DENAccessGrant.GrantPublished(aliceProxy, TIER_ID, 1);
        accessGrant.publishGrant(TIER_ID, paths1, sig);
    }

    function test_PublishGrantInvalidSignatureReverts() public {
        // Sign with bob's key instead of alice's
        bytes memory badSig = _signGrant(bobKey, aliceProxy, TIER_ID, paths1, 1);
        vm.prank(alice);
        vm.expectRevert("Invalid signature");
        accessGrant.publishGrant(TIER_ID, paths1, badSig);
    }

    function test_PublishGrantWrongVersionInSigReverts() public {
        // Sign with version 2 but contract expects version 1 (no existing grant)
        bytes memory sig = _signGrant(aliceKey, aliceProxy, TIER_ID, paths1, 2);
        vm.prank(alice);
        vm.expectRevert("Invalid signature");
        accessGrant.publishGrant(TIER_ID, paths1, sig);
    }

    function test_PublishGrantEmptyPathsReverts() public {
        string[] memory emptyPaths = new string[](0);
        bytes memory sig = _signGrant(aliceKey, aliceProxy, TIER_ID, emptyPaths, 1);
        vm.prank(alice);
        vm.expectRevert("Empty paths");
        accessGrant.publishGrant(TIER_ID, emptyPaths, sig);
    }

    function test_UnregisteredCannotPublishGrant() public {
        bytes memory sig = _signGrant(bobKey, address(0), TIER_ID, paths1, 1);
        vm.prank(carol);
        vm.expectRevert("Not registered");
        accessGrant.publishGrant(TIER_ID, paths1, sig);
    }

    // --- wallet rotation: old key rejected, new key accepted ---

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

    function test_OldWalletSignatureRejectedAfterRotation() public {
        // Alice publishes a grant at version 1
        bytes memory sig1 = _signGrant(aliceKey, aliceProxy, TIER_ID, paths1, 1);
        vm.prank(alice);
        accessGrant.publishGrant(TIER_ID, paths1, sig1);

        // Alice rotates to alice2
        (address alice2, uint256 alice2Key) = makeAddrAndKey("alice2");
        _rotateWallet(aliceProxy, aliceKey, alice2, alice2Key);

        // Old key tries to sign version 2 — rejected because primaryWallet is now alice2
        bytes memory oldSig = _signGrant(aliceKey, aliceProxy, TIER_ID, paths2, 2);
        vm.prank(alice2);
        vm.expectRevert("Invalid signature");
        accessGrant.publishGrant(TIER_ID, paths2, oldSig);

        (alice2Key); // silence unused variable warning
    }

    function test_NewWalletSignatureAcceptedAfterRotation() public {
        bytes memory sig1 = _signGrant(aliceKey, aliceProxy, TIER_ID, paths1, 1);
        vm.prank(alice);
        accessGrant.publishGrant(TIER_ID, paths1, sig1);

        (address alice2, uint256 alice2Key) = makeAddrAndKey("alice2");
        _rotateWallet(aliceProxy, aliceKey, alice2, alice2Key);

        // New wallet signs version 2 and it is accepted
        bytes memory newSig = _signGrant(alice2Key, aliceProxy, TIER_ID, paths2, 2);
        vm.prank(alice2);
        accessGrant.publishGrant(TIER_ID, paths2, newSig);

        IDENAccessGrant.AccessGrant memory grant = accessGrant.getGrant(aliceProxy, TIER_ID);
        assertEq(grant.version, 2);
        assertEq(grant.derivationPaths[1], "tier:2");
    }

    // --- revokeGrant ---

    function test_RevokeGrant() public {
        bytes memory sig = _signGrant(aliceKey, aliceProxy, TIER_ID, paths1, 1);
        vm.prank(alice);
        accessGrant.publishGrant(TIER_ID, paths1, sig);

        vm.prank(alice);
        accessGrant.revokeGrant(TIER_ID);

        IDENAccessGrant.AccessGrant memory grant = accessGrant.getGrant(aliceProxy, TIER_ID);
        assertFalse(grant.exists);
    }

    function test_RevokeNonexistentGrantReverts() public {
        vm.prank(alice);
        vm.expectRevert("Grant does not exist");
        accessGrant.revokeGrant(TIER_ID);
    }

    function test_NonPrimaryCannotRevoke() public {
        bytes memory sig = _signGrant(aliceKey, aliceProxy, TIER_ID, paths1, 1);
        vm.prank(alice);
        accessGrant.publishGrant(TIER_ID, paths1, sig);

        vm.prank(bob);
        registry.register();
        vm.prank(bob);
        vm.expectRevert("Grant does not exist");
        accessGrant.revokeGrant(TIER_ID);
    }

    function test_RevokeEmitsEvent() public {
        bytes memory sig = _signGrant(aliceKey, aliceProxy, TIER_ID, paths1, 1);
        vm.prank(alice);
        accessGrant.publishGrant(TIER_ID, paths1, sig);

        vm.prank(alice);
        vm.expectEmit(true, true, false, false);
        emit DENAccessGrant.GrantRevoked(aliceProxy, TIER_ID);
        accessGrant.revokeGrant(TIER_ID);
    }

    // --- verifyGrant ---

    function test_VerifyGrantReturnsPathsWhenExists() public {
        bytes memory sig = _signGrant(aliceKey, aliceProxy, TIER_ID, paths1, 1);
        vm.prank(alice);
        accessGrant.publishGrant(TIER_ID, paths1, sig);

        (bool valid, string[] memory returnedPaths) = accessGrant.verifyGrant(aliceProxy, TIER_ID);
        assertTrue(valid);
        assertEq(returnedPaths.length, 1);
        assertEq(returnedPaths[0], "tier:1");
    }

    function test_VerifyGrantReturnsFalseWhenMissing() public view {
        (bool valid, string[] memory returnedPaths) = accessGrant.verifyGrant(aliceProxy, TIER_ID);
        assertFalse(valid);
        assertEq(returnedPaths.length, 0);
    }

    function test_VerifyGrantReturnsFalseAfterRevocation() public {
        bytes memory sig = _signGrant(aliceKey, aliceProxy, TIER_ID, paths1, 1);
        vm.prank(alice);
        accessGrant.publishGrant(TIER_ID, paths1, sig);

        vm.prank(alice);
        accessGrant.revokeGrant(TIER_ID);

        (bool valid,) = accessGrant.verifyGrant(aliceProxy, TIER_ID);
        assertFalse(valid);
    }

    // --- re-publish after revocation resets version ---

    function test_RepublishAfterRevocationStartsAtVersionOne() public {
        bytes memory sig1 = _signGrant(aliceKey, aliceProxy, TIER_ID, paths1, 1);
        vm.prank(alice);
        accessGrant.publishGrant(TIER_ID, paths1, sig1);

        vm.prank(alice);
        accessGrant.revokeGrant(TIER_ID);

        // After revocation the slot is empty, so next publish must use version 1
        bytes memory sig2 = _signGrant(aliceKey, aliceProxy, TIER_ID, paths1, 1);
        vm.prank(alice);
        accessGrant.publishGrant(TIER_ID, paths1, sig2);

        IDENAccessGrant.AccessGrant memory grant = accessGrant.getGrant(aliceProxy, TIER_ID);
        assertEq(grant.version, 1);
    }
}
