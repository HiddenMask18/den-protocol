// Governance parameter routes (spec §10, §13.4).
//
// GET /governance/params — unauthenticated; returns all on-chain governance parameters.
//   Allows clients and operators to read current protocol values without knowing the
//   governance contract address directly. Values are read live from chain on each call.
//
// type(uint256).max is returned as the string "unlimited" for post_rate_limit tier 3.

import { Hono } from 'hono';
import { governance } from '../chain/contracts.ts';

export const governanceRoutes = new Hono();

const UINT256_MAX = (2n ** 256n) - 1n;

governanceRoutes.get('/params', async (c) => {
  try {
    const [
      walletRotationDelay,
      rotationAnnouncementCooldown,
      handleChangeAllowance,
      handleChangePeriod,
      handleAliasRetentionWindow,
      subscriberProtectionWindow,
      sunsetWindowDuration,
      storageCompensationLookback,
      microMax,
      smallMax,
      mediumMax,
      tier1Threshold,
      tier2Threshold,
      tier3Threshold,
      tierLookbackWindow,
      postSizeLimit0,
      postSizeLimit1,
      postSizeLimit2,
      postSizeLimit3,
      postRateLimit0,
      postRateLimit1,
      postRateLimit2,
      postRateLimit3,
      creatorResponseWindow,
      csamSuspensionDuration,
      feeBps,
      inactivityGracePeriod,
      batchSettlementInterval,
      subscriptionExpiryGracePeriod,
      resolverCacheTtl,
    ] = await Promise.all([
      governance.read.getWalletRotationDelay(),
      governance.read.getRotationAnnouncementCooldown(),
      governance.read.getHandleChangeAllowance(),
      governance.read.getHandleChangePeriod(),
      governance.read.getHandleAliasRetentionWindow(),
      governance.read.getSubscriberProtectionWindow(),
      governance.read.getSunsetWindowDuration(),
      governance.read.getStorageCompensationLookback(),
      governance.read.getMicroMax(),
      governance.read.getSmallMax(),
      governance.read.getMediumMax(),
      governance.read.getTier1Threshold(),
      governance.read.getTier2Threshold(),
      governance.read.getTier3Threshold(),
      governance.read.getTierLookbackWindow(),
      governance.read.getPostSizeLimit([0]),
      governance.read.getPostSizeLimit([1]),
      governance.read.getPostSizeLimit([2]),
      governance.read.getPostSizeLimit([3]),
      governance.read.getPostRateLimit([0]),
      governance.read.getPostRateLimit([1]),
      governance.read.getPostRateLimit([2]),
      governance.read.getPostRateLimit([3]),
      governance.read.getCreatorResponseWindow(),
      governance.read.getCsamSuspensionDuration(),
      governance.read.getFeeBps(),
      governance.read.getInactivityGracePeriod(),
      governance.read.getBatchSettlementInterval(),
      governance.read.getSubscriptionExpiryGracePeriod(),
      governance.read.getResolverCacheTtl(),
    ]);

    return c.json({
      identity: {
        wallet_rotation_delay:           walletRotationDelay.toString(),
        rotation_announcement_cooldown:  rotationAnnouncementCooldown.toString(),
        handle_change_allowance:         handleChangeAllowance.toString(),
        handle_change_period:            handleChangePeriod.toString(),
        handle_alias_retention_window:   handleAliasRetentionWindow.toString(),
      },
      content: {
        subscriber_protection_window: subscriberProtectionWindow.toString(),
        sunset_window_duration:       sunsetWindowDuration.toString(),
      },
      compensation: {
        storage_compensation_lookback: storageCompensationLookback.toString(),
        instance_size_brackets: {
          micro_max:  microMax.toString(),
          small_max:  smallMax.toString(),
          medium_max: mediumMax.toString(),
        },
      },
      trust_tiers: {
        thresholds: {
          tier_1: tier1Threshold.toString(),
          tier_2: tier2Threshold.toString(),
          tier_3: tier3Threshold.toString(),
        },
        lookback_window: tierLookbackWindow === 0n ? 'all-time' : tierLookbackWindow.toString(),
        post_size_limits: {
          tier_0: postSizeLimit0.toString(),
          tier_1: postSizeLimit1.toString(),
          tier_2: postSizeLimit2.toString(),
          tier_3: postSizeLimit3.toString(),
        },
        post_rate_limits: {
          tier_0: postRateLimit0.toString(),
          tier_1: postRateLimit1.toString(),
          tier_2: postRateLimit2.toString(),
          tier_3: postRateLimit3 === UINT256_MAX ? 'unlimited' : postRateLimit3.toString(),
        },
      },
      reporting: {
        creator_response_window:  creatorResponseWindow.toString(),
        csam_suspension_duration: csamSuspensionDuration.toString(),
      },
      fees: {
        protocol_fee_bps: feeBps.toString(),
      },
      misc: {
        inactivity_grace_period:           inactivityGracePeriod.toString(),
        batch_settlement_interval:         batchSettlementInterval.toString(),
        subscription_expiry_grace_period:  subscriptionExpiryGracePeriod.toString(),
        resolver_cache_ttl:                resolverCacheTtl.toString(),
      },
    });
  } catch (err) {
    console.error('[governance] failed to read params from chain', err);
    return c.json({ error: 'failed to read governance parameters from chain' }, 500);
  }
});
