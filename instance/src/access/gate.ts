// On-chain access checks for subscription and purchase flows.
//
// Every call here is a live chain read — no caching. Subscription state is time-sensitive:
// a subscription can lapse between requests, and the instance must not serve a key to a
// subscriber whose paid period has just expired. The on-chain contract is the sole authority.
//
// Each check has two steps:
//   1. Verify the participant holds the required entitlement (active subscription or purchase).
//   2. Verify the creator has a valid access grant on-chain for the requested tier or listing.
//      verifyGrant() re-verifies the stored signature against the creator's current primary wallet
//      (spec §4.1 MUST) — if the creator's wallet has rotated and the grant hasn't been re-published,
//      verifyGrant returns false and access is denied until the creator re-publishes the grant.
//
// The gate returns the derivation paths on success. The access route uses those paths to call
// deriveKey() once per path and return the full set of keys to the subscriber.
//
// Chain errors (RPC failure, timeout) are not caught here. They propagate as thrown errors
// and are handled by the global error handler in index.ts, which returns a 500 response.

import { subscription, purchaseState, accessGrant } from '../chain/contracts.ts';

export type GateResult =
  | { ok: true; paths: readonly string[]; expiry?: bigint }
  | { ok: false; reason: string };

// Checks whether subscriberProxy holds an active subscription to tierId on creatorProxy,
// and whether creatorProxy has a signature-valid access grant on-chain for that tier.
// Grant is read from chain (authoritative) — bypasses any stale local grant store.
// verifyGrant re-verifies the stored signature against the current primary wallet (spec §4.1).
export async function checkSubscriptionAccess(
  subscriberProxy: `0x${string}`,
  creatorProxy: `0x${string}`,
  tierId: bigint,
): Promise<GateResult> {
  const active = await subscription.read.isSubscribed([subscriberProxy, creatorProxy, tierId]);
  if (!active) {
    return { ok: false, reason: 'no active subscription for this tier' };
  }

  // Read expiry for subscriber state mirroring (spec §4.2).
  const expiry = await subscription.read.getSubscriptionExpiry([subscriberProxy, creatorProxy, tierId]);

  const [valid, paths] = await accessGrant.read.verifyGrant([creatorProxy, tierId]);
  if (!valid || paths.length === 0) {
    return { ok: false, reason: 'no valid access grant declared for this tier' };
  }

  return { ok: true, paths, expiry };
}

// Checks whether buyerProxy has purchased listingId from creatorProxy,
// and whether creatorProxy has a signature-valid access grant on-chain for that listing.
export async function checkPurchaseAccess(
  buyerProxy: `0x${string}`,
  creatorProxy: `0x${string}`,
  listingId: bigint,
): Promise<GateResult> {
  const purchased = await purchaseState.read.hasPurchased([buyerProxy, creatorProxy, listingId]);
  if (!purchased) {
    return { ok: false, reason: 'no purchase record for this listing' };
  }

  const [valid, paths] = await accessGrant.read.verifyGrant([creatorProxy, listingId]);
  if (!valid || paths.length === 0) {
    return { ok: false, reason: 'no valid access grant declared for this listing' };
  }

  return { ok: true, paths };
}
