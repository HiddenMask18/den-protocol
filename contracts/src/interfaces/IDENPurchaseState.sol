// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

interface IDENPurchaseState {
    function setContentRegistry(address contentRegistry) external;
    // token = address(0) for native ETH; any ERC-20 contract address otherwise.
    function setListing(uint256 listingId, uint256 price, address token) external;
    // For ETH listings: call with msg.value == listing.price.
    // For ERC-20 listings: approve this contract for listing.price first, then call with msg.value == 0.
    function purchase(address creatorProxy, uint256 listingId) external payable;
    // token = address(0) to withdraw ETH escrow; ERC-20 address to withdraw token escrow.
    function withdraw(address token) external;
    function hasPurchased(address buyerProxy, address creatorProxy, uint256 listingId) external view returns (bool);
    function getPurchaseTimestamp(address buyerProxy, address creatorProxy, uint256 listingId) external view returns (uint256);
    function getListing(address creatorProxy, uint256 listingId) external view returns (uint256 price, address token, bool exists);
    function getEscrowBalance(address creatorProxy, address token) external view returns (uint256);
}
