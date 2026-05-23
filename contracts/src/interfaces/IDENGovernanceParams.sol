// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

// Read interface for the DEN governance parameter store (spec §10, §13.4).
// All governance parameters listed in §13.4 are exposed here.
// Contracts read these values via this interface instead of hardcoding constants.
interface IDENGovernanceParams {

    // §2 Identity — wallet rotation
    function getWalletRotationDelay() external view returns (uint256);
    function getRotationAnnouncementCooldown() external view returns (uint256);

    // §2 Identity — handle management
    function getHandleChangeAllowance() external view returns (uint256);
    function getHandleChangePeriod() external view returns (uint256);
    function getHandleAliasRetentionWindow() external view returns (uint256);

    // §7 Content sunset — subscriber protection
    function getSubscriberProtectionWindow() external view returns (uint256);
    function getSunsetWindowDuration() external view returns (uint256);

    // §7 Hoster compensation — storage threshold and bracket assignment
    function getStorageCompensationLookback() external view returns (uint256);
    function getMicroMax() external view returns (uint256);
    function getSmallMax() external view returns (uint256);
    function getMediumMax() external view returns (uint256);

    // §9 Trust tiers — graduation thresholds and limits
    function getTier1Threshold() external view returns (uint256);
    function getTier2Threshold() external view returns (uint256);
    function getTier3Threshold() external view returns (uint256);
    function getTierLookbackWindow() external view returns (uint256);

    // §9 Trust tiers — upload limits (enforced by instance layer)
    // Returns file size limit in bytes for the given tier (0–3).
    function getPostSizeLimit(uint8 tier) external view returns (uint256);
    // Returns max posts per day for the given tier (type(uint256).max = unlimited).
    function getPostRateLimit(uint8 tier) external view returns (uint256);

    // §12 Reporting
    function getCreatorResponseWindow() external view returns (uint256);
    function getCsamSuspensionDuration() external view returns (uint256);

    // §13 Fee transparency
    function getFeeBps() external view returns (uint256);

    // §15 Inactivity and batch settlement (not yet enforced on-chain in V1; stored for auditability)
    function getInactivityGracePeriod() external view returns (uint256);
    function getBatchSettlementInterval() external view returns (uint256);
    function getSubscriptionExpiryGracePeriod() external view returns (uint256);
    function getResolverCacheTtl() external view returns (uint256);
}
