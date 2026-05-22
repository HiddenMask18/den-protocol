// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

interface IDENTrustTier {

    // Emitted when a new distinct participant qualifies a transaction for a creator,
    // incrementing the creator's qualified participant count.
    event TransactionQualified(
        address indexed creatorProxy,
        address indexed participantProxy,
        uint256 newCount
    );

    // Called by DENSubscription and DENPurchaseState at payment time to record a
    // qualifying inbound transaction for tier graduation purposes (spec §9.2).
    // Applies self-exclusion (spec §9.3) and de-duplicates by participant proxy.
    // No-ops silently if the transaction does not qualify.
    function recordTransaction(address creatorProxy, address participantProxy) external;

    // Returns the creator's current trust tier (0–3) based on their qualified participant count
    // relative to governance-parameter thresholds (spec §9.1, §9.2, §13.4).
    // Tier 0 is the baseline — all new creators begin here (spec §9.4).
    function getTier(address creatorProxy) external view returns (uint8);

    // Returns the number of distinct external participants whose transactions have qualified
    // toward this creator's tier graduation (spec §9.2).
    function getQualifiedCount(address creatorProxy) external view returns (uint256);

    // One-time wiring — owner only.
    function setSubscriptionContract(address sub) external;
    function setPurchaseContract(address purchase) external;
    function setContentRegistry(address contentRegistry) external;
}
