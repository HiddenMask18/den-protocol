// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "../interfaces/IDENIdentity.sol";
import "../interfaces/IDENParticipantIdentity.sol";
import "../interfaces/IDENPurchaseState.sol";
import "../interfaces/IDENContentRegistry.sol";
import "../interfaces/IDENHostCompensation.sol";
import "../interfaces/IDENTrustTier.sol";
import "../interfaces/IDENGovernanceParams.sol";
import "../interfaces/IERC20.sol";

contract DENPurchaseState is IDENPurchaseState {

    // V1 default — used when governance params not yet wired.
    uint256 private constant _DEFAULT_FEE_BPS = 250;

    // Governance parameter store (spec §10). Set once after deploy.
    address private _govParams;

    IDENIdentity private _identity;
    address private _contentRegistry;
    address private _compensation;
    address private _trustTier;

    struct Listing {
        uint256 price;
        address token;  // address(0) = native ETH; any other address = ERC-20
        bool exists;
    }

    // creatorProxy => listingId => Listing
    mapping(address => mapping(uint256 => Listing)) private _listings;

    // buyerProxy => creatorProxy => listingId => purchasedAt timestamp (0 = not purchased)
    mapping(address => mapping(address => mapping(uint256 => uint256))) private _purchases;

    // creatorProxy => token => claimable escrow balance
    mapping(address => mapping(address => uint256)) private _escrow;

    event ListingSet(address indexed creatorProxy, uint256 indexed listingId, uint256 price, address indexed token);
    event Purchased(address indexed buyerProxy, address indexed creatorProxy, uint256 indexed listingId, uint256 purchasedAt);
    event Withdrawn(address indexed creatorProxy, address indexed token, uint256 amount);

    constructor(address identityContractAddress) {
        _identity = IDENIdentity(identityContractAddress);
    }

    // Wire the governance parameter store. Callable once.
    function setGovernanceParams(address govParams_) external {
        require(_govParams == address(0), "Already set");
        require(govParams_ != address(0), "Zero address");
        _govParams = govParams_;
    }

    // Exposed with original constant name for backward compatibility.
    function FEE_BPS() public view returns (uint256) {
        return _govParams != address(0)
            ? IDENGovernanceParams(_govParams).getFeeBps()
            : _DEFAULT_FEE_BPS;
    }

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

    // Wire up the trust tier contract after deployment. Callable once.
    // If not set, purchases do not update tier graduation state (spec §9.2).
    function setTrustTier(address trustTier) external {
        require(_trustTier == address(0), "Already set");
        require(trustTier != address(0), "Zero address");
        _trustTier = trustTier;
    }

    // token = address(0) for native ETH; any ERC-20 contract address otherwise.
    function setListing(uint256 listingId, uint256 price, address token) external {
        address proxy = _identity.getProxy(msg.sender);
        require(proxy != address(0), "Not registered");
        require(IDENParticipantIdentity(proxy).primaryWallet() == msg.sender, "Not primary wallet");
        require(price > 0, "Price must be nonzero");
        _listings[proxy][listingId] = Listing(price, token, true);
        emit ListingSet(proxy, listingId, price, token);
    }

    // For ETH listings: send msg.value == listing.price.
    // For ERC-20 listings: approve this contract first, then call with msg.value == 0.
    function purchase(address creatorProxy, uint256 listingId) external payable {
        address buyerProxy = _identity.getProxy(msg.sender);
        require(buyerProxy != address(0), "Buyer not registered");
        require(_identity.isRegisteredProxy(creatorProxy), "Creator proxy not registered");

        // Spec §5.6 restricts new subscriptions during sunset — purchases are not restricted.
        Listing memory listing = _listings[creatorProxy][listingId];
        require(listing.exists, "Listing does not exist");
        require(_purchases[buyerProxy][creatorProxy][listingId] == 0, "Already purchased");

        uint256 feeBps = FEE_BPS();
        if (listing.token == address(0)) {
            require(msg.value == listing.price, "Incorrect payment amount");
            if (_compensation != address(0)) {
                uint256 fee = (listing.price * feeBps) / 10000;
                _escrow[creatorProxy][address(0)] += listing.price - fee;
                IDENHostCompensation(_compensation).depositFee{value: fee}(creatorProxy, address(0), fee);
            } else {
                _escrow[creatorProxy][address(0)] += msg.value;
            }
        } else {
            require(msg.value == 0, "Do not send ETH for token payment");
            bool ok = IERC20(listing.token).transferFrom(msg.sender, address(this), listing.price);
            require(ok, "Token transfer failed");
            if (_compensation != address(0)) {
                uint256 fee = (listing.price * feeBps) / 10000;
                _escrow[creatorProxy][listing.token] += listing.price - fee;
                bool feeOk = IERC20(listing.token).transfer(_compensation, fee);
                require(feeOk, "Fee transfer failed");
                IDENHostCompensation(_compensation).depositFee(creatorProxy, listing.token, fee);
            } else {
                _escrow[creatorProxy][listing.token] += listing.price;
            }
        }

        _purchases[buyerProxy][creatorProxy][listingId] = block.timestamp;

        // Record qualifying transaction for creator trust tier graduation (spec §9.2).
        // Self-exclusion is applied inside the tier contract.
        if (_trustTier != address(0)) {
            IDENTrustTier(_trustTier).recordTransaction(creatorProxy, buyerProxy);
        }

        emit Purchased(buyerProxy, creatorProxy, listingId, block.timestamp);
    }

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

    function hasPurchased(
        address buyerProxy,
        address creatorProxy,
        uint256 listingId
    ) external view returns (bool) {
        return _purchases[buyerProxy][creatorProxy][listingId] != 0;
    }

    function getPurchaseTimestamp(
        address buyerProxy,
        address creatorProxy,
        uint256 listingId
    ) external view returns (uint256) {
        return _purchases[buyerProxy][creatorProxy][listingId];
    }

    function getListing(
        address creatorProxy,
        uint256 listingId
    ) external view returns (uint256 price, address token, bool exists) {
        Listing memory l = _listings[creatorProxy][listingId];
        return (l.price, l.token, l.exists);
    }

    function getEscrowBalance(address creatorProxy, address token) external view returns (uint256) {
        return _escrow[creatorProxy][token];
    }
}
