// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

interface IDENSubscription {
    // token = address(0) for native ETH; any ERC-20 contract address otherwise.
    function setTier(uint256 tierId, uint256 price, uint256 duration, address token) external;
    // For ETH tiers: call with msg.value == tier.price.
    // For ERC-20 tiers: approve this contract for tier.price first, then call with msg.value == 0.
    function subscribe(address creatorProxy, uint256 tierId) external payable;
    function isSubscribed(address subscriberProxy, address creatorProxy, uint256 tierId) external view returns (bool);
    function getSubscriptionExpiry(address subscriberProxy, address creatorProxy, uint256 tierId) external view returns (uint256);
    function getTierDuration(address creatorProxy, uint256 tierId) external view returns (uint256);
    function getTierToken(address creatorProxy, uint256 tierId) external view returns (address);
    // Returns the highest subscription expiry ever recorded for this creator+tier across all subscribers.
    // Used by DENContentRegistry.issueSunsetNotice to set deletableAfter correctly (spec §7.5 Step 3).
    function getMaxSubscriptionExpiry(address creatorProxy, uint256 tierId) external view returns (uint256);
    // token = address(0) to withdraw ETH escrow; ERC-20 address to withdraw token escrow.
    function withdraw(address token) external;
    function getEscrowBalance(address creatorProxy, address token) external view returns (uint256);

    // Wire up the content registry post-deployment to enable sunset-notice subscription gate.
    // Callable once; address(0) is rejected.
    function setContentRegistry(address contentRegistry) external;

    // Wire up the host compensation contract post-deployment to enable protocol fee collection.
    // Callable once; address(0) is rejected. If not set, full payment goes to creator escrow.
    function setCompensation(address compensation) external;
}
