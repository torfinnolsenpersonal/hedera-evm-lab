// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/Counter.sol";

contract CounterTest is Test {
    Counter public counter;
    address public owner;
    address public other;

    event CountChanged(uint256 indexed newCount, address indexed changedBy);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    function setUp() public {
        owner = address(this);
        other = address(0xBEEF);
        counter = new Counter();
    }

    function test_InitialCountIsZero() public view {
        assertEq(counter.count(), 0);
    }

    function test_DeployerIsOwner() public view {
        assertEq(counter.owner(), owner);
    }

    function test_Increment() public {
        counter.increment();
        assertEq(counter.count(), 1);
    }

    function test_IncrementEmitsEvent() public {
        vm.expectEmit(true, true, false, true);
        emit CountChanged(1, owner);
        counter.increment();
    }

    function test_AnyoneCanIncrement() public {
        vm.prank(other);
        counter.increment();
        assertEq(counter.count(), 1);
    }

    function test_Decrement() public {
        counter.increment();
        counter.increment();
        counter.decrement();
        assertEq(counter.count(), 1);
    }

    function test_DecrementRevertsWhenZero() public {
        vm.expectRevert(Counter.CannotDecrementBelowZero.selector);
        counter.decrement();
    }

    function test_Reset() public {
        counter.increment();
        counter.increment();
        counter.reset();
        assertEq(counter.count(), 0);
    }

    function test_ResetOnlyOwner() public {
        counter.increment();
        vm.prank(other);
        vm.expectRevert(Counter.NotOwner.selector);
        counter.reset();
    }

    function test_SetCount() public {
        counter.setCount(42);
        assertEq(counter.count(), 42);
    }

    function test_TransferOwnership() public {
        counter.transferOwnership(other);
        assertEq(counter.owner(), other);
    }

    function test_TransferOwnershipRevertsOnZeroAddress() public {
        vm.expectRevert(Counter.ZeroAddress.selector);
        counter.transferOwnership(address(0));
    }

    function testFuzz_Increment(uint8 times) public {
        for (uint8 i = 0; i < times; i++) {
            counter.increment();
        }
        assertEq(counter.count(), times);
    }
}
