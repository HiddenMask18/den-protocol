// Full ABI set for the DEN protocol contracts.
//
// This is the single source of truth. Both the instance server (den-protocol/instance/)
// and the furden client (furden/) import from here. Drift between them is a build error,
// not a runtime failure.
//
// Organisation: each export covers one contract, read and write functions together.
// The instance's original abis.ts re-exports from this file.
//
// Encoding note: `as const` is required for viem to infer precise TypeScript types
// from the ABI. Without it, function names and argument types resolve to `string`.

// ---------------------------------------------------------------------------
// DENIdentityRegistry
// Authoritative registry: maps wallets to their stable proxy address.
// Deploys a per-participant ERC-1967 proxy on register().
// ---------------------------------------------------------------------------
export const identityRegistryAbi = [
  // --- writes ---
  {
    name: 'register',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [],
    outputs: [],
  },
  {
    name: 'setHandle',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [{ name: 'newHandle', type: 'string' }],
    outputs: [],
  },
  {
    name: 'syncWallet',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [{ name: 'proxyAddress', type: 'address' }],
    outputs: [],
  },
  // --- reads ---
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
    name: 'getIdentityAddress',
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
  {
    name: 'resolve',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: 'handle', type: 'string' }],
    outputs: [{ name: 'proxy', type: 'address' }],
  },
  {
    name: 'handleChangeInfo',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: 'proxy', type: 'address' }],
    outputs: [
      { name: 'changeCount', type: 'uint256' },
      { name: 'periodStart', type: 'uint256' },
    ],
  },
  // --- events ---
  {
    name: 'Registered',
    type: 'event',
    inputs: [
      { name: 'wallet', type: 'address', indexed: true },
      { name: 'proxy',  type: 'address', indexed: true },
    ],
  },
  {
    name: 'HandleSet',
    type: 'event',
    inputs: [
      { name: 'proxy',  type: 'address', indexed: true },
      { name: 'handle', type: 'string',  indexed: false },
    ],
  },
] as const;

// ---------------------------------------------------------------------------
// DENIdentityImpl (per-proxy identity contract — call at the proxy address)
// Each participant's proxy IS a deployed DENIdentityImpl instance.
// ---------------------------------------------------------------------------
export const identityImplAbi = [
  // --- writes ---
  {
    name: 'updateInstanceURL',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'url',                    type: 'string'  },
      { name: 'receivingInstanceProxy', type: 'address' },
      { name: 'instanceSig',            type: 'bytes'   },
    ],
    outputs: [],
  },
  {
    name: 'registerEmergencyWallet',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [{ name: 'wallet', type: 'address' }],
    outputs: [],
  },
  {
    name: 'announceEmergencyWalletRevocation',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [{ name: 'wallet', type: 'address' }],
    outputs: [],
  },
  {
    name: 'cancelEmergencyWalletRevocation',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [],
    outputs: [],
  },
  {
    name: 'executeEmergencyWalletRevocation',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [],
    outputs: [],
  },
  {
    name: 'initiateCleanRotation',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'newWallet',    type: 'address' },
      { name: 'newWalletSig', type: 'bytes'   },
    ],
    outputs: [],
  },
  {
    name: 'initiateCompromiseRotation',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [{ name: 'newWallet', type: 'address' }],
    outputs: [],
  },
  {
    name: 'cancelCompromiseRotation',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [],
    outputs: [],
  },
  {
    name: 'executeCompromiseRotation',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [],
    outputs: [],
  },
  {
    name: 'upgradeTo',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [{ name: 'newImplementation', type: 'address' }],
    outputs: [],
  },
  // --- reads ---
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
  {
    name: 'instanceURL',
    type: 'function',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ name: '', type: 'string' }],
  },
  {
    name: 'rotationNonce',
    type: 'function',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ name: '', type: 'uint256' }],
  },
  {
    name: 'pendingRotation',
    type: 'function',
    stateMutability: 'view',
    inputs: [],
    outputs: [
      { name: 'newWallet',    type: 'address' },
      { name: 'executeAfter', type: 'uint256' },
    ],
  },
  {
    name: 'pendingRevocation',
    type: 'function',
    stateMutability: 'view',
    inputs: [],
    outputs: [
      { name: 'wallet',       type: 'address' },
      { name: 'executeAfter', type: 'uint256' },
    ],
  },
  {
    name: 'urlUpdateNonce',
    type: 'function',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ name: '', type: 'uint256' }],
  },
  {
    name: 'lastAnnouncementAt',
    type: 'function',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ name: '', type: 'uint256' }],
  },
  {
    name: 'WALLET_ROTATION_DELAY',
    type: 'function',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ name: '', type: 'uint256' }],
  },
  // --- events ---
  {
    name: 'InstanceURLUpdated',
    type: 'event',
    inputs: [{ name: 'url', type: 'string', indexed: false }],
  },
  {
    name: 'EmergencyWalletRegistered',
    type: 'event',
    inputs: [{ name: 'wallet', type: 'address', indexed: true }],
  },
  {
    name: 'CleanRotationExecuted',
    type: 'event',
    inputs: [
      { name: 'oldWallet', type: 'address', indexed: true },
      { name: 'newWallet', type: 'address', indexed: true },
    ],
  },
  {
    name: 'CompromiseRotationAnnounced',
    type: 'event',
    inputs: [
      { name: 'announcer',    type: 'address', indexed: true  },
      { name: 'newWallet',    type: 'address', indexed: true  },
      { name: 'executeAfter', type: 'uint256', indexed: false },
    ],
  },
] as const;

