// Minimal ABI slices for the five DEN protocol contracts.
//
// An ABI (Application Binary Interface) describes the public functions of a smart contract
// so that off-chain code knows how to encode calls and decode return values. We only include
// the functions the instance actually calls — keeping this file focused makes it easy to see
// exactly what the instance reads from the chain.
//
// Full ABIs live in contracts/out/ (Foundry's build output). If a new function needs to be
// called from the instance, add the ABI entry here.
//
// The `as const` at the end of each array is required for viem to infer precise TypeScript
// types from the ABI — without it, everything would be typed as `string` instead of the
// actual Solidity types.

// DENIdentityRegistry: maps wallets to their stable proxy address.
// The proxy is the canonical DEN identity — it never changes even when the wallet rotates.
export const identityRegistryAbi = [
  {
    name: 'isRegistered',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: 'wallet', type: 'address' }],
    outputs: [{ name: '', type: 'bool' }],
  },
  {
    name: 'isRegisteredProxy',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: 'proxy', type: 'address' }],
    outputs: [{ name: '', type: 'bool' }],
  },
  {
    name: 'getProxy',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: 'wallet', type: 'address' }],
    outputs: [{ name: '', type: 'address' }],
  },
  {
    name: 'handleOf',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: 'proxy', type: 'address' }],
    outputs: [{ name: '', type: 'string' }],
  },
] as const;

// DENSubscription: tracks which subscribers have active paid periods for which creator tiers.
// isSubscribed incorporates expiry — it returns false once the paid period ends.
// TierSet is queried via getLogs to enumerate a creator's tiers for the public profile (spec §6.2) —
// the contract has no enumeration function, so event logs are the only way to discover tier IDs.
export const subscriptionAbi = [
  {
    name: 'isSubscribed',
    type: 'function',
    stateMutability: 'view',
    inputs: [
      { name: 'subscriberProxy', type: 'address' },
      { name: 'creatorProxy', type: 'address' },
      { name: 'tierId', type: 'uint256' },
    ],
    outputs: [{ name: '', type: 'bool' }],
  },
  {
    name: 'getSubscriptionExpiry',
    type: 'function',
    stateMutability: 'view',
    inputs: [
      { name: 'subscriberProxy', type: 'address' },
      { name: 'creatorProxy', type: 'address' },
      { name: 'tierId', type: 'uint256' },
    ],
    outputs: [{ name: '', type: 'uint256' }],
  },
  {
    name: 'TierSet',
    type: 'event',
    inputs: [
      { name: 'creatorProxy', type: 'address', indexed: true },
      { name: 'tierId',       type: 'uint256', indexed: true },
      { name: 'price',        type: 'uint256', indexed: false },
      { name: 'duration',     type: 'uint256', indexed: false },
      { name: 'token',        type: 'address', indexed: true },
    ],
  },
] as const;

// DENPurchaseState: permanent purchase records for shop items and packs.
// Unlike subscriptions, purchases never expire — hasPurchased returns true indefinitely.
export const purchaseStateAbi = [
  {
    name: 'hasPurchased',
    type: 'function',
    stateMutability: 'view',
    inputs: [
      { name: 'buyerProxy', type: 'address' },
      { name: 'creatorProxy', type: 'address' },
      { name: 'listingId', type: 'uint256' },
    ],
    outputs: [{ name: '', type: 'bool' }],
  },
] as const;

// DENAccessGrant: stores creator-signed declarations that map tier IDs to derivation paths.
// verifyGrant checks the on-chain signature and returns the paths if valid.
// getGrant returns the full grant struct including the stored signature (for migration use).
export const accessGrantAbi = [
  {
    name: 'verifyGrant',
    type: 'function',
    stateMutability: 'view',
    inputs: [
      { name: 'creatorProxy', type: 'address' },
      { name: 'tierId', type: 'uint256' },
    ],
    outputs: [
      { name: 'valid', type: 'bool' },
      { name: 'paths', type: 'string[]' },
    ],
  },
  {
    name: 'getGrant',
    type: 'function',
    stateMutability: 'view',
    inputs: [
      { name: 'creatorProxy', type: 'address' },
      { name: 'tierId', type: 'uint256' },
    ],
    outputs: [
      {
        name: '',
        type: 'tuple',
        components: [
          { name: 'derivationPaths', type: 'string[]' },
          { name: 'version', type: 'uint256' },
          { name: 'exists', type: 'bool' },
          { name: 'signature', type: 'bytes' },
        ],
      },
    ],
  },
] as const;

// DENIdentityImpl: the per-proxy identity contract deployed for each registered participant.
// Each proxy IS a deployed DENIdentityImpl instance — call it directly at the proxy address.
// Used to read the creator's current primary wallet for access grant signature verification.
export const identityImplAbi = [
  {
    name: 'primaryWallet',
    type: 'function',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ name: '', type: 'address' }],
  },
  {
    name: 'isEmergencyWallet',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: 'wallet', type: 'address' }],
    outputs: [{ name: '', type: 'bool' }],
  },
] as const;

