// On-chain access checks for subscription and purchase flows.
//
// Every call here is a live chain read — no caching. Subscription state is time-sensitive:
// a subscription can lapse between requests, and the instance must not serve a key to a
// subscriber whose paid period has just expired. The on-chain contract is the sole authority.
//
// Each check has two steps:
//   1. Verify the participant holds the required entitlement (active subscription or purchase).
//   2. Verify the creator has a locally-stored access grant for the requested tier or listing,
//      re-verify its signature against the creator's current primary wallet, and retrieve the
//      derivation paths it covers. Spec §4.1 MUST: signature verification is required before
//      every key derivation — the on-chain verifyGrant() only checks existence, not signature.
//
// The gate returns the derivation paths on success. The access route uses those paths to call
// deriveKey() once per path and return the full set of keys to the subscriber.
//
// Chain errors (RPC failure, timeout) are not caught here. They propagate as thrown errors
// and are handled by the global error handler in index.ts, which returns a 500 response.

import { subscription, purchaseState, getPrimaryWallet } from '../chain/contracts.ts';
import { getGrant, verifyGrantSignature } from '../grants/store.ts';

export type GateResult =
  | { ok: true; paths: readonly string[]; expiry?: bigint }
  | { ok: false; reason: string };

// Checks whether subscriberProxy holds an active subscription to tierId on creatorProxy,
// and whether creatorProxy has a locally-stored, signature-verified access grant for that tier.
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

  const tierIdStr = tierId.toString();
  const grant = getGrant(creatorProxy, tierIdStr);
  if (!grant) {
    return { ok: false, reason: 'no access grant declared for this tier' };
  }

  const primaryWallet = await getPrimaryWallet(creatorProxy);
  const valid = await verifyGrantSignature(grant, primaryWallet);
  if (!valid) {
    return { ok: false, reason: 'access grant signature does not match creator primary wallet' };
  }

  const parsed = JSON.parse(grant.declaration) as { paths: string[] };
  return { ok: true, paths: parsed.paths, expiry };
}

// Checks whether buyerProxy has purchased listingId from creatorProxy,
// and whether creatorProxy has a locally-stored, signature-verified access grant for that listing.
export async function checkPurchaseAccess(
  buyerProxy: `0x${string}`,
  creatorProxy: `0x${string}`,
  listingId: bigint,
): Promise<GateResult> {
  const purchased = await purchaseState.read.hasPurchased([buyerProxy, creatorProxy, listingId]);
  if (!purchased) {
    return { ok: false, reason: 'no purchase record for this listing' };
  }

  const listingIdStr = listingId.toString();
  const grant = getGrant(creatorProxy, listingIdStr);
  if (!grant) {
    return { ok: false, reason: 'no access grant declared for this listing' };
  }

  const primaryWallet = await getPrimaryWallet(creatorProxy);
  const valid = await verifyGrantSignature(grant, primaryWallet);
  if (!valid) {
    return { ok: false, reason: 'access grant signature does not match creator primary wallet' };
  }

  const parsed = JSON.parse(grant.declaration) as { paths: string[] };
  return { ok: true, paths: parsed.paths };
}
