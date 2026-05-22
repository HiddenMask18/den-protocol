// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/identity/DENIdentityImpl.sol";
import "../src/identity/DENIdentityRegistry.sol";
import "../src/interfaces/IDENParticipantIdentity.sol";
import "../src/subscription/DENSubscription.sol";
import "../src/content/DENContentRegistry.sol";
import "../src/purchase/DENPurchaseState.sol";
import "../src/compensation/DENHostCompensation.sol";
import "../src/interfaces/IDENHostCompensation.sol";
import "./mocks/MockERC20.sol";

contract DENHostCompensationTest is Test {
    DENIdentityImpl impl;
    DENIdentityRegistry registry;
    DENSubscription subscription;
    DENContentRegistry contentRegistry;
    DENPurchaseState purchaseState;
    DENHostCompensation compensation;
    MockERC20 token;

    address alice;
    uint256 aliceKey;
    address bob;
    address carol;
    uint256 carolKey;

    address aliceProxy;
    address bobProxy;
    address carolProxy;

    uint256 constant TIER_ID    = 1;
    uint256 constant LISTING_ID = 1;
    uint256 constant PRICE      = 1 ether;
    uint256 constant DURATION   = 30 days;

    // Expected fee on a 1 ETH payment: 2.5% = 0.025 ETH
    uint256 constant FEE        = (PRICE * 250) / 10000;
    uint256 constant NET        = PRICE - FEE;

    function setUp() public {
        (alice, aliceKey) = makeAddrAndKey("alice");
        bob   = makeAddr("bob");
        (carol, carolKey) = makeAddrAndKey("carol");

        impl           = new DENIdentityImpl();
        registry       = new DENIdentityRegistry(address(impl));
        subscription   = new DENSubscription(address(registry));
        contentRegistry = new DENContentRegistry(address(registry), address(subscription));
        purchaseState  = new DENPurchaseState(address(registry));
        compensation   = new DENHostCompensation(address(registry), address(contentRegistry));
        token          = new MockERC20();

        vm.prank(alice); registry.register();
        aliceProxy = registry.getProxy(alice);

        vm.prank(bob);  registry.register();
        bobProxy = registry.getProxy(bob);

        vm.prank(carol); registry.register();
        carolProxy = registry.getProxy(carol);

        // Wire all contracts.
        subscription.setContentRegistry(address(contentRegistry));
        purchaseState.setContentRegistry(address(contentRegistry));
        subscription.setCompensation(address(compensation));
        purchaseState.setCompensation(address(compensation));
        compensation.setSubscriptionContract(address(subscription));
        compensation.setPurchaseContract(address(purchaseState));

        // Set initial ETH rates matching the deploy script (micro bracket for most tests).
        IDENHostCompensation.BracketRates[4] memory ethRates;
        ethRates[0] = IDENHostCompensation.BracketRates({storageRatePerGB: 3e14,           bandwidthRatePerGB: 4e14});
        ethRates[1] = IDENHostCompensation.BracketRates({storageRatePerGB: 225000000000000, bandwidthRatePerGB: 3e14});
        ethRates[2] = IDENHostCompensation.BracketRates({storageRatePerGB: 15e13,           bandwidthRatePerGB: 2e14});
        ethRates[3] = IDENHostCompensation.BracketRates({storageRatePerGB: 23e13,           bandwidthRatePerGB: 345000000000000});
        compensation.setTokenRates(address(0), ethRates);

        // Alice sets a subscription tier and a shop listing.
        vm.prank(alice); subscription.setTier(TIER_ID, PRICE, DURATION, address(0));
        vm.prank(alice); purchaseState.setListing(LISTING_ID, PRICE, address(0));

        // Alice registers carol as her content operator (hoster).
        vm.prank(alice); contentRegistry.setContentOperator(carolProxy);

        vm.deal(bob, 100 ether);
    }

    // --- Fee split on subscription ---

    function test_FeeDeductedFromCreatorEscrowOnSubscription() public {
        vm.prank(bob);
        subscription.subscribe{value: PRICE}(aliceProxy, TIER_ID);

        assertEq(subscription.getEscrowBalance(aliceProxy, address(0)), NET);
        assertEq(compensation.getFeePool(aliceProxy, address(0)), FEE);
    }

    function test_FeePoolAccumulatesAcrossSubscriptions() public {
        vm.prank(bob);
        subscription.subscribe{value: PRICE}(aliceProxy, TIER_ID);

        address dave = makeAddr("dave");
        vm.prank(dave); registry.register();
        vm.deal(dave, 10 ether);
        vm.prank(dave);
        subscription.subscribe{value: PRICE}(aliceProxy, TIER_ID);

        assertEq(compensation.getFeePool(aliceProxy, address(0)), FEE * 2);
        assertEq(subscription.getEscrowBalance(aliceProxy, address(0)), NET * 2);
    }

    function test_FeeDeductedFromCreatorEscrowOnPurchase() public {
        vm.prank(bob);
        purchaseState.purchase{value: PRICE}(aliceProxy, LISTING_ID);

        assertEq(purchaseState.getEscrowBalance(aliceProxy, address(0)), NET);
        assertEq(compensation.getFeePool(aliceProxy, address(0)), FEE);
    }

    function test_NoFeeWithoutCompensationContract() public {
        DENSubscription freshSub = new DENSubscription(address(registry));
        vm.prank(alice); freshSub.setTier(TIER_ID, PRICE, DURATION, address(0));

        vm.prank(bob);
        freshSub.subscribe{value: PRICE}(aliceProxy, TIER_ID);

        assertEq(freshSub.getEscrowBalance(aliceProxy, address(0)), PRICE);
    }

    // --- Unauthorized deposit ---

    function test_UnauthorizedDepositReverts() public {
        vm.prank(bob);
        vm.expectRevert("Unauthorized");
        compensation.depositFee{value: FEE}(aliceProxy, address(0), FEE);
    }

    // --- One-time setters ---

    function test_SetCompensationOnlyOnce() public {
        vm.expectRevert("Already set");
        subscription.setCompensation(address(compensation));
    }

    function test_SetSubscriptionContractOnlyOnce() public {
        vm.expectRevert("Already set");
        compensation.setSubscriptionContract(address(subscription));
    }

    function test_SetPurchaseContractOnlyOnce() public {
        vm.expectRevert("Already set");
        compensation.setPurchaseContract(address(purchaseState));
    }

    function test_SetTokenRatesOnlyOwner() public {
        IDENHostCompensation.BracketRates[4] memory rates;
        vm.prank(bob);
        vm.expectRevert("Not owner");
        compensation.setTokenRates(address(0), rates);
    }

    // --- Claim: happy path ---

    function test_HosterClaimsCompensation() public {
        vm.prank(bob);
        subscription.subscribe{value: PRICE}(aliceProxy, TIER_ID);

        uint256 carolBalanceBefore = carol.balance;

        // Carol's instance: instanceSize=50 (micro bracket), 1 GB storage, 5 GB bandwidth.
        // formula = 1*3e14 + 5*4e14 = 3e14 + 20e14 = 23e14
        vm.prank(carol);
        compensation.claimCompensation(aliceProxy, address(0), 1, 5, 50, 1);

        uint256 expectedClaim = 1 * 3e14 + 5 * 4e14; // 2.3e15
        assertLe(expectedClaim, FEE, "test setup: formula must be <= fee pool");
        assertEq(carol.balance, carolBalanceBefore + expectedClaim);
        assertEq(aliceProxy.balance, 0); // surplus goes to primary wallet (alice), not proxy
    }

    function test_SurplusReturnsToCreatorPrimaryWallet() public {
        vm.prank(bob);
        subscription.subscribe{value: PRICE}(aliceProxy, TIER_ID);

        uint256 aliceBalanceBefore = alice.balance;

        // 0 GB storage and bandwidth → formula = 0 → hoster claim = 0 → full pool is surplus.
        vm.prank(carol);
        compensation.claimCompensation(aliceProxy, address(0), 0, 0, 50, 1);

        assertEq(alice.balance, aliceBalanceBefore + FEE);
        assertEq(compensation.getFeePool(aliceProxy, address(0)), 0);
    }

    function test_ClaimCappedAtFeePool() public {
        vm.prank(bob);
        subscription.subscribe{value: PRICE}(aliceProxy, TIER_ID);

        uint256 carolBalanceBefore = carol.balance;

        // 1000 GB storage: formula >> fee pool; cap activates.
        vm.prank(carol);
        compensation.claimCompensation(aliceProxy, address(0), 1000, 1000, 50, 1);

        // Hoster receives the entire fee pool; no surplus.
        assertEq(carol.balance, carolBalanceBefore + FEE);
        assertEq(compensation.getFeePool(aliceProxy, address(0)), 0);
    }

    function test_FeePoolZeroedAfterClaim() public {
        vm.prank(bob);
        subscription.subscribe{value: PRICE}(aliceProxy, TIER_ID);

        vm.prank(carol);
        compensation.claimCompensation(aliceProxy, address(0), 1, 1, 50, 1);

        assertEq(compensation.getFeePool(aliceProxy, address(0)), 0);
    }

    function test_NothingToClaimReverts() public {
        vm.prank(carol);
        vm.expectRevert("Nothing to claim");
        compensation.claimCompensation(aliceProxy, address(0), 1, 1, 50, 1);
    }

    // --- Authorization ---

    function test_NonOperatorCannotClaim() public {
        vm.prank(bob);
        subscription.subscribe{value: PRICE}(aliceProxy, TIER_ID);

        // Bob is not the content operator.
        vm.prank(bob);
        vm.expectRevert("Not content operator");
        compensation.claimCompensation(aliceProxy, address(0), 1, 1, 50, 1);
    }

    function test_UnregisteredCannotClaim() public {
        address stranger = makeAddr("stranger");
        vm.prank(bob);
        subscription.subscribe{value: PRICE}(aliceProxy, TIER_ID);

        vm.prank(stranger);
        vm.expectRevert("Not registered");
        compensation.claimCompensation(aliceProxy, address(0), 1, 1, 50, 1);
    }

    // --- Progressive bracket rates ---

    function test_MicroBracketRates() public {
        vm.prank(bob); subscription.subscribe{value: PRICE}(aliceProxy, TIER_ID);
        vm.prank(bob); subscription.subscribe{value: PRICE}(aliceProxy, TIER_ID);
        // Add more funds so we can test the formula fully.

        uint256 carolBefore = carol.balance;
        uint256 aliceBefore = alice.balance;

        // instanceSize = 50 (micro, <80). 2 GB storage, 3 GB bandwidth.
        // formula = 2*3e14 + 3*4e14 = 6e14 + 12e14 = 18e14
        vm.prank(carol);
        compensation.claimCompensation(aliceProxy, address(0), 2, 3, 50, 1);

        uint256 expectedClaim = 2 * 3e14 + 3 * 4e14;
        assertEq(carol.balance, carolBefore + expectedClaim);
        assertEq(alice.balance, aliceBefore + (FEE * 2 - expectedClaim));
    }

    function test_SmallBracketRates() public {
        vm.prank(bob); subscription.subscribe{value: PRICE}(aliceProxy, TIER_ID);
        vm.prank(bob); subscription.subscribe{value: PRICE}(aliceProxy, TIER_ID);

        uint256 carolBefore = carol.balance;

        // instanceSize = 100 (small, 80–200). 2 GB storage, 3 GB bandwidth.
        // formula = 2*225000000000000 + 3*3e14 = 4.5e14 + 9e14 = 13.5e14
        vm.prank(carol);
        compensation.claimCompensation(aliceProxy, address(0), 2, 3, 100, 1);

        uint256 expectedClaim = 2 * 225000000000000 + 3 * 3e14;
        assertEq(carol.balance, carolBefore + expectedClaim);
    }

    function test_MediumBracketRates() public {
        vm.prank(bob); subscription.subscribe{value: PRICE}(aliceProxy, TIER_ID);
        vm.prank(bob); subscription.subscribe{value: PRICE}(aliceProxy, TIER_ID);

        uint256 carolBefore = carol.balance;

        // instanceSize = 300 (medium, 200–500). 2 GB storage, 3 GB bandwidth.
        // formula = 2*15e13 + 3*2e14 = 3e14 + 6e14 = 9e14
        vm.prank(carol);
        compensation.claimCompensation(aliceProxy, address(0), 2, 3, 300, 1);

        uint256 expectedClaim = 2 * 15e13 + 3 * 2e14;
        assertEq(carol.balance, carolBefore + expectedClaim);
    }

    function test_LargeBracketRates() public {
        vm.prank(bob); subscription.subscribe{value: PRICE}(aliceProxy, TIER_ID);
        vm.prank(bob); subscription.subscribe{value: PRICE}(aliceProxy, TIER_ID);

        uint256 carolBefore = carol.balance;

        // instanceSize = 600 (large, 500+). 2 GB storage, 3 GB bandwidth.
        // formula = 2*23e13 + 3*345000000000000 = 4.6e14 + 10.35e14 = 14.95e14
        vm.prank(carol);
        compensation.claimCompensation(aliceProxy, address(0), 2, 3, 600, 1);

        uint256 expectedClaim = 2 * 23e13 + 3 * 345000000000000;
        assertEq(carol.balance, carolBefore + expectedClaim);
    }

    function test_ZeroRatesResultsInFullSurplus() public {
        IDENHostCompensation.BracketRates[4] memory zeroRates;
        compensation.setTokenRates(address(0), zeroRates);

        vm.prank(bob); subscription.subscribe{value: PRICE}(aliceProxy, TIER_ID);
        uint256 aliceBefore = alice.balance;

        vm.prank(carol);
        compensation.claimCompensation(aliceProxy, address(0), 100, 100, 50, 1);

        assertEq(alice.balance, aliceBefore + FEE);
    }

    // --- Storage compensation threshold (spec §7.2) ---
    // Declared-plus-auditable model: hoster declares subscriberCount; must be >= 1.
    // Spec gap: on-chain enumeration of active subscribers is not gas-practical — declared
    // count is emitted for community audit, consistent with §7.3 bandwidth model.

    function test_ZeroSubscriberCountBlocksStorageClaim() public {
        vm.prank(bob);
        subscription.subscribe{value: PRICE}(aliceProxy, TIER_ID);

        vm.prank(carol);
        vm.expectRevert("Storage compensation threshold: no verified active subscribers");
        compensation.claimCompensation(aliceProxy, address(0), 1, 1, 50, 0);
    }

    function test_NonZeroSubscriberCountPassesThreshold() public {
        vm.prank(bob);
        subscription.subscribe{value: PRICE}(aliceProxy, TIER_ID);

        vm.prank(carol);
        compensation.claimCompensation(aliceProxy, address(0), 0, 0, 50, 1);
        // Claim succeeds. Full pool is surplus.
        assertEq(compensation.getFeePool(aliceProxy, address(0)), 0);
    }

    function test_MigrationWindowBypassesSubscriberCountThreshold() public {
        vm.prank(bob);
        subscription.subscribe{value: PRICE}(aliceProxy, TIER_ID);

        // Register content and issue a sunset notice to activate the migration window.
        bytes32 fp = keccak256("test-content");
        vm.prank(alice); contentRegistry.registerContent(fp, TIER_ID);
        vm.prank(carol); contentRegistry.issueSunsetNotice(fp);
        assertTrue(contentRegistry.hasActiveSunset(aliceProxy));

        // subscriberCount = 0 but threshold is bypassed because creator is in migration window.
        vm.prank(carol);
        compensation.claimCompensation(aliceProxy, address(0), 0, 0, 50, 0);
        assertEq(compensation.getFeePool(aliceProxy, address(0)), 0);
    }

    // --- ERC-20 flow ---

    function test_ERC20FeeDeposit() public {
        vm.prank(alice); subscription.setTier(2, PRICE, DURATION, address(token));

        token.mint(bob, PRICE);
        vm.prank(bob); token.approve(address(subscription), PRICE);
        vm.prank(bob); subscription.subscribe(aliceProxy, 2);

        uint256 expectedFee = (PRICE * 250) / 10000;
        assertEq(compensation.getFeePool(aliceProxy, address(token)), expectedFee);
        assertEq(subscription.getEscrowBalance(aliceProxy, address(token)), PRICE - expectedFee);
        assertEq(token.balanceOf(address(compensation)), expectedFee);
    }

    function test_ERC20ClaimAndSurplus() public {
        vm.prank(alice); subscription.setTier(2, PRICE, DURATION, address(token));

        // Set token rates (same proportions as ETH).
        IDENHostCompensation.BracketRates[4] memory tokenRates;
        tokenRates[0] = IDENHostCompensation.BracketRates({storageRatePerGB: 3e14, bandwidthRatePerGB: 4e14});
        tokenRates[1] = tokenRates[0];
        tokenRates[2] = tokenRates[0];
        tokenRates[3] = tokenRates[0];
        compensation.setTokenRates(address(token), tokenRates);

        token.mint(bob, PRICE);
        vm.prank(bob); token.approve(address(subscription), PRICE);
        vm.prank(bob); subscription.subscribe(aliceProxy, 2);

        uint256 pool = compensation.getFeePool(aliceProxy, address(token));
        uint256 carolTokenBefore = token.balanceOf(carol);
        uint256 aliceTokenBefore = token.balanceOf(alice);

        // 0 GB → claim = 0 → full surplus to alice.
        vm.prank(carol);
        compensation.claimCompensation(aliceProxy, address(token), 0, 0, 50, 1);

        assertEq(token.balanceOf(carol), carolTokenBefore);
        assertEq(token.balanceOf(alice), aliceTokenBefore + pool);
        assertEq(compensation.getFeePool(aliceProxy, address(token)), 0);
    }

    function test_PurchaseFeeERC20() public {
        vm.prank(alice); purchaseState.setListing(2, PRICE, address(token));
        token.mint(bob, PRICE);
        vm.prank(bob); token.approve(address(purchaseState), PRICE);
        vm.prank(bob); purchaseState.purchase(aliceProxy, 2);

        uint256 expectedFee = (PRICE * 250) / 10000;
        assertEq(compensation.getFeePool(aliceProxy, address(token)), expectedFee);
        assertEq(purchaseState.getEscrowBalance(aliceProxy, address(token)), PRICE - expectedFee);
    }

    // --- Events ---

    function test_FeeDepositedEventEmitted() public {
        vm.prank(bob);
        vm.expectEmit(true, true, false, true);
        emit IDENHostCompensation.FeeDeposited(aliceProxy, address(0), FEE);
        subscription.subscribe{value: PRICE}(aliceProxy, TIER_ID);
    }

    function test_CompensationClaimedEventEmitted() public {
        vm.prank(bob);
        subscription.subscribe{value: PRICE}(aliceProxy, TIER_ID);

        uint256 expectedClaim = 1 * 3e14 + 5 * 4e14;
        uint256 expectedSurplus = FEE - expectedClaim;

        vm.prank(carol);
        vm.expectEmit(true, true, true, true);
        emit IDENHostCompensation.CompensationClaimed(carolProxy, aliceProxy, address(0), expectedClaim, expectedSurplus, 50, 1);
        compensation.claimCompensation(aliceProxy, address(0), 1, 5, 50, 1);
    }

    // --- Surplus goes to current wallet after rotation ---

    function test_SurplusGoesToCurrentPrimaryWalletAfterCreatorRotation() public {
        vm.prank(bob);
        subscription.subscribe{value: PRICE}(aliceProxy, TIER_ID);

        // Rotate alice's wallet to alice2.
        (address alice2, uint256 alice2Key) = makeAddrAndKey("alice2");
        uint256 nonce = IDENParticipantIdentity(aliceProxy).rotationNonce();
        bytes32 structHash = keccak256(abi.encode("DEN-clean-rotation", aliceProxy, nonce));
        bytes32 ethHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alice2Key, ethHash);
        vm.prank(alice);
        IDENParticipantIdentity(aliceProxy).initiateCleanRotation(alice2, abi.encodePacked(r, s, v));
        vm.prank(alice2); registry.syncWallet(aliceProxy);

        uint256 alice2Before = alice2.balance;
        uint256 aliceBefore  = alice.balance;

        // Claim with 0 GB — full pool is surplus, goes to alice2 (current primary wallet).
        vm.prank(carol);
        compensation.claimCompensation(aliceProxy, address(0), 0, 0, 50, 1);

        assertEq(alice2.balance, alice2Before + FEE);
        assertEq(alice.balance,  aliceBefore);
        (alice2Key); // suppress unused warning
    }
}
