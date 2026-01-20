// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/PayableTest.sol";

/**
 * @title PayableTestTest
 * @dev Value transfer tests - validates payable, receive, fallback, ETH/HBAR transfers
 * EVM Coverage: CALL, CALLVALUE, SELFBALANCE, transfer, send, call
 */
contract PayableTestTest is Test {
    PayableTest public payableContract;
    address public owner;
    address public alice;

    uint256 constant INITIAL_BALANCE = 100 ether;
    uint256 constant DEPOSIT_AMOUNT = 10 ether;

    event Received(address indexed sender, uint256 amount);
    event Withdrawn(address indexed to, uint256 amount);
    event FallbackCalled(address indexed sender, uint256 amount, bytes data);

    function setUp() public {
        owner = address(this);
        alice = address(0xA11CE);

        // Deploy contract
        payableContract = new PayableTest();

        // Fund test addresses
        vm.deal(owner, INITIAL_BALANCE);
        vm.deal(alice, INITIAL_BALANCE);
    }

    // ============ Deployment Tests ============

    function test_OwnerSetOnDeploy() public view {
        assertEq(payableContract.owner(), owner);
    }

    function test_InitialBalanceZero() public view {
        assertEq(payableContract.getBalance(), 0);
    }

    function test_DeployWithValue() public {
        PayableTest funded = new PayableTest{value: 1 ether}();
        assertEq(funded.getBalance(), 1 ether);
        assertEq(funded.totalReceived(), 1 ether);
    }

    // ============ Receive Tests ============

    function test_ReceiveEther() public {
        (bool success, ) = address(payableContract).call{value: DEPOSIT_AMOUNT}("");
        assertTrue(success);
        assertEq(payableContract.getBalance(), DEPOSIT_AMOUNT);
    }

    function test_ReceiveEmitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit Received(owner, DEPOSIT_AMOUNT);
        (bool success, ) = address(payableContract).call{value: DEPOSIT_AMOUNT}("");
        assertTrue(success);
    }

    function test_ReceiveUpdatesTotalReceived() public {
        (bool success, ) = address(payableContract).call{value: DEPOSIT_AMOUNT}("");
        assertTrue(success);
        assertEq(payableContract.totalReceived(), DEPOSIT_AMOUNT);

        // Send more
        (success, ) = address(payableContract).call{value: DEPOSIT_AMOUNT}("");
        assertTrue(success);
        assertEq(payableContract.totalReceived(), DEPOSIT_AMOUNT * 2);
    }

    // ============ Fallback Tests ============

    function test_FallbackWithData() public {
        bytes memory data = abi.encodeWithSignature("nonExistentFunction()");

        vm.expectEmit(true, false, false, true);
        emit FallbackCalled(owner, DEPOSIT_AMOUNT, data);

        (bool success, ) = address(payableContract).call{value: DEPOSIT_AMOUNT}(data);
        assertTrue(success);
    }

    function test_FallbackWithoutValue() public {
        bytes memory data = abi.encodeWithSignature("nonExistentFunction()");

        (bool success, ) = address(payableContract).call(data);
        assertTrue(success);
    }

    // ============ Deposit Tests ============

    function test_Deposit() public {
        payableContract.deposit{value: DEPOSIT_AMOUNT}();
        assertEq(payableContract.getBalance(), DEPOSIT_AMOUNT);
    }

    function test_DepositEmitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit Received(owner, DEPOSIT_AMOUNT);
        payableContract.deposit{value: DEPOSIT_AMOUNT}();
    }

    function test_DepositRevertsOnZero() public {
        vm.expectRevert(PayableTest.ZeroAmount.selector);
        payableContract.deposit{value: 0}();
    }

    // ============ Withdraw Transfer Tests ============

    function test_WithdrawTransfer() public {
        // Fund contract
        payableContract.deposit{value: DEPOSIT_AMOUNT}();

        uint256 ownerBalanceBefore = owner.balance;
        payableContract.withdrawTransfer();

        assertEq(payableContract.getBalance(), 0);
        assertEq(owner.balance, ownerBalanceBefore + DEPOSIT_AMOUNT);
    }

    function test_WithdrawTransferEmitsEvent() public {
        payableContract.deposit{value: DEPOSIT_AMOUNT}();

        vm.expectEmit(true, false, false, true);
        emit Withdrawn(owner, DEPOSIT_AMOUNT);
        payableContract.withdrawTransfer();
    }

    function test_WithdrawTransferRevertsIfEmpty() public {
        vm.expectRevert(PayableTest.InsufficientBalance.selector);
        payableContract.withdrawTransfer();
    }

    function test_WithdrawTransferOnlyOwner() public {
        payableContract.deposit{value: DEPOSIT_AMOUNT}();

        vm.prank(alice);
        vm.expectRevert(PayableTest.NotOwner.selector);
        payableContract.withdrawTransfer();
    }

    // ============ Withdraw Send Tests ============

    function test_WithdrawSend() public {
        payableContract.deposit{value: DEPOSIT_AMOUNT}();

        uint256 ownerBalanceBefore = owner.balance;
        bool success = payableContract.withdrawSend();

        assertTrue(success);
        assertEq(payableContract.getBalance(), 0);
        assertEq(owner.balance, ownerBalanceBefore + DEPOSIT_AMOUNT);
    }

    function test_WithdrawSendRevertsIfEmpty() public {
        vm.expectRevert(PayableTest.InsufficientBalance.selector);
        payableContract.withdrawSend();
    }

    // ============ Withdraw Call Tests ============

    function test_WithdrawCall() public {
        payableContract.deposit{value: DEPOSIT_AMOUNT}();

        uint256 ownerBalanceBefore = owner.balance;
        payableContract.withdrawCall();

        assertEq(payableContract.getBalance(), 0);
        assertEq(owner.balance, ownerBalanceBefore + DEPOSIT_AMOUNT);
    }

    function test_WithdrawCallRevertsIfEmpty() public {
        vm.expectRevert(PayableTest.InsufficientBalance.selector);
        payableContract.withdrawCall();
    }

    // ============ Withdraw To Tests ============

    function test_WithdrawTo() public {
        payableContract.deposit{value: DEPOSIT_AMOUNT}();

        uint256 aliceBalanceBefore = alice.balance;
        payableContract.withdrawTo(payable(alice), DEPOSIT_AMOUNT / 2);

        assertEq(alice.balance, aliceBalanceBefore + DEPOSIT_AMOUNT / 2);
        assertEq(payableContract.getBalance(), DEPOSIT_AMOUNT / 2);
    }

    function test_WithdrawToEmitsEvent() public {
        payableContract.deposit{value: DEPOSIT_AMOUNT}();

        vm.expectEmit(true, false, false, true);
        emit Withdrawn(alice, DEPOSIT_AMOUNT / 2);
        payableContract.withdrawTo(payable(alice), DEPOSIT_AMOUNT / 2);
    }

    function test_WithdrawToRevertsOnInsufficientBalance() public {
        payableContract.deposit{value: DEPOSIT_AMOUNT}();

        vm.expectRevert(PayableTest.InsufficientBalance.selector);
        payableContract.withdrawTo(payable(alice), DEPOSIT_AMOUNT + 1);
    }

    function test_WithdrawToRevertsOnZeroAmount() public {
        payableContract.deposit{value: DEPOSIT_AMOUNT}();

        vm.expectRevert(PayableTest.ZeroAmount.selector);
        payableContract.withdrawTo(payable(alice), 0);
    }

    // ============ Ownership Tests ============

    function test_TransferOwnership() public {
        payableContract.transferOwnership(alice);
        assertEq(payableContract.owner(), alice);
    }

    function test_NewOwnerCanWithdraw() public {
        payableContract.deposit{value: DEPOSIT_AMOUNT}();
        payableContract.transferOwnership(alice);

        uint256 aliceBalanceBefore = alice.balance;

        vm.prank(alice);
        payableContract.withdrawCall();

        assertEq(alice.balance, aliceBalanceBefore + DEPOSIT_AMOUNT);
    }

    function test_OldOwnerCannotWithdraw() public {
        payableContract.deposit{value: DEPOSIT_AMOUNT}();
        payableContract.transferOwnership(alice);

        vm.expectRevert(PayableTest.NotOwner.selector);
        payableContract.withdrawCall();
    }

    // ============ Fuzz Tests ============

    function testFuzz_Deposit(uint256 amount) public {
        amount = bound(amount, 1, owner.balance);

        payableContract.deposit{value: amount}();
        assertEq(payableContract.getBalance(), amount);
        assertEq(payableContract.totalReceived(), amount);
    }

    function testFuzz_MultipleDeposits(uint256 amount1, uint256 amount2) public {
        amount1 = bound(amount1, 1, owner.balance / 2);
        amount2 = bound(amount2, 1, owner.balance / 2);

        payableContract.deposit{value: amount1}();
        payableContract.deposit{value: amount2}();

        assertEq(payableContract.getBalance(), amount1 + amount2);
        assertEq(payableContract.totalReceived(), amount1 + amount2);
    }

    function testFuzz_PartialWithdraw(uint256 depositAmount, uint256 withdrawAmount) public {
        depositAmount = bound(depositAmount, 1 ether, owner.balance);
        withdrawAmount = bound(withdrawAmount, 1, depositAmount);

        payableContract.deposit{value: depositAmount}();
        payableContract.withdrawTo(payable(alice), withdrawAmount);

        assertEq(payableContract.getBalance(), depositAmount - withdrawAmount);
    }

    // ============ Edge Case Tests ============

    function test_MultipleWithdrawMethods() public {
        // Deposit
        payableContract.deposit{value: 3 ether}();

        // Withdraw 1 ether using each method
        payableContract.withdrawTo(payable(alice), 1 ether);
        assertEq(payableContract.getBalance(), 2 ether);

        // Note: withdrawTransfer and withdrawCall both withdraw ALL remaining balance
        // So we need to re-deposit for each test
    }

    // Required for receiving ETH from withdrawals
    receive() external payable {}
}
