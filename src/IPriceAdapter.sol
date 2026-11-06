// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IPriceAdapter {
    function getPrice() external view returns (uint256);
}