// ---------------------------------------------------------------------------
// DENSubscription
// Subscription state and tier definitions. subscribe() is payable for ETH tiers.
// ---------------------------------------------------------------------------
export const subscriptionAbi = [
  // --- writes ---
  {
    name: 'setTier',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'tierId',   type: 'uint256' },
      { name: 'price',    type: 'uint256' },
      { name: 'duration', type: 'uint256' },
      { name: 'token',    type: 'address' },
    ],
    outputs: [],
  },
  {
    // payable: pass msg.value for ETH tiers, 0 for ERC-20 (approval required first)
    name: 'subscribe',
    type: 'function',
    stateMutability: 'payable',
    inputs: [
      { name: 'creatorProxy', type: 'address' },
      { name: 'tierId',       type: 'uint256' },
    ],
    outputs: [],
  },
  // --- reads ---
  {
    name: 'isSubscribed',
    type: 'function',
    stateMutability: 'view',
    inputs: [
      { name: 'subscriberProxy', type: 'address' },
      { name: 'creatorProxy',    type: 'address' },
      { name: 'tierId',          type: 'uint256' },
    ],
    outputs: [{ name: '', type: 'bool' }],
  },
  {
    name: 'getSubscriptionExpiry',
    type: 'function',
    stateMutability: 'view',
    inputs: [
      { name: 'subscriberProxy', type: 'address' },
      { name: 'creatorProxy',    type: 'address' },
      { name: 'tierId',          type: 'uint256' },
    ],
    outputs: [{ name: '', type: 'uint256' }],
  },
  {
    name: 'getSubscriptionStart',
    type: 'function',
    stateMutability: 'view',
    inputs: [
      { name: 'subscriberProxy', type: 'address' },
      { name: 'creatorProxy',    type: 'address' },
      { name: 'tierId',          type: 'uint256' },
    ],
    outputs: [{ name: '', type: 'uint256' }],
  },
  {
    name: 'getTierDuration',
    type: 'function',
    stateMutability: 'view',
    inputs: [
      { name: 'creatorProxy', type: 'address' },
      { name: 'tierId',       type: 'uint256' },
    ],
    outputs: [{ name: '', type: 'uint256' }],
  },
  {
    name: 'getTierToken',
    type: 'function',
    stateMutability: 'view',
    inputs: [
      { name: 'creatorProxy', type: 'address' },
      { name: 'tierId',       type: 'uint256' },
    ],
    outputs: [{ name: '', type: 'address' }],
  },
  {
    name: 'getMaxSubscriptionExpiry',
    type: 'function',
    stateMutability: 'view',
    inputs: [
      { name: 'creatorProxy', type: 'address' },
      { name: 'tierId',       type: 'uint256' },
    ],
    outputs: [{ name: '', type: 'uint256' }],
  },
  // --- events ---
  {
    name: 'TierSet',
    type: 'event',
    inputs: [
      { name: 'creatorProxy', type: 'address', indexed: true  },
      { name: 'tierId',       type: 'uint256', indexed: true  },
      { name: 'price',        type: 'uint256', indexed: false },
      { name: 'duration',     type: 'uint256', indexed: false },
      { name: 'token',        type: 'address', indexed: true  },
    ],
  },
  {
    name: 'Subscribed',
    type: 'event',
    inputs: [
      { name: 'subscriberProxy', type: 'address', indexed: true  },
      { name: 'creatorProxy',    type: 'address', indexed: true  },
      { name: 'tierId',          type: 'uint256', indexed: true  },
      { name: 'expiresAt',       type: 'uint256', indexed: false },
    ],
  },
] as const;

