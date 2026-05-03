// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "../interfaces/IDENIdentity.sol";
import "../interfaces/IDENParticipantIdentity.sol";
import "../interfaces/IDENPurchaseState.sol";
import "../interfaces/IDENContentRegistry.sol";

contract DENPurchaseState is IDENPurchaseState {

    IDENIdentity private _identity;
    address private _contentRegistry;

    struct Listing {
        uint256 price;
        bool exists;
    }

    // creatorProxy => listingId => Listing
    mapping(address => mapping(uint256 => Listing)) private _listings;

    // buyerProxy => creatorProxy => listingId => purchasedAt timestamp (0 = not purchased)
    mapping(address => mapping(address => mapping(uint256 => uint256))) private _purchases;

    // creatorProxy => claimable escrow balance
    mapping(address => uint256) private _escrow;

    event ListingSet(address indexed creatorProxy, uint256 indexed listingId, uint256 price);
    event Purchased(address indexed buyerProxy, address indexed creatorProxy, uint256 indexed listingId, uint256 purchasedAt);
    event Withdrawn(address indexed creatorProxy, uint256 amount);

    constructor(address identityContractAddress) {
        _identity = IDENIdentity(identityContractAddress);
    }

    function setContentRegistry(address contentRegistry) external {
        require(_contentRegistry == address(0), "Already set");
        require(contentRegistry != address(0), "Zero address");
        _contentRegistry = contentRegistry;
    }

    function setListing(uint256 listingId, uint256 price) external {
        address proxy = _identity.getProxy(msg.sender);
        require(proxy != address(0), "Not registered");
        require(IDENParticipantIdentity(proxy).primaryWallet() == msg.sender, "Not primary wallet");
        require(price > 0, "Price must be nonzero");
        _listings[proxy][listingId] = Listing(price, true);
        emit ListingSet(proxy, listingId, price);
    }

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
        require(msg.value == listing.price, "Incorrect payment amount");
        require(_purchases[buyerProxy][creatorProxy][listingId] == 0, "Already purchased");

        _purchases[buyerProxy][creatorProxy][listingId] = block.timestamp;
        _escrow[creatorProxy] += msg.value;

        emit Purchased(buyerProxy, creatorProxy, listingId, block.timestamp);
    }

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
    ) external view returns (uint256 price, bool exists) {
        Listing memory l = _listings[creatorProxy][listingId];
        return (l.price, l.exists);
    }

    function getEscrowBalance(address creatorProxy) external view returns (uint256) {
        return _escrow[creatorProxy];
    }
}
