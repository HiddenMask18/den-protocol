// Moderation routes — evidence submission and operator determination (spec §12).
//
// POST   /moderation/report                  — subscriber submits off-chain evidence
// GET    /moderation/report/:id              — view on-chain report details
// POST   /moderation/report/:id/determine    — operator determines outcome (Upheld/Dismissed/FalseReport)
// POST   /moderation/report/:id/le-hold      — operator sets CSAM law enforcement hold
// DELETE /moderation/report/:id/le-hold      — operator removes CSAM law enforcement hold
// POST   /moderation/report/:id/reinstate    — permissionless CSAM reinstatement after suspension expiry
//
// Evidence submission (POST /moderation/report):
//   The subscriber must call DENReportRegistry.fileReport on-chain with their own wallet —
//   the contract checks msg.sender is the reporter's registered primary wallet (spec §12.2).
//   The instance cannot submit that transaction on the subscriber's behalf. Instead, the
//   subscriber submits evidence here first to get the evidenceHash (keccak256 of evidence bytes)
//   required by fileReport. The instance stores evidence so the creator can be notified with
//   full report contents on suspension (spec §12.4).
//
// Operator routes:
//   All write calls use the operator walletClient (INSTANCE_OPERATOR_PRIVATE_KEY). The operator
//   wallet must be the registered content operator for creators hosted on this instance.
//   Conflicted reports (operatorConflict=true on-chain) cannot be determined here — they require
//   governance resolution. The contract will revert; the error propagates as a 500.

import { Hono } from 'hono';
import { keccak256, parseAbiItem, parseEventLogs } from 'viem';
import { requireAuth } from '../auth/middleware.ts';
import { operatorAccount, walletClient } from '../chain/wallet.ts';
import { chainClient } from '../chain/client.ts';
import { governance, reportRegistry } from '../chain/contracts.ts';
import { reportRegistryAbi } from '../chain/abis.ts';
import { getDb } from '../db/index.ts';

type SessionEnv = {
  Variables: { proxy: string; wallet: string };
};

// ReportStatus uint8 values matching DENReportRegistry (spec §12.5).
const OUTCOME_MAP: Record<string, number> = {
  Upheld:      1,
  Dismissed:   2,
  FalseReport: 3,
};

// Defined at module level so parseAbiItem runs once, not per request.
const reportFiledEvent = parseAbiItem(
  'event ReportFiled(uint256 indexed reportId, bytes32 indexed fingerprint, address indexed reporterProxy, uint8 category, bool operatorConflict)',
);

export const moderationRoutes = new Hono<SessionEnv>();

