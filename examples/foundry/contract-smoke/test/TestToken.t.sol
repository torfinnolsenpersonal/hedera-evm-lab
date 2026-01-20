// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/TestToken.sol";

/**
 * @title TestTokenTest
 * @dev ERC-20 token tests - validates mappings, transfers, approvals
 * EVM Coverage: SLOAD, SSTORE, mappings, nested mappings, events
 */
contract TestTokenTest is Test {
    TestToken public token;
    address public owner;
    address public alice;
    address public bob;

    uint256 constant INITIAL_SUPPLY = 1000000; // 1 million tokens
    uint256 constant DECIMALS = 18;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        owner = address(this);
        alice = address(0xA11CE);
        bob = address(0xB0B);

        token = new TestToken("Test Token", "TEST", INITIAL_SUPPLY);
    }

    // ============ Deployment Tests ============

    function test_TokenName() public view {
        assertEq(token.name(), "Test Token");
    }

    function test_TokenSymbol() public view {
        assertEq(token.symbol(), "TEST");
    }

    function test_TokenDecimals() public view {
        assertEq(token.decimals(), 18);
    }

    function test_InitialSupply() public view {
        assertEq(token.totalSupply(), INITIAL_SUPPLY * 10 ** DECIMALS);
    }

    function test_OwnerHasInitialSupply() public view {
        assertEq(token.balanceOf(owner), INITIAL_SUPPLY * 10 ** DECIMALS);
    }

    // ============ Transfer Tests ============

    function test_Transfer() public {
        uint256 amount = 1000 * 10 ** DECIMALS;
        token.transfer(alice, amount);

        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(owner), (INITIAL_SUPPLY * 10 ** DECIMALS) - amount);
    }

    function test_TransferEmitsEvent() public {
        uint256 amount = 1000 * 10 ** DECIMALS;

        vm.expectEmit(true, true, false, true);
        emit Transfer(owner, alice, amount);
        token.transfer(alice, amount);
    }

    function test_TransferRevertsOnInsufficientBalance() public {
        uint256 tooMuch = (INITIAL_SUPPLY + 1) * 10 ** DECIMALS;

        vm.expectRevert(TestToken.InsufficientBalance.selector);
        token.transfer(alice, tooMuch);
    }

    function test_TransferRevertsOnZeroAddress() public {
        vm.expectRevert(TestToken.ZeroAddress.selector);
        token.transfer(address(0), 100);
    }

    function test_TransferBetweenAccounts() public {
        uint256 amount = 500 * 10 ** DECIMALS;

        // Owner -> Alice
        token.transfer(alice, amount);

        // Alice -> Bob
        vm.prank(alice);
        token.transfer(bob, amount / 2);

        assertEq(token.balanceOf(alice), amount / 2);
        assertEq(token.balanceOf(bob), amount / 2);
    }

    // ============ Approval Tests ============

    function test_Approve() public {
        uint256 amount = 1000 * 10 ** DECIMALS;
        token.approve(alice, amount);

        assertEq(token.allowance(owner, alice), amount);
    }

    function test_ApproveEmitsEvent() public {
        uint256 amount = 1000 * 10 ** DECIMALS;

        vm.expectEmit(true, true, false, true);
        emit Approval(owner, alice, amount);
        token.approve(alice, amount);
    }

    function test_ApproveRevertsOnZeroAddress() public {
        vm.expectRevert(TestToken.ZeroAddress.selector);
        token.approve(address(0), 100);
    }

    function test_ApproveOverwrite() public {
        token.approve(alice, 1000);
        token.approve(alice, 500);

        assertEq(token.allowance(owner, alice), 500);
    }

    // ============ TransferFrom Tests ============

    function test_TransferFrom() public {
        uint256 amount = 1000 * 10 ** DECIMALS;
        token.approve(alice, amount);

        vm.prank(alice);
        token.transferFrom(owner, bob, amount);

        assertEq(token.balanceOf(bob), amount);
        assertEq(token.allowance(owner, alice), 0);
    }

    function test_TransferFromEmitsEvent() public {
        uint256 amount = 1000 * 10 ** DECIMALS;
        token.approve(alice, amount);

        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit Transfer(owner, bob, amount);
        token.transferFrom(owner, bob, amount);
    }

    function test_TransferFromRevertsOnInsufficientAllowance() public {
        token.approve(alice, 100);

        vm.prank(alice);
        vm.expectRevert(TestToken.InsufficientAllowance.selector);
        token.transferFrom(owner, bob, 200);
    }

    function test_TransferFromRevertsOnInsufficientBalance() public {
        // Give alice approval for more than owner has
        token.approve(alice, type(uint256).max);

        // Transfer all tokens away first
        token.transfer(bob, token.balanceOf(owner));

        vm.prank(alice);
        vm.expectRevert(TestToken.InsufficientBalance.selector);
        token.transferFrom(owner, bob, 100);
    }

    function test_TransferFromReducesAllowance() public {
        uint256 allowance = 1000 * 10 ** DECIMALS;
        uint256 transferAmount = 400 * 10 ** DECIMALS;

        token.approve(alice, allowance);

        vm.prank(alice);
        token.transferFrom(owner, bob, transferAmount);

        assertEq(token.allowance(owner, alice), allowance - transferAmount);
    }

    // ============ Mint Tests ============

    function test_Mint() public {
        uint256 mintAmount = 1000 * 10 ** DECIMALS;
        uint256 supplyBefore = token.totalSupply();

        token.mint(alice, mintAmount);

        assertEq(token.balanceOf(alice), mintAmount);
        assertEq(token.totalSupply(), supplyBefore + mintAmount);
    }

    function test_MintEmitsEvent() public {
        uint256 mintAmount = 1000 * 10 ** DECIMALS;

        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), alice, mintAmount);
        token.mint(alice, mintAmount);
    }

    function test_MintRevertsOnZeroAddress() public {
        vm.expectRevert(TestToken.ZeroAddress.selector);
        token.mint(address(0), 100);
    }

    // ============ Burn Tests ============

    function test_Burn() public {
        uint256 burnAmount = 1000 * 10 ** DECIMALS;
        uint256 supplyBefore = token.totalSupply();
        uint256 balanceBefore = token.balanceOf(owner);

        token.burn(burnAmount);

        assertEq(token.balanceOf(owner), balanceBefore - burnAmount);
        assertEq(token.totalSupply(), supplyBefore - burnAmount);
    }

    function test_BurnEmitsEvent() public {
        uint256 burnAmount = 1000 * 10 ** DECIMALS;

        vm.expectEmit(true, true, false, true);
        emit Transfer(owner, address(0), burnAmount);
        token.burn(burnAmount);
    }

    function test_BurnRevertsOnInsufficientBalance() public {
        uint256 tooMuch = (INITIAL_SUPPLY + 1) * 10 ** DECIMALS;

        vm.expectRevert(TestToken.InsufficientBalance.selector);
        token.burn(tooMuch);
    }

    // ============ Fuzz Tests ============

    function testFuzz_Transfer(uint256 amount) public {
        amount = bound(amount, 0, token.balanceOf(owner));

        uint256 ownerBefore = token.balanceOf(owner);
        token.transfer(alice, amount);

        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(owner), ownerBefore - amount);
    }

    function testFuzz_ApproveAndTransferFrom(uint256 approveAmount, uint256 transferAmount) public {
        approveAmount = bound(approveAmount, 0, token.balanceOf(owner));
        transferAmount = bound(transferAmount, 0, approveAmount);

        token.approve(alice, approveAmount);

        vm.prank(alice);
        token.transferFrom(owner, bob, transferAmount);

        assertEq(token.balanceOf(bob), transferAmount);
        assertEq(token.allowance(owner, alice), approveAmount - transferAmount);
    }
}
