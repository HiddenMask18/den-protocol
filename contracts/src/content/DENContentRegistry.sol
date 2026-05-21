// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "../interfaces/IDENIdentity.sol";
import "../interfaces/IDENParticipantIdentity.sol";
import "../interfaces/IDENContentRegistry.sol";
import "../interfaces/IDENSubscription.sol";

contract DENContentRegistry is IDENContentRegistry {

    // Fallback protection window when tier duration is unavailable (governance parameter for V1).
    // Must become a governance parameter in a future upgrade.
    uint256 public constant SUBSCRIBER_PROTECTION_WINDOW = 30 days;

    IDENIdentity private _identity;
    IDENSubscription private _subscription;

    // fingerprint => ContentRecord
    mapping(bytes32 => ContentRecord) private _content;

    // creatorProxy => list of fingerprints (for enumeration)
    mapping(address => bytes32[]) private _creatorContent;

    // creatorProxy => approved operator proxy (the instance they're registered with)
    mapping(address => address) private _creatorOperator;

    // creatorProxy => true while any content is in SunsetNoticed state (used by subscription gate)
    mapping(address => bool) private _creatorSunsetActive;

    // creatorProxy => count of fingerprints currently in SunsetNoticed state.
    // Cleared to false when count drops to zero (creator completes migration and deletes all sunsetted content).
    mapping(address => uint256) private _activeSunsetCount;

    event ContentRegistered(address indexed creatorProxy, bytes32 indexed fingerprint, uint256 tierId);
    event ContentArchived(address indexed creatorProxy, bytes32 indexed fingerprint);
    event SunsetNoticeIssued(address indexed creatorProxy, bytes32 indexed fingerprint, uint256 deletableAfter);
    event ContentDeleted(address indexed creatorProxy, bytes32 indexed fingerprint);
    event ContentOperatorSet(address indexed creatorProxy, address indexed operatorProxy);

    constructor(address identityContractAddress, address subscriptionContractAddress) {
        _identity = IDENIdentity(identityContractAddress);
        _subscription = IDENSubscription(subscriptionContractAddress);
    }

    // Register a new content fingerprint under the caller's proxy, assigned to a tier.
    // Fingerprints are globally unique — re-registering an existing fingerprint reverts.
    function registerContent(bytes32 fingerprint, uint256 tierId) external {
        require(fingerprint != bytes32(0), "Zero fingerprint");
        require(_content[fingerprint].creatorProxy == address(0), "Fingerprint already registered");

        address proxy = _identity.getProxy(msg.sender);
        require(proxy != address(0), "Not registered");
        require(IDENParticipantIdentity(proxy).primaryWallet() == msg.sender, "Not primary wallet");

        _content[fingerprint] = ContentRecord({
            creatorProxy: proxy,
            tierId: tierId,
            lifecycle: Lifecycle.Active,
            registeredAt: block.timestamp,
            sunsetNoticedAt: 0,
            deletableAfter: 0
        });
        _creatorContent[proxy].push(fingerprint);

        emit ContentRegistered(proxy, fingerprint, tierId);
    }

    // Creator voluntarily marks content as archived. Still accessible to subscribers.
    // Only valid from Active state.
    function archiveContent(bytes32 fingerprint) external {
        ContentRecord storage record = _content[fingerprint];
        require(record.creatorProxy != address(0), "Content not found");
        require(record.lifecycle == Lifecycle.Active, "Content not active");
        _requirePrimaryWallet(record.creatorProxy);

        record.lifecycle = Lifecycle.Archived;
        emit ContentArchived(record.creatorProxy, fingerprint);
    }

    // Issue an immutable sunset notice. Only the creator's registered instance operator may call this.
    // The creator must have called setContentOperator() to designate their instance (spec §7.5).
    // Valid from Active or Archived state. Once issued, cannot be retracted.
    // deletableAfter is computed from the tier's subscription duration to ensure all active
    // subscriptions at notice time can lapse naturally (spec §7.5).
    function issueSunsetNotice(bytes32 fingerprint) external {
        ContentRecord storage record = _content[fingerprint];
        require(record.creatorProxy != address(0), "Content not found");
        require(
            record.lifecycle == Lifecycle.Active || record.lifecycle == Lifecycle.Archived,
            "Cannot issue sunset notice in current state"
        );

        address callerProxy = _identity.getProxy(msg.sender);
        require(callerProxy != address(0), "Not registered");
        require(IDENParticipantIdentity(callerProxy).primaryWallet() == msg.sender, "Not primary wallet");
        require(callerProxy == _creatorOperator[record.creatorProxy], "Not authorized operator");

        record.lifecycle = Lifecycle.SunsetNoticed;
        record.sunsetNoticedAt = block.timestamp;

        uint256 tierDuration = _subscription.getTierDuration(record.creatorProxy, record.tierId);
        uint256 window = tierDuration > 0 ? tierDuration : SUBSCRIBER_PROTECTION_WINDOW;
        // Use the maximum subscription expiry ever recorded for this tier as the floor.
        // A subscriber who stacked multiple renewals before the notice may have an expiry
        // beyond block.timestamp + window. spec §7.5 Step 3: access persists until their
        // paid period lapses naturally — not just one tier duration from now.
        uint256 maxSubExpiry = _subscription.getMaxSubscriptionExpiry(record.creatorProxy, record.tierId);
        uint256 deletableAfter = maxSubExpiry > block.timestamp + window
            ? maxSubExpiry
            : block.timestamp + window;
        record.deletableAfter = deletableAfter;

        _activeSunsetCount[record.creatorProxy]++;
        _creatorSunsetActive[record.creatorProxy] = true;

        emit SunsetNoticeIssued(record.creatorProxy, fingerprint, deletableAfter);
    }

    // Delete content. Only valid after SunsetNoticed AND the subscriber protection window has elapsed.
    // Callable by the creator's primary wallet OR the registered content operator — both are parties
    // to the removal process. After migration the creator may be gone; the operator must be able
    // to complete the process they initiated (spec §7.5 Step 4).
    // The record is kept with Deleted lifecycle to preserve the fingerprint audit trail.
    function deleteContent(bytes32 fingerprint) external {
        ContentRecord storage record = _content[fingerprint];
        require(record.creatorProxy != address(0), "Content not found");
        require(record.lifecycle == Lifecycle.SunsetNoticed, "Content not in sunset state");
        require(block.timestamp >= record.deletableAfter, "Subscriber protection window not elapsed");

        address callerProxy = _identity.getProxy(msg.sender);
        require(callerProxy != address(0), "Not registered");
        bool isCreator = IDENParticipantIdentity(record.creatorProxy).primaryWallet() == msg.sender;
        bool isOperator = callerProxy == _creatorOperator[record.creatorProxy];
        require(isCreator || isOperator, "Not authorized");

        record.lifecycle = Lifecycle.Deleted;

        _activeSunsetCount[record.creatorProxy]--;
        if (_activeSunsetCount[record.creatorProxy] == 0) {
            _creatorSunsetActive[record.creatorProxy] = false;
        }

        emit ContentDeleted(record.creatorProxy, fingerprint);
    }

    // Creator registers the instance they're hosted on as the authorized operator for sunset notices.
    // The operatorProxy must be a registered DEN participant (the instance's identity contract).
    function setContentOperator(address operatorProxy) external {
        address proxy = _identity.getProxy(msg.sender);
        require(proxy != address(0), "Not registered");
        require(IDENParticipantIdentity(proxy).primaryWallet() == msg.sender, "Not primary wallet");
        _creatorOperator[proxy] = operatorProxy;
        emit ContentOperatorSet(proxy, operatorProxy);
    }

    function getContent(bytes32 fingerprint) external view returns (ContentRecord memory) {
        return _content[fingerprint];
    }

    // Returns true for Active and Archived — both remain subscriber-accessible (spec §4.5).
    function isContentActive(bytes32 fingerprint) external view returns (bool) {
        Lifecycle lc = _content[fingerprint].lifecycle;
        return lc == Lifecycle.Active || lc == Lifecycle.Archived;
    }

    // Returns true if any of this creator's content is in SunsetNoticed state.
    function hasActiveSunset(address creatorProxy) external view returns (bool) {
        return _creatorSunsetActive[creatorProxy];
    }

    // Returns all fingerprints registered by a creator proxy (including non-active).
    function getCreatorContent(address creatorProxy) external view returns (bytes32[] memory) {
        return _creatorContent[creatorProxy];
    }

    function getContentOperator(address creatorProxy) external view returns (address) {
        return _creatorOperator[creatorProxy];
    }

    function _requirePrimaryWallet(address proxy) internal view {
        require(IDENParticipantIdentity(proxy).primaryWallet() == msg.sender, "Not primary wallet");
    }
}
