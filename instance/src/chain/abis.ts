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
] as const;

// DENSubscription: tracks which subscribers have active paid periods for which creator tiers.
// isSubscribed incorporates expiry — it returns false once the paid period ends.
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
