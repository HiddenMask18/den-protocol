// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

// Interface for the per-participant identity proxy.
// Every registered participant has a proxy at a stable address that exposes these functions.
// Logic is delegatecalled to DENIdentityImpl; state lives in the proxy's own storage.
interface IDENParticipantIdentity {
    event EmergencyWalletRegistered(address indexed wallet);
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

    function registerEmergencyWallet(address wallet) external;
    function revokeEmergencyWallet(address wallet) external;
    function updateInstanceURL(string calldata url) external;
    function initiateCleanRotation(address newWallet, bytes calldata newWalletSig) external;
    function initiateCompromiseRotation(address newWallet) external;
    function cancelCompromiseRotation() external;
    function executeCompromiseRotation() external;
    function upgradeTo(address newImplementation) external;
}
