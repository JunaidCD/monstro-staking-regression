// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function decimals() external view returns (uint8);
    function symbol() external view returns (string memory);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

/// @notice Sepolia mock tokens expose an unrestricted mint() faucet.
/// @dev Verified for MockERC20Decimals (USDC) and observed for the no-whitelist
///      mock RWA. The whitelist RWA and TSY token are role-gated; this suite
///      does not attempt to bypass that gating.
interface IMintableERC20 is IERC20Minimal {
    function mint(address to, uint256 amount) external;
}
