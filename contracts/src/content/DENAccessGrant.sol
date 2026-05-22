// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "../interfaces/IDENIdentity.sol";
import "../interfaces/IDENParticipantIdentity.sol";
import "../interfaces/IDENAccessGrant.sol";

contract DENAccessGrant is IDENAccessGrant {

    IDENIdentity private _identity;

    // creatorProxy => tierId => AccessGrant
    mapping(address => mapping(uint256 => AccessGrant)) private _grants;

    event GrantPublished(address indexed creatorProxy, uint256 indexed tierId, uint256 version);
    event GrantRevoked(address indexed creatorProxy, uint256 indexed tierId);

    constructor(address identityContractAddress) {
        _identity = IDENIdentity(identityContractAddress);
    }

    // Publish or update an access grant for a tier.
    // Caller must be the primary wallet of their proxy.
    // Signature must cover: ("DEN-access-grant", proxyAddress, tierId, keccak256(abi.encode(paths)), nextVersion)
    // using Ethereum personal sign (\x19Ethereum Signed Message:\n32 prefix).
    // The version in the signature must match what the contract will assign (existing.version + 1, or 1 if new).
    // The signature is stored alongside the grant for portable data set verification (spec §4.1).
    function publishGrant(uint256 tierId, string[] calldata paths, bytes calldata sig) external {
        require(paths.length > 0, "Empty paths");

        address proxy = _identity.getProxy(msg.sender);
        require(proxy != address(0), "Not registered");
        require(IDENParticipantIdentity(proxy).primaryWallet() == msg.sender, "Not primary wallet");

        AccessGrant storage existing = _grants[proxy][tierId];
        uint256 newVersion = existing.exists ? existing.version + 1 : 1;

        bytes32 pathsHash = keccak256(abi.encode(paths));
        bytes32 structHash = keccak256(abi.encode("DEN-access-grant", proxy, tierId, pathsHash, newVersion));
        bytes32 ethHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", structHash));
        require(_recoverSigner(ethHash, sig) == msg.sender, "Invalid signature");

        // Write new grant; string[] and bytes require explicit loops/assignment from calldata to storage
        delete _grants[proxy][tierId];
        AccessGrant storage grant = _grants[proxy][tierId];
        grant.version = newVersion;
        grant.exists = true;
        for (uint256 i = 0; i < paths.length; i++) {
            grant.derivationPaths.push(paths[i]);
        }
        grant.signature = sig;

        emit GrantPublished(proxy, tierId, newVersion);
    }

    // Revoke an existing grant. Caller must be the primary wallet of their proxy.
    function revokeGrant(uint256 tierId) external {
        address proxy = _identity.getProxy(msg.sender);
        require(proxy != address(0), "Not registered");
        require(IDENParticipantIdentity(proxy).primaryWallet() == msg.sender, "Not primary wallet");
        require(_grants[proxy][tierId].exists, "Grant does not exist");

        delete _grants[proxy][tierId];
        emit GrantRevoked(proxy, tierId);
    }

    function getGrant(address creatorProxy, uint256 tierId) external view returns (AccessGrant memory) {
        return _grants[creatorProxy][tierId];
    }

    // Returns true and the derivation paths only if the stored signature still verifies against
    // the creator's CURRENT primary wallet (spec §4.1). A grant signed by an old wallet after
    // a rotation returns valid=false — the creator must re-publish the grant with the new wallet.
    function verifyGrant(address creatorProxy, uint256 tierId) external view returns (bool valid, string[] memory paths) {
        AccessGrant storage grant = _grants[creatorProxy][tierId];
        if (!grant.exists) {
            return (false, new string[](0));
        }

        bytes32 pathsHash = keccak256(abi.encode(grant.derivationPaths));
        bytes32 structHash = keccak256(abi.encode("DEN-access-grant", creatorProxy, tierId, pathsHash, grant.version));
        bytes32 ethHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", structHash));

        address currentPrimary = IDENParticipantIdentity(creatorProxy).primaryWallet();
        address recovered = _recoverSignerFromMemory(ethHash, grant.signature);

        return (recovered == currentPrimary, grant.derivationPaths);
    }

    function _recoverSignerFromMemory(bytes32 ethSignedHash, bytes memory sig) internal pure returns (address) {
        if (sig.length != 65) return address(0);
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := mload(add(sig, 32))
            s := mload(add(sig, 64))
            v := byte(0, mload(add(sig, 96)))
        }
        if (v < 27) v += 27;
        if (v != 27 && v != 28) return address(0);
        return ecrecover(ethSignedHash, v, r, s);
    }

    function _recoverSigner(bytes32 ethSignedHash, bytes calldata sig) internal pure returns (address) {
        require(sig.length == 65, "Invalid sig length");
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := calldataload(sig.offset)
            s := calldataload(add(sig.offset, 32))
            v := byte(0, calldataload(add(sig.offset, 64)))
        }
        if (v < 27) v += 27;
        require(v == 27 || v == 28, "Invalid sig v");
        address signer = ecrecover(ethSignedHash, v, r, s);
        require(signer != address(0), "Invalid sig");
        return signer;
    }
}
