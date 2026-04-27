// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "../interfaces/IDENIdentity.sol";
import "../interfaces/IDENParticipantIdentity.sol";
import "../interfaces/IDENSubscription.sol";
import "../interfaces/IDENContentRegistry.sol";

contract DENSubscription is IDENSubscription {

    IDENIdentity private _identity;
    address private _contentRegistry;

    struct Tier {
        uint256 price;      // in wei
        uint256 duration;   // in seconds
        bool exists;
    }

    // creatorProxy => tierId => Tier
    mapping(address => mapping(uint256 => Tier)) private _tiers;

    // subscriberProxy => creatorProxy => tierId => expiry timestamp
    mapping(address => mapping(address => mapping(uint256 => uint256))) private _subscriptions;

    // creatorProxy => claimable escrow balance
    mapping(address => uint256) private _escrow;

    event TierSet(address indexed creatorProxy, uint256 indexed tierId, uint256 price, uint256 duration);
    event Subscribed(address indexed subscriberProxy, address indexed creatorProxy, uint256 indexed tierId, uint256 expiry);
    event Withdrawn(address indexed creatorProxy, uint256 amount);

    constructor(address identityContractAddress) {
        _identity = IDENIdentity(identityContractAddress);
    }

    // Wire up the content registry after deployment. Callable once.
    function setContentRegistry(address contentRegistry) external {
        require(_contentRegistry == address(0), "Already set");
        require(contentRegistry != address(0), "Zero address");
        _contentRegistry = contentRegistry;
    }

    // Creator calls from their wallet; proxy is resolved internally and used as the stable key.
    // Caller must be the current primary wallet of their proxy.
    function setTier(uint256 tierId, uint256 price, uint256 duration) external {
        address proxy = _identity.getProxy(msg.sender);
        require(proxy != address(0), "Not registered");
        require(IDENParticipantIdentity(proxy).primaryWallet() == msg.sender, "Not primary wallet");
        require(price > 0, "Price must be nonzero");
        require(duration > 0, "Duration must be nonzero");
        _tiers[proxy][tierId] = Tier(price, duration, true);
        emit TierSet(proxy, tierId, price, duration);
    }

    // Subscriber calls from their wallet. creatorProxy must be a valid registered proxy address
    // (obtained via IDENIdentity.getProxy or IDENIdentity.resolve off-chain before calling).
    // Reverts if the creator has an active sunset notice (spec §5.6: no new subscriptions after sunset).
    function subscribe(address creatorProxy, uint256 tierId) external payable {
        address subscriberProxy = _identity.getProxy(msg.sender);
        require(subscriberProxy != address(0), "Subscriber not registered");
        require(_identity.isRegisteredProxy(creatorProxy), "Creator proxy not registered");

        if (_contentRegistry != address(0)) {
            require(
                !IDENContentRegistry(_contentRegistry).hasActiveSunset(creatorProxy),
                "Creator has active sunset notice"
            );
        }

        Tier memory tier = _tiers[creatorProxy][tierId];
        require(tier.exists, "Tier does not exist");
        require(msg.value == tier.price, "Incorrect payment amount");

        uint256 start = block.timestamp;
        uint256 currentExpiry = _subscriptions[subscriberProxy][creatorProxy][tierId];
        if (currentExpiry > block.timestamp) {
            start = currentExpiry;
        }

        uint256 expiry = start + tier.duration;
        _subscriptions[subscriberProxy][creatorProxy][tierId] = expiry;
        _escrow[creatorProxy] += msg.value;

        emit Subscribed(subscriberProxy, creatorProxy, tierId, expiry);
    }

    function isSubscribed(
        address subscriberProxy,
        address creatorProxy,
        uint256 tierId
    ) external view returns (bool) {
        return _subscriptions[subscriberProxy][creatorProxy][tierId] > block.timestamp;
    }

    function getSubscriptionExpiry(
        address subscriberProxy,
        address creatorProxy,
        uint256 tierId
    ) external view returns (uint256) {
        return _subscriptions[subscriberProxy][creatorProxy][tierId];
    }

    function getTierDuration(address creatorProxy, uint256 tierId) external view returns (uint256) {
        return _tiers[creatorProxy][tierId].duration;
    }

    // Creator calls from their current wallet. Proxy is resolved internally, so this works
    // transparently after a wallet rotation + syncWallet() — escrow key is unchanged.
    function withdraw() external {
        address proxy = _identity.getProxy(msg.sender);
        require(proxy != address(0), "Not registered");
        uint256 amount = _escrow[proxy];
        require(amount > 0, "Nothing to withdraw");
        _escrow[proxy] = 0;
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "Transfer failed");
        emit Withdrawn(proxy, amount);
    }

    function getEscrowBalance(address creatorProxy) external view returns (uint256) {
        return _escrow[creatorProxy];
    }
}
