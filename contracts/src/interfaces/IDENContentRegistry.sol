// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

interface IDENContentRegistry {

    enum Lifecycle { Active, Archived, SunsetNoticed, Deleted }

    struct ContentRecord {
        address creatorProxy;
        uint256 tierId;
        Lifecycle lifecycle;
        uint256 registeredAt;
        uint256 sunsetNoticedAt; // 0 unless SunsetNoticed or Deleted
        uint256 deletableAfter;  // 0 until sunset notice; computed from tier duration at notice time
    }

    function registerContent(bytes32 fingerprint, uint256 tierId) external;
    function archiveContent(bytes32 fingerprint) external;

    // Only the creator's registered instance operator may issue a sunset notice (spec §7.5).
    // Creator must call setContentOperator() first to register the instance they're hosted on.
    function issueSunsetNotice(bytes32 fingerprint) external;
    function deleteContent(bytes32 fingerprint) external;

    function getContent(bytes32 fingerprint) external view returns (ContentRecord memory);

    // Returns true for Active and Archived lifecycle — both remain subscriber-accessible (spec §4.5).
    function isContentActive(bytes32 fingerprint) external view returns (bool);

    // Returns true if any of this creator's content is in SunsetNoticed state.
    // Used by DENSubscription to block new subscriptions after sunset (spec §5.6).
    function hasActiveSunset(address creatorProxy) external view returns (bool);

    // Creator registers their instance operator (the hoster whose platform they're on).
    // Only the registered operator can subsequently issue sunset notices for this creator's content.
    function setContentOperator(address operatorProxy) external;

    function getCreatorContent(address creatorProxy) external view returns (bytes32[] memory);
    function getContentOperator(address creatorProxy) external view returns (address);
}
