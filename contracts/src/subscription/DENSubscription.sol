// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "../interfaces/IDENIdentity.sol";
import "../interfaces/IDENParticipantIdentity.sol";
import "../interfaces/IDENSubscription.sol";
import "../interfaces/IDENContentRegistry.sol";
import "../interfaces/IERC20.sol";

contract DENSubscription is IDENSubscription {

    IDENIdentity private _identity;
    address private _contentRegistry;

    struct Tier {
        uint256 price;      // token units (wei for ETH, smallest denomination for ERC-20)
        uint256 duration;   // in seconds
        address token;      // address(0) = native ETH; any other address = ERC-20
        bool exists;
    }

    // creatorProxy => tierId => Tier
    mapping(address => mapping(uint256 => Tier)) private _tiers;

    // subscriberProxy => creatorProxy => tierId => expiry timestamp
    mapping(address => mapping(address => mapping(uint256 => uint256))) private _subscriptions;

    // creatorProxy => token => claimable escrow balance
    mapping(address => mapping(address => uint256)) private _escrow;

    event TierSet(address indexed creatorProxy, uint256 indexed tierId, uint256 price, uint256 duration, address indexed token);
    event Subscribed(address indexed subscriberProxy, address indexed creatorProxy, uint256 indexed tierId, uint256 expiry);
    event Withdrawn(address indexed creatorProxy, address indexed token, uint256 amount);

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
    // token = address(0) for native ETH; any ERC-20 contract address otherwise.
    function setTier(uint256 tierId, uint256 price, uint256 duration, address token) external {
        address proxy = _identity.getProxy(msg.sender);
        require(proxy != address(0), "Not registered");
        require(IDENParticipantIdentity(proxy).primaryWallet() == msg.sender, "Not primary wallet");
        require(price > 0, "Price must be nonzero");
        require(duration > 0, "Duration must be nonzero");
        _tiers[proxy][tierId] = Tier(price, duration, token, true);
        emit TierSet(proxy, tierId, price, duration, token);
    }

    // Subscriber calls from their wallet. creatorProxy must be a valid registered proxy address.
    // Reverts if the creator has an active sunset notice (spec §5.6: no new subscriptions after sunset).
    // For ETH tiers: send msg.value == tier.price.
    // For ERC-20 tiers: approve this contract first, then call with msg.value == 0.
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

        if (tier.token == address(0)) {
            require(msg.value == tier.price, "Incorrect payment amount");
            _escrow[creatorProxy][address(0)] += msg.value;
        } else {
            require(msg.value == 0, "Do not send ETH for token payment");
            bool ok = IERC20(tier.token).transferFrom(msg.sender, address(this), tier.price);
            require(ok, "Token transfer failed");
            _escrow[creatorProxy][tier.token] += tier.price;
        }

        uint256 start = block.timestamp;
        uint256 currentExpiry = _subscriptions[subscriberProxy][creatorProxy][tierId];
        if (currentExpiry > block.timestamp) {
            start = currentExpiry;
        }

        uint256 expiry = start + tier.duration;
        _subscriptions[subscriberProxy][creatorProxy][tierId] = expiry;

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

    function getTierToken(address creatorProxy, uint256 tierId) external view returns (address) {
        return _tiers[creatorProxy][tierId].token;
    }

    // Creator calls from their current wallet. Proxy is resolved internally, so this works
    // transparently after wallet rotation — escrow key is unchanged.
    // token = address(0) to withdraw ETH escrow; ERC-20 address to withdraw token escrow.
    function withdraw(address token) external {
        address proxy = _identity.getProxy(msg.sender);
        require(proxy != address(0), "Not registered");
        uint256 amount = _escrow[proxy][token];
        require(amount > 0, "Nothing to withdraw");
        _escrow[proxy][token] = 0;
        if (token == address(0)) {
            (bool success, ) = msg.sender.call{value: amount}("");
            require(success, "Transfer failed");
        } else {
            bool ok = IERC20(token).transfer(msg.sender, amount);
            require(ok, "Token transfer failed");
        }
        emit Withdrawn(proxy, token, amount);
    }

    function getEscrowBalance(address creatorProxy, address token) external view returns (uint256) {
        return _escrow[creatorProxy][token];
    }
}
