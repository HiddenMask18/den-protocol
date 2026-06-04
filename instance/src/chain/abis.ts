// Re-exports from the shared ABI package at den-protocol/abis.ts.
//
// The full ABI set lives one level up so that both the instance server and
// the furden client import from the same source. Drift between the two is
// a build error, not a runtime failure.
//
// Import from here within the instance codebase:
//   import { identityRegistryAbi } from './abis.ts';
//
// Import from furden:
//   import { identityRegistryAbi } from '@den/protocol/abis';

export {
  identityRegistryAbi,
  identityImplAbi,
  subscriptionAbi,
  contentRegistryAbi,
  accessGrantAbi,
  purchaseStateAbi,
  reportRegistryAbi,
  trustTierAbi,
  governanceAbi,
  compensationAbi,
  erc20Abi,
} from '../../../abis.ts';
