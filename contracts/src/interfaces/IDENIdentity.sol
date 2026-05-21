// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

interface IDENIdentity {
    function isRegistered(address wallet) external view returns (bool);
    function isRegisteredProxy(address proxy) external view returns (bool);
    function getIdentityAddress(address wallet) external view returns (address);
    function getProxy(address wallet) external view returns (address);
    function resolve(string calldata handle) external view returns (address proxy);
    function handleOf(address proxy) external view returns (string memory);
}