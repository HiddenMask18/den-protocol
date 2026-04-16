// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "../interfaces/IDENIdentity.sol";
import "../interfaces/IDENSubscription.sol";

contract DENSubscription is IDENSubscription {

    IDENIdentity private _identity;

    struct Tier {
        uint256 price;      // in wei
        uint256 duration;   // in seconds
        bool exists;
    }

    // creator address => tierId => Tier
    mapping(address => mapping(uint256 => Tier)) private _tiers;

    // subscriber => creator => tierId => expiry timestamp
    mapping(address => mapping(address => mapping(uint256 => uint256))) private _subscriptions;

    // creator => claimable escrow balance
    mapping(address => uint256) private _escrow;

    event TierSet(address indexed creator, uint256 indexed tierId, uint256 price, uint256 duration);
    event Subscribed(address indexed subscriber, address indexed creator, uint256 indexed tierId, uint256 expiry);
    event Withdrawn(address indexed creator, uint256 amount);

    constructor(address identityContractAddress) {
        _identity = IDENIdentity(identityContractAddress);
    }

    function setTier(uint256 tierId, uint256 price, uint256 duration) external {
        require(_identity.isRegistered(msg.sender), "Not registered");
        require(price > 0, "Price must be nonzero");
        require(duration > 0, "Duration must be nonzero");
        _tiers[msg.sender][tierId] = Tier(price, duration, true);
        emit TierSet(msg.sender, tierId, price, duration);
    }

    function subscribe(address creatorWallet, uint256 tierId) external payable {
        require(_identity.isRegistered(msg.sender), "Subscriber not registered");
        require(_identity.isRegistered(creatorWallet), "Creator not registered");

        Tier memory tier = _tiers[creatorWallet][tierId];
        require(tier.exists, "Tier does not exist");
        require(msg.value == tier.price, "Incorrect payment amount");

        // if already subscribed and not expired, extend from current expiry
        uint256 start = block.timestamp;
        uint256 currentExpiry = _subscriptions[msg.sender][creatorWallet][tierId];
        if (currentExpiry > block.timestamp) {
            start = currentExpiry;
        }

        uint256 expiry = start + tier.duration;
        _subscriptions[msg.sender][creatorWallet][tierId] = expiry;
        _escrow[creatorWallet] += msg.value;

        emit Subscribed(msg.sender, creatorWallet, tierId, expiry);
    }

    function isSubscribed(
        address subscriberWallet,
        address creatorWallet,
        uint256 tierId
    ) external view returns (bool) {
        return _subscriptions[subscriberWallet][creatorWallet][tierId] > block.timestamp;
    }

    function getSubscriptionExpiry(
        address subscriberWallet,
        address creatorWallet,
        uint256 tierId
    ) external view returns (uint256) {
        return _subscriptions[subscriberWallet][creatorWallet][tierId];
    }

    function withdraw() external {
        uint256 amount = _escrow[msg.sender];
        require(amount > 0, "Nothing to withdraw");
        _escrow[msg.sender] = 0;
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "Transfer failed");
        emit Withdrawn(msg.sender, amount);
    }

    function getEscrowBalance(address creator) external view returns (uint256) {
        return _escrow[creator];
    }
}