// ---------------------------------------------------------------------------
// DENContentRegistry
// Fingerprint lifecycle: Active → Archived → SunsetNoticed → Deleted.
// registerContent() is the primary creator write from the client.
// ---------------------------------------------------------------------------
export const contentRegistryAbi = [
  // --- writes ---
  {
    name: 'registerContent',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'fingerprint', type: 'bytes32' },
      { name: 'tierId',      type: 'uint256' },
    ],
    outputs: [],
  },
  {
    name: 'archiveContent',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [{ name: 'fingerprint', type: 'bytes32' }],
    outputs: [],
  },
  {
    name: 'setContentOperator',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [{ name: 'operatorProxy', type: 'address' }],
    outputs: [],
  },
  // --- reads ---
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
  {
    name: 'getContent',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: 'fingerprint', type: 'bytes32' }],
    outputs: [
      {
        name: '',
        type: 'tuple',
        components: [
          { name: 'creatorProxy',   type: 'address' },
          { name: 'tierId',         type: 'uint256' },
          { name: 'lifecycle',      type: 'uint8'   },
          { name: 'registeredAt',   type: 'uint256' },
          { name: 'sunsetNoticedAt',type: 'uint256' },
          { name: 'deletableAfter', type: 'uint256' },
        ],
      },
    ],
  },
  {
    name: 'getCreatorContent',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: 'creatorProxy', type: 'address' }],
    outputs: [{ name: '', type: 'bytes32[]' }],
  },
  {
    name: 'getContentOperator',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: 'creatorProxy', type: 'address' }],
    outputs: [{ name: '', type: 'address' }],
  },
  // --- events ---
  {
    name: 'ContentRegistered',
    type: 'event',
    inputs: [
      { name: 'creatorProxy', type: 'address', indexed: true },
      { name: 'fingerprint',  type: 'bytes32', indexed: true },
      { name: 'tierId',       type: 'uint256', indexed: false },
    ],
  },
] as const;

// ---------------------------------------------------------------------------
// DENAccessGrant
// Creator-signed declarations mapping tier IDs to derivation paths.
// ---------------------------------------------------------------------------
export const accessGrantAbi = [
  // --- writes ---
  {
    name: 'publishGrant',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'tierId', type: 'uint256'   },
      { name: 'paths',  type: 'string[]'  },
      { name: 'sig',    type: 'bytes'     },
    ],
    outputs: [],
  },
  {
    name: 'revokeGrant',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [{ name: 'tierId', type: 'uint256' }],
    outputs: [],
  },
  // --- reads ---
  {
    name: 'verifyGrant',
    type: 'function',
    stateMutability: 'view',
    inputs: [
      { name: 'creatorProxy', type: 'address' },
      { name: 'tierId',       type: 'uint256' },
    ],
    outputs: [
      { name: 'valid', type: 'bool'     },
      { name: 'paths', type: 'string[]' },
    ],
  },
  {
    name: 'getGrant',
    type: 'function',
    stateMutability: 'view',
    inputs: [
      { name: 'creatorProxy', type: 'address' },
      { name: 'tierId',       type: 'uint256' },
    ],
    outputs: [
      {
        name: '',
        type: 'tuple',
        components: [
          { name: 'derivationPaths', type: 'string[]' },
          { name: 'version',         type: 'uint256'  },
          { name: 'exists',          type: 'bool'     },
          { name: 'signature',       type: 'bytes'    },
        ],
      },
    ],
  },
  // --- events ---
  {
    name: 'GrantPublished',
    type: 'event',
    inputs: [
      { name: 'creatorProxy', type: 'address', indexed: true  },
      { name: 'tierId',       type: 'uint256', indexed: true  },
      { name: 'version',      type: 'uint256', indexed: false },
    ],
  },
] as const;

