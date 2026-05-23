// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "../interfaces/IDENIdentity.sol";
import "../interfaces/IDENParticipantIdentity.sol";
import "../interfaces/IDENGovernanceParams.sol";
import "./DENIdentityProxy.sol";

// Authoritative registry for DEN participant identity.
// Deploys a per-participant ERC-1967 proxy on registration.
// Manages handle → proxy resolution and alias retention.
// Wallet → proxy mappings must be synced via syncWallet() after a rotation.
contract DENIdentityRegistry is IDENIdentity {

    address public immutable implementation;
    address private _owner;

    // Governance parameter store (spec §10). Set once after deploy.
    // Falls back to V1 defaults when not set.
    address private _govParams;

    // V1 defaults — used when governance params not yet wired.
    uint256 private constant _DEFAULT_HANDLE_ALIAS_RETENTION  = 180 days;
    uint256 private constant _DEFAULT_HANDLE_CHANGE_ALLOWANCE = 2;
    uint256 private constant _DEFAULT_HANDLE_CHANGE_PERIOD    = 30 days;

    mapping(address => address) private _proxyByWallet;
    mapping(address => address) private _walletByProxy;
    mapping(bytes32 => address) private _proxyByHandle;
    mapping(address => string) private _currentHandleOf;
    mapping(bytes32 => AliasRecord) private _handleAliases;
    // Per-proxy change tracking. Period resets lazily on the next change attempt.
    mapping(address => uint256) private _handleChangeCount;
    mapping(address => uint256) private _handleChangePeriodStart;

    struct AliasRecord {
        address proxy;
        uint256 expiresAt;
    }

    event Registered(address indexed wallet, address indexed proxy);
    event HandleSet(address indexed proxy, string handle);
    event HandleChanged(address indexed proxy, string oldHandle, string newHandle);
    event WalletSynced(address indexed proxy, address indexed oldWallet, address indexed newWallet);

    constructor(address _implementation) {
        require(_implementation != address(0), "Zero implementation");
        implementation = _implementation;
        _owner = msg.sender;
    }

    // Wire the governance parameter store. Callable once; owner-only.
    function setGovernanceParams(address govParams_) external {
        require(msg.sender == _owner, "Not owner");
        require(_govParams == address(0), "Already set");
        require(govParams_ != address(0), "Zero address");
        _govParams = govParams_;
    }

    // Governance parameter views — exposed with original constant names for compatibility.
    function HANDLE_ALIAS_RETENTION() public view returns (uint256) {
        return _govParams != address(0)
            ? IDENGovernanceParams(_govParams).getHandleAliasRetentionWindow()
            : _DEFAULT_HANDLE_ALIAS_RETENTION;
    }
    function HANDLE_CHANGE_ALLOWANCE() public view returns (uint256) {
        return _govParams != address(0)
            ? IDENGovernanceParams(_govParams).getHandleChangeAllowance()
            : _DEFAULT_HANDLE_CHANGE_ALLOWANCE;
    }
    function HANDLE_CHANGE_PERIOD() public view returns (uint256) {
        return _govParams != address(0)
            ? IDENGovernanceParams(_govParams).getHandleChangePeriod()
            : _DEFAULT_HANDLE_CHANGE_PERIOD;
    }

    // --- Registration ---

    function register() external {
        require(_proxyByWallet[msg.sender] == address(0), "Already registered");

        bytes memory initData = abi.encodeWithSelector(
            IDENParticipantIdentity.initialize.selector,
            msg.sender
        );
        DENIdentityProxy proxy = new DENIdentityProxy(implementation, initData);

        _proxyByWallet[msg.sender] = address(proxy);
        _walletByProxy[address(proxy)] = msg.sender;
        emit Registered(msg.sender, address(proxy));
    }

    // --- Handle management ---

    // Set or update handle for the caller's identity proxy.
    // Caller must be the current primary wallet of their proxy.
    // Handles are globally unique; prior handle is retained as an alias for HANDLE_ALIAS_RETENTION.
    // Requires caller to already be registered (register() tx = "prior on-chain transaction" per spec §2.5).
    function setHandle(string calldata newHandle) external {
        require(bytes(newHandle).length > 0, "Empty handle");
        address proxy = _proxyByWallet[msg.sender];
        require(proxy != address(0), "Not registered");
        require(IDENParticipantIdentity(proxy).primaryWallet() == msg.sender, "Not primary wallet");

        bytes32 newHash = keccak256(bytes(newHandle));
        require(_proxyByHandle[newHash] == address(0), "Handle taken");
        // Reject if taken by an active alias belonging to a different proxy.
        // Spec §2.5.9: "MUST NOT be registered by another participant" — the same proxy
        // reclaiming its own old handle during the alias window is explicitly permitted.
        require(
            _handleAliases[newHash].proxy == address(0) ||
            _handleAliases[newHash].expiresAt < block.timestamp ||
            _handleAliases[newHash].proxy == proxy,
            "Handle reserved as alias by another participant"
        );

        string memory currentHandle = _currentHandleOf[proxy];
        if (bytes(currentHandle).length > 0) {
            // Rate limit handle changes (spec §2.5.9, §13.4).
            // Period resets lazily: if HANDLE_CHANGE_PERIOD has elapsed since period start, restart.
            // _handleChangePeriodStart == 0 for new proxies; the condition evaluates true only once
            // block.timestamp exceeds HANDLE_CHANGE_PERIOD from epoch, which is always the case on
            // mainnet (and in Foundry tests, block.timestamp = 1 so the condition is false — the
            // allowance is consumed directly without a period reset on the very first change).
            if (block.timestamp >= _handleChangePeriodStart[proxy] + HANDLE_CHANGE_PERIOD()) {
                _handleChangePeriodStart[proxy] = block.timestamp;
                _handleChangeCount[proxy] = 0;
            }
            require(_handleChangeCount[proxy] < HANDLE_CHANGE_ALLOWANCE(), "Handle change allowance exceeded");
            _handleChangeCount[proxy]++;

            bytes32 oldHash = keccak256(bytes(currentHandle));
            delete _proxyByHandle[oldHash];
            _handleAliases[oldHash] = AliasRecord({
                proxy: proxy,
                expiresAt: block.timestamp + HANDLE_ALIAS_RETENTION()
            });
            emit HandleChanged(proxy, currentHandle, newHandle);
        } else {
            emit HandleSet(proxy, newHandle);
        }

        _proxyByHandle[newHash] = proxy;
        _currentHandleOf[proxy] = newHandle;
    }

    // Returns the stored change count and period start for a proxy (spec §2.5.9).
    // Note: period reset is lazy — these values may reflect an expired period until the
    // next change attempt triggers the reset. Callers should check against HANDLE_CHANGE_PERIOD.
    function handleChangeInfo(address proxy) external view returns (uint256 changeCount, uint256 periodStart) {
        return (_handleChangeCount[proxy], _handleChangePeriodStart[proxy]);
    }

    // --- Wallet sync after rotation ---

    // Called by the new primary wallet after a rotation completes in the proxy.
    // Updates the registry's wallet → proxy mapping.
    function syncWallet(address proxyAddress) external {
        require(proxyAddress != address(0), "Zero address");
        address oldWallet = _walletByProxy[proxyAddress];
        require(oldWallet != address(0), "Unknown proxy");
        require(IDENParticipantIdentity(proxyAddress).primaryWallet() == msg.sender, "Not primary wallet");
        require(msg.sender != oldWallet, "Wallet unchanged");
        require(_proxyByWallet[msg.sender] == address(0), "New wallet already registered");

        delete _proxyByWallet[oldWallet];
        _proxyByWallet[msg.sender] = proxyAddress;
        _walletByProxy[proxyAddress] = msg.sender;
        emit WalletSynced(proxyAddress, oldWallet, msg.sender);
    }

    // --- Resolution ---

    // Resolve a handle to its proxy address.
    // Returns active proxy first; falls back to alias if within retention window.
    function resolve(string calldata handle) external view returns (address proxy) {
        bytes32 h = keccak256(bytes(handle));
        proxy = _proxyByHandle[h];
        if (proxy == address(0)) {
            AliasRecord storage record = _handleAliases[h];
            if (record.proxy != address(0) && block.timestamp <= record.expiresAt) {
                return record.proxy;
            }
        }
    }

    // Return the current handle for a proxy address (empty string if none set).
    function handleOf(address proxy) external view returns (string memory) {
        return _currentHandleOf[proxy];
    }

    // --- IDENIdentity compatibility ---

    function isRegistered(address wallet) external view returns (bool) {
        return _proxyByWallet[wallet] != address(0);
    }

    function isRegisteredProxy(address proxy) external view returns (bool) {
        return _walletByProxy[proxy] != address(0);
    }

    // Returns the proxy address for a wallet (stable identity address per spec §2.3).
    function getIdentityAddress(address wallet) external view returns (address) {
        return _proxyByWallet[wallet];
    }

    // Same as getIdentityAddress; clearer name for callers that know the proxy pattern.
    function getProxy(address wallet) external view returns (address) {
        return _proxyByWallet[wallet];
    }
}
