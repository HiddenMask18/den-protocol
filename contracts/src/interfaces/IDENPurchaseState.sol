// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

interface IDENPurchaseState {
    function setContentRegistry(address contentRegistry) external;
    function setListing(uint256 listingId, uint256 price) external;
    function purchase(address creatorProxy, uint256 listingId) external payable;
    function withdraw() external;
    function hasPurchased(address buyerProxy, address creatorProxy, uint256 listingId) external view returns (bool);
    function getPurchaseTimestamp(address buyerProxy, address creatorProxy, uint256 listingId) external view returns (uint256);
    function getListing(address creatorProxy, uint256 listingId) external view returns (uint256 price, bool exists);
    function getEscrowBalance(address creatorProxy) external view returns (uint256);
}
