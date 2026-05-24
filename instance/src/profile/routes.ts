// Public creator profile — unauthenticated (spec §6.2, §6.3, §6.5).
//
// GET /profile/:proxy
//
// Returns everything a prospective Subscriber needs to evaluate a Creator before
// connecting a wallet: handle, bio, subscription tiers + pricing, any publicly
// designated content (with its decryption key), and content warnings for paywalled posts.
//
// No authentication, session, or wallet connection is required — spec §6.5 explicitly
// prohibits a login wall before the subscription decision point.
//
// Tier data is sourced from TierSet chain events — the DENSubscription contract has no
// enumeration function, so event logs are the only way to discover which tiers exist.
// For each tierId, the latest TierSet event wins (creators can update tier pricing).
//
// Public content (spec §6.3) is a creator choice, not a protocol requirement. When a
// creator marks a post public via PUT /creator/content/:fingerprint/visibility, the
// instance stores the content decryption key and sets is_public=1. The profile includes
// the fingerprint and key so clients can fetch and decrypt the ciphertext without auth.
//
// Content warnings for paywalled posts are returned as metadata only — no ciphertext,
// no key — so prospective Subscribers can evaluate content maturity before subscribing.

import { Hono } from 'hono';
import { toHex, parseAbiItem } from 'viem';
import { getDb } from '../db/index.ts';
import { identityRegistry, subscription } from '../chain/contracts.ts';
import { chainClient } from '../chain/client.ts';

export const profileRoutes = new Hono();

const tierSetEvent = parseAbiItem(
  'event TierSet(address indexed creatorProxy, uint256 indexed tierId, uint256 price, uint256 duration, address indexed token)',
);

profileRoutes.get('/:proxy', async (c) => {
  const { proxy } = c.req.param();

  if (!/^0x[0-9a-fA-F]{40}$/.test(proxy)) {
    return c.json({ error: 'proxy must be a 0x-prefixed 40-char hex Ethereum address' }, 400);
  }

  // Verify the address is a registered DEN identity before doing any further work.
  let isRegistered: boolean;
  try {
    isRegistered = await identityRegistry.read.isRegisteredProxy([proxy as `0x${string}`]);
  } catch {
    return c.json({ error: 'chain read failed — check RPC connectivity' }, 500);
  }
  if (!isRegistered) {
    return c.json({ error: 'creator not found' }, 404);
  }

  // Fetch handle and tiers in parallel — both are chain reads with no dependency on each other.
  // Using .catch(() => null) so TypeScript infers the tuple type from Promise.all directly,
  // which preserves the event-specific arg types on tierLogs.
  const chainResults = await Promise.all([
    identityRegistry.read.handleOf([proxy as `0x${string}`]),
    chainClient.getLogs({
      address: subscription.address,
      event: tierSetEvent,
      args: { creatorProxy: proxy as `0x${string}` },
      fromBlock: 0n,
      toBlock: 'latest',
    }),
  ]).catch(() => null);

  if (!chainResults) {
    return c.json({ error: 'chain read failed — check RPC connectivity' }, 500);
  }

  const [handle, tierLogs] = chainResults;

  // Deduplicate tiers by tierId — the latest TierSet event for each tierId reflects the
  // current price and duration (creators can call setTier again to update a tier).
  const latestByTier = new Map<string, {
    tierId: string;
    price: string;
    duration: string;
    token: string;
  }>();
  for (const log of tierLogs) {
    const { tierId, price, duration, token } = log.args;
    if (tierId === undefined || price === undefined || duration === undefined || !token) {
      continue;
    }
    latestByTier.set(tierId.toString(), {
      tierId: tierId.toString(),
      price: price.toString(),
      duration: duration.toString(),
      token,
    });
  }

  // Bio from instance DB.
  type ProfileRow = { bio: string | null };
  const profileRow = getDb()
    .query<ProfileRow, [string]>(
      'SELECT bio FROM creator_profile WHERE LOWER(creator_proxy) = LOWER(?)',
    )
    .get(proxy);

  // Public content (spec §6.3): fingerprint + content key so clients can decrypt without auth.
  type PublicRow = {
    fingerprint: string;
    tier_id: string;
    timestamp: number;
    warnings: string | null;
    public_key: Uint8Array;
  };
  const publicContent = getDb()
    .query<PublicRow, [string]>(
      `SELECT fingerprint, tier_id, timestamp, warnings, public_key
       FROM content
       WHERE LOWER(creator_proxy) = LOWER(?) AND is_public = 1`,
    )
    .all(proxy)
    .map((r) => ({
      fingerprint: r.fingerprint,
      tierId: r.tier_id,
      timestamp: r.timestamp,
      warnings: r.warnings ? (JSON.parse(r.warnings) as string[]) : null,
      contentKey: toHex(new Uint8Array(r.public_key)),
    }));

  // Content warnings for paywalled posts — metadata only, no key or ciphertext.
  type WarnRow = { fingerprint: string; tier_id: string; warnings: string };
  const contentWarnings = getDb()
    .query<WarnRow, [string]>(
      `SELECT fingerprint, tier_id, warnings
       FROM content
       WHERE LOWER(creator_proxy) = LOWER(?) AND is_public = 0 AND warnings IS NOT NULL`,
    )
    .all(proxy)
    .map((r) => ({
      fingerprint: r.fingerprint,
      tierId: r.tier_id,
      warnings: JSON.parse(r.warnings) as string[],
    }));

  return c.json({
    proxy,
    handle,
    bio: profileRow?.bio ?? null,
    tiers: Array.from(latestByTier.values()),
    publicContent,
    contentWarnings,
  });
});