// ---------------------------------------------------------------------------
// DENPurchaseState
// Permanent purchase records for shop items. Not used in v1 subscriber flows
// (subscription only), but the client calls setListing() and purchase() for
// future one-time sale support.
// ---------------------------------------------------------------------------
export const purchaseStateAbi = [
  // --- writes (v1.x) ---
  {
    name: 'setListing',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'listingId', type: 'uint256' },
      { name: 'price',     type: 'uint256' },
      { name: 'token',     type: 'address' },
    ],
    outputs: [],
  },
  {
    name: 'purchase',
    type: 'function',
    stateMutability: 'payable',
    inputs: [
      { name: 'creatorProxy', type: 'address' },
      { name: 'listingId',    type: 'uint256' },
    ],
    outputs: [],
  },
  // --- reads ---
  {
    name: 'hasPurchased',
    type: 'function',
    stateMutability: 'view',
    inputs: [
      { name: 'buyerProxy',   type: 'address' },
      { name: 'creatorProxy', type: 'address' },
      { name: 'listingId',    type: 'uint256' },
    ],
    outputs: [{ name: '', type: 'bool' }],
  },
  {
    name: 'getListing',
    type: 'function',
    stateMutability: 'view',
    inputs: [
      { name: 'creatorProxy', type: 'address' },
      { name: 'listingId',    type: 'uint256' },
    ],
    outputs: [
      { name: 'price',  type: 'uint256' },
      { name: 'token',  type: 'address' },
      { name: 'exists', type: 'bool'    },
    ],
  },
] as const;

// ---------------------------------------------------------------------------
// DENReportRegistry
// Protocol floor violation reports. fileReport() is the subscriber write.
// isSuspended gates content serving on every key request.
// ---------------------------------------------------------------------------
export const reportRegistryAbi = [
  // --- writes ---
  {
    name: 'fileReport',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'fingerprint',    type: 'bytes32' },
      { name: 'accessTimestamp', type: 'uint256' },
      { name: 'category',       type: 'uint8'   },
      { name: 'evidenceHash',   type: 'bytes32' },
    ],
    outputs: [{ name: 'reportId', type: 'uint256' }],
  },
  // --- reads ---
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
        { name: 'id',                type: 'uint256'  },
        { name: 'fingerprint',       type: 'bytes32'  },
        { name: 'reporterProxy',     type: 'address'  },
        { name: 'accessTimestamp',   type: 'uint256'  },
        { name: 'category',          type: 'uint8'    },
        { name: 'evidenceHash',      type: 'bytes32'  },
        { name: 'status',            type: 'uint8'    },
        { name: 'filedAt',           type: 'uint256'  },
        { name: 'operatorConflict',  type: 'bool'     },
      ],
    }],
  },
  // --- events ---
  {
    name: 'ReportFiled',
    type: 'event',
    inputs: [
      { name: 'reportId',         type: 'uint256', indexed: true  },
      { name: 'fingerprint',      type: 'bytes32', indexed: true  },
      { name: 'reporterProxy',    type: 'address', indexed: true  },
      { name: 'category',         type: 'uint8',   indexed: false },
      { name: 'operatorConflict', type: 'bool',    indexed: false },
    ],
  },
  {
    name: 'ContentSuspended',
    type: 'event',
    inputs: [
      { name: 'fingerprint', type: 'bytes32', indexed: true },
      { name: 'reportId',    type: 'uint256', indexed: true },
    ],
  },
] as const;

