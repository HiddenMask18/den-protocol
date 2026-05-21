// Hoster management routes — operator-only endpoints for compensation settlement.
//
// POST /hoster/claim
//   Submit a resource compensation claim for a single creator. The instance signs and
//   broadcasts the DENHostCompensation.claimCompensation transaction. storageGB,
//   bandwidthGB, and instanceSize are declared by the hoster (spec §7.3
//   declared-plus-auditable). The on-chain contract applies the progressive rate formula,
//   transfers the hoster's claim, and returns any surplus to the creator's primary wallet.
//
// Auth: the session wallet must match operatorAccount.address — only the wallet that holds
// INSTANCE_OPERATOR_PRIVATE_KEY may trigger a settlement.

import { Hono } from 'hono';
import { isAddress, parseEventLogs } from 'viem';
import { requireAuth } from '../auth/middleware.ts';
import { operatorAccount, walletClient } from '../chain/wallet.ts';
import { chainClient } from '../chain/client.ts';
import { compensation } from '../chain/contracts.ts';
import { compensationAbi } from '../chain/abis.ts';

type SessionEnv = {
  Variables: { proxy: string; wallet: string };
};

export const hosterRoutes = new Hono<SessionEnv>();

// Claim resource compensation for one creator.
// Body: { creatorProxy, token?, storageGB, bandwidthGB, instanceSize }
//   creatorProxy  — the creator's DEN proxy address
//   token         — ERC-20 token address, or omit/null for native ETH
//   storageGB     — declared storage consumed in GB (non-negative integer)
//   bandwidthGB   — declared bandwidth served in GB (non-negative integer)
//   instanceSize  — declared instance size = creator_count + subscription_relationship_count,
//                   same-instance relationships excluded (spec §9.3)
hosterRoutes.post('/claim', requireAuth, async (c) => {
  const sessionWallet = c.get('wallet');
  if (sessionWallet.toLowerCase() !== operatorAccount.address.toLowerCase()) {
    return c.json({ error: 'forbidden: only the instance operator wallet may claim compensation' }, 403);
  }

  const body = await c.req.json().catch(() => null);
  if (!body) return c.json({ error: 'invalid JSON body' }, 400);

  const { creatorProxy, token, storageGB, bandwidthGB, instanceSize } = body;

  if (!creatorProxy || !isAddress(creatorProxy)) {
    return c.json({ error: 'invalid creatorProxy' }, 400);
  }
  const tokenAddr: `0x${string}` = token && isAddress(token)
    ? token
    : '0x0000000000000000000000000000000000000000';

  if (typeof storageGB !== 'number' || !Number.isInteger(storageGB) || storageGB < 0) {
    return c.json({ error: 'storageGB must be a non-negative integer' }, 400);
  }
  if (typeof bandwidthGB !== 'number' || !Number.isInteger(bandwidthGB) || bandwidthGB < 0) {
    return c.json({ error: 'bandwidthGB must be a non-negative integer' }, 400);
  }
  if (typeof instanceSize !== 'number' || !Number.isInteger(instanceSize) || instanceSize < 0) {
    return c.json({ error: 'instanceSize must be a non-negative integer' }, 400);
  }

  // Pre-check fee pool to catch the empty-pool case before spending gas.
  const pool = await compensation.read.getFeePool([creatorProxy as `0x${string}`, tokenAddr]);
  if (pool === 0n) {
    return c.json({ error: 'fee pool is empty for this creator and token' }, 400);
  }

  const hash = await walletClient.writeContract({
    address: compensation.address,
    abi: compensationAbi,
    functionName: 'claimCompensation',
    args: [
      creatorProxy as `0x${string}`,
      tokenAddr,
      BigInt(storageGB),
      BigInt(bandwidthGB),
      BigInt(instanceSize),
    ],
  });

  const receipt = await chainClient.waitForTransactionReceipt({ hash });

  const logs = parseEventLogs({
    abi: compensationAbi,
    eventName: 'CompensationClaimed',
    logs: receipt.logs,
  });
  const event = logs[0]?.args;

  return c.json({
    txHash: hash,
    hostedAmount: event?.hosterClaim?.toString() ?? '0',
    surplusAmount: event?.creatorSurplus?.toString() ?? '0',
  });
});
