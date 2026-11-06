// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseForkTest} from "./BaseForkTest.sol";
import {IMultiliquidSwap} from "../src/IMultiliquidSwap.sol";
import {console2} from "forge-std/console2.sol";

/// @notice Group 4: 12-route coverage matrix plus negative validation cases.
contract RouteMatrixTest is BaseForkTest {
    function test_routeMatrix_all12RoutesQuote() public {
        uint256 successCount;

        for (uint256 routeId = 0; routeId <= 11; routeId++) {
            RouteSpec memory s = routeSpec(routeId);
            uint256 amount = s.minAmount * 100;
            IMultiliquidSwap.SwapInputs memory inputs = IMultiliquidSwap.SwapInputs({
                routeId: routeId,
                assetInID: s.assetInID,
                assetOutID: s.assetOutID,
                stablecoinDelegateID: s.delegateID,
                assetInAmt: s.exactIn ? amount : type(uint256).max,
                assetOutAmt: s.exactIn ? 0 : amount
            });

            try swap.quoteSwap(TEST_USER, inputs) returns (IMultiliquidSwap.SwapResolved memory q) {
                successCount++;
                console2.log("route", routeId);
                console2.log("  label", s.label);
                console2.log("  status OK");
                console2.log("  tokenInAmt", q.tokenInAmt);
                console2.log("  tokenOutAmt", q.tokenOutAmt);
                console2.log("  issuerFeeAmt", q.issuerFeeAmt);
                console2.log("  spreadFeeAmt", q.spreadFeeAmt);
                console2.log("  lpFeeAmt", q.lpFeeAmt);

                assertGt(q.tokenInAmt, 0, "zero input");
                assertGt(q.tokenOutAmt, 0, "zero output");
                if (s.exactIn) {
                    assertEq(q.tokenInAmt, amount, "exact-in input mismatch");
                } else {
                    assertEq(q.tokenOutAmt, amount, "exact-out output mismatch");
                }
            } catch (bytes memory reason) {
                bytes4 sel = _selector(reason);
                console2.log("route", routeId);
                console2.log("  label", s.label);
                console2.log("  status REVERT");
                console2.log("  selector", vm.toString(sel));
                console2.log("  name", _revertName(sel));
                revert(string.concat("route ", vm.toString(routeId), " reverted: ", _revertName(sel)));
            }
        }

        assertEq(successCount, 12, "not all 12 routes quoted");
        console2.log("all 12 routes quoted successfully");
    }

    function test_routeValidation_unsupportedRouteId() public {
        RouteSpec memory s = routeSpec(0);
        s.routeId = 12;
        vm.expectRevert(abi.encodeWithSelector(IMultiliquidSwap.UnsupportedRouteId.selector, uint256(12)));
        _quoteExactIn(s, 100e6, TEST_USER);
    }

    function test_routeValidation_identicalAssets() public {
        RouteSpec memory s = routeSpec(0);
        s.assetOutID = USDC_ID;
        s.tokenOut = USDC;
        vm.expectRevert(IMultiliquidSwap.IdenticalAssets.selector);
        _quoteExactIn(s, 100e6, TEST_USER);
    }

    function test_routeValidation_wrongDelegate() public {
        RouteSpec memory s = routeSpec(0);
        s.delegateID = TSY_ID;
        vm.expectRevert(abi.encodeWithSelector(IMultiliquidSwap.InvalidStablecoinDelegateID.selector, TSY_ID, USDC_ID));
        _quoteExactIn(s, 100e6, TEST_USER);
    }

    function test_routeValidation_rwaNotAccepted() public {
        RouteSpec memory s = routeSpec(0);
        s.assetOutID = bytes32(uint256(0x1234));
        vm.expectRevert(IMultiliquidSwap.RWANotAccepted.selector);
        _quoteExactIn(s, 100e6, TEST_USER);
    }

    function test_routeValidation_stablecoinNotAccepted() public {
        RouteSpec memory s = routeSpec(6);
        s.assetOutID = bytes32(uint256(0x1234));
        s.delegateID = s.assetOutID;
        vm.expectRevert(IMultiliquidSwap.StablecoinNotAccepted.selector);
        _quoteExactIn(s, 100e6, TEST_USER);
    }

    /// @notice The deployed ABI only exposes a single-leg quote. The batch
    ///         `swap` entrypoint is the only place where _maxSwapLegs is
    ///         enforced, so the boundary is exercised through reverts before
    ///         any settlement work.
    function test_maxSwapLegs_boundary() public {
        uint256 maxLegs = uint256(vm.load(address(swap), bytes32(SLOT_MAX_SWAP_LEGS)));
        assertGt(maxLegs, 0, "max legs not configured");
        assertLe(maxLegs, 64, "implausible max legs");

        IMultiliquidSwap.ApprovalPermit memory permit;

        // 0 legs is always rejected.
        IMultiliquidSwap.SwapInputs[] memory zero = new IMultiliquidSwap.SwapInputs[](0);
        vm.expectRevert(IMultiliquidSwap.InvalidLegCount.selector);
        swap.swap(TEST_USER, RECEIVER, zero, permit);

        // maxLegs + 1 is rejected by the length check.
        IMultiliquidSwap.SwapInputs[] memory tooMany = new IMultiliquidSwap.SwapInputs[](maxLegs + 1);
        vm.expectRevert(IMultiliquidSwap.InvalidLegCount.selector);
        swap.swap(TEST_USER, RECEIVER, tooMany, permit);

        // Exactly maxLegs passes the length check and fails later on route
        // validation, not on InvalidLegCount.
        IMultiliquidSwap.SwapInputs[] memory atMax = new IMultiliquidSwap.SwapInputs[](maxLegs);
        (bool ok, bytes memory data) = address(swap)
            .call(abi.encodeWithSelector(IMultiliquidSwap.swap.selector, TEST_USER, RECEIVER, atMax, permit));
        assertFalse(ok, "empty legs unexpectedly succeeded");
        bytes4 sel = _selector(data);
        assertTrue(sel != IMultiliquidSwap.InvalidLegCount.selector, "max legs wrongly rejected");

        // A zero configured maximum disables swap entirely.
        _setMaxSwapLegs(0);
        assertEq(uint256(vm.load(address(swap), bytes32(SLOT_MAX_SWAP_LEGS))), 0, "override");
        IMultiliquidSwap.SwapInputs[] memory one = new IMultiliquidSwap.SwapInputs[](1);
        vm.expectRevert(IMultiliquidSwap.InvalidLegCount.selector);
        swap.swap(TEST_USER, RECEIVER, one, permit);

        console2.log("maxSwapLegs boundary: 0 and >max rejected; max accepted by length check");
        console2.log("  max_legs", maxLegs);
        console2.log("  at_max_later_selector", vm.toString(sel));
        console2.log("  at_max_later_name", _revertName(sel));
    }

    function _revertName(bytes4 sel) internal pure returns (string memory) {
        if (sel == IMultiliquidSwap.UnsupportedRouteId.selector) return "UnsupportedRouteId";
        if (sel == IMultiliquidSwap.IdenticalAssets.selector) return "IdenticalAssets";
        if (sel == IMultiliquidSwap.IdenticalStablecoins.selector) return "IdenticalStablecoins";
        if (sel == IMultiliquidSwap.InvalidStablecoinDelegateID.selector) {
            return "InvalidStablecoinDelegateID";
        }
        if (sel == IMultiliquidSwap.RWANotAccepted.selector) return "RWANotAccepted";
        if (sel == IMultiliquidSwap.StablecoinNotAccepted.selector) return "StablecoinNotAccepted";
        if (sel == IMultiliquidSwap.InvalidLegCount.selector) return "InvalidLegCount";
        if (sel == IMultiliquidSwap.InvalidSignature.selector) return "InvalidSignature";
        if (sel == IMultiliquidSwap.InvalidSwapAddress.selector) return "InvalidSwapAddress";
        return "Unknown";
    }
}
