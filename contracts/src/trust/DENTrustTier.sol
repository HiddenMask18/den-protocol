// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "../interfaces/IDENContentRegistry.sol";
import "../interfaces/IDENTrustTier.sol";

// Creator trust tier graduation tracker (spec §9).
//
// Tiers govern maximum storage per post, post rate limits, and maximum file size per upload.
// These limits are enforced by the instance layer, not this contract. This contract is the
// single on-chain source of truth for a creator's current tier.
//
// Graduation basis: verified inbound transactions from distinct external participant proxies.
// Qualifying events: subscription payments (DENSubscription) and purchases (DENPurchaseState).
// Each contract calls recordTransaction() at payment time; this contract de-duplicates by
// proxy and applies the self-exclusion rules from spec §9.3.
//
// V1 limitations (governance parameters hardcoded, must become on-chain governed per §10):
// - Tier thresholds (TIER_1_THRESHOLD etc.) are constants — adjust via governance amendment.
// - Lookback window: approximated as all-time in V1. The tier_lookback_window governance
//   parameter (spec §13.4) will introduce time-bounded expiry in a future version.
// - Same-instance exclusion (spec §9.3): on-chain enforcement covers only direct
//   self-subscription and the registered content operator. Broader same-instance wallet
//   exclusion is declared-plus-auditable (consistent with §7.3 bandwidth model).
contract DENTrustTier is IDENTrustTier {

    // Distinct-participant thresholds for tier graduation (spec §9.2, §13.4).
    // Governance parameters for V1 — hardcoded. Adjust through governance process (spec §10).
    uint256 public constant TIER_1_THRESHOLD = 10;
    uint256 public constant TIER_2_THRESHOLD = 50;
    uint256 public constant TIER_3_THRESHOLD = 200;

    address private _owner;
    IDENContentRegistry private _contentRegistry;

    address private _subscriptionContract;
    address private _purchaseContract;

    // creatorProxy => count of distinct qualified external participants
    mapping(address => uint256) private _qualifiedCount;

    // creatorProxy => participantProxy => has this participant ever contributed a qualifying tx?
    // Used to de-duplicate — only the first qualifying transaction from each participant counts.
    mapping(address => mapping(address => bool)) private _hasQualified;

    // Inherited from IDENTrustTier — do not redeclare.
    // event TransactionQualified(address indexed, address indexed, uint256);

    constructor() {
        _owner = msg.sender;
    }

    // --- One-time wiring (owner only) ---

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

    // Content registry wiring enables the operator self-exclusion check (spec §9.3).
    // If not set, only the direct self-subscription exclusion (creatorProxy == participantProxy)
    // is enforced on-chain; operator exclusion becomes declared-plus-auditable.
    function setContentRegistry(address contentRegistry) external {
        require(msg.sender == _owner, "Not owner");
        require(address(_contentRegistry) == address(0), "Already set");
        require(contentRegistry != address(0), "Zero address");
        _contentRegistry = IDENContentRegistry(contentRegistry);
    }

    // --- Payment hook (called by subscription and purchase contracts) ---

    // Records a qualifying inbound transaction for tier graduation purposes (spec §9.2).
    // Silently no-ops if the participant is excluded or has already qualified.
    // Caller must be the registered subscription or purchase contract.
    function recordTransaction(address creatorProxy, address participantProxy) external {
        require(
            msg.sender == _subscriptionContract || msg.sender == _purchaseContract,
            "Unauthorized"
        );

        // Direct self-subscription exclusion (spec §9.3).
        if (participantProxy == creatorProxy) return;

        // Content operator exclusion (spec §9.3): the operator who runs the creator's instance
        // subscribing to or purchasing from the creator they host does not count toward graduation.
        // Closes the self-hosting exploit where a creator-hoster inflates their own count via the
        // operator wallet. Broader same-instance exclusion is declared-plus-auditable in V1.
        if (address(_contentRegistry) != address(0)) {
            address operator = _contentRegistry.getContentOperator(creatorProxy);
            if (operator != address(0) && operator == participantProxy) return;
        }

        // De-duplicate: only count the first qualifying transaction from each distinct participant.
        // Lookback window is approximated as all-time in V1 (spec §13.4 tier_lookback_window).
        if (_hasQualified[creatorProxy][participantProxy]) return;

        _hasQualified[creatorProxy][participantProxy] = true;
        _qualifiedCount[creatorProxy]++;

        emit TransactionQualified(creatorProxy, participantProxy, _qualifiedCount[creatorProxy]);
    }

    // --- Views ---

    // Returns the creator's current trust tier (0–3).
    // Tier 0 is the new-creator baseline — sufficient for normal creative output (spec §9.4).
    function getTier(address creatorProxy) external view returns (uint8) {
        uint256 count = _qualifiedCount[creatorProxy];
        if (count >= TIER_3_THRESHOLD) return 3;
        if (count >= TIER_2_THRESHOLD) return 2;
        if (count >= TIER_1_THRESHOLD) return 1;
        return 0;
    }

    function getQualifiedCount(address creatorProxy) external view returns (uint256) {
        return _qualifiedCount[creatorProxy];
    }
}