// DENHostCompensation: per-creator fee escrow; hoster claims resource compensation each settlement interval.
export const compensationAbi = [
  {
    name: 'claimCompensation',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'creatorProxy', type: 'address' },
      { name: 'token', type: 'address' },
      { name: 'storageGB', type: 'uint256' },
      { name: 'bandwidthGB', type: 'uint256' },
      { name: 'instanceSize', type: 'uint256' },
      { name: 'subscriberCount', type: 'uint256' },
    ],
    outputs: [],
  },
  {
    name: 'getFeePool',
    type: 'function',
    stateMutability: 'view',
    inputs: [
      { name: 'creatorProxy', type: 'address' },
      { name: 'token', type: 'address' },
    ],
    outputs: [{ name: '', type: 'uint256' }],
  },
  {
    // instanceSize and subscriberCount declared by hoster, emitted for on-chain audit (spec §7.3).
    name: 'CompensationClaimed',
    type: 'event',
    inputs: [
      { name: 'hosterProxy',     type: 'address', indexed: true },
      { name: 'creatorProxy',    type: 'address', indexed: true },
      { name: 'token',           type: 'address', indexed: true },
      { name: 'hosterClaim',     type: 'uint256', indexed: false },
      { name: 'creatorSurplus',  type: 'uint256', indexed: false },
      { name: 'instanceSize',    type: 'uint256', indexed: false },
      { name: 'subscriberCount', type: 'uint256', indexed: false },
    ],
  },
] as const;

// DENReportRegistry: protocol floor violation reports (CSAM, NON_CONSENT).
// isSuspended is checked on every content request before serving ciphertext (spec §12.3).
// Operator determination routes use determineReport, setLawEnforcementHold, removeLawEnforcementHold.
// reinstateAfterCsamExpiry is permissionless — any caller may trigger it after the suspension period.
//
// Enums encoded as uint8 in ABI:
//   ViolationCategory: 0=CSAM, 1=NON_CONSENT
//   ReportStatus:      0=Active, 1=Upheld, 2=Dismissed, 3=FalseReport, 4=Reinstated
export const reportRegistryAbi = [
  {
    name: 'isSuspended',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: 'fingerprint', type: 'bytes32' }],
    outputs: [{ name: '', type: 'bool' }],
  },
  {
    name: 'getReport',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: 'reportId', type: 'uint256' }],
    outputs: [{
      name: '',
      type: 'tuple',
      components: [
        { name: 'id', type: 'uint256' },
        { name: 'fingerprint', type: 'bytes32' },
        { name: 'reporterProxy', type: 'address' },
        { name: 'accessTimestamp', type: 'uint256' },
        { name: 'category', type: 'uint8' },
        { name: 'evidenceHash', type: 'bytes32' },
        { name: 'status', type: 'uint8' },
        { name: 'filedAt', type: 'uint256' },
        { name: 'operatorConflict', type: 'bool' },
      ],
    }],
  },
  {
    name: 'determineReport',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'reportId', type: 'uint256' },
      { name: 'outcome', type: 'uint8' },
    ],
    outputs: [],
  },
  {
    name: 'setLawEnforcementHold',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [{ name: 'reportId', type: 'uint256' }],
    outputs: [],
  },
  {
    name: 'removeLawEnforcementHold',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [{ name: 'reportId', type: 'uint256' }],
    outputs: [],
  },
  {
    name: 'reinstateAfterCsamExpiry',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [{ name: 'reportId', type: 'uint256' }],
    outputs: [],
  },
  {
    name: 'ReportDetermined',
    type: 'event',
    inputs: [
      { name: 'reportId', type: 'uint256', indexed: true },
      { name: 'outcome', type: 'uint8', indexed: false },
    ],
  },
  {
    name: 'LawEnforcementHoldSet',
    type: 'event',
    inputs: [{ name: 'reportId', type: 'uint256', indexed: true }],
  },
  {
    name: 'LawEnforcementHoldRemoved',
    type: 'event',
    inputs: [{ name: 'reportId', type: 'uint256', indexed: true }],
  },
] as const;

// DENTrustTier: tracks verified distinct participant counts for creator tier graduation (spec §9).
// getTier returns the creator's current tier (0–3); the instance enforces storage and rate limits
// based on this value. Tier 0 is the new-creator baseline — sufficient for normal creative output.
export const trustTierAbi = [
  {
    name: 'getTier',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: 'creatorProxy', type: 'address' }],
    outputs: [{ name: '', type: 'uint8' }],
  },
  {
    name: 'getQualifiedCount',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: 'creatorProxy', type: 'address' }],
    outputs: [{ name: '', type: 'uint256' }],
  },
] as const;

