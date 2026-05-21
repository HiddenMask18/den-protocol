// Typed contract instances for the five DEN protocol contracts.
//
// A "contract instance" in viem is just an object that bundles together a contract's address,
// its ABI, and a client. Once you have one, you can call any read function on it without
// having to pass the address and ABI every time:
//
//   const proxy = await identityRegistry.read.getProxy([walletAddress])
//
// Contract addresses are loaded from environment variables. If any address is missing or
// malformed, the instance exits immediately at startup with a clear error — better to fail
// fast at boot than to produce confusing errors at request time.

import { getContract } from 'viem';
import { chainClient } from './client.ts';
import {
  accessGrantAbi,
  compensationAbi,
  contentRegistryAbi,
  identityImplAbi,
  identityRegistryAbi,
  purchaseStateAbi,
  subscriptionAbi,
} from './abis.ts';

function requireAddress(envVar: string): `0x${string}` {
  const addr = process.env[envVar];
  if (!addr || !addr.startsWith('0x') || addr.length !== 42) {
    throw new Error(
      `Environment variable ${envVar} must be a 0x-prefixed Ethereum address (42 chars). ` +
      `Deploy the contracts and set this value in your .env file.`,
    );
  }
  return addr as `0x${string}`;
}

export const identityRegistry = getContract({
  address: requireAddress('IDENTITY_REGISTRY_ADDRESS'),
  abi: identityRegistryAbi,
  client: chainClient,
});

export const subscription = getContract({
  address: requireAddress('SUBSCRIPTION_ADDRESS'),
  abi: subscriptionAbi,
  client: chainClient,
});

export const purchaseState = getContract({
  address: requireAddress('PURCHASE_STATE_ADDRESS'),
  abi: purchaseStateAbi,
  client: chainClient,
});

export const accessGrant = getContract({
  address: requireAddress('ACCESS_GRANT_ADDRESS'),
  abi: accessGrantAbi,
  client: chainClient,
});

export const contentRegistry = getContract({
  address: requireAddress('CONTENT_REGISTRY_ADDRESS'),
  abi: contentRegistryAbi,
  client: chainClient,
});

export const compensation = getContract({
  address: requireAddress('COMPENSATION_ADDRESS'),
  abi: compensationAbi,
  client: chainClient,
});

// Each creator's proxy IS a deployed DENIdentityImpl contract — call it directly at the proxy
// address to read live identity state. Used by the creator tooling routes to fetch the current
// primary wallet for access grant signature verification.
export async function getPrimaryWallet(proxyAddress: `0x${string}`): Promise<`0x${string}`> {
  return chainClient.readContract({
    address: proxyAddress,
    abi: identityImplAbi,
    functionName: 'primaryWallet',
  });
}

export async function getIsEmergencyWallet(proxyAddress: `0x${string}`, wallet: `0x${string}`): Promise<boolean> {
  return chainClient.readContract({
    address: proxyAddress,
    abi: identityImplAbi,
    functionName: 'isEmergencyWallet',
    args: [wallet],
  });
}
