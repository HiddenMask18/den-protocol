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

    // Governance parameter: delay before compromise rotation executes (3 days for V1).
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

    // --- Emergency wallet management ---

    function registerEmergencyWallet(address wallet) external onlyPrimary {
        require(wallet != address(0), "Zero address");
        require(wallet != _primaryWallet, "Cannot be primary");
        require(!_emergencyWallets[wallet], "Already emergency wallet");
        _emergencyWallets[wallet] = true;
        _emergencyWalletList.push(wallet);
        emit EmergencyWalletRegistered(wallet);
    }

    function revokeEmergencyWallet(address wallet) external onlyAuthorized {
        require(_emergencyWallets[wallet], "Not emergency wallet");
        _emergencyWallets[wallet] = false;
        _removeFromList(wallet);
        emit EmergencyWalletRevoked(wallet);
    }

    // --- Instance URL ---

    function updateInstanceURL(string calldata url) external onlyPrimary {
        _instanceURL = url;
        emit InstanceURLUpdated(url);
    }

    // --- Wallet rotation ---

    // Clean rotation: both wallets accessible.
    // newWallet must sign: keccak256(abi.encode("DEN-clean-rotation", proxyAddress, nonce))
    // using Ethereum personal sign (prefixed with "\x19Ethereum Signed Message:\n32").
    function initiateCleanRotation(address newWallet, bytes calldata newWalletSig) external onlyAuthorized {
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
    // Only callable by an emergency wallet (primary is assumed inaccessible).
    function initiateCompromiseRotation(address newWallet) external {
        require(_emergencyWallets[msg.sender], "Only emergency wallet");
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
