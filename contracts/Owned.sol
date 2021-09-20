// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;
contract Owned {
    address public owner;
    address public newOwner;

    modifier onlyOwner() {
        require(msg.sender == owner, "only owner");
        _;
    }

    function giveOwnership(address delegate) external onlyOwner {
        newOwner = delegate;
    }

    function acceptOwnership() external {
        require(msg.sender == newOwner, "Only NewOwner");
        owner = msg.sender;
        newOwner = address(0x0);
    }
}
