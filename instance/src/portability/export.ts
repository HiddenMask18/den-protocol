// Portable data set assembly — export side of creator migration (spec §8.1).
//
// The minimum portable data set covers everything a creator holds independently
// of any single instance. This module queries both the local DB and the chain
// to assemble the full bundle.
//
// On-chain queries:
//   - handleOf(proxy) → current handle (identity record)
//   - Subscribed event logs filtered by creatorProxy → subscriber list
//   - Purchased event logs filtered by creatorProxy → buyer list
//
// Local DB queries:
//   - master_secret_blobs.portability_blob → wallet-encrypted master secret
//   - content → fingerprints + metadata (no ciphertext — bytes live on IPFS)
//   - access_grants → tier→path declarations with creator signatures
//
// The portability blob (wallet-encrypted) is included so the creator can decrypt it
// client-side and re-encrypt it to the new instance's key before upload.
//
// Subscriber and buyer lists are derived from chain events. All three event fields
// that identify the relationship are indexed topics, so filtering by creatorProxy is
// efficient. getLogs scans from block 0 — acceptable for the infrequent export
// operation; a deployment-block optimization can be added later.
//
// Subscription deduplication: the Subscribed event fires on each payment (initial +
// renewals). For each (subscriberProxy, tierId) pair, the LAST event's expiry is the
// current authoritative expiry (renewals always extend from the last known end).

import { toHex, parseAbiItem } from 'viem';
import { getDb } from '../db/index.ts';
import { identityRegistry, subscription, purchaseState } from '../chain/contracts.ts';
import { chainClient } from '../chain/client.ts';

export type PortableDataBundle = {
  version: 1;
  exportedAt: number;
  creatorProxy: string;
  identityRecord: {
    proxy: string;
    handle: string;
  };
  portabilityBlob: string;
  oracleUrl: string | null;
  contentReferences: Array<{
    fingerprint: string;
    tierId: string;
    timestamp: number;
    warnings: string[] | null;
  }>;
  accessGrants: Array<{
    tierId: string;
    paths: string[];
    signature: string;
    version: number;
  }>;
  subscribers: Array<{
    subscriberProxy: string;
    tierId: string;
    expiry: string;
    active: boolean;
  }>;
  buyers: Array<{
    buyerProxy: string;
    listingId: string;
    purchasedAt: string;
  }>;
};

export class PortabilityError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'PortabilityError';
  }
}

const subscribedEvent = parseAbiItem(
  'event Subscribed(address indexed subscriberProxy, address indexed creatorProxy, uint256 indexed tierId, uint256 expiry)',
);

const purchasedEvent = parseAbiItem(
  'event Purchased(address indexed buyerProxy, address indexed creatorProxy, uint256 indexed listingId, uint256 purchasedAt)',
);

export async function assemblePortableData(creatorProxy: string): Promise<PortableDataBundle> {
  const proxy = creatorProxy as `0x${string}`;

  // 1. Portability blob and oracle URL.
  type BlobRow = { portability_blob: Uint8Array | null; oracle_url: string | null };
  const blobRow = getDb()
    .query<BlobRow, [string]>(
      'SELECT portability_blob, oracle_url FROM master_secret_blobs WHERE creator_proxy = ?',
    )
    .get(creatorProxy);

  if (!blobRow || !blobRow.portability_blob) {
    throw new PortabilityError(
      'portability blob not found — upload both blobs first via PUT /creator/blob',
    );
  }

  const portabilityBlob = toHex(new Uint8Array(blobRow.portability_blob));
  const oracleUrl = blobRow.oracle_url;

  // 2. Identity record — current handle from registry.
  const handle = await identityRegistry.read.handleOf([proxy]);

  // 3. Content references — fingerprints + metadata, no ciphertext.
  type ContentRow = { fingerprint: string; tier_id: string; timestamp: number; warnings: string | null };
  const contentRows = getDb()
    .query<ContentRow, [string]>(
      'SELECT fingerprint, tier_id, timestamp, warnings FROM content WHERE creator_proxy = ? ORDER BY timestamp ASC',
    )
    .all(creatorProxy);

  const contentReferences = contentRows.map((r) => ({
    fingerprint: r.fingerprint,
    tierId: r.tier_id,
    timestamp: r.timestamp,
    warnings: r.warnings ? (JSON.parse(r.warnings) as string[]) : null,
  }));

  // 4. Access grant declarations — include stored creator signatures for verification on import.
  type GrantRow = { tier_id: string; declaration: string; signature: string; version: number };
  const grantRows = getDb()
    .query<GrantRow, [string]>(
      'SELECT tier_id, declaration, signature, version FROM access_grants WHERE creator_proxy = ?',
    )
    .all(creatorProxy);

  const accessGrants = grantRows.map((r) => {
    const { paths } = JSON.parse(r.declaration) as { paths: string[] };
    return { tierId: r.tier_id, paths, signature: r.signature, version: r.version };
  });

  // 5. Subscriber list from chain events.
  const subscribedLogs = await chainClient.getLogs({
    address: subscription.address,
    event: subscribedEvent,
    args: { creatorProxy: proxy },
    fromBlock: 0n,
    toBlock: 'latest',
  });

  // Deduplicate by (subscriber, tier), keeping the entry with the highest expiry
  // (the most recent subscription or renewal).
  const latestBySubTier = new Map<string, { subscriberProxy: string; tierId: string; expiry: bigint }>();
  for (const log of subscribedLogs) {
    if (!log.args.subscriberProxy || log.args.tierId === undefined || log.args.expiry === undefined) {
      continue;
    }
    const key = `${log.args.subscriberProxy.toLowerCase()}-${log.args.tierId}`;
    const existing = latestBySubTier.get(key);
    if (!existing || log.args.expiry > existing.expiry) {
      latestBySubTier.set(key, {
        subscriberProxy: log.args.subscriberProxy,
        tierId: log.args.tierId.toString(),
        expiry: log.args.expiry,
      });
    }
  }

  const nowSec = BigInt(Math.floor(Date.now() / 1000));
  const subscribers = Array.from(latestBySubTier.values()).map((s) => ({
    subscriberProxy: s.subscriberProxy,
    tierId: s.tierId,
    expiry: s.expiry.toString(),
    active: s.expiry > nowSec,
  }));

  // 6. Buyer list from chain events.
  // Each (buyer, listing) pair can only appear once on-chain — no deduplication needed.
  const purchasedLogs = await chainClient.getLogs({
    address: purchaseState.address,
    event: purchasedEvent,
    args: { creatorProxy: proxy },
    fromBlock: 0n,
    toBlock: 'latest',
  });

  const buyers = purchasedLogs
    .filter(
      (l) =>
        l.args.buyerProxy !== undefined &&
        l.args.listingId !== undefined &&
        l.args.purchasedAt !== undefined,
    )
    .map((l) => ({
      buyerProxy: l.args.buyerProxy!,
      listingId: l.args.listingId!.toString(),
      purchasedAt: l.args.purchasedAt!.toString(),
    }));

  return {
    version: 1,
    exportedAt: Date.now(),
    creatorProxy,
    identityRecord: { proxy: creatorProxy, handle },
    portabilityBlob,
    oracleUrl,
    contentReferences,
    accessGrants,
    subscribers,
    buyers,
  };
}
