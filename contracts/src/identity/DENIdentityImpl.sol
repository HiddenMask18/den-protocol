// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "../interfaces/IDENParticipantIdentity.sol";

// Logic contract for per-participant identity proxies.
// All state lives in the proxy's storage via delegatecall.
// Storage layout is append-only across upgrades.
contract DENIdentityImpl is IDENParticipantIdentity {

    // ERC-1967 implementation slot: keccak256("eip1967.proxy.implementation") - 1
    bytes32 internal constant _IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    // --- Storage layout (must never reorder for upgrade safety) ---
    uint256 private _initialized;           // slot 0
    address private _primaryWallet;         // slot 1
    uint256 private _rotationNonce;         // slot 2
    address private _pendingNewWallet;      // slot 3
    uint256 private _rotationExecuteAfter;  // slot 4
    string private _instanceURL;            // slot 5
    address[] private _emergencyWalletList; // slot 6
    mapping(address => bool) private _emergencyWallets; // slot 7
    address private _pendingRevokedWallet;   // slot 8
    uint256 private _revocationExecuteAfter; // slot 9
    uint256 private _urlUpdateNonce;         // slot 10

    // Governance parameter: delay before compromise rotation or revocation executes (3 days for V1).
    // Must become a governance parameter in a future upgrade.
    uint256 public constant WALLET_ROTATION_DELAY = 3 days;

    // Prevent direct initialization of the impl contract itself.
    constructor() {
        _initialized = 1;
    }

    modifier onlyPrimary() {
        require(msg.sender == _primaryWallet, "Not primary wallet");
        _;
    }

    modifier onlyAuthorized() {
        require(
            msg.sender == _primaryWallet || _emergencyWallets[msg.sender],
            "Not authorized"
        );
        _;
    }

    // --- Initialization ---

    function initialize(address wallet) external {
        require(_initialized == 0, "Already initialized");
        require(wallet != address(0), "Zero address");
        _initialized = 1;
        _primaryWallet = wallet;
    }

    // --- View functions ---

    function primaryWallet() external view returns (address) {
        return _primaryWallet;
    }

    function isEmergencyWallet(address wallet) external view returns (bool) {
        return _emergencyWallets[wallet];
    }

    function instanceURL() external view returns (string memory) {
        return _instanceURL;
    }

    function rotationNonce() external view returns (uint256) {
        return _rotationNonce;
    }

    function pendingRotation() external view returns (address newWallet, uint256 executeAfter) {
        return (_pendingNewWallet, _rotationExecuteAfter);
    }

    function pendingRevocation() external view returns (address wallet, uint256 executeAfter) {
        return (_pendingRevokedWallet, _revocationExecuteAfter);
    }

    function urlUpdateNonce() external view returns (uint256) {
        return _urlUpdateNonce;
    }

    // --- Emergency wallet management ---

    function registerEmergencyWallet(address wallet) external onlyPrimary {
        require(wallet != address(0), "Zero address");
        require(wallet != _primaryWallet, "Cannot be primary");
        require(!_emergencyWallets[wallet], "Already emergency wallet");
        _emergencyWallets[wallet] = true;
        _emergencyWalletList.push(wallet);
        emit EmergencyWalletRegistered(wallet);
    }

    // Announces a time-delayed revocation. Any registered wallet can cancel during the delay window.
    // Revocation follows the same time-delay mechanism as unilateral rotation (spec §2.5.5).
    function announceEmergencyWalletRevocation(address wallet) external onlyAuthorized {
        require(_emergencyWallets[wallet], "Not emergency wallet");
        require(_revocationExecuteAfter == 0, "Revocation already pending");
        _pendingRevokedWallet = wallet;
        _revocationExecuteAfter = block.timestamp + WALLET_ROTATION_DELAY;
        emit EmergencyWalletRevocationAnnounced(msg.sender, wallet, _revocationExecuteAfter);
    }

    // Cancel a pending revocation. Any registered wallet can cancel during the delay window.
    function cancelEmergencyWalletRevocation() external onlyAuthorized {
        require(_revocationExecuteAfter != 0, "No pending revocation");
        address wallet = _pendingRevokedWallet;
        _pendingRevokedWallet = address(0);
        _revocationExecuteAfter = 0;
        emit EmergencyWalletRevocationCancelled(msg.sender, wallet);
    }

    // Execute revocation after the delay has elapsed.
    function executeEmergencyWalletRevocation() external {
        require(_revocationExecuteAfter != 0, "No pending revocation");
        require(block.timestamp >= _revocationExecuteAfter, "Delay not elapsed");
        address wallet = _pendingRevokedWallet;
        _emergencyWallets[wallet] = false;
        _removeFromList(wallet);
        _pendingRevokedWallet = address(0);
        _revocationExecuteAfter = 0;
        emit EmergencyWalletRevoked(wallet);
    }

    // --- Instance URL ---

    // Update the instance URL. Non-empty URL requires a countersignature from the receiving
    // instance's primary wallet confirming it holds the Creator's portable data set (spec §2.5.9).
    // Pass empty url with zero address and empty sig to clear without countersig.
    function updateInstanceURL(
        string calldata url,
        address receivingInstanceProxy,
        bytes calldata instanceSig
    ) external onlyPrimary {
        if (bytes(url).length > 0) {
            bytes32 structHash = keccak256(abi.encode("DEN-url-confirm", address(this), url, _urlUpdateNonce));
            bytes32 ethHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", structHash));
            address instancePrimary = IDENParticipantIdentity(receivingInstanceProxy).primaryWallet();
            require(_recoverSigner(ethHash, instanceSig) == instancePrimary, "Invalid instance signature");
            _urlUpdateNonce++;
        }
        _instanceURL = url;
        emit InstanceURLUpdated(url);
    }

    // --- Wallet rotation ---

    // Clean rotation: both wallets accessible.
    // Requires the current primary wallet as caller — it is the "old wallet" in the dual-signature
    // scheme (spec §2.5.4). Emergency wallets use initiateCompromiseRotation for unilateral rotation.
    // newWallet must sign: keccak256(abi.encode("DEN-clean-rotation", proxyAddress, nonce))
    // using Ethereum personal sign (\x19Ethereum Signed Message:\n32 prefix).
    function initiateCleanRotation(address newWallet, bytes calldata newWalletSig) external onlyPrimary {
        require(newWallet != address(0), "Zero address");
        require(newWallet != _primaryWallet, "Already primary");
        require(_rotationExecuteAfter == 0, "Compromise rotation pending");

        bytes32 structHash = keccak256(abi.encode("DEN-clean-rotation", address(this), _rotationNonce));
        bytes32 ethHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", structHash));
        require(_recoverSigner(ethHash, newWalletSig) == newWallet, "Invalid new wallet signature");

        address old = _primaryWallet;
        _primaryWallet = newWallet;
        _rotationNonce++;
        emit CleanRotationExecuted(old, newWallet);
    }

    // Compromise rotation step 1: initiate time-locked rotation.
    // Any registered wallet (primary or emergency) may announce a unilateral rotation (spec §2.5.4).
    function initiateCompromiseRotation(address newWallet) external onlyAuthorized {
        require(newWallet != address(0), "Zero address");
        require(_rotationExecuteAfter == 0, "Rotation already pending");
        _pendingNewWallet = newWallet;
        _rotationExecuteAfter = block.timestamp + WALLET_ROTATION_DELAY;
        emit CompromiseRotationAnnounced(msg.sender, newWallet, _rotationExecuteAfter);
    }

    // Cancel a pending compromise rotation. Any registered wallet can cancel during the delay window.
    function cancelCompromiseRotation() external onlyAuthorized {
        require(_rotationExecuteAfter != 0, "No pending rotation");
        _pendingNewWallet = address(0);
        _rotationExecuteAfter = 0;
        emit CompromiseRotationCancelled(msg.sender);
    }

    // Execute compromise rotation after the delay has elapsed.
    function executeCompromiseRotation() external {
        require(_rotationExecuteAfter != 0, "No pending rotation");
        require(block.timestamp >= _rotationExecuteAfter, "Delay not elapsed");
        address old = _primaryWallet;
        address newWallet = _pendingNewWallet;
        _primaryWallet = newWallet;
        _pendingNewWallet = address(0);
        _rotationExecuteAfter = 0;
        _rotationNonce++;
        emit CompromiseRotationExecuted(old, newWallet);
    }

    // --- Upgrade ---

    // Participant upgrades their own proxy. Only primary wallet can upgrade.
    function upgradeTo(address newImplementation) external onlyPrimary {
        require(newImplementation != address(0), "Zero address");
        assembly {
            sstore(
                0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc,
                newImplementation
            )
        }
        emit Upgraded(newImplementation);
    }

    // --- Internal helpers ---

    function _removeFromList(address wallet) internal {
        uint256 len = _emergencyWalletList.length;
        for (uint256 i = 0; i < len; i++) {
            if (_emergencyWalletList[i] == wallet) {
                _emergencyWalletList[i] = _emergencyWalletList[len - 1];
                _emergencyWalletList.pop();
                return;
            }
        }
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