// Returns all reports filed against this creator's content, with full evidence (spec §12.4).
//
// The spec requires the Creator to receive, on suspension: full report contents, the pseudonymous
// identifier of the reporting Subscriber, the violation category, and the response window duration.
// This endpoint satisfies that requirement by giving the authenticated Creator a single query
// covering all their fingerprints hosted on this instance.
//
// For each report the creator gets:
//   - On-chain fields: reportId, fingerprint, reporterProxy, accessTimestamp, category,
//     evidenceHash, status, filedAt, operatorConflict
//   - Off-chain evidence bytes (base64): present when the subscriber submitted via
//     POST /moderation/report; null if the subscriber filed directly on-chain
//   - creatorResponseWindowSeconds: from on-chain governance (spec §13.4)
//
// Status 0 = Active means the fingerprint is currently suspended; those are the reports requiring
// a creator response. The full history (Upheld, Dismissed, FalseReport, Reinstated) is also
// included so the creator has an audit trail.
moderationRoutes.get('/creator/reports', requireAuth, async (c) => {
  const proxy = c.get('proxy');

  // All fingerprints this creator has uploaded to this instance.
  type FpRow = { fingerprint: string };
  const fingerprints = getDb()
    .query<FpRow, [string]>(
      'SELECT fingerprint FROM content WHERE LOWER(creator_proxy) = LOWER(?)',
    )
    .all(proxy)
    .map((r) => r.fingerprint as `0x${string}`);

  // creator_response_window is required by §12.4 regardless of whether any reports exist.
  let creatorResponseWindow: bigint;
  try {
    creatorResponseWindow = await governance.read.getCreatorResponseWindow();
  } catch {
    return c.json({ error: 'governance read failed — check RPC connectivity' }, 500);
  }

  if (fingerprints.length === 0) {
    return c.json({ reports: [], creatorResponseWindowSeconds: creatorResponseWindow.toString() });
  }

  // Scan ReportFiled events per fingerprint in parallel. fingerprint is indexed (topic2) so the
  // RPC node filters server-side — only matching logs are returned for each call.
  let logBatches: { reportId: bigint; fingerprint: `0x${string}` }[][];
  try {
    logBatches = await Promise.all(
      fingerprints.map(async (fp) => {
        const logs = await chainClient.getLogs({
          address: reportRegistry.address,
          event: reportFiledEvent,
          args: { fingerprint: fp },
          fromBlock: 0n,
          toBlock: 'latest',
        });
        return logs
          .filter((l) => l.args.reportId !== undefined)
          .map((l) => ({ reportId: l.args.reportId!, fingerprint: fp }));
      }),
    );
  } catch {
    return c.json({ error: 'chain scan failed — check RPC connectivity' }, 500);
  }

  // Flatten to unique reportIds. A fingerprint can accumulate multiple reports.
  const seen = new Set<string>();
  const uniqueReports: { reportId: bigint; fingerprint: `0x${string}` }[] = [];
  for (const batch of logBatches) {
    for (const r of batch) {
      const key = r.reportId.toString();
      if (!seen.has(key)) {
        seen.add(key);
        uniqueReports.push(r);
      }
    }
  }

  if (uniqueReports.length === 0) {
    return c.json({ reports: [], creatorResponseWindowSeconds: creatorResponseWindow.toString() });
  }

  // Fetch full on-chain report data for all reports in one parallel batch.
  type OnChainReport = Awaited<ReturnType<typeof reportRegistry.read.getReport>>;
  let onChainReports: OnChainReport[];
  try {
    onChainReports = await Promise.all(
      uniqueReports.map(({ reportId }) => reportRegistry.read.getReport([reportId])),
    );
  } catch {
    return c.json({ error: 'failed to fetch report details from chain' }, 500);
  }

  // Join each on-chain report with its off-chain evidence bytes (stored by POST /moderation/report).
  // Evidence is null if the subscriber filed directly on-chain without submitting via this instance.
  type EvidenceRow = { evidence: Uint8Array };
  const result = onChainReports.map((report) => {
    const row = getDb()
      .query<EvidenceRow, [string]>(
        'SELECT evidence FROM report_evidence WHERE LOWER(evidence_hash) = LOWER(?)',
      )
      .get(report.evidenceHash);

    return {
      reportId:         report.id.toString(),
      fingerprint:      report.fingerprint,
      reporterProxy:    report.reporterProxy,
      accessTimestamp:  report.accessTimestamp.toString(),
      category:         report.category,
      evidenceHash:     report.evidenceHash,
      status:           report.status,
      filedAt:          report.filedAt.toString(),
      operatorConflict: report.operatorConflict,
      evidence:         row ? Buffer.from(row.evidence).toString('base64') : null,
    };
  });

  // Most-recent reports first.
  result.sort((a, b) => {
    const diff = BigInt(b.filedAt) - BigInt(a.filedAt);
    return diff > 0n ? 1 : diff < 0n ? -1 : 0;
  });

  return c.json({ reports: result, creatorResponseWindowSeconds: creatorResponseWindow.toString() });
});

