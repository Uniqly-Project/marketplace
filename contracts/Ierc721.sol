// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

// we need some information from token contract
// we also need ability to transfer tokens from/to this contract
interface Ierc721 {
    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external;

    function isApprovedForAll(address owner, address operator)
        external
        view
        returns (bool);

    function getApproved(uint256 tokenId)
        external
        view
        returns (address operator);

    function royaltyInfo(uint256)
        external
        view
        returns (address receiver, uint256 amount);

    function receivedRoyalties(
        address _firstOwner,
        address _buyer,
        uint256 _tokenId,
        address _tokenPaid,
        uint256 _amount
    ) external;
}
