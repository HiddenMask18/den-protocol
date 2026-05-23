// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "../interfaces/IDENGovernanceParams.sol";
import "../interfaces/IDENReportRegistry.sol";

// On-chain governance parameter store for the DEN protocol (spec §10, §13.4).
//
// All values listed in §13.4 are stored here and adjustable by the owner through
// the governance process defined in §10. During the bootstrap phase (§10.5), the
// founding maintainer is owner. Ownership is transferable to a community multisig
// as the protocol transitions to post-bootstrap governance (§10.6).
//
// Every parameter update emits an event for on-chain auditability.
// Initial values match the V1 defaults previously hardcoded in each contract.
//
// Also implements the Option B governance path for operator-conflicted reports
// (spec §12.2): the owner calls resolveConflictedReport(), which forwards the
// determination to DENReportRegistry as msg.sender == this contract address.
// Wire by calling DENReportRegistry.setGovernance(address(this)) after deploy.
contract DENGovernanceParams is IDENGovernanceParams {

    address private _owner;

    // §2 Identity
    uint256 private _walletRotationDelay;
    uint256 private _rotationAnnouncementCooldown;
    uint256 private _handleChangeAllowance;
    uint256 private _handleChangePeriod;
    uint256 private _handleAliasRetentionWindow;

    // §7 Content sunset / hoster compensation
    uint256 private _subscriberProtectionWindow;
    uint256 private _sunsetWindowDuration;
    uint256 private _storageCompensationLookback;
    uint256 private _microMax;
    uint256 private _smallMax;
    uint256 private _mediumMax;

    // §9 Trust tiers
    uint256 private _tier1Threshold;
    uint256 private _tier2Threshold;
    uint256 private _tier3Threshold;
    uint256 private _tierLookbackWindow;
    uint256[4] private _postSizeLimits;
    uint256[4] private _postRateLimits;

    // §12 Reporting
    uint256 private _creatorResponseWindow;
    uint256 private _csamSuspensionDuration;

    // §13 Fee transparency
    uint256 private _feeBps;

    // §15 Inactivity / batch / misc (not yet enforced on-chain in V1)
    uint256 private _inactivityGracePeriod;
    uint256 private _batchSettlementInterval;
    uint256 private _subscriptionExpiryGracePeriod;
    uint256 private _resolverCacheTtl;

    // Option B — conflicted report resolution (spec §12.2).
    // Set once after deploy via setReportRegistry().
    address private _reportRegistry;

    // --- Events ---

    event OwnershipTransferred(address indexed from, address indexed to);

    // §2 Identity events
    event WalletRotationDelayUpdated(uint256 newValue);
    event RotationAnnouncementCooldownUpdated(uint256 newValue);
    event HandleChangeAllowanceUpdated(uint256 newValue);
    event HandleChangePeriodUpdated(uint256 newValue);
    event HandleAliasRetentionWindowUpdated(uint256 newValue);

    // §7 events
    event SubscriberProtectionWindowUpdated(uint256 newValue);
    event SunsetWindowDurationUpdated(uint256 newValue);
    event StorageCompensationLookbackUpdated(uint256 newValue);
    event InstanceSizeBracketsUpdated(uint256 microMax, uint256 smallMax, uint256 mediumMax);

    // §9 events
    event TierThresholdsUpdated(uint256 tier1, uint256 tier2, uint256 tier3);
    event TierLookbackWindowUpdated(uint256 newValue);
    event PostSizeLimitsUpdated(uint256 tier0, uint256 tier1, uint256 tier2, uint256 tier3);
    event PostRateLimitsUpdated(uint256 tier0, uint256 tier1, uint256 tier2, uint256 tier3);

    // §12 events
    event CreatorResponseWindowUpdated(uint256 newValue);
    event CsamSuspensionDurationUpdated(uint256 newValue);

    // §13 events
    event FeeBpsUpdated(uint256 newValue);

    // §15 events
    event InactivityGracePeriodUpdated(uint256 newValue);
    event BatchSettlementIntervalUpdated(uint256 newValue);
    event SubscriptionExpiryGracePeriodUpdated(uint256 newValue);
    event ResolverCacheTtlUpdated(uint256 newValue);

    // Conflicted report resolved by governance (spec §12.2 Option B).
    event ConflictedReportResolved(uint256 indexed reportId, IDENReportRegistry.ReportStatus outcome);

    // --- Constructor (V1 defaults) ---

    constructor() {
        _owner = msg.sender;

        // §2 Identity — V1 defaults
        _walletRotationDelay            = 3 days;
        _rotationAnnouncementCooldown   = 1 hours;
        _handleChangeAllowance          = 2;
        _handleChangePeriod             = 30 days;
        _handleAliasRetentionWindow     = 180 days;

        // §7 Content sunset / hoster compensation — V1 defaults
        _subscriberProtectionWindow     = 30 days;
        _sunsetWindowDuration           = 30 days;
        _storageCompensationLookback    = 90 days;
        _microMax                       = 80;
        _smallMax                       = 200;
        _mediumMax                      = 500;

        // §9 Trust tiers — V1 defaults
        _tier1Threshold                 = 10;
        _tier2Threshold                 = 50;
        _tier3Threshold                 = 200;
        _tierLookbackWindow             = 0;       // 0 = all-time in V1

        // Post size limits in bytes: 500 MB, 1 GB, 5 GB, 20 GB
        _postSizeLimits[0]              = 524_288_000;
        _postSizeLimits[1]              = 1_073_741_824;
        _postSizeLimits[2]              = 5_368_709_120;
        _postSizeLimits[3]              = 21_474_836_480;

        // Post rate limits per day; type(uint256).max = unlimited (tier 3)
        _postRateLimits[0]              = 10;
        _postRateLimits[1]              = 30;
        _postRateLimits[2]              = 100;
        _postRateLimits[3]              = type(uint256).max;

        // §12 Reporting — V1 defaults
        _creatorResponseWindow          = 7 days;
        _csamSuspensionDuration         = 30 days;

        // §13 Fee — V1 default (2.5%)
        _feeBps                         = 250;

        // §15 Misc — V1 defaults (not yet enforced on-chain)
        _inactivityGracePeriod          = 0;
        _batchSettlementInterval        = 30 days;
        _subscriptionExpiryGracePeriod  = 0;
        _resolverCacheTtl               = 5 minutes;
    }

    modifier onlyOwner() {
        require(msg.sender == _owner, "Not owner");
        _;
    }

    // --- Ownership ---

    function owner() external view returns (address) {
        return _owner;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }

    // --- Report registry wiring (one-time) ---

    function setReportRegistry(address registry) external onlyOwner {
        require(_reportRegistry == address(0), "Already set");
        require(registry != address(0), "Zero address");
        _reportRegistry = registry;
    }

    // --- Option B: resolve operator-conflicted reports (spec §12.2) ---
    // Owner calls this after governance process approves a determination.
    // Forwards to DENReportRegistry as msg.sender == this contract, satisfying
    // the reportRegistry._governance check.
    function resolveConflictedReport(
        uint256 reportId,
        IDENReportRegistry.ReportStatus outcome
    ) external onlyOwner {
        require(_reportRegistry != address(0), "Report registry not set");
        IDENReportRegistry(_reportRegistry).determineReport(reportId, outcome);
        emit ConflictedReportResolved(reportId, outcome);
    }

    // --- Getters (IDENGovernanceParams) ---

    function getWalletRotationDelay() external view returns (uint256) {
        return _walletRotationDelay;
    }
    function getRotationAnnouncementCooldown() external view returns (uint256) {
        return _rotationAnnouncementCooldown;
    }
    function getHandleChangeAllowance() external view returns (uint256) {
        return _handleChangeAllowance;
    }
    function getHandleChangePeriod() external view returns (uint256) {
        return _handleChangePeriod;
    }
    function getHandleAliasRetentionWindow() external view returns (uint256) {
        return _handleAliasRetentionWindow;
    }
    function getSubscriberProtectionWindow() external view returns (uint256) {
        return _subscriberProtectionWindow;
    }
    function getSunsetWindowDuration() external view returns (uint256) {
        return _sunsetWindowDuration;
    }
    function getStorageCompensationLookback() external view returns (uint256) {
        return _storageCompensationLookback;
    }
    function getMicroMax() external view returns (uint256) {
        return _microMax;
    }
    function getSmallMax() external view returns (uint256) {
        return _smallMax;
    }
    function getMediumMax() external view returns (uint256) {
        return _mediumMax;
    }
    function getTier1Threshold() external view returns (uint256) {
        return _tier1Threshold;
    }
    function getTier2Threshold() external view returns (uint256) {
        return _tier2Threshold;
    }
    function getTier3Threshold() external view returns (uint256) {
        return _tier3Threshold;
    }
    function getTierLookbackWindow() external view returns (uint256) {
        return _tierLookbackWindow;
    }
    function getPostSizeLimit(uint8 tier) external view returns (uint256) {
        require(tier <= 3, "Invalid tier");
        return _postSizeLimits[tier];
    }
    function getPostRateLimit(uint8 tier) external view returns (uint256) {
        require(tier <= 3, "Invalid tier");
        return _postRateLimits[tier];
    }
    function getCreatorResponseWindow() external view returns (uint256) {
        return _creatorResponseWindow;
    }
    function getCsamSuspensionDuration() external view returns (uint256) {
        return _csamSuspensionDuration;
    }
    function getFeeBps() external view returns (uint256) {
        return _feeBps;
    }
    function getInactivityGracePeriod() external view returns (uint256) {
        return _inactivityGracePeriod;
    }
    function getBatchSettlementInterval() external view returns (uint256) {
        return _batchSettlementInterval;
    }
    function getSubscriptionExpiryGracePeriod() external view returns (uint256) {
        return _subscriptionExpiryGracePeriod;
    }
    function getResolverCacheTtl() external view returns (uint256) {
        return _resolverCacheTtl;
    }

    // --- Setters (owner-only; each emits a named event) ---

    function setWalletRotationDelay(uint256 v) external onlyOwner {
        _walletRotationDelay = v;
        emit WalletRotationDelayUpdated(v);
    }
    function setRotationAnnouncementCooldown(uint256 v) external onlyOwner {
        _rotationAnnouncementCooldown = v;
        emit RotationAnnouncementCooldownUpdated(v);
    }
    function setHandleChangeAllowance(uint256 v) external onlyOwner {
        _handleChangeAllowance = v;
        emit HandleChangeAllowanceUpdated(v);
    }
    function setHandleChangePeriod(uint256 v) external onlyOwner {
        _handleChangePeriod = v;
        emit HandleChangePeriodUpdated(v);
    }
    function setHandleAliasRetentionWindow(uint256 v) external onlyOwner {
        _handleAliasRetentionWindow = v;
        emit HandleAliasRetentionWindowUpdated(v);
    }
    function setSubscriberProtectionWindow(uint256 v) external onlyOwner {
        _subscriberProtectionWindow = v;
        emit SubscriberProtectionWindowUpdated(v);
    }
    function setSunsetWindowDuration(uint256 v) external onlyOwner {
        _sunsetWindowDuration = v;
        emit SunsetWindowDurationUpdated(v);
    }
    function setStorageCompensationLookback(uint256 v) external onlyOwner {
        _storageCompensationLookback = v;
        emit StorageCompensationLookbackUpdated(v);
    }
    function setInstanceSizeBrackets(uint256 microMax, uint256 smallMax, uint256 mediumMax) external onlyOwner {
        require(microMax < smallMax && smallMax < mediumMax, "Invalid bracket ordering");
        _microMax = microMax;
        _smallMax = smallMax;
        _mediumMax = mediumMax;
        emit InstanceSizeBracketsUpdated(microMax, smallMax, mediumMax);
    }
    function setTierThresholds(uint256 tier1, uint256 tier2, uint256 tier3) external onlyOwner {
        require(tier1 < tier2 && tier2 < tier3, "Invalid threshold ordering");
        _tier1Threshold = tier1;
        _tier2Threshold = tier2;
        _tier3Threshold = tier3;
        emit TierThresholdsUpdated(tier1, tier2, tier3);
    }
    function setTierLookbackWindow(uint256 v) external onlyOwner {
        _tierLookbackWindow = v;
        emit TierLookbackWindowUpdated(v);
    }
    function setPostSizeLimits(uint256 t0, uint256 t1, uint256 t2, uint256 t3) external onlyOwner {
        _postSizeLimits[0] = t0;
        _postSizeLimits[1] = t1;
        _postSizeLimits[2] = t2;
        _postSizeLimits[3] = t3;
        emit PostSizeLimitsUpdated(t0, t1, t2, t3);
    }
    function setPostRateLimits(uint256 t0, uint256 t1, uint256 t2, uint256 t3) external onlyOwner {
        _postRateLimits[0] = t0;
        _postRateLimits[1] = t1;
        _postRateLimits[2] = t2;
        _postRateLimits[3] = t3;
        emit PostRateLimitsUpdated(t0, t1, t2, t3);
    }
    function setCreatorResponseWindow(uint256 v) external onlyOwner {
        _creatorResponseWindow = v;
        emit CreatorResponseWindowUpdated(v);
    }
    function setCsamSuspensionDuration(uint256 v) external onlyOwner {
        _csamSuspensionDuration = v;
        emit CsamSuspensionDurationUpdated(v);
    }
    function setFeeBps(uint256 v) external onlyOwner {
        require(v <= 10000, "Fee exceeds 100%");
        _feeBps = v;
        emit FeeBpsUpdated(v);
    }
    function setInactivityGracePeriod(uint256 v) external onlyOwner {
        _inactivityGracePeriod = v;
        emit InactivityGracePeriodUpdated(v);
    }
    function setBatchSettlementInterval(uint256 v) external onlyOwner {
        _batchSettlementInterval = v;
        emit BatchSettlementIntervalUpdated(v);
    }
    function setSubscriptionExpiryGracePeriod(uint256 v) external onlyOwner {
        require(v <= 24 hours, "Grace period exceeds 24h max (spec 13.4)");
        _subscriptionExpiryGracePeriod = v;
        emit SubscriptionExpiryGracePeriodUpdated(v);
    }
    function setResolverCacheTtl(uint256 v) external onlyOwner {
        _resolverCacheTtl = v;
        emit ResolverCacheTtlUpdated(v);
    }
}
