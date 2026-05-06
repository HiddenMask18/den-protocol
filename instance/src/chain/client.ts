// Creates a viem publicClient — the instance's read-only connection to the Ethereum chain.
//
// Key design point: the instance NEVER signs transactions. Creators and subscribers sign
// their own transactions from their own wallets. The instance only reads state from the
// contracts to answer questions like "is this subscriber currently active?" or "is this
// wallet registered?". A publicClient is exactly that — read-only chain access.
//
// For local development, CHAIN=anvil connects to Foundry's local anvil node (port 8545).
// For production, CHAIN=base connects to Base mainnet. The RPC_URL controls the endpoint.

import { createPublicClient, http } from 'viem';
import { anvil, base } from 'viem/chains';

const rpcUrl = process.env.RPC_URL ?? 'http://localhost:8545';
const chainName = process.env.CHAIN ?? 'anvil';

const chain = chainName === 'base' ? base : anvil;

export const chainClient = createPublicClient({
  chain,
  transport: http(rpcUrl),
});
