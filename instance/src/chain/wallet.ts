// Instance operator wallet — used exclusively for signing claimCompensation transactions.
//
// The instance reads chain state with a publicClient (client.ts) and NEVER signs creator or
// subscriber transactions. This file is the single exception: the hoster's operator wallet
// signs DENHostCompensation.claimCompensation settlements on their behalf (spec §7.2).
//
// The corresponding wallet address must be registered as a DEN participant and set as the
// content operator for each hosted creator via DENContentRegistry.setContentOperator.
//
// Fails at startup if INSTANCE_OPERATOR_PRIVATE_KEY is missing or malformed — better than
// a confusing error when the first claim is attempted.

import { createWalletClient, http } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { anvil, base } from 'viem/chains';

const rpcUrl = process.env.RPC_URL ?? 'http://localhost:8545';
const chain = (process.env.CHAIN ?? 'anvil') === 'base' ? base : anvil;

const rawKey = process.env.INSTANCE_OPERATOR_PRIVATE_KEY;
if (!rawKey || !rawKey.startsWith('0x') || rawKey.length !== 66) {
  throw new Error(
    'INSTANCE_OPERATOR_PRIVATE_KEY must be a 0x-prefixed 32-byte hex private key (66 chars). ' +
    'Generate with: openssl rand -hex 32 (then prepend 0x).',
  );
}

export const operatorAccount = privateKeyToAccount(rawKey as `0x${string}`);

export const walletClient = createWalletClient({
  account: operatorAccount,
  chain,
  transport: http(rpcUrl),
});