// Submit off-chain evidence for a protocol floor violation.
// Returns the evidenceHash the subscriber must pass to DENReportRegistry.fileReport on-chain.
// Body: { fingerprint, accessTimestamp, category, evidence }
//   fingerprint     — 0x-prefixed SHA-256 of the content (64 hex chars)
//   accessTimestamp — Unix seconds when the subscriber accessed the content
//   category        — 0 (CSAM) or 1 (NON_CONSENT)
//   evidence        — base64-encoded evidence bytes (screenshots, descriptions, etc.)
moderationRoutes.post('/report', requireAuth, async (c) => {
  const reporterProxy = c.get('proxy');

  const body = await c.req.json().catch(() => null);
  if (!body) return c.json({ error: 'invalid JSON body' }, 400);

  const { fingerprint, accessTimestamp, category, evidence } = body;

  if (!fingerprint || !/^0x[0-9a-fA-F]{64}$/.test(fingerprint)) {
    return c.json({ error: 'fingerprint must be a 0x-prefixed 64-char hex string (SHA-256)' }, 400);
  }
  if (typeof accessTimestamp !== 'number' || !Number.isInteger(accessTimestamp) || accessTimestamp <= 0) {
    return c.json({ error: 'accessTimestamp must be a positive integer Unix timestamp (seconds)' }, 400);
  }
  if (category !== 0 && category !== 1) {
    return c.json({ error: 'category must be 0 (CSAM) or 1 (NON_CONSENT)' }, 400);
  }
  if (!evidence || typeof evidence !== 'string') {
    return c.json({ error: 'evidence must be a non-empty base64-encoded string' }, 400);
  }

  let evidenceBytes: Uint8Array;
  try {
    evidenceBytes = Uint8Array.from(Buffer.from(evidence, 'base64'));
  } catch {
    return c.json({ error: 'evidence must be valid base64' }, 400);
  }
  if (evidenceBytes.length === 0) {
    return c.json({ error: 'evidence must not be empty' }, 400);
  }

  const evidenceHash = keccak256(evidenceBytes);

  getDb().run(
    `INSERT OR REPLACE INTO report_evidence
       (evidence_hash, fingerprint, reporter_proxy, category, evidence, submitted_at)
     VALUES (?, ?, ?, ?, ?, ?)`,
    [evidenceHash, fingerprint, reporterProxy, category, evidenceBytes, Date.now()],
  );

  return c.json({
    evidenceHash,
    reportRegistryAddress: reportRegistry.address,
  }, 201);
});

// View on-chain report details. Public — reports are on-chain and readable by anyone.
moderationRoutes.get('/report/:id', async (c) => {
  const { id } = c.req.param();
  let reportId: bigint;
  try {
    reportId = BigInt(id);
  } catch {
    return c.json({ error: 'reportId must be a non-negative integer' }, 400);
  }

  let report;
  try {
    report = await reportRegistry.read.getReport([reportId]);
  } catch {
    return c.json({ error: 'report not found' }, 404);
  }

  return c.json({
    id:               report.id.toString(),
    fingerprint:      report.fingerprint,
    reporterProxy:    report.reporterProxy,
    accessTimestamp:  report.accessTimestamp.toString(),
    category:         report.category,
    evidenceHash:     report.evidenceHash,
    status:           report.status,
    filedAt:          report.filedAt.toString(),
    operatorConflict: report.operatorConflict,
  });
});

