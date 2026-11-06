// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @notice Minimal interface for the deployed MultiliquidSwap proxy.
/// @dev The current Sepolia implementation (0x7d88...6905, reached through
///      0x0cc2...43F) uses the 4-field ApprovalPermit layout. The SDK v0.5.1
///      ABI matches this layout. The older verified implementation listed in
///      the docs (0x51A6...7480) used a 2-field permit; the proxy has since
///      been upgraded, so these tests use the current 4-field layout.
interface IMultiliquidSwap {
    struct SwapInputs {
        uint256 routeId;
        bytes32 assetInID;
        bytes32 assetOutID;
        bytes32 stablecoinDelegateID;
        uint256 assetInAmt;
        uint256 assetOutAmt;
    }

    struct SwapResolved {
        uint256 tokenInAmt;
        uint256 tokenOutAmt;
        uint256 issuerFeeAmt;
        uint256 spreadFeeAmt;
        uint256 lpFeeAmt;
    }

    struct ApprovalPermit {
        uint256 deadline;
        bytes signature;
        uint256 nonce;
        bool unordered;
    }

    function quoteSwap(address user, SwapInputs calldata inputs) external view returns (SwapResolved memory outputs);

    function swap(address user, address receiver, SwapInputs[] calldata inputs, ApprovalPermit calldata permit) external;

    // --- configuration / read surface used by the tests ---
    function paused() external view returns (bool);
    function spreadProtocolTakeRate() external view returns (uint256);
    function issuerPaidProtocolFeeRates(bytes32 stablecoinID) external view returns (uint256);
    function protocolFeeExempt(bytes32 stablecoinID) external view returns (bool);
    function discountRates(bytes32 stablecoinID, bytes32 rwaID) external view returns (uint256);
    function redemptionFees(bytes32 stablecoinID, bytes32 rwaID) external view returns (uint256);
    function stablecoinAcceptanceFees(bytes32 stablecoinOutID, address stablecoin) external view returns (uint256);
    function stablecoinRedemptionFees(bytes32 stablecoinOutID, address stablecoin) external view returns (uint256);
    function stablecoinInfo(bytes32 stablecoinID)
        external
        view
        returns (bool accepted, bool yieldBearing, uint8 decimals, address delegate, address assetAddress);
    function rwaInfo(bytes32 rwaID)
        external
        view
        returns (bool accepted, bool additionalRiskControls, uint8 decimals, address delegate, address assetAddress);
    function rwaPriceAdapters(bytes32 rwaID) external view returns (address);
    function rwaWhitelistAdapters(bytes32 rwaID) external view returns (address);
    function stablecoinUSDValue(bytes32 stablecoinID) external view returns (uint256);
    function autoLiquidityStablecoinIDs(bytes32 stablecoinID) external view returns (bytes32);
    function nonces(address user) external view returns (uint256);
    function usedUnorderedNonces(address user, uint256 nonce) external view returns (bool);
    function swapInputAllowances(address user, address operator, bytes32 assetInID) external view returns (uint256);

    // --- errors used in [expectRevert] / revert decoding ---
    error IdenticalAssets();
    error IdenticalStablecoins();
    error InvalidSignature();
    error InvalidStablecoinDelegateID(bytes32 actual, bytes32 expected);
    error InsufficientRWAInput();
    error InsufficientRWAOutput();
    error InsufficientStablecoinInput();
    error InsufficientStablecoinOutput();
    error RWANotAccepted();
    error StablecoinNotAccepted();
    error UnsupportedRouteId(uint256 routeId);
    error UserNotWhitelisted(bytes32 rwaID, address user);
    error StablecoinPriceOutsideBand(bytes32 stablecoinID, uint256 adminValue, uint256 oraclePrice, uint256 band);
    error PermitExpired();
    error InvalidLegCount();
    error InsufficientSwapAllowance();
    error ContractPaused();
    error InvalidSwapAddress(address account);
}
