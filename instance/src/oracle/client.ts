// Creator oracle client — DORMANT (V1 does not use the oracle model).
//
// This file is retained for reference and as a V2 starting point. The threshold-split oracle
// design was removed from V1 for the following reasons:
//
//   1. Organisational separation cannot be cryptographically enforced.
//      The oracle relies on the creator operating an independent service. Nothing in the
//      protocol prevents a compliant or compromised hoster from running the oracle themselves,
//      silently collapsing the "two-party" split into one.
//
//   2. Creator liveness creates a single point of failure.
//      If the creator's oracle is offline or deleted, all subscribers lose decryption access
//      immediately. The cure is worse than the disease — a jurisdiction-ordered takedown of
//      the instance would still achieve its goal by targeting the oracle instead.
//
//   3. The problem is jurisdictional availability, not key custodianship.
//      The actual defense against legal compulsion is: (a) E2EE at rest so the hoster stores
//      only ciphertext; (b) portability so a creator can migrate to a different jurisdiction
//      in hours; (c) key rotation so a seized instance's copy of the blob becomes useless.
//      Adding an organisational split on top of that does not strengthen these guarantees.
//
// V2 path: if threshold decryption with a decentralised custodian network (e.g. Lit Protocol
// or Medusa Network) becomes production-ready, the oracle design should be revisited using
// cryptographically enforced access policies rather than per-creator HTTP services.
//
// Nothing in V1 imports this file.

import { fromHex } from 'viem';

export type OracleRequest =
  | { type: 'subscription'; subscriberProxy: string; creatorProxy: string; tierId: string }
  | { type: 'purchase'; buyerProxy: string; creatorProxy: string; listingId: string };

export class OracleError extends Error {
  constructor(
    message: string,
    public readonly status?: number,
  ) {
    super(message);
    this.name = 'OracleError';
  }
}

// 5-minute cache keyed by (creatorProxy, subscriberProxy/buyerProxy, tierId/listingId).
//
// creator_share is cryptographically the same for all tiers of a creator, but the oracle
// performs an independent per-request entitlement check — it verifies that THIS subscriber
// holds THIS specific tier before returning the share. Caching by creatorProxy alone would
// allow a cached response from subscriber A to serve subscriber B without an oracle check,
// bypassing the oracle's authorization entirely.
//
// Spec gap (§4.1): the spec says "oracle offline immediately prevents new key derivations."
// Strict compliance requires zero caching — any TTL creates a bounded window (5 min max)
// where cached entries survive after the oracle goes offline. The per-entitlement key
// minimizes blast radius: only subscribers who made a recent successful request are affected,
// and only for that specific creator+tier combination.
type CacheEntry = { share: Uint8Array; expiresAt: number };
const shareCache = new Map<string, CacheEntry>();

const CACHE_TTL_MS = 5 * 60 * 1000; // 5 minutes
const ORACLE_TIMEOUT_MS = 10_000;    // 10 seconds — oracle should respond quickly

function cacheKey(request: OracleRequest): string {
  if (request.type === 'subscription') {
    return `${request.creatorProxy.toLowerCase()}:${request.subscriberProxy.toLowerCase()}:${request.tierId}`;
  }
  return `${request.creatorProxy.toLowerCase()}:${request.buyerProxy.toLowerCase()}:${request.listingId}`;
}

function getCached(request: OracleRequest): Uint8Array | null {
  const key = cacheKey(request);
  const entry = shareCache.get(key);
  if (!entry) return null;
  if (Date.now() > entry.expiresAt) {
    shareCache.delete(key);
    return null;
  }
  return entry.share;
}

function setCache(request: OracleRequest, share: Uint8Array): void {
  shareCache.set(cacheKey(request), {
    share,
    expiresAt: Date.now() + CACHE_TTL_MS,
  });
}

// Fetches creator_share from the creator's oracle for the given entitlement context.
// Returns a 32-byte Uint8Array.
// Throws OracleError if the oracle rejects the request, is unreachable, or returns
// a malformed response.
export async function fetchCreatorShare(
  oracleUrl: string,
  request: OracleRequest,
): Promise<Uint8Array> {
  const cached = getCached(request);
  if (cached) return cached;

  let response: Response;
  try {
    response = await fetch(`${oracleUrl.replace(/\/$/, '')}/share`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(request),
      signal: AbortSignal.timeout(ORACLE_TIMEOUT_MS),
    });
  } catch (err) {
    throw new OracleError(
      `oracle unreachable at ${oracleUrl}: ${(err as Error).message}`,
    );
  }

  if (response.status === 403) {
    throw new OracleError('oracle denied request — on-chain entitlement check failed', 403);
  }
  if (!response.ok) {
    throw new OracleError(`oracle returned unexpected status ${response.status}`, response.status);
  }

  let body: unknown;
  try {
    body = await response.json();
  } catch {
    throw new OracleError('oracle returned non-JSON response');
  }

  if (
    !body ||
    typeof body !== 'object' ||
    !('share' in body) ||
    typeof (body as Record<string, unknown>).share !== 'string'
  ) {
    throw new OracleError('oracle response missing "share" field');
  }

  const shareHex = (body as { share: string }).share;
  let shareBytes: Uint8Array;
  try {
    shareBytes = fromHex(shareHex as `0x${string}`, 'bytes');
  } catch {
    throw new OracleError('oracle share is not valid hex');
  }

  if (shareBytes.length !== 32) {
    throw new OracleError(
      `oracle share must be 32 bytes, got ${shareBytes.length}`,
    );
  }

  setCache(request, shareBytes);
  return shareBytes;
}
