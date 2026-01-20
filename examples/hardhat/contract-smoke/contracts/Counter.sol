// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title Counter
 * @dev Simple counter contract for smoke testing Hedera EVM
 */
contract Counter {
    uint256 public count;
    address public owner;

    event CountChanged(uint256 indexed newCount, address indexed changedBy);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    modifier onlyOwner() {
        require(msg.sender == owner, "Counter: caller is not owner");
        _;
    }

    constructor() {
        owner = msg.sender;
        count = 0;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    /**
     * @dev Increment the counter by 1
     */
    function increment() public {
        count += 1;
        emit CountChanged(count, msg.sender);
    }

    /**
     * @dev Decrement the counter by 1
     */
    function decrement() public {
        require(count > 0, "Counter: cannot decrement below zero");
        count -= 1;
        emit CountChanged(count, msg.sender);
    }

    /**
     * @dev Reset the counter to 0 (only owner)
     */
    function reset() public onlyOwner {
        count = 0;
        emit CountChanged(count, msg.sender);
    }

    /**
     * @dev Set the counter to a specific value (only owner)
     * @param newCount The new count value
     */
    function setCount(uint256 newCount) public onlyOwner {
        count = newCount;
        emit CountChanged(count, msg.sender);
    }

    /**
     * @dev Transfer ownership to a new address
     * @param newOwner The address of the new owner
     */
    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Counter: new owner is zero address");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    /**
     * @dev Get current count (explicit getter for testing)
     */
    function getCount() public view returns (uint256) {
        return count;
    }
}
