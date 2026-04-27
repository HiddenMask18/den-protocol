// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

interface IDENAccessGrant {

    struct AccessGrant {
        string[] derivationPaths; // e.g. ["tier:1"] or ["tier:1","tier:2"] for cumulative tiers
        uint256 version;          // increments on each publish; used for replay protection
        bool exists;
        bytes signature;          // stored alongside declaration per spec §4.1; required for migration verification
    }

    // Creator publishes a signed access grant for a tier.
    // Caller must be the primary wallet of their proxy. Signature must cover
    // (proxyAddress, tierId, derivationPaths, nextVersion).
    function publishGrant(uint256 tierId, string[] calldata paths, bytes calldata sig) external;

    // Creator revokes a tier grant. No signature required — on-chain auth via msg.sender suffices.
    function revokeGrant(uint256 tierId) external;

    function getGrant(address creatorProxy, uint256 tierId) external view returns (AccessGrant memory);

    // Returns (valid, paths). valid is false if the grant does not exist.
    function verifyGrant(address creatorProxy, uint256 tierId) external view returns (bool valid, string[] memory paths);
}
