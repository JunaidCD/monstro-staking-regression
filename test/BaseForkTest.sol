// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {IMultiliquidSwap} from "../src/IMultiliquidSwap.sol";
import {IPriceAdapter} from "../src/IPriceAdapter.sol";

/// @title BaseForkTest
/// @notice Shared constants, fork setup, route descriptors, and accounting helpers.
/// @dev All tests are fork tests against live Sepolia. Nothing is broadcast.
abstract contract BaseForkTest is Test {
    // ---------------------------------------------------------------------
    // Live Sepolia addresses (checked against the current proxy implementation)
    // ---------------------------------------------------------------------
    address internal constant SWAP = 0x0cc2ff62B7d5f3584045e12490eA9f5c06Fce43F;
    address internal constant USDC_DELEGATE = 0x8De2F6a2A012a4e5A7C73e8ADA7141B0F380B4B0;
    address internal constant TREASURY_DELEGATE = 0x2Eb8EC371E1e76b6718CCD59567c9E158F46a905;
    address internal constant TSY_DELEGATE = 0x23ddF02Cc519FBE1c22fC4b0A59c166f2F29faed;
    address internal constant CUSTODY = 0x00D02037a99de8b15E2CbF4889DFa07788E206C0;

    address internal constant USDC = 0x092BB220f7Ec652EB871D395D5f957F5f06E1e2D;
    address internal constant RW_WHITELIST_TOKEN = 0x1b2F0A294a3B8162FB4cB5356c689d296B750609; // 6 decimals
    address internal constant RW_NO_WHITELIST_TOKEN = 0x063EE9692eB3E4328a279961922d2e41CB9DAAA8; // 18 decimals
    address internal constant TSY = 0x072Db736308c58465e9FB0961327bFd4bF28E809; // 18 decimals

    bytes32 internal constant USDC_ID = 0x0d29c0dffbd2c0c346869448228ca2a7abc53ed8b9bc71131711a7dc1b2e1dbf;
    bytes32 internal constant RW_WHITELIST_ID = 0x6d09dcd821cf2afe46330125a279e144550a23423a257a0ca98685a875132b9d;
    bytes32 internal constant RW_NO_WHITELIST_ID = 0x35fd271424d6ce4630dcb0603b4ff43d415002f8635fdd3ed8958b55da9b7196;
    bytes32 internal constant TSY_ID = 0x06aa03964db1f7257357ef09714a5f0ca3633723df419e97015e0c7a3e83edb7;

    address internal constant TEST_USER = address(0xB0B);
    address internal constant RECEIVER = address(0xCAFE);

    // Stablecoin delegate fee fields are denominated in the delegate's decimals.
    // USDC has 6 decimals and a WAD USD value of 1e18.
    uint8 internal constant FEE_DECIMALS = 6;
    uint256 internal constant FEE_USD_VALUE = 1e18;

    // 1e-5 USD expressed in WAD. This covers one-unit truncation of a 6-decimal
    // stablecoin plus the three fee fields' independent rounding-up steps.
    int256 internal constant DUST_USD_WAD = 1e13;

    // Storage slots verified empirically below (proxy storage, current impl).
    uint256 internal constant SLOT_DISCOUNT_RATES = 1;
    uint256 internal constant SLOT_REDEMPTION_FEES = 2;
    uint256 internal constant SLOT_STABLECOIN_ACCEPTANCE_FEES = 9;
    uint256 internal constant SLOT_STABLECOIN_REDEMPTION_FEES = 10;
    uint256 internal constant SLOT_PROTOCOL_FEE_EXEMPT = 16;
    uint256 internal constant SLOT_ISSUER_PAID_PROTOCOL_FEE_RATES = 17;
    uint256 internal constant SLOT_SPREAD_PROTOCOL_TAKE_RATE = 18;
    uint256 internal constant SLOT_AUTO_LIQUIDITY = 21;
    uint256 internal constant SLOT_MAX_SWAP_LEGS = 22;

    IMultiliquidSwap internal swap;
    uint256 internal forkId;

    /// @dev Describes one selectable route and the token pair this suite uses.
    struct RouteSpec {
        uint256 routeId;
        bytes32 assetInID;
        bytes32 assetOutID;
        bytes32 delegateID;
        address tokenIn;
        address tokenOut;
        uint8 inDecimals;
        uint8 outDecimals;
        uint256 inUsdValue;
        uint256 outUsdValue;
        uint8 feeDecimals;
        uint256 feeUsdValue;
        uint256 implicitDiscountWad;
        bool exactIn;
        uint256 minAmount;
        uint256 maxAmount;
        string label;
    }

    function setUp() public virtual {
        string memory rpc = vm.envOr("SEPOLIA_RPC_URL", string("https://sepolia.gateway.tenderly.co"));
        uint256 pinnedBlock = vm.envOr("SEPOLIA_FORK_BLOCK", uint256(0));
        if (pinnedBlock == 0) {
            forkId = vm.createSelectFork(rpc);
        } else {
            forkId = vm.createSelectFork(rpc, pinnedBlock);
        }
        swap = IMultiliquidSwap(SWAP);
    }

    // ---------------------------------------------------------------------
    // Route descriptors
    // ---------------------------------------------------------------------
    function routeSpec(uint256 routeId) internal view returns (RouteSpec memory s) {
        require(routeId <= 11, "route out of range");
        s.routeId = routeId;
        s.feeDecimals = FEE_DECIMALS;
        s.feeUsdValue = FEE_USD_VALUE;
        s.exactIn = routeId % 2 == 0;

        if (routeId <= 1) {
            // USDC <-> RW_NO_WHITELIST (18 decimals). Explicit redemption fee.
            s.assetInID = USDC_ID;
            s.assetOutID = RW_NO_WHITELIST_ID;
            s.delegateID = USDC_ID;
            s.tokenIn = USDC;
            s.tokenOut = RW_NO_WHITELIST_TOKEN;
            s.inDecimals = 6;
            s.outDecimals = 18;
            s.inUsdValue = swap.stablecoinUSDValue(USDC_ID);
            s.outUsdValue = _rwaUsd(RW_NO_WHITELIST_ID);
            s.implicitDiscountWad = 0;
            s.minAmount = s.exactIn ? 1e6 : 1e16; // 1 USDC or 0.01 RWA
            s.maxAmount = s.exactIn ? 1_000_000e6 : 1_000_000e18;
            s.label = "USDC->RW0";
        } else if (routeId <= 3 || routeId == 8 || routeId == 9) {
            // RW_NO_WHITELIST -> USDC. Implicit discount on the RWA leg.
            s.assetInID = RW_NO_WHITELIST_ID;
            s.assetOutID = USDC_ID;
            s.delegateID = USDC_ID;
            s.tokenIn = RW_NO_WHITELIST_TOKEN;
            s.tokenOut = USDC;
            s.inDecimals = 18;
            s.outDecimals = 6;
            s.inUsdValue = _rwaUsd(RW_NO_WHITELIST_ID);
            s.outUsdValue = swap.stablecoinUSDValue(USDC_ID);
            s.implicitDiscountWad = swap.discountRates(USDC_ID, RW_NO_WHITELIST_ID);
            s.minAmount = s.exactIn ? 1e16 : 1e6; // 0.01 RWA or 1 USDC
            s.maxAmount = s.exactIn ? 1_000_000e18 : 1_000_000e6;
            s.label = "RW0->USDC";
        } else if (routeId <= 5) {
            // RW_WHITELIST (6 decimals) -> RW_NO_WHITELIST (18 decimals).
            s.assetInID = RW_WHITELIST_ID;
            s.assetOutID = RW_NO_WHITELIST_ID;
            s.delegateID = USDC_ID;
            s.tokenIn = RW_WHITELIST_TOKEN;
            s.tokenOut = RW_NO_WHITELIST_TOKEN;
            s.inDecimals = 6;
            s.outDecimals = 18;
            s.inUsdValue = _rwaUsd(RW_WHITELIST_ID);
            s.outUsdValue = _rwaUsd(RW_NO_WHITELIST_ID);
            s.implicitDiscountWad = swap.discountRates(USDC_ID, RW_WHITELIST_ID);
            s.minAmount = s.exactIn ? 1e6 : 1e16; // 1 RW1 or 0.01 RW0
            s.maxAmount = s.exactIn ? 1_000_000e6 : 1_000_000e18;
            s.label = "RW1->RW0";
        } else {
            // USDC -> TSY (18 decimals), USDC delegate. Routes 10/11 alias 6/7.
            s.assetInID = USDC_ID;
            s.assetOutID = TSY_ID;
            s.delegateID = USDC_ID;
            s.tokenIn = USDC;
            s.tokenOut = TSY;
            s.inDecimals = 6;
            s.outDecimals = 18;
            s.inUsdValue = swap.stablecoinUSDValue(USDC_ID);
            s.outUsdValue = swap.stablecoinUSDValue(TSY_ID);
            s.implicitDiscountWad = 0;
            s.minAmount = s.exactIn ? 1e6 : 1e18; // 1 USDC or 1 TSY
            s.maxAmount = s.exactIn ? 1_000_000e6 : 1_000_000e18;
            s.label = "USDC->TSY";
        }
    }

    function _rwaUsd(bytes32 rwaID) internal view returns (uint256) {
        address adapter = swap.rwaPriceAdapters(rwaID);
        require(adapter != address(0), "RWA price adapter missing");
        return IPriceAdapter(adapter).getPrice();
    }

    // ---------------------------------------------------------------------
    // Quote helpers
    // ---------------------------------------------------------------------
    function _quote(RouteSpec memory s, uint256 amountIn, uint256 amountOut, address user)
        internal
        view
        returns (IMultiliquidSwap.SwapResolved memory)
    {
        return swap.quoteSwap(
            user,
            IMultiliquidSwap.SwapInputs({
                routeId: s.routeId,
                assetInID: s.assetInID,
                assetOutID: s.assetOutID,
                stablecoinDelegateID: s.delegateID,
                assetInAmt: amountIn,
                assetOutAmt: amountOut
            })
        );
    }

    function _quoteExactIn(RouteSpec memory s, uint256 amountIn, address user)
        internal
        view
        returns (IMultiliquidSwap.SwapResolved memory)
    {
        return _quote(s, amountIn, 0, user);
    }

    function _quoteExactOut(RouteSpec memory s, uint256 amountOut, address user)
        internal
        view
        returns (IMultiliquidSwap.SwapResolved memory)
    {
        return _quote(s, type(uint256).max, amountOut, user);
    }

    function _quoteFor(RouteSpec memory s, uint256 amount, address user)
        internal
        view
        returns (IMultiliquidSwap.SwapResolved memory)
    {
        return s.exactIn ? _quoteExactIn(s, amount, user) : _quoteExactOut(s, amount, user);
    }

    // ---------------------------------------------------------------------
    // USD accounting helpers (all values are WAD, 1e18 = 1 USD)
    // ---------------------------------------------------------------------
    function _toUsd(uint256 amount, uint8 decimals, uint256 usdValueWad) internal pure returns (uint256) {
        return amount * usdValueWad / (10 ** uint256(decimals));
    }

    function _totalFeeUsd(IMultiliquidSwap.SwapResolved memory q, RouteSpec memory s) internal pure returns (uint256) {
        uint256 fees = q.issuerFeeAmt + q.spreadFeeAmt + q.lpFeeAmt;
        return fees * s.feeUsdValue / (10 ** uint256(s.feeDecimals));
    }

    /// @notice Reported user-facing fees only (issuer fee is CP-funded, not deducted).
    function _userFeeUsd(IMultiliquidSwap.SwapResolved memory q, RouteSpec memory s) internal pure returns (uint256) {
        uint256 fees = q.spreadFeeAmt + q.lpFeeAmt;
        return fees * s.feeUsdValue / (10 ** uint256(s.feeDecimals));
    }

    /// @notice inUsd - outUsd - reportedFees. Zero for routes without an implicit
    ///         discount; equal to the implicit discount (plus dust) otherwise.
    function _residual(IMultiliquidSwap.SwapResolved memory q, RouteSpec memory s) internal pure returns (int256) {
        int256 inUsd = int256(_toUsd(q.tokenInAmt, s.inDecimals, s.inUsdValue));
        int256 outUsd = int256(_toUsd(q.tokenOutAmt, s.outDecimals, s.outUsdValue));
        int256 feeUsd = int256(_totalFeeUsd(q, s));
        return inUsd - outUsd - feeUsd;
    }

    function _implicitBound(IMultiliquidSwap.SwapResolved memory q, RouteSpec memory s)
        internal
        pure
        returns (uint256)
    {
        if (s.implicitDiscountWad == 0) return 0;
        uint256 inUsd = _toUsd(q.tokenInAmt, s.inDecimals, s.inUsdValue);
        return inUsd * s.implicitDiscountWad / 1e18;
    }

    function _selector(bytes memory data) internal pure returns (bytes4 sel) {
        if (data.length < 4) return bytes4(0);
        assembly {
            sel := mload(add(data, 32))
        }
    }

    function _feeFields(IMultiliquidSwap.SwapResolved memory q) internal pure returns (string memory) {
        return string.concat(
            "issuer=",
            vm.toString(q.issuerFeeAmt),
            " spread=",
            vm.toString(q.spreadFeeAmt),
            " lp=",
            vm.toString(q.lpFeeAmt)
        );
    }

    // ---------------------------------------------------------------------
    // Storage-slot helpers (fork-local overrides only)
    // ---------------------------------------------------------------------
    function _mappingSlot(bytes32 key, uint256 base) internal pure returns (bytes32) {
        return keccak256(abi.encode(key, base));
    }

    function _mappingSlot2(bytes32 outerKey, bytes32 innerKey, uint256 base) internal pure returns (bytes32) {
        return keccak256(abi.encode(innerKey, keccak256(abi.encode(outerKey, base))));
    }

    function _mappingSlotAddr(bytes32 key, address addr, uint256 base) internal pure returns (bytes32) {
        return keccak256(abi.encode(addr, keccak256(abi.encode(key, base))));
    }

    function _storeUint(bytes32 slot, uint256 value) internal {
        vm.store(address(swap), slot, bytes32(value));
    }

    function _setDiscountRate(bytes32 stableID, bytes32 rwaID, uint256 rate) internal {
        _storeUint(_mappingSlot2(stableID, rwaID, SLOT_DISCOUNT_RATES), rate);
    }

    function _setRedemptionFee(bytes32 stableID, bytes32 rwaID, uint256 rate) internal {
        _storeUint(_mappingSlot2(stableID, rwaID, SLOT_REDEMPTION_FEES), rate);
    }

    function _setIssuerFee(bytes32 stableID, uint256 rate) internal {
        _storeUint(_mappingSlot(stableID, SLOT_ISSUER_PAID_PROTOCOL_FEE_RATES), rate);
    }

    function _setProtocolFeeExempt(bytes32 stableID, bool exempt) internal {
        _storeUint(_mappingSlot(stableID, SLOT_PROTOCOL_FEE_EXEMPT), exempt ? 1 : 0);
    }

    function _setStablecoinAcceptanceFee(bytes32 outStableID, address token, uint256 rate) internal {
        _storeUint(_mappingSlotAddr(outStableID, token, SLOT_STABLECOIN_ACCEPTANCE_FEES), rate);
    }

    function _setStablecoinRedemptionFee(bytes32 outStableID, address token, uint256 rate) internal {
        _storeUint(_mappingSlotAddr(outStableID, token, SLOT_STABLECOIN_REDEMPTION_FEES), rate);
    }

    function _setSpreadTakeRate(uint256 rate) internal {
        _storeUint(bytes32(SLOT_SPREAD_PROTOCOL_TAKE_RATE), rate);
    }

    function _setMaxSwapLegs(uint256 legs) internal {
        _storeUint(bytes32(SLOT_MAX_SWAP_LEGS), legs);
    }

    // ---------------------------------------------------------------------
    // Shared assertions
    // ---------------------------------------------------------------------
    /// @notice Core invariant: USD closes after subtracting all externally
    ///         reported fees, up to (a) one-unit rounding dust and (b) the
    ///         route's implicit discount, which is deliberately not reported
    ///         in the fee fields on RWA-input routes.
    function _assertFeeAccounting(RouteSpec memory s, uint256 amount) internal view {
        IMultiliquidSwap.SwapResolved memory q = _quoteFor(s, amount, TEST_USER);

        if (s.exactIn) {
            assertEq(q.tokenInAmt, amount, "exact-in changed tokenInAmt");
        } else {
            assertEq(q.tokenOutAmt, amount, "exact-out changed tokenOutAmt");
        }
        assertGt(q.tokenInAmt, 0, "zero tokenIn");
        assertGt(q.tokenOutAmt, 0, "zero tokenOut");

        int256 residual = _residual(q, s);
        int256 lower = -DUST_USD_WAD;
        int256 upper = int256(_implicitBound(q, s)) + DUST_USD_WAD;

        assertTrue(residual >= lower, string.concat(s.label, ": residual below -dust; ", _feeFields(q)));
        assertTrue(residual <= upper, string.concat(s.label, ": residual above implicit bound + dust; ", _feeFields(q)));
    }
}
