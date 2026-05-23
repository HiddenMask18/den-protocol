// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "../../src/interfaces/IDENGovernanceParams.sol";

// Test mock: returns V1 default values for all governance parameters.
// Used when constructing DENIdentityImpl in tests that don't need live governance.
contract MockGovParams is IDENGovernanceParams {
    function getWalletRotationDelay() external pure returns (uint256) { return 3 days; }
    function getRotationAnnouncementCooldown() external pure returns (uint256) { return 1 hours; }
    function getHandleChangeAllowance() external pure returns (uint256) { return 2; }
    function getHandleChangePeriod() external pure returns (uint256) { return 30 days; }
    function getHandleAliasRetentionWindow() external pure returns (uint256) { return 180 days; }
    function getSubscriberProtectionWindow() external pure returns (uint256) { return 30 days; }
    function getSunsetWindowDuration() external pure returns (uint256) { return 30 days; }
    function getStorageCompensationLookback() external pure returns (uint256) { return 90 days; }
    function getMicroMax() external pure returns (uint256) { return 80; }
    function getSmallMax() external pure returns (uint256) { return 200; }
    function getMediumMax() external pure returns (uint256) { return 500; }
    function getTier1Threshold() external pure returns (uint256) { return 10; }
    function getTier2Threshold() external pure returns (uint256) { return 50; }
    function getTier3Threshold() external pure returns (uint256) { return 200; }
    function getTierLookbackWindow() external pure returns (uint256) { return 0; }
    function getPostSizeLimit(uint8 tier) external pure returns (uint256) {
        if (tier == 0) return 524_288_000;
        if (tier == 1) return 1_073_741_824;
        if (tier == 2) return 5_368_709_120;
        return 21_474_836_480;
    }
    function getPostRateLimit(uint8 tier) external pure returns (uint256) {
        if (tier == 0) return 10;
        if (tier == 1) return 30;
        if (tier == 2) return 100;
        return type(uint256).max;
    }
    function getCreatorResponseWindow() external pure returns (uint256) { return 7 days; }
    function getCsamSuspensionDuration() external pure returns (uint256) { return 30 days; }
    function getFeeBps() external pure returns (uint256) { return 250; }
    function getInactivityGracePeriod() external pure returns (uint256) { return 0; }
    function getBatchSettlementInterval() external pure returns (uint256) { return 30 days; }
    function getSubscriptionExpiryGracePeriod() external pure returns (uint256) { return 0; }
    function getResolverCacheTtl() external pure returns (uint256) { return 5 minutes; }
}
