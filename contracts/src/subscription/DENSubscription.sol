// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "../interfaces/IDENIdentity.sol";
import "../interfaces/IDENParticipantIdentity.sol";
import "../interfaces/IDENSubscription.sol";
import "../interfaces/IDENContentRegistry.sol";
import "../interfaces/IDENHostCompensation.sol";
import "../interfaces/IERC20.sol";

contract DENSubscription is IDENSubscription {

    // Protocol fee basis points (2.5%). Governance parameter for V1 — hardcoded.
    // Must match FEE_BPS in DENHostCompensation and DENPurchaseState.
    uint256 public constant FEE_BPS = 250;

    IDENIdentity private _identity;
    address private _contentRegistry;
    address private _compensation;

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

    // subscriberProxy => creatorProxy => tierId => start of the current subscription period.
    // Set when first subscribing or after a lapse. NOT updated on renewals (while still active).
    // Enables report filing to verify subscription was active at the claimed access time (spec §12.2).
    // Spec gap: only the current period is tracked; prior lapsed periods are lost on re-subscribe.
    mapping(address => mapping(address => mapping(uint256 => uint256))) private _subscriptionStart;

    // creatorProxy => token => claimable escrow balance
    mapping(address => mapping(address => uint256)) private _escrow;

    // creatorProxy => tierId => highest subscription expiry ever recorded (high-water mark).
    // Never decremented. Used by DENContentRegistry to compute deletableAfter (spec §7.5 Step 3).
    mapping(address => mapping(uint256 => uint256)) private _maxSubscriptionExpiry;

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

    // Wire up the host compensation contract after deployment. Callable once.
    // If not set, the full payment goes to creator escrow with no protocol fee deducted.
    function setCompensation(address compensation) external {
        require(_compensation == address(0), "Already set");
        require(compensation != address(0), "Zero address");
        _compensation = compensation;
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
            if (_compensation != address(0)) {
                uint256 fee = (tier.price * FEE_BPS) / 10000;
                _escrow[creatorProxy][address(0)] += tier.price - fee;
                IDENHostCompensation(_compensation).depositFee{value: fee}(creatorProxy, address(0), fee);
            } else {
                _escrow[creatorProxy][address(0)] += msg.value;
            }
        } else {
            require(msg.value == 0, "Do not send ETH for token payment");
            bool ok = IERC20(tier.token).transferFrom(msg.sender, address(this), tier.price);
            require(ok, "Token transfer failed");
            if (_compensation != address(0)) {
                uint256 fee = (tier.price * FEE_BPS) / 10000;
                _escrow[creatorProxy][tier.token] += tier.price - fee;
                bool feeOk = IERC20(tier.token).transfer(_compensation, fee);
                require(feeOk, "Fee transfer failed");
                IDENHostCompensation(_compensation).depositFee(creatorProxy, tier.token, fee);
            } else {
                _escrow[creatorProxy][tier.token] += tier.price;
            }
        }

        uint256 start = block.timestamp;
        uint256 currentExpiry = _subscriptions[subscriberProxy][creatorProxy][tierId];
        if (currentExpiry > block.timestamp) {
            // Active renewal: extend from current expiry. Preserve _subscriptionStart.
            start = currentExpiry;
        } else {
            // New subscription or re-subscribe after lapse: record current period start.
            _subscriptionStart[subscriberProxy][creatorProxy][tierId] = block.timestamp;
        }

        uint256 expiry = start + tier.duration;
        _subscriptions[subscriberProxy][creatorProxy][tierId] = expiry;

        if (expiry > _maxSubscriptionExpiry[creatorProxy][tierId]) {
            _maxSubscriptionExpiry[creatorProxy][tierId] = expiry;
        }

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

    function getSubscriptionStart(
        address subscriberProxy,
        address creatorProxy,
        uint256 tierId
    ) external view returns (uint256) {
        return _subscriptionStart[subscriberProxy][creatorProxy][tierId];
    }

    function getTierDuration(address creatorProxy, uint256 tierId) external view returns (uint256) {
        return _tiers[creatorProxy][tierId].duration;
    }

    function getTierToken(address creatorProxy, uint256 tierId) external view returns (address) {
        return _tiers[creatorProxy][tierId].token;
    }

    function getMaxSubscriptionExpiry(address creatorProxy, uint256 tierId) external view returns (uint256) {
        return _maxSubscriptionExpiry[creatorProxy][tierId];
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
