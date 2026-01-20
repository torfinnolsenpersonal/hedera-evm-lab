// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title PayableTest
 * @dev Contract for testing value transfers on Hedera EVM
 * Tests: payable, receive, fallback, ETH/HBAR transfer, balance checks
 */
contract PayableTest {
    address public owner;
    uint256 public totalReceived;

    event Received(address indexed sender, uint256 amount);
    event Withdrawn(address indexed to, uint256 amount);
    event FallbackCalled(address indexed sender, uint256 amount, bytes data);

    error NotOwner();
    error TransferFailed();
    error InsufficientBalance();
    error ZeroAmount();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor() payable {
        owner = msg.sender;
        if (msg.value > 0) {
            totalReceived = msg.value;
            emit Received(msg.sender, msg.value);
        }
    }

    /// @dev Receive HBAR/ETH directly
    receive() external payable {
        totalReceived += msg.value;
        emit Received(msg.sender, msg.value);
    }

    /// @dev Fallback for calls with data
    fallback() external payable {
        totalReceived += msg.value;
        emit FallbackCalled(msg.sender, msg.value, msg.data);
    }

    /// @dev Deposit HBAR/ETH explicitly
    function deposit() public payable {
        if (msg.value == 0) revert ZeroAmount();
        totalReceived += msg.value;
        emit Received(msg.sender, msg.value);
    }

    /// @dev Get contract balance
    function getBalance() public view returns (uint256) {
        return address(this).balance;
    }

    /// @dev Withdraw all funds to owner (using transfer)
    function withdrawTransfer() public onlyOwner {
        uint256 balance = address(this).balance;
        if (balance == 0) revert InsufficientBalance();

        payable(owner).transfer(balance);
        emit Withdrawn(owner, balance);
    }

    /// @dev Withdraw all funds to owner (using send)
    function withdrawSend() public onlyOwner returns (bool) {
        uint256 balance = address(this).balance;
        if (balance == 0) revert InsufficientBalance();

        bool success = payable(owner).send(balance);
        if (success) {
            emit Withdrawn(owner, balance);
        }
        return success;
    }

    /// @dev Withdraw all funds to owner (using call - recommended)
    function withdrawCall() public onlyOwner {
        uint256 balance = address(this).balance;
        if (balance == 0) revert InsufficientBalance();

        (bool success, ) = payable(owner).call{value: balance}("");
        if (!success) revert TransferFailed();
        emit Withdrawn(owner, balance);
    }

    /// @dev Withdraw specific amount to specific address
    function withdrawTo(address payable to, uint256 amount) public onlyOwner {
        if (amount == 0) revert ZeroAmount();
        if (address(this).balance < amount) revert InsufficientBalance();

        (bool success, ) = to.call{value: amount}("");
        if (!success) revert TransferFailed();
        emit Withdrawn(to, amount);
    }

    /// @dev Transfer ownership
    function transferOwnership(address newOwner) public onlyOwner {
        owner = newOwner;
    }
}
