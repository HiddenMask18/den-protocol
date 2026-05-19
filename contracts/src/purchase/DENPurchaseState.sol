// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "../interfaces/IDENIdentity.sol";
import "../interfaces/IDENParticipantIdentity.sol";
import "../interfaces/IDENPurchaseState.sol";
import "../interfaces/IDENContentRegistry.sol";
import "../interfaces/IERC20.sol";

contract DENPurchaseState is IDENPurchaseState {

    IDENIdentity private _identity;
    address private _contentRegistry;

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

    function setContentRegistry(address contentRegistry) external {
        require(_contentRegistry == address(0), "Already set");
        require(contentRegistry != address(0), "Zero address");
        _contentRegistry = contentRegistry;
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

        if (_contentRegistry != address(0)) {
            require(
                !IDENContentRegistry(_contentRegistry).hasActiveSunset(creatorProxy),
                "Creator has active sunset notice"
            );
        }

        Listing memory listing = _listings[creatorProxy][listingId];
        require(listing.exists, "Listing does not exist");
        require(_purchases[buyerProxy][creatorProxy][listingId] == 0, "Already purchased");

        if (listing.token == address(0)) {
            require(msg.value == listing.price, "Incorrect payment amount");
            _escrow[creatorProxy][address(0)] += msg.value;
        } else {
            require(msg.value == 0, "Do not send ETH for token payment");
            bool ok = IERC20(listing.token).transferFrom(msg.sender, address(this), listing.price);
            require(ok, "Token transfer failed");
            _escrow[creatorProxy][listing.token] += listing.price;
        }

        _purchases[buyerProxy][creatorProxy][listingId] = block.timestamp;

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
