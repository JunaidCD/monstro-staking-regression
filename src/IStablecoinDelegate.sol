// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IStablecoinDelegate {
    function balanceSheetCustodyAddress() external view returns (address);
    function stablecoinCustodyAddress() external view returns (address);
    function stablecoinAddress() external view returns (address);
    function stablecoinID() external view returns (bytes32);
    function rwaWhitelist(address rwa) external view returns (bool);
    function stablecoinWhitelist(address stablecoin) external view returns (bool);
    function paused() external view returns (bool);
}
