// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

// bad ERC20 contract token to mimic real one in tests
contract simpleErc20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor() {
        balanceOf[msg.sender] = 10 ** 18;
    }

    function transfer(address dest, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[dest] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external {
        allowance[msg.sender][spender] = amount;
    }

    function transferFrom(
        address source,
        address dest,
        uint256 amount
    ) external returns (bool) {
        allowance[source][msg.sender] -= amount;
        balanceOf[source] -= amount;
        balanceOf[dest] += amount;
        return true;
    }
}
