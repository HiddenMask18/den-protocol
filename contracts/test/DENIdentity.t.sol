// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/identity/DENIdentity.sol";

contract DENIdentityTest is Test {
    DENIdentity identity;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function setUp() public {
        identity = new DENIdentity();
    }

    function test_UnregisteredWalletIsNotRegistered() public view {
        assertFalse(identity.isRegistered(alice));
    }

    function test_RegisteredWalletIsRegistered() public {
        vm.prank(alice);
        identity.register();
        assertTrue(identity.isRegistered(alice));
    }

    function test_RegistrationDoesNotAffectOtherWallets() public {
        vm.prank(alice);
        identity.register();
        assertFalse(identity.isRegistered(bob));
    }

    function test_CannotRegisterTwice() public {
        vm.prank(alice);
        identity.register();

        vm.prank(alice);
        vm.expectRevert("Already registered");
        identity.register();
    }

    function test_GetIdentityAddressReturnsWalletForRegistered() public {
        vm.prank(alice);
        identity.register();
        assertEq(identity.getIdentityAddress(alice), alice);
    }

    function test_GetIdentityAddressReturnsZeroForUnregistered() public view {
        assertEq(identity.getIdentityAddress(alice), address(0));
    }

    function test_EmitsRegisteredEvent() public {
        vm.prank(alice);
        vm.expectEmit(true, false, false, false);
        emit DENIdentity.Registered(alice);
        identity.register();
    }
}