// DENGovernanceParams: on-chain governance parameter store (spec §10, §13.4).
// All governance parameters adjustable through the community approval process are readable here.
// The instance reads post_size_limits and post_rate_limits from this contract to enforce
// creator upload limits dynamically rather than relying on hardcoded constants.
export const governanceAbi = [
  { name: 'getPostSizeLimit',                type: 'function', stateMutability: 'view', inputs: [{ name: 'tier', type: 'uint8' }], outputs: [{ name: '', type: 'uint256' }] },
  { name: 'getPostRateLimit',                type: 'function', stateMutability: 'view', inputs: [{ name: 'tier', type: 'uint8' }], outputs: [{ name: '', type: 'uint256' }] },
  { name: 'getFeeBps',                       type: 'function', stateMutability: 'view', inputs: [], outputs: [{ name: '', type: 'uint256' }] },
  { name: 'getWalletRotationDelay',          type: 'function', stateMutability: 'view', inputs: [], outputs: [{ name: '', type: 'uint256' }] },
  { name: 'getRotationAnnouncementCooldown', type: 'function', stateMutability: 'view', inputs: [], outputs: [{ name: '', type: 'uint256' }] },
  { name: 'getHandleChangeAllowance',        type: 'function', stateMutability: 'view', inputs: [], outputs: [{ name: '', type: 'uint256' }] },
  { name: 'getHandleChangePeriod',           type: 'function', stateMutability: 'view', inputs: [], outputs: [{ name: '', type: 'uint256' }] },
  { name: 'getHandleAliasRetentionWindow',   type: 'function', stateMutability: 'view', inputs: [], outputs: [{ name: '', type: 'uint256' }] },
  { name: 'getSubscriberProtectionWindow',   type: 'function', stateMutability: 'view', inputs: [], outputs: [{ name: '', type: 'uint256' }] },
  { name: 'getSunsetWindowDuration',         type: 'function', stateMutability: 'view', inputs: [], outputs: [{ name: '', type: 'uint256' }] },
  { name: 'getStorageCompensationLookback',  type: 'function', stateMutability: 'view', inputs: [], outputs: [{ name: '', type: 'uint256' }] },
  { name: 'getMicroMax',                     type: 'function', stateMutability: 'view', inputs: [], outputs: [{ name: '', type: 'uint256' }] },
  { name: 'getSmallMax',                     type: 'function', stateMutability: 'view', inputs: [], outputs: [{ name: '', type: 'uint256' }] },
  { name: 'getMediumMax',                    type: 'function', stateMutability: 'view', inputs: [], outputs: [{ name: '', type: 'uint256' }] },
  { name: 'getTier1Threshold',               type: 'function', stateMutability: 'view', inputs: [], outputs: [{ name: '', type: 'uint256' }] },
  { name: 'getTier2Threshold',               type: 'function', stateMutability: 'view', inputs: [], outputs: [{ name: '', type: 'uint256' }] },
  { name: 'getTier3Threshold',               type: 'function', stateMutability: 'view', inputs: [], outputs: [{ name: '', type: 'uint256' }] },
  { name: 'getTierLookbackWindow',           type: 'function', stateMutability: 'view', inputs: [], outputs: [{ name: '', type: 'uint256' }] },
  { name: 'getCreatorResponseWindow',        type: 'function', stateMutability: 'view', inputs: [], outputs: [{ name: '', type: 'uint256' }] },
  { name: 'getCsamSuspensionDuration',       type: 'function', stateMutability: 'view', inputs: [], outputs: [{ name: '', type: 'uint256' }] },
  { name: 'getInactivityGracePeriod',        type: 'function', stateMutability: 'view', inputs: [], outputs: [{ name: '', type: 'uint256' }] },
  { name: 'getBatchSettlementInterval',      type: 'function', stateMutability: 'view', inputs: [], outputs: [{ name: '', type: 'uint256' }] },
  { name: 'getSubscriptionExpiryGracePeriod', type: 'function', stateMutability: 'view', inputs: [], outputs: [{ name: '', type: 'uint256' }] },
  { name: 'getResolverCacheTtl',             type: 'function', stateMutability: 'view', inputs: [], outputs: [{ name: '', type: 'uint256' }] },
] as const;

// DENContentRegistry: tracks content fingerprints and their lifecycle states.
// hasActiveSunset is used by the access gate — when a creator has an active sunset notice,
// the instance should not accept new subscriptions (the contracts already enforce this, but
// the instance can check proactively to give better error messages).
export const contentRegistryAbi = [
  {
    name: 'isContentActive',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: 'fingerprint', type: 'bytes32' }],
    outputs: [{ name: '', type: 'bool' }],
  },
  {
    name: 'hasActiveSunset',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: 'creatorProxy', type: 'address' }],
    outputs: [{ name: '', type: 'bool' }],
  },
] as const;
