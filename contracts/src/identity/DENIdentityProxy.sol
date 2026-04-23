// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

// Minimal ERC-1967 proxy deployed once per participant by DENIdentityRegistry.
// All identity state lives in this contract's storage; logic is delegatecalled
// to DENIdentityImpl (or any upgraded implementation the participant installs).
// The participant's primary wallet controls upgrades via DENIdentityImpl.upgradeTo().
contract DENIdentityProxy {

    // ERC-1967 implementation slot: keccak256("eip1967.proxy.implementation") - 1
    bytes32 internal constant _IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    constructor(address implementation, bytes memory initData) {
        require(implementation != address(0), "Zero implementation");
        assembly {
            sstore(
                0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc,
                implementation
            )
        }
        if (initData.length > 0) {
            (bool success, bytes memory reason) = implementation.delegatecall(initData);
            if (!success) {
                assembly { revert(add(reason, 32), mload(reason)) }
            }
        }
    }

    fallback() external payable {
        assembly {
            let impl := sload(0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc)
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), impl, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }

    receive() external payable {}
}
