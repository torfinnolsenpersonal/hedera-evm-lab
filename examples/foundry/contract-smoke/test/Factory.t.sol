// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/Factory.sol";
import "../src/Counter.sol";

/**
 * @title FactoryTest
 * @dev Contract factory tests - validates CREATE, CREATE2, contract calls
 * EVM Coverage: CREATE, CREATE2, CALL, STATICCALL, EXTCODESIZE, address prediction
 */
contract FactoryTest is Test {
    Factory public factory;
    ChildFactory public childFactory;
    address public owner;

    event ContractDeployed(address indexed contractAddress, address indexed deployer, bytes32 salt);
    event ContractCalled(address indexed contractAddress, bool success);
    event ChildDeployed(address indexed child, uint256 value);

    function setUp() public {
        owner = address(this);
        factory = new Factory();
        childFactory = new ChildFactory();
    }

    // ============ Factory Deployment Tests ============

    function test_FactoryOwner() public view {
        assertEq(factory.owner(), owner);
    }

    function test_InitialDeployedCountZero() public view {
        assertEq(factory.getDeployedCount(), 0);
    }

    // ============ CREATE Tests ============

    function test_DeployCounter() public {
        address deployed = factory.deployCounter();

        assertTrue(deployed != address(0));
        assertEq(factory.getDeployedCount(), 1);
        assertEq(factory.deployedContracts(0), deployed);
    }

    function test_DeployCounterEmitsEvent() public {
        vm.expectEmit(false, true, false, true);
        emit ContractDeployed(address(0), owner, bytes32(0)); // address is dynamic
        factory.deployCounter();
    }

    function test_DeployedCounterWorks() public {
        address deployed = factory.deployCounter();
        Counter counter = Counter(deployed);

        assertEq(counter.count(), 0);
        counter.increment();
        assertEq(counter.count(), 1);
    }

    function test_DeployMultipleCounters() public {
        address counter1 = factory.deployCounter();
        address counter2 = factory.deployCounter();
        address counter3 = factory.deployCounter();

        assertTrue(counter1 != counter2);
        assertTrue(counter2 != counter3);
        assertEq(factory.getDeployedCount(), 3);
    }

    function test_GetAllDeployed() public {
        factory.deployCounter();
        factory.deployCounter();
        factory.deployCounter();

        address[] memory deployed = factory.getAllDeployed();
        assertEq(deployed.length, 3);
    }

    // ============ CREATE2 Tests ============

    function test_DeployCounterCreate2() public {
        bytes32 salt = keccak256("test-salt");
        address deployed = factory.deployCounterCreate2(salt);

        assertTrue(deployed != address(0));
        assertEq(factory.getDeployedCount(), 1);
    }

    function test_DeployCounterCreate2EmitsEvent() public {
        bytes32 salt = keccak256("test-salt");

        vm.expectEmit(false, true, false, true);
        emit ContractDeployed(address(0), owner, salt);
        factory.deployCounterCreate2(salt);
    }

    function test_PredictAddress() public {
        bytes32 salt = keccak256("predict-test");

        address predicted = factory.predictAddress(salt);
        address deployed = factory.deployCounterCreate2(salt);

        assertEq(predicted, deployed);
    }

    function test_DifferentSaltsDifferentAddresses() public {
        bytes32 salt1 = keccak256("salt-1");
        bytes32 salt2 = keccak256("salt-2");

        address addr1 = factory.deployCounterCreate2(salt1);
        address addr2 = factory.deployCounterCreate2(salt2);

        assertTrue(addr1 != addr2);
    }

    function test_SameSaltSameAddressPrediction() public {
        bytes32 salt = keccak256("same-salt");

        address predicted1 = factory.predictAddress(salt);
        address predicted2 = factory.predictAddress(salt);

        assertEq(predicted1, predicted2);
    }

    // ============ Contract Interaction Tests ============

    function test_CallIncrement() public {
        address deployed = factory.deployCounter();

        factory.callIncrement(deployed);

        assertEq(Counter(deployed).count(), 1);
    }

    function test_CallIncrementEmitsEvent() public {
        address deployed = factory.deployCounter();

        vm.expectEmit(true, false, false, true);
        emit ContractCalled(deployed, true);
        factory.callIncrement(deployed);
    }

    function test_CallGetCount() public {
        address deployed = factory.deployCounter();

        uint256 count = factory.callGetCount(deployed);
        assertEq(count, 0);

        Counter(deployed).increment();
        count = factory.callGetCount(deployed);
        assertEq(count, 1);
    }

    function test_StaticCallGetCount() public {
        address deployed = factory.deployCounter();

        uint256 count = factory.staticCallGetCount(deployed);
        assertEq(count, 0);

        Counter(deployed).increment();
        count = factory.staticCallGetCount(deployed);
        assertEq(count, 1);
    }

    function test_LowLevelCall() public {
        address deployed = factory.deployCounter();

        bytes memory callData = abi.encodeWithSignature("increment()");
        (bool success, ) = factory.lowLevelCall(deployed, callData);

        assertTrue(success);
        assertEq(Counter(deployed).count(), 1);
    }

    function test_LowLevelCallView() public {
        address deployed = factory.deployCounter();
        Counter(deployed).increment();
        Counter(deployed).increment();

        bytes memory callData = abi.encodeWithSignature("getCount()");
        (bool success, bytes memory returnData) = factory.lowLevelCall(deployed, callData);

        assertTrue(success);
        uint256 count = abi.decode(returnData, (uint256));
        assertEq(count, 2);
    }

    // ============ Deploy and Call Tests ============

    function test_DeployAndIncrement() public {
        (address deployed, uint256 count) = factory.deployAndIncrement();

        assertTrue(deployed != address(0));
        assertEq(count, 1);
        assertEq(Counter(deployed).count(), 1);
    }

    // ============ ChildFactory Tests ============

    function test_DeployChild() public {
        address child = childFactory.deployChild(42);

        assertTrue(child != address(0));
        assertEq(SimpleChild(child).value(), 42);
        assertEq(SimpleChild(child).factory(), address(childFactory));
    }

    function test_DeployChildEmitsEvent() public {
        vm.expectEmit(false, false, false, true);
        emit ChildDeployed(address(0), 42);
        childFactory.deployChild(42);
    }

    function test_DeployChildCreate2() public {
        bytes32 salt = keccak256("child-salt");
        address child = childFactory.deployChildCreate2(42, salt);

        assertTrue(child != address(0));
        assertEq(SimpleChild(child).value(), 42);
    }

    function test_PredictChildAddress() public {
        bytes32 salt = keccak256("predict-child");
        uint256 value = 123;

        address predicted = childFactory.predictChildAddress(value, salt);
        address deployed = childFactory.deployChildCreate2(value, salt);

        assertEq(predicted, deployed);
    }

    function test_DifferentValuesAffectCreate2Address() public {
        bytes32 salt = keccak256("same-salt");

        address addr1 = childFactory.predictChildAddress(100, salt);
        address addr2 = childFactory.predictChildAddress(200, salt);

        // Different constructor args = different addresses with CREATE2
        assertTrue(addr1 != addr2);
    }

    // ============ Fuzz Tests ============

    function testFuzz_DeployMultiple(uint8 count) public {
        for (uint8 i = 0; i < count; i++) {
            factory.deployCounter();
        }
        assertEq(factory.getDeployedCount(), count);
    }

    function testFuzz_PredictAddress(bytes32 salt) public {
        address predicted = factory.predictAddress(salt);
        address deployed = factory.deployCounterCreate2(salt);
        assertEq(predicted, deployed);
    }

    function testFuzz_ChildValue(uint256 value) public {
        address child = childFactory.deployChild(value);
        assertEq(SimpleChild(child).value(), value);
    }
}
