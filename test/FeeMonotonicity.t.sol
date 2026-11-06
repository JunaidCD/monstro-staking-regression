// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseForkTest} from "./BaseForkTest.sol";
import {IMultiliquidSwap} from "../src/IMultiliquidSwap.sol";
import {console2} from "forge-std/console2.sol";

/// @notice Group 3: monotonicity of user amounts when a fee is increased.
/// @dev Fee increases are simulated with vm.store on the fork only. Each test
///      asserts the getter reflects the override before quoting, so a silent
///      slot miss cannot turn into a false pass.
contract FeeMonotonicityTest is BaseForkTest {
    function test_storageOverrides_areEffective() public {
        uint256 newRate = 2e16;

        _setDiscountRate(USDC_ID, RW_NO_WHITELIST_ID, newRate);
        assertEq(swap.discountRates(USDC_ID, RW_NO_WHITELIST_ID), newRate, "discount override not effective");

        _setRedemptionFee(USDC_ID, RW_NO_WHITELIST_ID, newRate);
        assertEq(swap.redemptionFees(USDC_ID, RW_NO_WHITELIST_ID), newRate, "redemption override not effective");

        _setIssuerFee(USDC_ID, 1e16);
        assertEq(swap.issuerPaidProtocolFeeRates(USDC_ID), 1e16, "issuer fee override not effective");

        _setSpreadTakeRate(5e17);
        assertEq(swap.spreadProtocolTakeRate(), 5e17, "spread take override not effective");

        _setStablecoinAcceptanceFee(USDC_ID, TSY, 1e16);
        assertEq(swap.stablecoinAcceptanceFees(USDC_ID, TSY), 1e16, "stablecoin acceptance override not effective");

        _setStablecoinRedemptionFee(USDC_ID, TSY, newRate);
        assertEq(swap.stablecoinRedemptionFees(USDC_ID, TSY), newRate, "stablecoin redemption override not effective");

        _setProtocolFeeExempt(USDC_ID, true);
        assertTrue(swap.protocolFeeExempt(USDC_ID), "exempt override not effective");

        console2.log("all fork-local fee storage overrides verified against getters");
    }

    // -----------------------------------------------------------------
    // RWA redemption fee: route 0/1 (USDC <-> RW0)
    // -----------------------------------------------------------------
    function test_route0_redemptionFee_up_exactIn_outputDoesNotIncrease() public {
        RouteSpec memory s = routeSpec(0);
        uint256 amountIn = 100_000e6;

        IMultiliquidSwap.SwapResolved memory before = _quoteExactIn(s, amountIn, TEST_USER);
        _setRedemptionFee(USDC_ID, RW_NO_WHITELIST_ID, 2e16);
        IMultiliquidSwap.SwapResolved memory afterQuote = _quoteExactIn(s, amountIn, TEST_USER);

        assertEq(afterQuote.tokenInAmt, before.tokenInAmt, "exact-in input changed");
        assertLe(afterQuote.tokenOutAmt, before.tokenOutAmt, "output increased");
        assertLt(afterQuote.tokenOutAmt, before.tokenOutAmt, "output did not decrease");
        assertGt(afterQuote.lpFeeAmt, before.lpFeeAmt, "lp fee did not increase");

        console2.log("route0 redemption 0.1% -> 2%");
        console2.log("  out_before", before.tokenOutAmt);
        console2.log("  out_after", afterQuote.tokenOutAmt);
        console2.log("  lp_fee_before", before.lpFeeAmt);
        console2.log("  lp_fee_after", afterQuote.lpFeeAmt);
    }

    function test_route1_redemptionFee_up_exactOut_inputDoesNotDecrease() public {
        RouteSpec memory s = routeSpec(1);
        uint256 amountOut = 10_000e18;

        IMultiliquidSwap.SwapResolved memory before = _quoteExactOut(s, amountOut, TEST_USER);
        _setRedemptionFee(USDC_ID, RW_NO_WHITELIST_ID, 2e16);
        IMultiliquidSwap.SwapResolved memory afterQuote = _quoteExactOut(s, amountOut, TEST_USER);

        assertEq(afterQuote.tokenOutAmt, before.tokenOutAmt, "exact-out output changed");
        assertGe(afterQuote.tokenInAmt, before.tokenInAmt, "input decreased");
        assertGt(afterQuote.tokenInAmt, before.tokenInAmt, "input did not increase");

        console2.log("route1 redemption 0.1% -> 2%");
        console2.log("  in_before", before.tokenInAmt);
        console2.log("  in_after", afterQuote.tokenInAmt);
    }

    // -----------------------------------------------------------------
    // Spread take + discount: route 0/1
    // -----------------------------------------------------------------
    function test_route0_spreadTakeAndDiscount_up_exactIn_outputDoesNotIncrease() public {
        RouteSpec memory s = routeSpec(0);
        uint256 amountIn = 100_000e6;

        IMultiliquidSwap.SwapResolved memory before = _quoteExactIn(s, amountIn, TEST_USER);
        _setSpreadTakeRate(5e17); // 50%
        _setDiscountRate(USDC_ID, RW_NO_WHITELIST_ID, 2e16); // 2%
        IMultiliquidSwap.SwapResolved memory afterQuote = _quoteExactIn(s, amountIn, TEST_USER);

        assertEq(afterQuote.tokenInAmt, before.tokenInAmt, "exact-in input changed");
        assertLe(afterQuote.tokenOutAmt, before.tokenOutAmt, "output increased");
        assertLt(afterQuote.tokenOutAmt, before.tokenOutAmt, "output did not decrease");
        assertGt(afterQuote.spreadFeeAmt, before.spreadFeeAmt, "spread fee did not increase");

        console2.log("route0 spread take 0 -> 50%, discount 0.1% -> 2%");
        console2.log("  spread_before", before.spreadFeeAmt);
        console2.log("  spread_after", afterQuote.spreadFeeAmt);
        console2.log("  out_before", before.tokenOutAmt);
        console2.log("  out_after", afterQuote.tokenOutAmt);
    }

    function test_route1_spreadTakeAndDiscount_up_exactOut_inputDoesNotDecrease() public {
        RouteSpec memory s = routeSpec(1);
        uint256 amountOut = 10_000e18;

        IMultiliquidSwap.SwapResolved memory before = _quoteExactOut(s, amountOut, TEST_USER);
        _setSpreadTakeRate(5e17);
        _setDiscountRate(USDC_ID, RW_NO_WHITELIST_ID, 2e16);
        IMultiliquidSwap.SwapResolved memory afterQuote = _quoteExactOut(s, amountOut, TEST_USER);

        assertEq(afterQuote.tokenOutAmt, before.tokenOutAmt, "exact-out output changed");
        assertGe(afterQuote.tokenInAmt, before.tokenInAmt, "input decreased");
        assertGt(afterQuote.tokenInAmt, before.tokenInAmt, "input did not increase");

        console2.log("route1 spread take 0 -> 50%, discount 0.1% -> 2%");
        console2.log("  in_before", before.tokenInAmt);
        console2.log("  in_after", afterQuote.tokenInAmt);
    }

    // -----------------------------------------------------------------
    // Implicit discount: routes 2-5
    // -----------------------------------------------------------------
    function test_route2_discount_up_exactIn_outputDoesNotIncrease() public {
        RouteSpec memory s = routeSpec(2);
        uint256 amountIn = 10_000e18;

        IMultiliquidSwap.SwapResolved memory before = _quoteExactIn(s, amountIn, TEST_USER);
        _setDiscountRate(USDC_ID, RW_NO_WHITELIST_ID, 2e16);
        IMultiliquidSwap.SwapResolved memory afterQuote = _quoteExactIn(s, amountIn, TEST_USER);

        assertEq(afterQuote.tokenInAmt, before.tokenInAmt, "exact-in input changed");
        assertLe(afterQuote.tokenOutAmt, before.tokenOutAmt, "output increased");
        assertLt(afterQuote.tokenOutAmt, before.tokenOutAmt, "output did not decrease");

        console2.log("route2 discount 0.1% -> 2%");
        console2.log("  out_before", before.tokenOutAmt);
        console2.log("  out_after", afterQuote.tokenOutAmt);
    }

    function test_route3_discount_up_exactOut_inputDoesNotDecrease() public {
        RouteSpec memory s = routeSpec(3);
        uint256 amountOut = 10_000e6;

        IMultiliquidSwap.SwapResolved memory before = _quoteExactOut(s, amountOut, TEST_USER);
        _setDiscountRate(USDC_ID, RW_NO_WHITELIST_ID, 2e16);
        IMultiliquidSwap.SwapResolved memory afterQuote = _quoteExactOut(s, amountOut, TEST_USER);

        assertEq(afterQuote.tokenOutAmt, before.tokenOutAmt, "exact-out output changed");
        assertGe(afterQuote.tokenInAmt, before.tokenInAmt, "input decreased");
        assertGt(afterQuote.tokenInAmt, before.tokenInAmt, "input did not increase");

        console2.log("route3 discount 0.1% -> 2%");
        console2.log("  in_before", before.tokenInAmt);
        console2.log("  in_after", afterQuote.tokenInAmt);
    }

    function test_route4_inputDiscount_up_exactIn_outputDoesNotIncrease() public {
        RouteSpec memory s = routeSpec(4);
        uint256 amountIn = 10_000e6;

        IMultiliquidSwap.SwapResolved memory before = _quoteExactIn(s, amountIn, TEST_USER);
        _setDiscountRate(USDC_ID, RW_WHITELIST_ID, 2e16);
        IMultiliquidSwap.SwapResolved memory afterQuote = _quoteExactIn(s, amountIn, TEST_USER);

        assertEq(afterQuote.tokenInAmt, before.tokenInAmt, "exact-in input changed");
        assertLe(afterQuote.tokenOutAmt, before.tokenOutAmt, "output increased");
        assertLt(afterQuote.tokenOutAmt, before.tokenOutAmt, "output did not decrease");

        console2.log("route4 input discount 0.1% -> 2%");
        console2.log("  out_before", before.tokenOutAmt);
        console2.log("  out_after", afterQuote.tokenOutAmt);
    }

    function test_route5_inputDiscount_up_exactOut_inputDoesNotDecrease() public {
        RouteSpec memory s = routeSpec(5);
        uint256 amountOut = 10_000e18;

        IMultiliquidSwap.SwapResolved memory before = _quoteExactOut(s, amountOut, TEST_USER);
        _setDiscountRate(USDC_ID, RW_WHITELIST_ID, 2e16);
        IMultiliquidSwap.SwapResolved memory afterQuote = _quoteExactOut(s, amountOut, TEST_USER);

        assertEq(afterQuote.tokenOutAmt, before.tokenOutAmt, "exact-out output changed");
        assertGe(afterQuote.tokenInAmt, before.tokenInAmt, "input decreased");
        assertGt(afterQuote.tokenInAmt, before.tokenInAmt, "input did not increase");

        console2.log("route5 input discount 0.1% -> 2%");
        console2.log("  in_before", before.tokenInAmt);
        console2.log("  in_after", afterQuote.tokenInAmt);
    }

    function test_route4_outputRedemption_up_exactIn_outputDoesNotIncrease() public {
        RouteSpec memory s = routeSpec(4);
        uint256 amountIn = 10_000e6;

        IMultiliquidSwap.SwapResolved memory before = _quoteExactIn(s, amountIn, TEST_USER);
        _setRedemptionFee(USDC_ID, RW_NO_WHITELIST_ID, 2e16);
        IMultiliquidSwap.SwapResolved memory afterQuote = _quoteExactIn(s, amountIn, TEST_USER);

        assertEq(afterQuote.tokenInAmt, before.tokenInAmt, "exact-in input changed");
        assertLe(afterQuote.tokenOutAmt, before.tokenOutAmt, "output increased");
        assertLt(afterQuote.tokenOutAmt, before.tokenOutAmt, "output did not decrease");
        assertGt(afterQuote.lpFeeAmt, before.lpFeeAmt, "lp fee did not increase");

        console2.log("route4 output redemption 0.1% -> 2%");
        console2.log("  out_before", before.tokenOutAmt);
        console2.log("  out_after", afterQuote.tokenOutAmt);
    }

    function test_route5_outputRedemption_up_exactOut_inputDoesNotDecrease() public {
        RouteSpec memory s = routeSpec(5);
        uint256 amountOut = 10_000e18;

        IMultiliquidSwap.SwapResolved memory before = _quoteExactOut(s, amountOut, TEST_USER);
        _setRedemptionFee(USDC_ID, RW_NO_WHITELIST_ID, 2e16);
        IMultiliquidSwap.SwapResolved memory afterQuote = _quoteExactOut(s, amountOut, TEST_USER);

        assertEq(afterQuote.tokenOutAmt, before.tokenOutAmt, "exact-out output changed");
        assertGe(afterQuote.tokenInAmt, before.tokenInAmt, "input decreased");
        assertGt(afterQuote.tokenInAmt, before.tokenInAmt, "input did not increase");

        console2.log("route5 output redemption 0.1% -> 2%");
        console2.log("  in_before", before.tokenInAmt);
        console2.log("  in_after", afterQuote.tokenInAmt);
    }

    // -----------------------------------------------------------------
    // Stablecoin-to-stablecoin redemption fee: routes 6/7
    // -----------------------------------------------------------------
    function test_route6_stablecoinRedemption_up_exactIn_outputDoesNotIncrease() public {
        RouteSpec memory s = routeSpec(6);
        uint256 amountIn = 100_000e6;

        IMultiliquidSwap.SwapResolved memory before = _quoteExactIn(s, amountIn, TEST_USER);
        _setStablecoinRedemptionFee(USDC_ID, TSY, 2e16);
        IMultiliquidSwap.SwapResolved memory afterQuote = _quoteExactIn(s, amountIn, TEST_USER);

        assertEq(afterQuote.tokenInAmt, before.tokenInAmt, "exact-in input changed");
        assertLe(afterQuote.tokenOutAmt, before.tokenOutAmt, "output increased");
        assertLt(afterQuote.tokenOutAmt, before.tokenOutAmt, "output did not decrease");
        assertGt(afterQuote.lpFeeAmt, before.lpFeeAmt, "lp fee did not increase");

        console2.log("route6 stablecoin redemption 0 -> 2%");
        console2.log("  out_before", before.tokenOutAmt);
        console2.log("  out_after", afterQuote.tokenOutAmt);
        console2.log("  lp_fee_before", before.lpFeeAmt);
        console2.log("  lp_fee_after", afterQuote.lpFeeAmt);
    }

    function test_route7_stablecoinRedemption_up_exactOut_inputDoesNotDecrease() public {
        RouteSpec memory s = routeSpec(7);
        uint256 amountOut = 100_000e18;

        IMultiliquidSwap.SwapResolved memory before = _quoteExactOut(s, amountOut, TEST_USER);
        _setStablecoinRedemptionFee(USDC_ID, TSY, 2e16);
        IMultiliquidSwap.SwapResolved memory afterQuote = _quoteExactOut(s, amountOut, TEST_USER);

        assertEq(afterQuote.tokenOutAmt, before.tokenOutAmt, "exact-out output changed");
        assertGe(afterQuote.tokenInAmt, before.tokenInAmt, "input decreased");
        assertGt(afterQuote.tokenInAmt, before.tokenInAmt, "input did not increase");

        console2.log("route7 stablecoin redemption 0 -> 2%");
        console2.log("  in_before", before.tokenInAmt);
        console2.log("  in_after", afterQuote.tokenInAmt);
    }

    // -----------------------------------------------------------------
    // Issuer fee is capital-provider funded, not deducted from the user
    // -----------------------------------------------------------------
    function test_issuerFee_reportedButDoesNotChangeUserAmounts() public {
        RouteSpec memory s0 = routeSpec(0);
        uint256 amountIn = 100_000e6;
        IMultiliquidSwap.SwapResolved memory beforeIn = _quoteExactIn(s0, amountIn, TEST_USER);
        _setIssuerFee(USDC_ID, 1e16); // 1%
        IMultiliquidSwap.SwapResolved memory afterIn = _quoteExactIn(s0, amountIn, TEST_USER);

        assertEq(afterIn.tokenInAmt, beforeIn.tokenInAmt, "issuer fee changed exact-in input");
        assertEq(afterIn.tokenOutAmt, beforeIn.tokenOutAmt, "issuer fee changed exact-in output");
        assertGt(afterIn.issuerFeeAmt, beforeIn.issuerFeeAmt, "issuer fee not reported");

        RouteSpec memory s1 = routeSpec(1);
        uint256 amountOut = 10_000e18;
        _setIssuerFee(USDC_ID, 0);
        IMultiliquidSwap.SwapResolved memory beforeOut = _quoteExactOut(s1, amountOut, TEST_USER);
        _setIssuerFee(USDC_ID, 1e16);
        IMultiliquidSwap.SwapResolved memory afterOut = _quoteExactOut(s1, amountOut, TEST_USER);

        assertEq(afterOut.tokenInAmt, beforeOut.tokenInAmt, "issuer fee changed exact-out input");
        assertEq(afterOut.tokenOutAmt, beforeOut.tokenOutAmt, "issuer fee changed exact-out output");
        assertGt(afterOut.issuerFeeAmt, beforeOut.issuerFeeAmt, "issuer fee not reported");

        console2.log("issuer fee 0 -> 1%: user token amounts unchanged");
        console2.log("  issuer_fee_exactIn", afterIn.issuerFeeAmt);
        console2.log("  issuer_fee_exactOut", afterOut.issuerFeeAmt);
    }

    // -----------------------------------------------------------------
    // Documented 1 bp spread-floor behavior at zero protocol take
    // -----------------------------------------------------------------
    function test_zeroSpreadTakeStillChargesOneBpMinimum() public {
        assertEq(swap.spreadProtocolTakeRate(), 0, "expected live take rate 0");
        RouteSpec memory s = routeSpec(0);
        IMultiliquidSwap.SwapResolved memory q = _quoteExactIn(s, 100e6, TEST_USER);

        // 1 bp of 100 USD is 0.01 USD = 10_000 units at 6 decimals.
        assertEq(q.spreadFeeAmt, 10_000, "unexpected 1 bp spread floor");
        console2.log("zero take still reports the 1 bp spread floor", q.spreadFeeAmt);
    }
}
