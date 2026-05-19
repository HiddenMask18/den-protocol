// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/identity/DENIdentityImpl.sol";
import "../src/identity/DENIdentityRegistry.sol";
import "../src/interfaces/IDENParticipantIdentity.sol";
import "../src/purchase/DENPurchaseState.sol";
import "../src/content/DENContentRegistry.sol";
import "../src/subscription/DENSubscription.sol";
import "./mocks/MockERC20.sol";

contract DENPurchaseStateTest is Test {
    DENIdentityImpl impl;
    DENIdentityRegistry registry;
    DENPurchaseState purchaseState;
    MockERC20 token;

    uint256 aliceKey;
    address alice;
    uint256 bobKey;
    address bob;
    address carol;

    address aliceProxy;
    address bobProxy;

    uint256 constant LISTING_ID = 1;
    uint256 constant PRICE = 1 ether;

    function setUp() public {
        (alice, aliceKey) = makeAddrAndKey("alice");
        (bob, bobKey) = makeAddrAndKey("bob");
        carol = makeAddr("carol");

        impl = new DENIdentityImpl();
        registry = new DENIdentityRegistry(address(impl));
        purchaseState = new DENPurchaseState(address(registry));
        token = new MockERC20();

        vm.prank(alice);
        registry.register();
        aliceProxy = registry.getProxy(alice);

        vm.prank(bob);
        registry.register();
        bobProxy = registry.getProxy(bob);

        // ETH listing set up by default.
        vm.prank(alice);
        purchaseState.setListing(LISTING_ID, PRICE, address(0));

        vm.deal(bob, 10 ether);
    }

    // --- setListing ---

    function test_UnregisteredCannotSetListing() public {
        vm.prank(carol);
        vm.expectRevert("Not registered");
        purchaseState.setListing(LISTING_ID, PRICE, address(0));
    }

    function test_NonPrimaryWalletCannotSetListing() public {
        (address alice2, uint256 alice2Key) = makeAddrAndKey("alice2");
        uint256 nonce = IDENParticipantIdentity(aliceProxy).rotationNonce();
        bytes32 structHash = keccak256(abi.encode("DEN-clean-rotation", aliceProxy, nonce));
        bytes32 ethHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alice2Key, ethHash);
        vm.prank(alice);
        IDENParticipantIdentity(aliceProxy).initiateCleanRotation(alice2, abi.encodePacked(r, s, v));

        vm.prank(alice);
        vm.expectRevert("Not primary wallet");
        purchaseState.setListing(2, PRICE, address(0));
    }

    function test_ListingPriceMustBeNonzero() public {
        vm.prank(alice);
        vm.expectRevert("Price must be nonzero");
        purchaseState.setListing(2, 0, address(0));
    }

    function test_SetListingSucceeds() public {
        vm.prank(alice);
        purchaseState.setListing(2, 0.5 ether, address(0));
        (uint256 price, address tok, bool exists) = purchaseState.getListing(aliceProxy, 2);
        assertEq(price, 0.5 ether);
        assertEq(tok, address(0));
        assertTrue(exists);
    }

    function test_SetListingWithTokenSucceeds() public {
        vm.prank(alice);
        purchaseState.setListing(2, PRICE, address(token));
        (uint256 price, address tok, bool exists) = purchaseState.getListing(aliceProxy, 2);
        assertEq(price, PRICE);
        assertEq(tok, address(token));
        assertTrue(exists);
    }

    function test_CreatorCanUpdateListingPrice() public {
        vm.prank(alice);
        purchaseState.setListing(LISTING_ID, 2 ether, address(0));
        (uint256 price, , bool exists) = purchaseState.getListing(aliceProxy, LISTING_ID);
        assertEq(price, 2 ether);
        assertTrue(exists);
    }

    function test_PriceUpdateDoesNotAffectExistingPurchases() public {
        vm.prank(bob);
        purchaseState.purchase{value: PRICE}(aliceProxy, LISTING_ID);

        vm.prank(alice);
        purchaseState.setListing(LISTING_ID, 2 ether, address(0));

        assertTrue(purchaseState.hasPurchased(bobProxy, aliceProxy, LISTING_ID));
    }

    function test_EmitsListingSetEvent() public {
        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit DENPurchaseState.ListingSet(aliceProxy, 2, 0.5 ether, address(0));
        purchaseState.setListing(2, 0.5 ether, address(0));
    }

    function test_GetListingReturnsCorrectValues() public view {
        (uint256 price, address tok, bool exists) = purchaseState.getListing(aliceProxy, LISTING_ID);
        assertEq(price, PRICE);
        assertEq(tok, address(0));
        assertTrue(exists);
    }

    function test_GetListingReturnsFalseForUnsetListing() public view {
        (, , bool exists) = purchaseState.getListing(aliceProxy, 99);
        assertFalse(exists);
    }

    // --- purchase (ETH) ---

    function test_PurchaseSucceeds() public {
        vm.prank(bob);
        purchaseState.purchase{value: PRICE}(aliceProxy, LISTING_ID);
        assertTrue(purchaseState.hasPurchased(bobProxy, aliceProxy, LISTING_ID));
    }

    function test_PurchaseTimestampIsRecorded() public {
        uint256 ts = block.timestamp;
        vm.prank(bob);
        purchaseState.purchase{value: PRICE}(aliceProxy, LISTING_ID);
        assertEq(purchaseState.getPurchaseTimestamp(bobProxy, aliceProxy, LISTING_ID), ts);
    }

    function test_UnregisteredBuyerCannotPurchase() public {
        vm.deal(carol, 10 ether);
        vm.prank(carol);
        vm.expectRevert("Buyer not registered");
        purchaseState.purchase{value: PRICE}(aliceProxy, LISTING_ID);
    }

    function test_CannotPurchaseFromUnregisteredProxy() public {
        vm.prank(bob);
        vm.expectRevert("Creator proxy not registered");
        purchaseState.purchase{value: PRICE}(carol, LISTING_ID);
    }

    function test_CannotPurchaseNonexistentListing() public {
        vm.prank(bob);
        vm.expectRevert("Listing does not exist");
        purchaseState.purchase{value: PRICE}(aliceProxy, 99);
    }

    function test_UnderpaymentReverts() public {
        vm.prank(bob);
        vm.expectRevert("Incorrect payment amount");
        purchaseState.purchase{value: 0.5 ether}(aliceProxy, LISTING_ID);
    }

    function test_OverpaymentReverts() public {
        vm.prank(bob);
        vm.expectRevert("Incorrect payment amount");
        purchaseState.purchase{value: 2 ether}(aliceProxy, LISTING_ID);
    }

    function test_DuplicatePurchaseReverts() public {
        vm.prank(bob);
        purchaseState.purchase{value: PRICE}(aliceProxy, LISTING_ID);

        vm.prank(bob);
        vm.expectRevert("Already purchased");
        purchaseState.purchase{value: PRICE}(aliceProxy, LISTING_ID);
    }

    function test_NoPurchaseBeforeBuying() public view {
        assertFalse(purchaseState.hasPurchased(bobProxy, aliceProxy, LISTING_ID));
        assertEq(purchaseState.getPurchaseTimestamp(bobProxy, aliceProxy, LISTING_ID), 0);
    }

    function test_EmitsPurchasedEvent() public {
        uint256 ts = block.timestamp;
        vm.prank(bob);
        vm.expectEmit(true, true, true, true);
        emit DENPurchaseState.Purchased(bobProxy, aliceProxy, LISTING_ID, ts);
        purchaseState.purchase{value: PRICE}(aliceProxy, LISTING_ID);
    }

    // --- purchase (ERC-20) ---

    function test_ERC20PurchaseSucceeds() public {
        uint256 tokenListingId = 2;
        vm.prank(alice);
        purchaseState.setListing(tokenListingId, PRICE, address(token));

        token.mint(bob, PRICE);
        vm.prank(bob);
        token.approve(address(purchaseState), PRICE);

        vm.prank(bob);
        purchaseState.purchase(aliceProxy, tokenListingId);

        assertTrue(purchaseState.hasPurchased(bobProxy, aliceProxy, tokenListingId));
        assertEq(purchaseState.getEscrowBalance(aliceProxy, address(token)), PRICE);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(address(purchaseState)), PRICE);
    }

    function test_ERC20PurchaseRevertsIfEthSent() public {
        uint256 tokenListingId = 2;
        vm.prank(alice);
        purchaseState.setListing(tokenListingId, PRICE, address(token));

        token.mint(bob, PRICE);
        vm.prank(bob);
        token.approve(address(purchaseState), PRICE);

        vm.prank(bob);
        vm.expectRevert("Do not send ETH for token payment");
        purchaseState.purchase{value: 1}(aliceProxy, tokenListingId);
    }

    function test_ERC20PurchaseRevertsWithoutApproval() public {
        uint256 tokenListingId = 2;
        vm.prank(alice);
        purchaseState.setListing(tokenListingId, PRICE, address(token));

        token.mint(bob, PRICE);

        vm.prank(bob);
        vm.expectRevert("Allowance exceeded");
        purchaseState.purchase(aliceProxy, tokenListingId);
    }

    function test_ERC20DuplicatePurchaseReverts() public {
        uint256 tokenListingId = 2;
        vm.prank(alice);
        purchaseState.setListing(tokenListingId, PRICE, address(token));

        token.mint(bob, PRICE * 2);
        vm.prank(bob);
        token.approve(address(purchaseState), PRICE * 2);

        vm.prank(bob);
        purchaseState.purchase(aliceProxy, tokenListingId);

        vm.prank(bob);
        vm.expectRevert("Already purchased");
        purchaseState.purchase(aliceProxy, tokenListingId);
    }

    // --- escrow ---

    function test_EscrowAccumulatesOnPurchase() public {
        vm.prank(bob);
        purchaseState.purchase{value: PRICE}(aliceProxy, LISTING_ID);
        assertEq(purchaseState.getEscrowBalance(aliceProxy, address(0)), PRICE);
    }

    function test_EscrowAccumulatesAcrossMultipleBuyers() public {
        address dave = makeAddr("dave");
        vm.prank(dave);
        registry.register();
        vm.deal(dave, 10 ether);

        uint256 listing2 = 2;
        vm.prank(alice);
        purchaseState.setListing(listing2, PRICE, address(0));

        vm.prank(bob);
        purchaseState.purchase{value: PRICE}(aliceProxy, LISTING_ID);

        vm.prank(dave);
        purchaseState.purchase{value: PRICE}(aliceProxy, listing2);

        assertEq(purchaseState.getEscrowBalance(aliceProxy, address(0)), PRICE * 2);
    }

    function test_EthAndTokenEscrowAreIndependent() public {
        uint256 tokenListingId = 2;
        vm.prank(alice);
        purchaseState.setListing(tokenListingId, PRICE, address(token));

        // Bob buys ETH listing
        vm.prank(bob);
        purchaseState.purchase{value: PRICE}(aliceProxy, LISTING_ID);

        // Bob buys token listing
        token.mint(bob, PRICE);
        vm.prank(bob);
        token.approve(address(purchaseState), PRICE);
        vm.prank(bob);
        purchaseState.purchase(aliceProxy, tokenListingId);

        assertEq(purchaseState.getEscrowBalance(aliceProxy, address(0)), PRICE);
        assertEq(purchaseState.getEscrowBalance(aliceProxy, address(token)), PRICE);
    }

    // --- withdraw ---

    function test_CreatorCanWithdrawEthEscrow() public {
        vm.prank(bob);
        purchaseState.purchase{value: PRICE}(aliceProxy, LISTING_ID);

        uint256 balanceBefore = alice.balance;
        vm.prank(alice);
        purchaseState.withdraw(address(0));

        assertEq(alice.balance, balanceBefore + PRICE);
        assertEq(purchaseState.getEscrowBalance(aliceProxy, address(0)), 0);
    }

    function test_CreatorCanWithdrawTokenEscrow() public {
        uint256 tokenListingId = 2;
        vm.prank(alice);
        purchaseState.setListing(tokenListingId, PRICE, address(token));

        token.mint(bob, PRICE);
        vm.prank(bob);
        token.approve(address(purchaseState), PRICE);
        vm.prank(bob);
        purchaseState.purchase(aliceProxy, tokenListingId);

        vm.prank(alice);
        purchaseState.withdraw(address(token));

        assertEq(token.balanceOf(alice), PRICE);
        assertEq(purchaseState.getEscrowBalance(aliceProxy, address(token)), 0);
    }

    function test_WithdrawWithNothingReverts() public {
        vm.prank(alice);
        vm.expectRevert("Nothing to withdraw");
        purchaseState.withdraw(address(0));
    }

    function test_CannotWithdrawOthersEscrow() public {
        vm.prank(bob);
        purchaseState.purchase{value: PRICE}(aliceProxy, LISTING_ID);

        vm.prank(bob);
        vm.expectRevert("Nothing to withdraw");
        purchaseState.withdraw(address(0));
    }

    function test_UnregisteredCannotWithdraw() public {
        vm.prank(carol);
        vm.expectRevert("Not registered");
        purchaseState.withdraw(address(0));
    }

    function test_EmitsWithdrawnEvent() public {
        vm.prank(bob);
        purchaseState.purchase{value: PRICE}(aliceProxy, LISTING_ID);

        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit DENPurchaseState.Withdrawn(aliceProxy, address(0), PRICE);
        purchaseState.withdraw(address(0));
    }

    // --- sunset gate ---

    function test_PurchaseBlockedAfterSunset() public {
        DENSubscription subscription = new DENSubscription(address(registry));
        DENContentRegistry cr = new DENContentRegistry(address(registry), address(subscription));
        purchaseState.setContentRegistry(address(cr));

        address op = makeAddr("op");
        vm.prank(op);
        registry.register();
        address opProxy = registry.getProxy(op);
        vm.prank(alice);
        cr.setContentOperator(opProxy);

        bytes32 fp = keccak256("test-content");
        vm.prank(alice);
        cr.registerContent(fp, LISTING_ID);

        vm.prank(op);
        cr.issueSunsetNotice(fp);

        vm.prank(bob);
        vm.expectRevert("Creator has active sunset notice");
        purchaseState.purchase{value: PRICE}(aliceProxy, LISTING_ID);
    }

    function test_PurchaseSucceedsBeforeSunset() public {
        DENSubscription subscription = new DENSubscription(address(registry));
        DENContentRegistry cr = new DENContentRegistry(address(registry), address(subscription));
        purchaseState.setContentRegistry(address(cr));

        vm.prank(bob);
        purchaseState.purchase{value: PRICE}(aliceProxy, LISTING_ID);
        assertTrue(purchaseState.hasPurchased(bobProxy, aliceProxy, LISTING_ID));
    }

    function test_PurchaseSucceedsWithoutContentRegistry() public {
        vm.prank(bob);
        purchaseState.purchase{value: PRICE}(aliceProxy, LISTING_ID);
        assertTrue(purchaseState.hasPurchased(bobProxy, aliceProxy, LISTING_ID));
    }

    function test_SetContentRegistryCannotBeCalledTwice() public {
        DENSubscription subscription = new DENSubscription(address(registry));
        DENContentRegistry cr = new DENContentRegistry(address(registry), address(subscription));
        purchaseState.setContentRegistry(address(cr));

        vm.expectRevert("Already set");
        purchaseState.setContentRegistry(address(cr));
    }

    function test_SetContentRegistryRejectsZeroAddress() public {
        vm.expectRevert("Zero address");
        purchaseState.setContentRegistry(address(0));
    }

    // --- wallet rotation survival ---

    function test_PurchaseStateSurvivesCreatorWalletRotation() public {
        vm.prank(bob);
        purchaseState.purchase{value: PRICE}(aliceProxy, LISTING_ID);
        assertTrue(purchaseState.hasPurchased(bobProxy, aliceProxy, LISTING_ID));

        (address alice2, uint256 alice2Key) = makeAddrAndKey("alice2");
        _rotateWallet(aliceProxy, aliceKey, alice2, alice2Key);

        assertEq(registry.getProxy(alice2), aliceProxy);
        assertTrue(purchaseState.hasPurchased(bobProxy, aliceProxy, LISTING_ID));
    }

    function test_WithdrawByNewWalletAfterCreatorRotation() public {
        vm.prank(bob);
        purchaseState.purchase{value: PRICE}(aliceProxy, LISTING_ID);

        (address alice2, uint256 alice2Key) = makeAddrAndKey("alice2");
        _rotateWallet(aliceProxy, aliceKey, alice2, alice2Key);

        uint256 balanceBefore = alice2.balance;
        vm.prank(alice2);
        purchaseState.withdraw(address(0));

        assertEq(alice2.balance, balanceBefore + PRICE);
        assertEq(purchaseState.getEscrowBalance(aliceProxy, address(0)), 0);
    }

    function test_PurchaseStateSurvivesBuyerWalletRotation() public {
        vm.prank(bob);
        purchaseState.purchase{value: PRICE}(aliceProxy, LISTING_ID);
        assertTrue(purchaseState.hasPurchased(bobProxy, aliceProxy, LISTING_ID));

        (address bob2, uint256 bob2Key) = makeAddrAndKey("bob2");
        _rotateWallet(bobProxy, bobKey, bob2, bob2Key);

        assertEq(registry.getProxy(bob2), bobProxy);
        assertTrue(purchaseState.hasPurchased(bobProxy, aliceProxy, LISTING_ID));
    }

    // --- helpers ---

    function _rotateWallet(address proxy, uint256 oldKey, address newWallet, uint256 newKey) internal {
        uint256 nonce = IDENParticipantIdentity(proxy).rotationNonce();
        bytes32 structHash = keccak256(abi.encode("DEN-clean-rotation", proxy, nonce));
        bytes32 ethHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(newKey, ethHash);

        address oldWallet = IDENParticipantIdentity(proxy).primaryWallet();
        vm.prank(oldWallet);
        IDENParticipantIdentity(proxy).initiateCleanRotation(newWallet, abi.encodePacked(r, s, v));

        vm.prank(newWallet);
        registry.syncWallet(proxy);

        (oldKey);
    }
}
