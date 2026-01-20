// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./Counter.sol";

/**
 * @title Factory
 * @dev Contract factory for testing CREATE and CREATE2 on Hedera EVM
 * Tests: CREATE, CREATE2, contract-to-contract calls, address prediction
 */
contract Factory {
    address public owner;
    address[] public deployedContracts;

    event ContractDeployed(address indexed contractAddress, address indexed deployer, bytes32 salt);
    event ContractCalled(address indexed contractAddress, bool success);

    error NotOwner();
    error DeploymentFailed();
    error Create2Failed();
    error CallFailed();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    /// @dev Deploy a new Counter using CREATE
    function deployCounter() public returns (address) {
        Counter counter = new Counter();
        address deployed = address(counter);
        deployedContracts.push(deployed);
        emit ContractDeployed(deployed, msg.sender, bytes32(0));
        return deployed;
    }

    /// @dev Deploy a new Counter using CREATE2 with salt
    function deployCounterCreate2(bytes32 salt) public returns (address) {
        Counter counter = new Counter{salt: salt}();
        address deployed = address(counter);
        deployedContracts.push(deployed);
        emit ContractDeployed(deployed, msg.sender, salt);
        return deployed;
    }

    /// @dev Predict CREATE2 address before deployment
    function predictAddress(bytes32 salt) public view returns (address) {
        bytes memory bytecode = type(Counter).creationCode;
        bytes32 hash = keccak256(
            abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(bytecode))
        );
        return address(uint160(uint256(hash)));
    }

    /// @dev Call increment on a deployed Counter
    function callIncrement(address counterAddress) public {
        Counter(counterAddress).increment();
        emit ContractCalled(counterAddress, true);
    }

    /// @dev Call getCount on a deployed Counter
    function callGetCount(address counterAddress) public view returns (uint256) {
        return Counter(counterAddress).getCount();
    }

    /// @dev Low-level call to a deployed contract
    function lowLevelCall(address target, bytes memory data) public returns (bool, bytes memory) {
        (bool success, bytes memory returnData) = target.call(data);
        emit ContractCalled(target, success);
        return (success, returnData);
    }

    /// @dev Static call (read-only)
    function staticCallGetCount(address counterAddress) public view returns (uint256) {
        (bool success, bytes memory returnData) = counterAddress.staticcall(
            abi.encodeWithSignature("getCount()")
        );
        if (!success) revert CallFailed();
        return abi.decode(returnData, (uint256));
    }

    /// @dev Get number of deployed contracts
    function getDeployedCount() public view returns (uint256) {
        return deployedContracts.length;
    }

    /// @dev Get all deployed contract addresses
    function getAllDeployed() public view returns (address[] memory) {
        return deployedContracts;
    }

    /// @dev Deploy and immediately call increment
    function deployAndIncrement() public returns (address, uint256) {
        address deployed = deployCounter();
        Counter(deployed).increment();
        uint256 count = Counter(deployed).getCount();
        return (deployed, count);
    }
}

/**
 * @title SimpleChild
 * @dev Minimal contract for factory deployment testing
 */
contract SimpleChild {
    address public factory;
    uint256 public value;

    constructor(uint256 _value) {
        factory = msg.sender;
        value = _value;
    }
}

/**
 * @title ChildFactory
 * @dev Factory that deploys SimpleChild contracts with parameters
 */
contract ChildFactory {
    event ChildDeployed(address indexed child, uint256 value);

    function deployChild(uint256 value) public returns (address) {
        SimpleChild child = new SimpleChild(value);
        emit ChildDeployed(address(child), value);
        return address(child);
    }

    function deployChildCreate2(uint256 value, bytes32 salt) public returns (address) {
        SimpleChild child = new SimpleChild{salt: salt}(value);
        emit ChildDeployed(address(child), value);
        return address(child);
    }

    function predictChildAddress(uint256 value, bytes32 salt) public view returns (address) {
        bytes memory bytecode = abi.encodePacked(
            type(SimpleChild).creationCode,
            abi.encode(value)
        );
        bytes32 hash = keccak256(
            abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(bytecode))
        );
        return address(uint160(uint256(hash)));
    }
}
