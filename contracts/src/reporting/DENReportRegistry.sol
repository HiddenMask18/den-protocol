// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "../interfaces/IDENIdentity.sol";
import "../interfaces/IDENParticipantIdentity.sol";
import "../interfaces/IDENSubscription.sol";
import "../interfaces/IDENPurchaseState.sol";
import "../interfaces/IDENContentRegistry.sol";
import "../interfaces/IDENReportRegistry.sol";
import "../interfaces/IDENGovernanceParams.sol";

contract DENReportRegistry is IDENReportRegistry {

    // V1 defaults — used when governance params not yet wired.
    uint256 private constant _DEFAULT_CREATOR_RESPONSE_WINDOW  = 7 days;
    uint256 private constant _DEFAULT_CSAM_SUSPENSION_DURATION = 30 days;

    // Governance parameter store (spec §10). Set once after deploy.
    address private _govParams;

    address private _owner;
    IDENIdentity private _identity;
    IDENSubscription private _subscription;
    IDENPurchaseState private _purchaseState;
    IDENContentRegistry private _contentRegistry;

    // Option B governance placeholder (spec §12.2).
    // Initially address(0) — operator-conflicted reports cannot be determined until set.
    // Wire via setGovernance() when the governance contract is deployed.
    // V1 limitation: conflicted reports remain Active until this is set.
    // Audit note: any address set here can determine conflicted reports — set only to the
    // deployed governance contract. One-time setter; cannot be changed once set.
    address private _governance;

    Report[] private _reports;

    // fingerprint => list of report IDs (all-time, for audit trail)
    mapping(bytes32 => uint256[]) private _reportsByFingerprint;

    // fingerprint => count of currently Active reports
    // Temporary suspension lasts while this count is above zero.
    mapping(bytes32 => uint256) private _activeReportCount;

    // fingerprint => true once any report against this fingerprint is Upheld.
    // Permanent suspension; never cleared. Content proceeds to §7.5 sunset and deletion.
    mapping(bytes32 => bool) private _permanentlySuspended;

    // reportId => true when a CSAM report has an active law enforcement hold.
    // Holds block reinstateAfterCsamExpiry until explicitly removed.
    mapping(uint256 => bool) private _lawEnforcementHold;

    // reporterProxy => count of substantiated false reports (spec §12.6).
    // Written to chain permanently; used by instances to enforce subscriber consequences.
    mapping(address => uint256) private _falseReportCount;

    constructor(address identityRegistry, address subscriptionContract, address purchaseContract, address contentRegistry) {
        require(identityRegistry != address(0), "Zero address");
        require(subscriptionContract != address(0), "Zero address");
        require(purchaseContract != address(0), "Zero address");
        require(contentRegistry != address(0), "Zero address");
        _owner = msg.sender;
        _identity = IDENIdentity(identityRegistry);
        _subscription = IDENSubscription(subscriptionContract);
        _purchaseState = IDENPurchaseState(purchaseContract);
        _contentRegistry = IDENContentRegistry(contentRegistry);
    }

    // --- Governance wiring ---

    // Wire the governance parameter store. Callable once.
    function setGovernanceParams(address govParams_) external {
        require(msg.sender == _owner, "Not owner");
        require(_govParams == address(0), "Already set");
        require(govParams_ != address(0), "Zero address");
        _govParams = govParams_;
    }

    // Wire the governance contract for resolving operator-conflicted reports (spec §12.2, Option B).
    // One-time setter; cannot be changed once set.
    function setGovernance(address governance) external {
        require(msg.sender == _owner, "Not owner");
        require(_governance == address(0), "Already set");
        require(governance != address(0), "Zero address");
        _governance = governance;
    }

    // Exposed with original constant names for backward compatibility.
    function CREATOR_RESPONSE_WINDOW() public view returns (uint256) {
        return _govParams != address(0)
            ? IDENGovernanceParams(_govParams).getCreatorResponseWindow()
            : _DEFAULT_CREATOR_RESPONSE_WINDOW;
    }
    function CSAM_SUSPENSION_DURATION() public view returns (uint256) {
        return _govParams != address(0)
            ? IDENGovernanceParams(_govParams).getCsamSuspensionDuration()
            : _DEFAULT_CSAM_SUSPENSION_DURATION;
    }

    // --- Report filing ---

    function fileReport(
        bytes32 fingerprint,
        uint256 accessTimestamp,
        ViolationCategory category,
        bytes32 evidenceHash
    ) external returns (uint256 reportId) {
        require(fingerprint != bytes32(0), "Zero fingerprint");
        require(evidenceHash != bytes32(0), "Missing evidence hash");
        require(accessTimestamp > 0 && accessTimestamp <= block.timestamp, "Invalid access timestamp");

        address reporterProxy = _identity.getProxy(msg.sender);
        require(reporterProxy != address(0), "Not registered");
        require(IDENParticipantIdentity(reporterProxy).primaryWallet() == msg.sender, "Not primary wallet");

        IDENContentRegistry.ContentRecord memory content = _contentRegistry.getContent(fingerprint);
        require(content.creatorProxy != address(0), "Content not found");
        // Only Active and Archived content is reportable — SunsetNoticed/Deleted is already being removed.
        require(
            content.lifecycle == IDENContentRegistry.Lifecycle.Active ||
            content.lifecycle == IDENContentRegistry.Lifecycle.Archived,
            "Content not reportable"
        );

        // Reporter must have had plaintext access at the claimed access time (spec §12.2).
        // Two valid access paths: active subscription or permanent purchase.
        //
        // Subscription check: start <= accessTimestamp <= expiry.
        // getSubscriptionStart returns the start of the CURRENT subscription period (0 if never subscribed).
        // Spec gap (§12.2): a subscriber who lapsed and re-subscribed loses the ability to report content
        // they accessed during a prior subscription period — only the current period's start is on-chain.
        uint256 subExpiry = _subscription.getSubscriptionExpiry(reporterProxy, content.creatorProxy, content.tierId);
        uint256 subStart  = _subscription.getSubscriptionStart(reporterProxy, content.creatorProxy, content.tierId);
        bool hasSubscriptionAccess = subStart > 0 && subStart <= accessTimestamp && subExpiry >= accessTimestamp;

        // Purchase check: purchasedAt <= accessTimestamp (permanent access once purchased).
        // content.tierId doubles as listingId for purchase-based content (same on-chain namespace).
        uint256 purchasedAt = _purchaseState.getPurchaseTimestamp(reporterProxy, content.creatorProxy, content.tierId);
        bool hasPurchaseAccess = purchasedAt > 0 && purchasedAt <= accessTimestamp;

        require(hasSubscriptionAccess || hasPurchaseAccess, "No verified access at claimed access time");

        // Auto-detect operator conflict: reporter proxy is the registered content operator (spec §12.2).
        // The "different wallet, demonstrable relationship" case is not detectable on-chain — V1 limitation.
        bool operatorConflict = (reporterProxy == _contentRegistry.getContentOperator(content.creatorProxy));

        reportId = _reports.length;
        _reports.push(Report({
            id:               reportId,
            fingerprint:      fingerprint,
            reporterProxy:    reporterProxy,
            accessTimestamp:  accessTimestamp,
            category:         category,
            evidenceHash:     evidenceHash,
            status:           ReportStatus.Active,
            filedAt:          block.timestamp,
            operatorConflict: operatorConflict
        }));
        _reportsByFingerprint[fingerprint].push(reportId);

        // Suspend on first active report (spec §12.3: mandatory first step for all violation claims).
        if (_activeReportCount[fingerprint] == 0) {
            emit ContentSuspended(fingerprint, reportId);
        }
        _activeReportCount[fingerprint]++;

        emit ReportFiled(reportId, fingerprint, reporterProxy, category, operatorConflict);
    }

    // --- Determination ---

    function determineReport(uint256 reportId, ReportStatus outcome) external {
        require(reportId < _reports.length, "Report not found");
        Report storage report = _reports[reportId];
        require(report.status == ReportStatus.Active, "Report not active");
        require(
            outcome == ReportStatus.Upheld ||
            outcome == ReportStatus.Dismissed ||
            outcome == ReportStatus.FalseReport,
            "Invalid outcome"
        );

        // CSAM cannot be internally adjudicated at all (spec §12.5): "the protocol does not
        // conduct independent adjudication — this is a legal matter handled by the appropriate
        // authorities." Upheld is equally prohibited — use reinstateAfterCsamExpiry after the
        // suspension window, or setLawEnforcementHold to extend it.
        require(
            report.category != ViolationCategory.CSAM,
            "CSAM reports cannot be internally adjudicated: use reinstateAfterCsamExpiry or setLawEnforcementHold"
        );

        IDENContentRegistry.ContentRecord memory content = _contentRegistry.getContent(report.fingerprint);
        address operatorProxy = _contentRegistry.getContentOperator(content.creatorProxy);

        if (report.operatorConflict) {
            // Conflicted reports must not be adjudicated by the instance operator (spec §12.2).
            // Requires the governance address to be set via setGovernance() (Option B).
            // V1 limitation: these reports remain Active until the governance contract is wired.
            require(_governance != address(0), "Conflicted report requires governance: not yet configured");
            require(msg.sender == _governance, "Conflicted reports require governance resolution");
        } else {
            address callerProxy = _identity.getProxy(msg.sender);
            require(callerProxy != address(0), "Not registered");
            require(IDENParticipantIdentity(callerProxy).primaryWallet() == msg.sender, "Not primary wallet");
            require(callerProxy == operatorProxy, "Not content operator");
        }

        report.status = outcome;
        _activeReportCount[report.fingerprint]--;

        if (outcome == ReportStatus.Upheld) {
            // Permanently suspended. Operator initiates §7.5 sunset process via DENContentRegistry separately.
            _permanentlySuspended[report.fingerprint] = true;
        } else {
            // Dismissed or FalseReport: reinstate if no remaining active reports and not permanently suspended.
            if (_activeReportCount[report.fingerprint] == 0 && !_permanentlySuspended[report.fingerprint]) {
                emit ContentReinstated(report.fingerprint, reportId);
            }
            if (outcome == ReportStatus.FalseReport) {
                _falseReportCount[report.reporterProxy]++;
                emit FalseReportFlagged(reportId, report.reporterProxy, _falseReportCount[report.reporterProxy]);
            }
        }

        emit ReportDetermined(reportId, outcome);
    }

    // --- CSAM reinstatement ---

    function reinstateAfterCsamExpiry(uint256 reportId) external {
        require(reportId < _reports.length, "Report not found");
        Report storage report = _reports[reportId];
        require(report.status == ReportStatus.Active, "Report not active");
        require(report.category == ViolationCategory.CSAM, "Not a CSAM report");
        require(!_lawEnforcementHold[reportId], "Law enforcement hold active");
        require(
            block.timestamp >= report.filedAt + CSAM_SUSPENSION_DURATION(),
            "Suspension period not elapsed"
        );

        report.status = ReportStatus.Reinstated;
        _activeReportCount[report.fingerprint]--;

        if (_activeReportCount[report.fingerprint] == 0 && !_permanentlySuspended[report.fingerprint]) {
            emit ContentReinstated(report.fingerprint, reportId);
        }

        emit ReportDetermined(reportId, ReportStatus.Reinstated);
    }

    // --- CSAM law enforcement hold ---

    function setLawEnforcementHold(uint256 reportId) external {
        require(reportId < _reports.length, "Report not found");
        Report storage report = _reports[reportId];
        require(report.status == ReportStatus.Active, "Report not active");
        require(report.category == ViolationCategory.CSAM, "LE hold only applies to CSAM reports");
        require(!_lawEnforcementHold[reportId], "Hold already active");
        _requireContentOperator(report.fingerprint);
        _lawEnforcementHold[reportId] = true;
        emit LawEnforcementHoldSet(reportId);
    }

    function removeLawEnforcementHold(uint256 reportId) external {
        require(reportId < _reports.length, "Report not found");
        require(_lawEnforcementHold[reportId], "No hold active");
        _requireContentOperator(_reports[reportId].fingerprint);
        _lawEnforcementHold[reportId] = false;
        emit LawEnforcementHoldRemoved(reportId);
    }

    // --- Views ---

    // True while any Active report exists OR any report has been Upheld (permanent suspension).
    // Checked by the instance access gate on every content request alongside isContentActive.
    function isSuspended(bytes32 fingerprint) external view returns (bool) {
        return _permanentlySuspended[fingerprint] || _activeReportCount[fingerprint] > 0;
    }

    function getReport(uint256 reportId) external view returns (Report memory) {
        require(reportId < _reports.length, "Report not found");
        return _reports[reportId];
    }

    function getReportCount() external view returns (uint256) {
        return _reports.length;
    }

    function getReportsByFingerprint(bytes32 fingerprint) external view returns (uint256[] memory) {
        return _reportsByFingerprint[fingerprint];
    }

    function getFalseReportCount(address reporterProxy) external view returns (uint256) {
        return _falseReportCount[reporterProxy];
    }

    function hasLawEnforcementHold(uint256 reportId) external view returns (bool) {
        return _lawEnforcementHold[reportId];
    }

    // --- Internal ---

    function _requireContentOperator(bytes32 fingerprint) internal view {
        IDENContentRegistry.ContentRecord memory content = _contentRegistry.getContent(fingerprint);
        address callerProxy = _identity.getProxy(msg.sender);
        require(callerProxy != address(0), "Not registered");
        require(IDENParticipantIdentity(callerProxy).primaryWallet() == msg.sender, "Not primary wallet");
        require(
            callerProxy == _contentRegistry.getContentOperator(content.creatorProxy),
            "Not content operator"
        );
    }
}
