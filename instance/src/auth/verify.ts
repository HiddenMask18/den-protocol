// Verifies a wallet signature and resolves the wallet to its DEN proxy address.
//
// This is the core of the auth system. After verifying the signature, we resolve
// the wallet to a proxy via DENIdentityRegistry. The proxy is what everything else
// in the instance uses as the participant's identity — not the wallet address.
//
// Why work with proxies instead of wallets:
//   Wallets can rotate. If a creator rotates their wallet, their new wallet address
//   is different, but their proxy address stays the same. By resolving to the proxy
//   here, every other module (subscriptions, content, grants) works correctly
//   without knowing or caring about wallet rotation.
//
// The auth flow:
//   consumeNonce()  → validates the nonce was issued and hasn't expired (and deletes it)
//   verifyMessage() → confirms the signature was produced by the claimed wallet
//   isRegistered()  → confirms the wallet is registered in the DEN identity system
//   getProxy()      → resolves the wallet to its stable proxy address

import { verifyMessage } from 'viem';
import { identityRegistry } from '../chain/contracts.ts';
import { consumeNonce } from './nonce.ts';

export type AuthResult =
  | { ok: true; proxy: `0x${string}`; wallet: `0x${string}` }
  | { ok: false; reason: string };

export async function verifyAuth(
  wallet: `0x${string}`,
  nonce: string,
  signature: `0x${string}`,
): Promise<AuthResult> {
  // Validate and consume the nonce. This must happen before signature verification
  // so that even an invalid signature attempt burns the nonce (prevents enumeration).
  if (!consumeNonce(wallet, nonce)) {
    return { ok: false, reason: 'invalid or expired nonce' };
  }

  // Verify that the signature was produced by the claimed wallet address.
  // viem's verifyMessage handles EIP-191 personal_sign prefix automatically —
  // the client signs the raw nonce string, viem verifies it against the prefixed hash.
  let valid: boolean;
  try {
    valid = await verifyMessage({ address: wallet, message: nonce, signature });
  } catch {
    return { ok: false, reason: 'signature verification failed' };
  }

  if (!valid) {
    return { ok: false, reason: 'signature does not match wallet' };
  }

  // Confirm this wallet is registered in the DEN identity system.
  // Unregistered wallets cannot authenticate — they have no proxy and no identity in DEN.
  let registered: boolean;
  try {
    registered = await identityRegistry.read.isRegistered([wallet]);
  } catch {
    return { ok: false, reason: 'could not verify registration status — check chain connectivity' };
  }

  if (!registered) {
    return { ok: false, reason: 'wallet is not registered in DEN' };
  }

  // Resolve the wallet to its stable proxy address.
  let proxy: `0x${string}`;
  try {
    proxy = await identityRegistry.read.getProxy([wallet]);
  } catch {
    return { ok: false, reason: 'could not resolve proxy — check chain connectivity' };
  }

  return { ok: true, proxy, wallet };
}
