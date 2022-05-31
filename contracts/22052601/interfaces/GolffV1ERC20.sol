// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

interface GolffV1ERC20 {
    function mint(address to, uint256 amount) external;
    function burnFrom(address from, uint256 amount) external;
}
