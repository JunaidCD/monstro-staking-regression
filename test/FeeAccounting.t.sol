// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseForkTest} from "./BaseForkTest.sol";
import {IMultiliquidSwap} from "../src/IMultiliquidSwap.sol";
import {console2} from "forge-std/console2.sol";

/// @notice Group 1: quote-level fee accounting closure for every route.
///         The invariant is evaluated in USD WAD:
///             tokenInUsd - tokenOutUsd - reportedFeesUsd == implicitDiscount + dust
///         The implicit discount is a deliberate, unreported CP discount on
///         RWA-input routes, so it is bounded separately instead of being
///         treated as an accounting leak.
contract FeeAccountingTest is BaseForkTest {
    function test_fuzz_feeAccounting_route00(uint256 seed) public {
        _fuzzRoute(0, seed);
    }

    function test_fuzz_feeAccounting_route01(uint256 seed) public {
        _fuzzRoute(1, seed);
    }

    function test_fuzz_feeAccounting_route02(uint256 seed) public {
        _fuzzRoute(2, seed);
    }

    function test_fuzz_feeAccounting_route03(uint256 seed) public {
        _fuzzRoute(3, seed);
    }

    function test_fuzz_feeAccounting_route04(uint256 seed) public {
        _fuzzRoute(4, seed);
    }

    function test_fuzz_feeAccounting_route05(uint256 seed) public {
        _fuzzRoute(5, seed);
    }

    function test_fuzz_feeAccounting_route06(uint256 seed) public {
        _fuzzRoute(6, seed);
    }

    function test_fuzz_feeAccounting_route07(uint256 seed) public {
        _fuzzRoute(7, seed);
    }

    function test_fuzz_feeAccounting_route08(uint256 seed) public {
        _fuzzRoute(8, seed);
    }

    function test_fuzz_feeAccounting_route09(uint256 seed) public {
        _fuzzRoute(9, seed);
    }

    function test_fuzz_feeAccounting_route10(uint256 seed) public {
        _fuzzRoute(10, seed);
    }

    function test_fuzz_feeAccounting_route11(uint256 seed) public {
        _fuzzRoute(11, seed);
    }

    function _fuzzRoute(uint256 routeId, uint256 seed) internal view {
        RouteSpec memory s = routeSpec(routeId);
        uint256 amount = bound(seed, s.minAmount, s.maxAmount);
        _assertFeeAccounting(s, amount);
    }

    /// @notice Deterministic sweep that prints the observed residual distribution
    ///         for every route. Fuzz tests above enforce the same bounds.
    function test_feeAccounting_residualDistribution() public view {
        // Fractions of the route's bounded range, denominator 1e6.
        // 0, 0.0001%, 0.001%, 0.01%, 0.1%, 1%, 50%, 90%, 100%.
        uint256[9] memory fractions = [uint256(0), 1, 10, 100, 1_000, 10_000, 500_000, 900_000, 1_000_000];

        for (uint256 routeId = 0; routeId <= 11; routeId++) {
            RouteSpec memory s = routeSpec(routeId);
            int256 minResidual = type(int256).max;
            int256 maxResidual = type(int256).min;
            int256 maxPositiveBps = 0;
            int256 maxNegativeBps = 0;
            uint256 maxImplicitBound = 0;

            for (uint256 i = 0; i < fractions.length; i++) {
                uint256 frac = fractions[i];
                uint256 amount = s.minAmount + (s.maxAmount - s.minAmount) * frac / 1e6;
                if (amount < s.minAmount) amount = s.minAmount;

                IMultiliquidSwap.SwapResolved memory q = _quoteFor(s, amount, TEST_USER);
                int256 residual = _residual(q, s);
                uint256 inUsd = _toUsd(q.tokenInAmt, s.inDecimals, s.inUsdValue);
                int256 bps = residual * 10_000 / int256(inUsd);

                if (residual < minResidual) minResidual = residual;
                if (residual > maxResidual) maxResidual = residual;
                if (bps > maxPositiveBps) maxPositiveBps = bps;
                if (bps < maxNegativeBps) maxNegativeBps = bps;

                uint256 implicitBound = _implicitBound(q, s);
                if (implicitBound > maxImplicitBound) maxImplicitBound = implicitBound;

                // Same invariant as the fuzz tests.
                assertTrue(residual >= -DUST_USD_WAD, string.concat(s.label, ": residual below -dust"));
                assertTrue(
                    residual <= int256(implicitBound) + DUST_USD_WAD,
                    string.concat(s.label, ": residual above implicit bound + dust")
                );
            }

            console2.log("route", routeId);
            console2.log("  label", s.label);
            console2.log("  residual_min_usd_wad", vm.toString(minResidual));
            console2.log("  residual_max_usd_wad", vm.toString(maxResidual));
            console2.log("  residual_max_positive_bps", vm.toString(maxPositiveBps));
            console2.log("  residual_max_negative_bps", vm.toString(maxNegativeBps));
            console2.log("  implicit_bound_max_usd_wad", maxImplicitBound);
            console2.log("  dust_usd_wad", uint256(DUST_USD_WAD));
        }
    }
}
