// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title Counter
 * @dev Simple counter contract for smoke testing Hedera EVM with Foundry
 */
contract Counter {
    uint256 public count;
    address public owner;

    event CountChanged(uint256 indexed newCount, address indexed changedBy);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    error NotOwner();
    error CannotDecrementBelowZero();
    error ZeroAddress();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor() {
        owner = msg.sender;
        count = 0;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    function increment() public {
        count += 1;
        emit CountChanged(count, msg.sender);
    }

    function decrement() public {
        if (count == 0) revert CannotDecrementBelowZero();
        count -= 1;
        emit CountChanged(count, msg.sender);
    }

    function reset() public onlyOwner {
        count = 0;
        emit CountChanged(count, msg.sender);
    }

    function setCount(uint256 newCount) public onlyOwner {
        count = newCount;
        emit CountChanged(count, msg.sender);
    }

    function transferOwnership(address newOwner) public onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    function getCount() public view returns (uint256) {
        return count;
    }
}
