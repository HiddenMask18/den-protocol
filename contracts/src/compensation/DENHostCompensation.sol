// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "../interfaces/IDENIdentity.sol";
import "../interfaces/IDENParticipantIdentity.sol";
import "../interfaces/IDENContentRegistry.sol";
import "../interfaces/IDENHostCompensation.sol";
import "../interfaces/IERC20.sol";

contract DENHostCompensation is IDENHostCompensation {

    // Protocol fee: 2.5% of each subscription and purchase payment (spec §13.3).
    // Governance parameter for V1 — hardcoded. Must match FEE_BPS in DENSubscription and DENPurchaseState.
    uint256 public constant FEE_BPS = 250;

    // How far back subscriber activity is checked before denying a storage compensation claim (spec §7.2).
    // Governance parameter for V1 — hardcoded.
    uint256 public constant STORAGE_COMPENSATION_LOOKBACK = 90 days;

    // Instance size bracket thresholds (spec §13.4 progressive_rate_parameters).
    // Instance size = creator_count + subscription_relationship_count, same-instance excluded (spec §9.3).
    uint256 public constant MICRO_MAX  = 80;
    uint256 public constant SMALL_MAX  = 200;
    uint256 public constant MEDIUM_MAX = 500;

    address private _owner;
    IDENIdentity private _identity;
    IDENContentRegistry private _contentRegistry;

    address private _subscriptionContract;
    address private _purchaseContract;

    // token => [micro, small, medium, large] rates
    mapping(address => BracketRates[4]) private _rates;

    // creatorProxy => token => accumulated protocol fee available for hoster claim
    mapping(address => mapping(address => uint256)) private _feePool;

    // creatorProxy => token => timestamp of last depositFee call (informational; not used for threshold check).
    mapping(address => mapping(address => uint256)) private _lastFeeTimestamp;

    constructor(address identityRegistry, address contentRegistry) {
        require(identityRegistry != address(0), "Zero address");
        require(contentRegistry != address(0), "Zero address");
        _owner = msg.sender;
        _identity = IDENIdentity(identityRegistry);
        _contentRegistry = IDENContentRegistry(contentRegistry);
    }

    // --- Owner-only configuration ---

    function setSubscriptionContract(address sub) external {
        require(msg.sender == _owner, "Not owner");
        require(_subscriptionContract == address(0), "Already set");
        require(sub != address(0), "Zero address");
        _subscriptionContract = sub;
    }

    function setPurchaseContract(address purchase) external {
        require(msg.sender == _owner, "Not owner");
        require(_purchaseContract == address(0), "Already set");
        require(purchase != address(0), "Zero address");
        _purchaseContract = purchase;
    }

    function setTokenRates(address token, BracketRates[4] calldata rates) external {
        require(msg.sender == _owner, "Not owner");
        _rates[token][0] = rates[0];
        _rates[token][1] = rates[1];
        _rates[token][2] = rates[2];
        _rates[token][3] = rates[3];
    }

    // --- Fee deposit (called by subscription and purchase contracts at payment time) ---

    function depositFee(address creatorProxy, address token, uint256 amount) external payable {
        require(msg.sender == _subscriptionContract || msg.sender == _purchaseContract, "Unauthorized");
        require(amount > 0, "Zero amount");
        if (token == address(0)) {
            require(msg.value == amount, "ETH mismatch");
        } else {
            require(msg.value == 0, "No ETH for token deposit");
        }
        _feePool[creatorProxy][token] += amount;
        _lastFeeTimestamp[creatorProxy][token] = block.timestamp;
        emit FeeDeposited(creatorProxy, token, amount);
    }

    // --- Hoster resource compensation claim (spec §7.2, §13.2) ---

    function claimCompensation(
        address creatorProxy,
        address token,
        uint256 storageGB,
        uint256 bandwidthGB,
        uint256 instanceSize,
        uint256 subscriberCount
    ) external {
        // Caller must be the registered content operator for this creator.
        address hosterProxy = _identity.getProxy(msg.sender);
        require(hosterProxy != address(0), "Not registered");
        require(IDENParticipantIdentity(hosterProxy).primaryWallet() == msg.sender, "Not primary wallet");
        require(_identity.isRegisteredProxy(creatorProxy), "Creator proxy not registered");
        require(_contentRegistry.getContentOperator(creatorProxy) == hosterProxy, "Not content operator");

        uint256 pool = _feePool[creatorProxy][token];
        require(pool > 0, "Nothing to claim");

        // Storage compensation threshold (spec §7.2): hoster cannot claim storage compensation if
        // the creator has had zero verified active subscribers within the lookback window.
        // Exempted during active migration (active sunset = migration window, spec §7.2).
        // Spec gap: on-chain enumeration of all subscribers is not gas-practical; subscriberCount
        // is declared by the hoster and emitted for community audit (declared-plus-auditable,
        // consistent with §7.3 bandwidth model). Systematic false claims are detectable on-chain.
        if (!_contentRegistry.hasActiveSunset(creatorProxy)) {
            require(subscriberCount > 0, "Storage compensation threshold: no verified active subscribers");
        }

        // Progressive rate formula (spec §13.2): hoster_claim = min(formula, fee_pool).
        BracketRates memory rates = _getBracketRates(token, instanceSize);
        uint256 formulaResult = (storageGB * rates.storageRatePerGB) + (bandwidthGB * rates.bandwidthRatePerGB);
        uint256 hosterClaim = formulaResult < pool ? formulaResult : pool;
        uint256 creatorSurplus = pool - hosterClaim;

        // Zero pool before transfers (checks-effects-interactions).
        _feePool[creatorProxy][token] = 0;

        emit CompensationClaimed(hosterProxy, creatorProxy, token, hosterClaim, creatorSurplus, instanceSize, subscriberCount);

        if (hosterClaim > 0) {
            _transfer(token, msg.sender, hosterClaim);
        }

        // Surplus returns to creator's current primary wallet.
        // Resolves correctly after wallet rotation — proxy always holds the current active wallet.
        if (creatorSurplus > 0) {
            address creatorWallet = IDENParticipantIdentity(creatorProxy).primaryWallet();
            _transfer(token, creatorWallet, creatorSurplus);
        }
    }

    // --- Views ---

    function getFeePool(address creatorProxy, address token) external view returns (uint256) {
        return _feePool[creatorProxy][token];
    }

    function getTokenRates(address token) external view returns (BracketRates[4] memory) {
        return _rates[token];
    }

    // --- Internal helpers ---

    function _getBracketRates(address token, uint256 instanceSize) internal view returns (BracketRates memory) {
        if (instanceSize < MICRO_MAX)  return _rates[token][0];
        if (instanceSize < SMALL_MAX)  return _rates[token][1];
        if (instanceSize < MEDIUM_MAX) return _rates[token][2];
        return _rates[token][3];
    }

    function _transfer(address token, address to, uint256 amount) internal {
        if (token == address(0)) {
            (bool ok,) = to.call{value: amount}("");
            require(ok, "ETH transfer failed");
        } else {
            bool ok = IERC20(token).transfer(to, amount);
            require(ok, "Token transfer failed");
        }
    }
}
