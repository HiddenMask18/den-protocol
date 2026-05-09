// On-chain access checks for subscription and purchase flows.
//
// Every call here is a live chain read — no caching. Subscription state is time-sensitive:
// a subscription can lapse between requests, and the instance must not serve a key to a
// subscriber whose paid period has just expired. The on-chain contract is the sole authority.
//
// Each check has two steps:
//   1. Verify the participant holds the required entitlement (active subscription or purchase).
//   2. Verify the creator has published a valid access grant for the requested tier or listing
//      and retrieve the derivation paths it covers.
//
// The gate returns the derivation paths on success. The access route uses those paths to call
// deriveKey() once per path and return the full set of keys to the subscriber.
//
// Chain errors (RPC failure, timeout) are not caught here. They propagate as thrown errors
// and are handled by the global error handler in index.ts, which returns a 500 response.

import { subscription, purchaseState, accessGrant } from '../chain/contracts.ts';

export type GateResult =
  | { ok: true; paths: readonly string[] }
  | { ok: false; reason: string };

// Checks whether subscriberProxy holds an active subscription to tierId on creatorProxy,
// and whether creatorProxy has published a valid access grant for that tier.
export async function checkSubscriptionAccess(
  subscriberProxy: `0x${string}`,
  creatorProxy: `0x${string}`,
  tierId: bigint,
): Promise<GateResult> {
  const active = await subscription.read.isSubscribed([subscriberProxy, creatorProxy, tierId]);
  if (!active) {
    return { ok: false, reason: 'no active subscription for this tier' };
  }

  const [valid, paths] = await accessGrant.read.verifyGrant([creatorProxy, tierId]);
  if (!valid) {
    return { ok: false, reason: 'no valid access grant published for this tier' };
  }

  return { ok: true, paths };
}

// Checks whether buyerProxy has purchased listingId from creatorProxy,
// and whether creatorProxy has published a valid access grant for that listing.
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
  if (!valid) {
    return { ok: false, reason: 'no valid access grant published for this listing' };
  }

  return { ok: true, paths };
}
