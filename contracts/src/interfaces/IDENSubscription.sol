// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

interface IDENSubscription {
    function subscribe(address creatorProxy, uint256 tierId) external payable;
    function isSubscribed(address subscriberProxy, address creatorProxy, uint256 tierId) external view returns (bool);
    function getSubscriptionExpiry(address subscriberProxy, address creatorProxy, uint256 tierId) external view returns (uint256);
    function getTierDuration(address creatorProxy, uint256 tierId) external view returns (uint256);

    // Wire up the content registry post-deployment to enable sunset-notice subscription gate.
    // Callable once; pass address(0) is rejected.
    function setContentRegistry(address contentRegistry) external;
}
