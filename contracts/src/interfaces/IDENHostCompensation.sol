// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

interface IDENHostCompensation {

    // Per-bracket rate pair: both values are in the token's smallest unit per declared GB.
    // For ETH: wei per GB. For USDC (6 decimals): USDC-units per GB.
    // Index 0 = micro, 1 = small, 2 = medium, 3 = large (spec §13.4).
    struct BracketRates {
        uint256 storageRatePerGB;
        uint256 bandwidthRatePerGB;
    }

    event FeeDeposited(address indexed creatorProxy, address indexed token, uint256 amount);

    // instanceSize and subscriberCount are declared by the hoster and emitted for on-chain audit
    // (spec §7.3 declared-plus-auditable). Systematic overclaiming is detectable via anomaly analysis.
    event CompensationClaimed(
        address indexed hosterProxy,
        address indexed creatorProxy,
        address indexed token,
        uint256 hosterClaim,
        uint256 creatorSurplus,
        uint256 instanceSize,
        uint256 subscriberCount
    );

    // Called by subscription and purchase contracts to deposit the protocol fee into the
    // per-creator fee pool. For ETH: msg.value must equal amount. For ERC-20: tokens already
    // transferred to this contract, msg.value == 0 (spec §13.2).
    function depositFee(address creatorProxy, address token, uint256 amount) external payable;

    // Called by the registered content operator (hoster) to claim resource compensation and
    // return any surplus to the creator. Uses the progressive rate formula (spec §7.2, §13.2).
    // storageGB, bandwidthGB, instanceSize, and subscriberCount are declared by the hoster
    // (declared-plus-auditable, spec §7.3). All four are emitted for community audit.
    // subscriberCount: verified active subscribers for this creator on this instance within the
    // storage_compensation_lookback window. Must be >= 1 to claim storage compensation (spec §7.2).
    // Spec gap: on-chain enumeration of active subscribers is not gas-practical; declared-plus-
    // auditable is the correct model per §7.3 (same as bandwidth).
    // instanceSize = creator_count + subscription_relationship_count, same-instance excluded (spec §9.3).
    function claimCompensation(
        address creatorProxy,
        address token,
        uint256 storageGB,
        uint256 bandwidthGB,
        uint256 instanceSize,
        uint256 subscriberCount
    ) external;

    // One-time wiring — owner only.
    function setSubscriptionContract(address sub) external;
    function setPurchaseContract(address purchase) external;

    // Set progressive rate table for a token. Rates in token's smallest unit per GB.
    // Owner only. Must be called for each supported token before any claim can succeed (spec §13.4).
    function setTokenRates(address token, BracketRates[4] calldata rates) external;

    function getFeePool(address creatorProxy, address token) external view returns (uint256);
    function getTokenRates(address token) external view returns (BracketRates[4] memory);
}
