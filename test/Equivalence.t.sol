// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseForkTest} from "./BaseForkTest.sol";
import {IMultiliquidSwap} from "../src/IMultiliquidSwap.sol";
import {console2} from "forge-std/console2.sol";

/// @notice Group 2: exact-in(X) -> Y -> exact-out(Y) -> X' equivalence.
///         The two quoting paths are implemented separately in the contract, so
///         this checks that they invert within a small, documented rounding
///         bound expressed in raw input-token units.
contract EquivalenceTest is BaseForkTest {
    // The exact-out path rounds its computed input at the route's 6-decimal
    // stablecoin granularity. For an 18-decimal RWA/TSY leg this can move the
    // raw input by up to ~3.24e11 wei (about 9.8e-7 USD in the worst observed
    // case). Measuring the bound in USD keeps the assertion meaningful across
    // 6- and 18-decimal legs. Observed maximum: 9.998e-7 USD.
    uint256 internal constant MAX_EQUIV_DIFF_USD_WAD = 2e12; // 2e-6 USD

    function test_fuzz_equiv_exactIn_then_exactOut_00_01(uint256 seed) public view {
        _assertEquivalence(0, 1, seed, false);
    }

    function test_fuzz_equiv_exactIn_then_exactOut_02_03(uint256 seed) public view {
        _assertEquivalence(2, 3, seed, false);
    }

    function test_fuzz_equiv_exactIn_then_exactOut_04_05(uint256 seed) public view {
        _assertEquivalence(4, 5, seed, false);
    }

    function test_fuzz_equiv_exactIn_then_exactOut_06_07(uint256 seed) public view {
        _assertEquivalence(6, 7, seed, false);
    }

    function test_fuzz_equiv_exactIn_then_exactOut_08_09(uint256 seed) public view {
        _assertEquivalence(8, 9, seed, false);
    }

    function test_fuzz_equiv_exactIn_then_exactOut_10_11(uint256 seed) public view {
        _assertEquivalence(10, 11, seed, false);
    }

    function test_fuzz_equiv_exactOut_then_exactIn_00_01(uint256 seed) public view {
        _assertEquivalence(0, 1, seed, true);
    }

    function test_fuzz_equiv_exactOut_then_exactIn_02_03(uint256 seed) public view {
        _assertEquivalence(2, 3, seed, true);
    }

    function test_fuzz_equiv_exactOut_then_exactIn_04_05(uint256 seed) public view {
        _assertEquivalence(4, 5, seed, true);
    }

    function test_fuzz_equiv_exactOut_then_exactIn_06_07(uint256 seed) public view {
        _assertEquivalence(6, 7, seed, true);
    }

    function test_fuzz_equiv_exactOut_then_exactIn_08_09(uint256 seed) public view {
        _assertEquivalence(8, 9, seed, true);
    }

    function test_fuzz_equiv_exactOut_then_exactIn_10_11(uint256 seed) public view {
        _assertEquivalence(10, 11, seed, true);
    }

    function _assertEquivalence(uint256 evenId, uint256 oddId, uint256 seed, bool reverse) internal view {
        RouteSpec memory sIn = routeSpec(evenId);
        RouteSpec memory sOut = routeSpec(oddId);

        if (!reverse) {
            // X -> Y via exact-in.
            uint256 x = bound(seed, sIn.minAmount, sIn.maxAmount);
            IMultiliquidSwap.SwapResolved memory qIn = _quoteExactIn(sIn, x, TEST_USER);
            uint256 y = qIn.tokenOutAmt;
            assertGt(y, 0, "exact-in produced zero output");

            // Y -> X' via exact-out.
            IMultiliquidSwap.SwapResolved memory qOut = _quoteExactOut(sOut, y, TEST_USER);
            assertEq(qOut.tokenOutAmt, y, "exact-out did not echo requested output");
            uint256 xPrime = qOut.tokenInAmt;
            uint256 diff = x > xPrime ? x - xPrime : xPrime - x;
            uint256 diffUsd = _toUsd(diff, sIn.inDecimals, sIn.inUsdValue);
            assertLe(diffUsd, MAX_EQUIV_DIFF_USD_WAD, string.concat("exact-in/out mismatch on ", sIn.label));
        } else {
            // Y -> X' via exact-out, then X' -> Y' via exact-in.
            uint256 y = bound(seed, sOut.minAmount, sOut.maxAmount);
            IMultiliquidSwap.SwapResolved memory qOut = _quoteExactOut(sOut, y, TEST_USER);
            uint256 xPrime = qOut.tokenInAmt;
            assertGt(xPrime, 0, "exact-out produced zero input");

            IMultiliquidSwap.SwapResolved memory qIn = _quoteExactIn(sIn, xPrime, TEST_USER);
            uint256 yPrime = qIn.tokenOutAmt;
            uint256 diff = y > yPrime ? y - yPrime : yPrime - y;
            uint256 diffUsd = _toUsd(diff, sOut.outDecimals, sOut.outUsdValue);
            assertLe(diffUsd, MAX_EQUIV_DIFF_USD_WAD, string.concat("exact-out/in mismatch on ", sOut.label));
        }
    }

    /// @notice Deterministic sweep that prints the observed maximum deltas.
    function test_equivalence_sweep() public view {
        uint256[8] memory fractions = [uint256(0), 1, 10, 100, 1_000, 10_000, 500_000, 1_000_000];

        for (uint256 base = 0; base <= 10; base += 2) {
            RouteSpec memory sIn = routeSpec(base);
            uint256 maxForwardDiff = _measureForward(base, fractions);
            uint256 maxReverseDiff = _measureReverse(base, fractions);

            assertLe(maxForwardDiff, MAX_EQUIV_DIFF_USD_WAD, "sweep: forward diff");
            assertLe(maxReverseDiff, MAX_EQUIV_DIFF_USD_WAD, "sweep: reverse diff");

            console2.log("pair", base, base + 1);
            console2.log("  label", sIn.label);
            console2.log("  max_forward_diff_usd_wad", maxForwardDiff);
            console2.log("  max_reverse_diff_usd_wad", maxReverseDiff);
        }
    }

    function _measureForward(uint256 base, uint256[8] memory fractions) internal view returns (uint256 maxDiff) {
        RouteSpec memory sIn = routeSpec(base);
        RouteSpec memory sOut = routeSpec(base + 1);

        for (uint256 i = 0; i < fractions.length; i++) {
            uint256 x = sIn.minAmount + (sIn.maxAmount - sIn.minAmount) * fractions[i] / 1e6;
            uint256 y = _quoteExactIn(sIn, x, TEST_USER).tokenOutAmt;
            uint256 xPrime = _quoteExactOut(sOut, y, TEST_USER).tokenInAmt;
            uint256 diff = x > xPrime ? x - xPrime : xPrime - x;
            uint256 diffUsd = _toUsd(diff, sIn.inDecimals, sIn.inUsdValue);
            if (diffUsd > maxDiff) maxDiff = diffUsd;
        }
    }

    function _measureReverse(uint256 base, uint256[8] memory fractions) internal view returns (uint256 maxDiff) {
        RouteSpec memory sIn = routeSpec(base);
        RouteSpec memory sOut = routeSpec(base + 1);

        for (uint256 i = 0; i < fractions.length; i++) {
            uint256 y = sOut.minAmount + (sOut.maxAmount - sOut.minAmount) * fractions[i] / 1e6;
            uint256 xPrime = _quoteExactOut(sOut, y, TEST_USER).tokenInAmt;
            uint256 yPrime = _quoteExactIn(sIn, xPrime, TEST_USER).tokenOutAmt;
            uint256 diff = y > yPrime ? y - yPrime : yPrime - y;
            uint256 diffUsd = _toUsd(diff, sOut.outDecimals, sOut.outUsdValue);
            if (diffUsd > maxDiff) maxDiff = diffUsd;
        }
    }
}
