// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

// Interface for the per-participant identity proxy.
// Every registered participant has a proxy at a stable address that exposes these functions.
// Logic is delegatecalled to DENIdentityImpl; state lives in the proxy's own storage.
interface IDENParticipantIdentity {
    event EmergencyWalletRegistered(address indexed wallet);
    // Emitted when a revocation is announced (time-delay begins).
    event EmergencyWalletRevocationAnnounced(address indexed initiator, address indexed wallet, uint256 executeAfter);
    // Emitted when a pending revocation is cancelled by any registered wallet.
    event EmergencyWalletRevocationCancelled(address indexed cancelledBy, address indexed wallet);
    // Emitted when a revocation executes after the delay elapses.
    event EmergencyWalletRevoked(address indexed wallet);
    event InstanceURLUpdated(string url);
    event CleanRotationExecuted(address indexed oldWallet, address indexed newWallet);
    event CompromiseRotationAnnounced(address indexed initiator, address indexed newWallet, uint256 executeAfter);
    event CompromiseRotationCancelled(address indexed cancelledBy);
    event CompromiseRotationExecuted(address indexed oldWallet, address indexed newWallet);
    event Upgraded(address indexed newImplementation);

    function initialize(address primaryWallet) external;
    function primaryWallet() external view returns (address);
    function isEmergencyWallet(address wallet) external view returns (bool);
    function instanceURL() external view returns (string memory);
    function rotationNonce() external view returns (uint256);
    function pendingRotation() external view returns (address newWallet, uint256 executeAfter);
    function pendingRevocation() external view returns (address wallet, uint256 executeAfter);
    function urlUpdateNonce() external view returns (uint256);
    // Unix timestamp of the last rotation or revocation announcement; 0 if none yet.
    // Clients use this to compute when the next announcement is permitted (spec §2.5.6).
    function lastAnnouncementAt() external view returns (uint256);

    function registerEmergencyWallet(address wallet) external;

    // Announces a time-delayed revocation of an emergency wallet (spec §2.5.5).
    // Any registered wallet can cancel during the delay window.
    function announceEmergencyWalletRevocation(address wallet) external;
    function cancelEmergencyWalletRevocation() external;
    function executeEmergencyWalletRevocation() external;

    // Update the instance URL. Non-empty URLs require a countersignature from the
    // receiving instance's primary wallet confirming it holds the Creator's portable data set.
    // Pass empty url with zero address and empty sig to clear.
    // Signature covers: keccak256(abi.encode("DEN-url-confirm", proxyAddress, url, urlUpdateNonce))
    function updateInstanceURL(string calldata url, address receivingInstanceProxy, bytes calldata instanceSig) external;

    function initiateCleanRotation(address newWallet, bytes calldata newWalletSig) external;
    // Any registered wallet (primary or emergency) may announce a unilateral rotation (spec §2.5.4).
    function initiateCompromiseRotation(address newWallet) external;
    function cancelCompromiseRotation() external;
    function executeCompromiseRotation() external;
    function upgradeTo(address newImplementation) external;
}
