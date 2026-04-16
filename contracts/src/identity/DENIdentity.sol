// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "../interfaces/IDENIdentity.sol";

contract DENIdentity is IDENIdentity {

    mapping(address => bool) private _registered;
    mapping(address => address) private _identityAddress;

    event Registered(address indexed wallet);

    function register() external {
        require(!_registered[msg.sender], "Already registered");
        _registered[msg.sender] = true;
        _identityAddress[msg.sender] = msg.sender; // stub: real version deploys proxy
        emit Registered(msg.sender);
    }

    function isRegistered(address wallet) external view returns (bool) {
        return _registered[wallet];
    }

    function getIdentityAddress(address wallet) external view returns (address) {
        return _identityAddress[wallet];
    }
}