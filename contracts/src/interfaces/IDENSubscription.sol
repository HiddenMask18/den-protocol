// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

interface IDENSubscription {
    function subscribe(address creatorWallet, uint256 tierId) external payable;
    function isSubscribed(address subscriberWallet, address creatorWallet, uint256 tierId) external view returns (bool);
    function getSubscriptionExpiry(address subscriberWallet, address creatorWallet, uint256 tierId) external view returns (uint256);
}