// Determine the outcome of an active report. Operator-only (spec §12.5).
// CSAM reports cannot be Dismissed or FalseReport — use POST .../reinstate for no-action cases.
// Conflicted reports (operatorConflict=true) require governance and will revert on-chain.
// Body: { outcome: "Upheld" | "Dismissed" | "FalseReport" }
moderationRoutes.post('/report/:id/determine', requireAuth, async (c) => {
  if (c.get('wallet').toLowerCase() !== operatorAccount.address.toLowerCase()) {
    return c.json({ error: 'forbidden: only the instance operator wallet may determine reports' }, 403);
  }

  const { id } = c.req.param();
  let reportId: bigint;
  try {
    reportId = BigInt(id);
  } catch {
    return c.json({ error: 'reportId must be a non-negative integer' }, 400);
  }

  const body = await c.req.json().catch(() => null);
  if (!body) return c.json({ error: 'invalid JSON body' }, 400);

  const outcomeValue = OUTCOME_MAP[body.outcome];
  if (outcomeValue === undefined) {
    return c.json({ error: 'outcome must be "Upheld", "Dismissed", or "FalseReport"' }, 400);
  }

  const hash = await walletClient.writeContract({
    address: reportRegistry.address,
    abi: reportRegistryAbi,
    functionName: 'determineReport',
    args: [reportId, outcomeValue],
  });

  const receipt = await chainClient.waitForTransactionReceipt({ hash });
  const logs = parseEventLogs({ abi: reportRegistryAbi, eventName: 'ReportDetermined', logs: receipt.logs });
  const event = logs[0]?.args;

  return c.json({
    txHash:   hash,
    reportId: event?.reportId?.toString() ?? id,
    outcome:  body.outcome,
  });
});

// Declare that law enforcement has taken action on a CSAM report (spec §12.5).
// Blocks auto-reinstatement until the hold is explicitly removed. Operator-only.
moderationRoutes.post('/report/:id/le-hold', requireAuth, async (c) => {
  if (c.get('wallet').toLowerCase() !== operatorAccount.address.toLowerCase()) {
    return c.json({ error: 'forbidden: only the instance operator wallet may set law enforcement holds' }, 403);
  }

  const { id } = c.req.param();
  let reportId: bigint;
  try {
    reportId = BigInt(id);
  } catch {
    return c.json({ error: 'reportId must be a non-negative integer' }, 400);
  }

  const hash = await walletClient.writeContract({
    address: reportRegistry.address,
    abi: reportRegistryAbi,
    functionName: 'setLawEnforcementHold',
    args: [reportId],
  });

  await chainClient.waitForTransactionReceipt({ hash });
  return c.json({ txHash: hash });
});

// Remove a law enforcement hold once the LE process concludes (spec §12.5). Operator-only.
// After removal, reinstateAfterCsamExpiry may be called if the suspension period has elapsed.
moderationRoutes.delete('/report/:id/le-hold', requireAuth, async (c) => {
  if (c.get('wallet').toLowerCase() !== operatorAccount.address.toLowerCase()) {
    return c.json({ error: 'forbidden: only the instance operator wallet may remove law enforcement holds' }, 403);
  }

  const { id } = c.req.param();
  let reportId: bigint;
  try {
    reportId = BigInt(id);
  } catch {
    return c.json({ error: 'reportId must be a non-negative integer' }, 400);
  }

  const hash = await walletClient.writeContract({
    address: reportRegistry.address,
    abi: reportRegistryAbi,
    functionName: 'removeLawEnforcementHold',
    args: [reportId],
  });

  await chainClient.waitForTransactionReceipt({ hash });
  return c.json({ txHash: hash });
});

// Permissionless CSAM reinstatement after the suspension period expires with no LE action (spec §12.5).
// Any authenticated participant may trigger this — the contract accepts any caller.
// Requires instance auth to prevent unauthenticated transaction spam; the operator wallet pays gas.
moderationRoutes.post('/report/:id/reinstate', requireAuth, async (c) => {
  const { id } = c.req.param();
  let reportId: bigint;
  try {
    reportId = BigInt(id);
  } catch {
    return c.json({ error: 'reportId must be a non-negative integer' }, 400);
  }

  const hash = await walletClient.writeContract({
    address: reportRegistry.address,
    abi: reportRegistryAbi,
    functionName: 'reinstateAfterCsamExpiry',
    args: [reportId],
  });

  const receipt = await chainClient.waitForTransactionReceipt({ hash });
  const logs = parseEventLogs({ abi: reportRegistryAbi, eventName: 'ReportDetermined', logs: receipt.logs });
  const event = logs[0]?.args;

  return c.json({
    txHash:   hash,
    reportId: event?.reportId?.toString() ?? id,
  });
});
