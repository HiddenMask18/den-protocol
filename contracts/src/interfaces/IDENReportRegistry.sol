// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

interface IDENReportRegistry {

    // Protocol floor violation categories (spec §11.2).
    // Above-floor (instance-level) violations are handled via §7.5 sunset directly, not this registry.
    enum ViolationCategory {
        CSAM,        // sexual content depicting a real, identifiable minor — triggers mandatory LE referral path
        NON_CONSENT  // real, identifiable person in sexual or defamatory context without documented consent
    }

    enum ReportStatus {
        Active,      // report filed; content suspended; awaiting determination
        Upheld,      // violation confirmed; content permanently suspended; operator initiates §7.5 sunset
        Dismissed,   // no violation; content reinstated (if no remaining active reports)
        FalseReport, // deliberate false report; reporter flagged; content reinstated
        Reinstated   // CSAM only: no law enforcement action within suspension period; auto-reinstated
    }

    struct Report {
        uint256           id;
        bytes32           fingerprint;
        address           reporterProxy;
        uint256           accessTimestamp;   // claimed time of access; checked against subscription expiry
        ViolationCategory category;
        bytes32           evidenceHash;      // keccak256 of off-chain evidence bundle; evidence stored by instance
        ReportStatus      status;
        uint256           filedAt;
        bool              operatorConflict;  // true when reporter proxy === registered content operator (spec §12.2)
    }

    // Emitted when a valid report is filed.
    event ReportFiled(
        uint256 indexed reportId,
        bytes32 indexed fingerprint,
        address indexed reporterProxy,
        ViolationCategory category,
        bool operatorConflict
    );

    // Emitted when the first active report against a fingerprint is filed (suspension begins).
    event ContentSuspended(bytes32 indexed fingerprint, uint256 indexed reportId);

    // Emitted when content is reinstated: all active reports resolved non-upheld and no permanent suspension.
    event ContentReinstated(bytes32 indexed fingerprint, uint256 indexed reportId);

    // Emitted when any report reaches a terminal status.
    event ReportDetermined(uint256 indexed reportId, ReportStatus outcome);

    // Emitted when a CSAM report is flagged with a law enforcement hold.
    event LawEnforcementHoldSet(uint256 indexed reportId);
    event LawEnforcementHoldRemoved(uint256 indexed reportId);

    // Emitted when a report is determined to be a false report.
    event FalseReportFlagged(uint256 indexed reportId, address indexed reporterProxy, uint256 falseReportCount);

    // File a protocol floor violation report.
    // Reporter must be registered and have held an active subscription at accessTimestamp (spec §12.2).
    // Content is suspended immediately on the first valid report against a fingerprint (spec §12.3).
    // Operator-reporter conflicts are auto-detected and flagged; those reports require governance resolution.
    function fileReport(
        bytes32 fingerprint,
        uint256 accessTimestamp,
        ViolationCategory category,
        bytes32 evidenceHash
    ) external returns (uint256 reportId);

    // Determine an active, non-conflicted report. Caller must be the registered content operator.
    // outcome must be Upheld, Dismissed, or FalseReport.
    // CSAM reports cannot be Dismissed or FalseReport — use reinstateAfterCsamExpiry for no-action cases.
    // Conflicted reports (operatorConflict = true) require governance resolution via the governance address.
    function determineReport(uint256 reportId, ReportStatus outcome) external;

    // Reinstate content after a CSAM suspension expires with no law enforcement action (spec §12.5).
    // Permissionless — any caller may trigger reinstatement once CSAM_SUSPENSION_DURATION has elapsed,
    // provided no law enforcement hold is active. Permissionless so the operator cannot block
    // reinstatement by inaction when no LE action was taken.
    function reinstateAfterCsamExpiry(uint256 reportId) external;

    // Declare that law enforcement has taken action on a CSAM report, blocking auto-reinstatement (spec §12.5).
    // Content operator only. Records the declaration on-chain for audit; the LE action itself is off-chain.
    function setLawEnforcementHold(uint256 reportId) external;

    // Remove a law enforcement hold once the LE process concludes without action.
    // Content operator only. After removal, reinstateAfterCsamExpiry may be called if duration has elapsed.
    function removeLawEnforcementHold(uint256 reportId) external;

    // Wire the governance contract for resolving operator-conflicted reports (spec §12.2, Option B).
    // Owner only. Callable once. Until set, conflicted reports cannot be determined — V1 limitation.
    function setGovernance(address governance) external;

    // Returns true if the fingerprint is currently suspended.
    // True when any Active report exists OR when any report has been Upheld (permanent suspension).
    // Checked by the instance access gate alongside DENContentRegistry.isContentActive.
    function isSuspended(bytes32 fingerprint) external view returns (bool);

    function getReport(uint256 reportId) external view returns (Report memory);
    function getReportCount() external view returns (uint256);
    function getReportsByFingerprint(bytes32 fingerprint) external view returns (uint256[] memory);
    function getFalseReportCount(address reporterProxy) external view returns (uint256);
    function hasLawEnforcementHold(uint256 reportId) external view returns (bool);
}