// ---------------------------------------------------------------------------
// DENTrustTier
// Read-only for the client: display the creator's tier to surface post limits.
// ---------------------------------------------------------------------------
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

// ---------------------------------------------------------------------------
// DENGovernanceParams
// On-chain governance parameter store. Client reads these at startup to surface
// protocol fee, post size limits, and rotation delay to users.
// ---------------------------------------------------------------------------
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
  { name: 'getTier1Threshold',               type: 'function', stateMutability: 'view', inputs: [], outputs: [{ name: '', type: 'uint256' }] },
  { name: 'getTier2Threshold',               type: 'function', stateMutability: 'view', inputs: [], outputs: [{ name: '', type: 'uint256' }] },
  { name: 'getTier3Threshold',               type: 'function', stateMutability: 'view', inputs: [], outputs: [{ name: '', type: 'uint256' }] },
  { name: 'getSubscriptionExpiryGracePeriod', type: 'function', stateMutability: 'view', inputs: [], outputs: [{ name: '', type: 'uint256' }] },
  { name: 'getCsamSuspensionDuration',       type: 'function', stateMutability: 'view', inputs: [], outputs: [{ name: '', type: 'uint256' }] },
  { name: 'getInactivityGracePeriod',        type: 'function', stateMutability: 'view', inputs: [], outputs: [{ name: '', type: 'uint256' }] },
  { name: 'getResolverCacheTtl',             type: 'function', stateMutability: 'view', inputs: [], outputs: [{ name: '', type: 'uint256' }] },
  { name: 'getMicroMax',                      type: 'function', stateMutability: 'view', inputs: [], outputs: [{ name: '', type: 'uint256' }] },
  { name: 'getSmallMax',                      type: 'function', stateMutability: 'view', inputs: [], outputs: [{ name: '', type: 'uint256' }] },
  { name: 'getMediumMax',                     type: 'function', stateMutability: 'view', inputs: [], outputs: [{ name: '', type: 'uint256' }] },
  { name: 'getTierLookbackWindow',           type: 'function', stateMutability: 'view', inputs: [], outputs: [{ name: '', type: 'uint256' }] },
  { name: 'getBatchSettlementInterval',      type: 'function', stateMutability: 'view', inputs: [], outputs: [{ name: '', type: 'uint256' }] },
  { name: 'getCreatorResponseWindow',        type: 'function', stateMutability: 'view', inputs: [], outputs: [{ name: '', type: 'uint256' }] },
  { name: 'getStorageCompensationLookback',  type: 'function', stateMutability: 'view', inputs: [], outputs: [{ name: '', type: 'uint256' }] },
] as const;

// ---------------------------------------------------------------------------
// DENHostCompensation
// Instance-operator facing. Client only reads getFeePool to display creator
// compensation information in the studio (informational, not a creator action).
// ---------------------------------------------------------------------------
export const compensationAbi = [
  {
    name: 'getFeePool',
    type: 'function',
    stateMutability: 'view',
    inputs: [
      { name: 'creatorProxy', type: 'address' },
      { name: 'token',        type: 'address' },
    ],
    outputs: [{ name: '', type: 'uint256' }],
  },
] as const;

// ---------------------------------------------------------------------------
// IERC20 (minimal)
// Required for ERC-20 token approval before subscribe() on non-ETH tiers.
// ---------------------------------------------------------------------------
export const erc20Abi = [
  {
    name: 'approve',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'spender', type: 'address' },
      { name: 'amount',  type: 'uint256' },
    ],
    outputs: [{ name: '', type: 'bool' }],
  },
  {
    name: 'allowance',
    type: 'function',
    stateMutability: 'view',
    inputs: [
      { name: 'owner',   type: 'address' },
      { name: 'spender', type: 'address' },
    ],
    outputs: [{ name: '', type: 'uint256' }],
  },
  {
    name: 'balanceOf',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: 'account', type: 'address' }],
    outputs: [{ name: '', type: 'uint256' }],
  },
  {
    name: 'decimals',
    type: 'function',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ name: '', type: 'uint8' }],
  },
  {
    name: 'symbol',
    type: 'function',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ name: '', type: 'string' }],
  },
] as const;
