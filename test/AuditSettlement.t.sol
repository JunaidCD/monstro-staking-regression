// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseForkTest} from "./BaseForkTest.sol";
import {IMultiliquidSwap} from "../src/IMultiliquidSwap.sol";
import {IERC20Minimal, IMintableERC20} from "../src/IERC20Minimal.sol";
import {console2} from "forge-std/console2.sol";

contract AuditSettlementTest is BaseForkTest {
    function _fundApprove(address user, address token, address spender, uint256 amount) internal {
        IMintableERC20(token).mint(user, amount);
        vm.prank(user);
        IERC20Minimal(token).approve(spender, amount);
    }

    function test_route8_exactIn_revertsInsufficientCredits() public {
        uint256 userPk = 0xA11CE;
        address user = vm.addr(userPk);
        uint256 amountIn = 10e18; // 10 RW0

        RouteSpec memory s = routeSpec(8);
        IMultiliquidSwap.SwapResolved memory q = _quoteExactIn(s, amountIn, user);
        console2.log("route8 quote tokenIn", q.tokenInAmt);
        console2.log("route8 quote tokenOut", q.tokenOutAmt);
        console2.log("route8 quote issuer", q.issuerFeeAmt);
        console2.log("route8 quote spread", q.spreadFeeAmt);
        console2.log("route8 quote lp", q.lpFeeAmt);

        _fundApprove(user, RW_NO_WHITELIST_TOKEN, USDC_DELEGATE, amountIn);

        IMultiliquidSwap.SwapInputs[] memory legs = new IMultiliquidSwap.SwapInputs[](1);
        legs[0] = IMultiliquidSwap.SwapInputs({
            routeId: 8,
            assetInID: RW_NO_WHITELIST_ID,
            assetOutID: USDC_ID,
            stablecoinDelegateID: USDC_ID,
            assetInAmt: amountIn,
            assetOutAmt: 0
        });

        IMultiliquidSwap.ApprovalPermit memory permit;
        vm.prank(user);
        vm.expectPartialRevert(ITSYDelegateErrors.InsufficientCredits.selector);
        swap.swap(user, user, legs, permit);
    }

    function test_route10_exactIn_settles() public {
        address user = address(0xB0B);
        uint256 amountIn = 10e6; // 10 USDC

        RouteSpec memory s = routeSpec(10);
        IMultiliquidSwap.SwapResolved memory q = _quoteExactIn(s, amountIn, user);
        console2.log("route10 quote tokenIn", q.tokenInAmt);
        console2.log("route10 quote tokenOut", q.tokenOutAmt);

        _fundApprove(user, USDC, USDC_DELEGATE, amountIn);

        IMultiliquidSwap.SwapInputs[] memory legs = new IMultiliquidSwap.SwapInputs[](1);
        legs[0] = IMultiliquidSwap.SwapInputs({
            routeId: 10,
            assetInID: USDC_ID,
            assetOutID: TSY_ID,
            stablecoinDelegateID: USDC_ID,
            assetInAmt: amountIn,
            assetOutAmt: 0
        });

        IMultiliquidSwap.ApprovalPermit memory permit;
        uint256 beforeUsdc = IERC20Minimal(USDC).balanceOf(user);
        uint256 beforeTsy = IERC20Minimal(TSY).balanceOf(user);
        vm.prank(user);
        swap.swap(user, user, legs, permit);
        console2.log("route10 usdc delta", beforeUsdc - IERC20Minimal(USDC).balanceOf(user));
        console2.log("route10 tsy delta", IERC20Minimal(TSY).balanceOf(user) - beforeTsy);
    }


    function test_route9_exactOut_revertsInsufficientCredits() public {
        address user = address(0xCAFE2);
        uint256 amountOut = 1e6; // 1 USDC

        RouteSpec memory s = routeSpec(9);
        IMultiliquidSwap.SwapResolved memory q = _quoteExactOut(s, amountOut, user);
        console2.log("route9 quote tokenIn", q.tokenInAmt);
        console2.log("route9 quote tokenOut", q.tokenOutAmt);

        _fundApprove(user, RW_NO_WHITELIST_TOKEN, USDC_DELEGATE, q.tokenInAmt);

        IMultiliquidSwap.SwapInputs[] memory legs = new IMultiliquidSwap.SwapInputs[](1);
        legs[0] = IMultiliquidSwap.SwapInputs({
            routeId: 9,
            assetInID: RW_NO_WHITELIST_ID,
            assetOutID: USDC_ID,
            stablecoinDelegateID: USDC_ID,
            assetInAmt: q.tokenInAmt,
            assetOutAmt: amountOut
        });

        IMultiliquidSwap.ApprovalPermit memory permit;
        vm.prank(user);
        vm.expectPartialRevert(ITSYDelegateErrors.InsufficientCredits.selector);
        swap.swap(user, user, legs, permit);
    }

    function test_route11_exactOut_settles() public {
        address user = address(0xCAFE3);
        uint256 amountOut = 10e18; // 10 TSY

        RouteSpec memory s = routeSpec(11);
        IMultiliquidSwap.SwapResolved memory q = _quoteExactOut(s, amountOut, user);
        console2.log("route11 quote tokenIn", q.tokenInAmt);
        console2.log("route11 quote tokenOut", q.tokenOutAmt);

        _fundApprove(user, USDC, USDC_DELEGATE, q.tokenInAmt);

        IMultiliquidSwap.SwapInputs[] memory legs = new IMultiliquidSwap.SwapInputs[](1);
        legs[0] = IMultiliquidSwap.SwapInputs({
            routeId: 11,
            assetInID: USDC_ID,
            assetOutID: TSY_ID,
            stablecoinDelegateID: USDC_ID,
            assetInAmt: q.tokenInAmt,
            assetOutAmt: amountOut
        });

        IMultiliquidSwap.ApprovalPermit memory permit;
        vm.prank(user);
        swap.swap(user, user, legs, permit);
    }

}

contract AuditSettlementRoutesTest is BaseForkTest {
    function _fundApprove(address user, address token, address spender, uint256 amount) internal {
        IMintableERC20(token).mint(user, amount);
        vm.prank(user);
        IERC20Minimal(token).approve(spender, amount);
    }

    function test_route2_exactIn_settles() public {
        address user = address(0xD00D);
        uint256 amountIn = 10e18;
        RouteSpec memory s = routeSpec(2);
        IMultiliquidSwap.SwapResolved memory q = _quoteExactIn(s, amountIn, user);
        console2.log("route2 quote in", q.tokenInAmt, "out", q.tokenOutAmt);
        _fundApprove(user, RW_NO_WHITELIST_TOKEN, USDC_DELEGATE, amountIn);
        IMultiliquidSwap.SwapInputs[] memory legs = new IMultiliquidSwap.SwapInputs[](1);
        legs[0] = IMultiliquidSwap.SwapInputs(2, RW_NO_WHITELIST_ID, USDC_ID, USDC_ID, amountIn, 0);
        IMultiliquidSwap.ApprovalPermit memory permit;
        vm.prank(user);
        swap.swap(user, user, legs, permit);
    }

    function test_route3_exactOut_settles() public {
        address user = address(0xD00E);
        uint256 amountOut = 10e6;
        RouteSpec memory s = routeSpec(3);
        IMultiliquidSwap.SwapResolved memory q = _quoteExactOut(s, amountOut, user);
        console2.log("route3 quote in", q.tokenInAmt, "out", q.tokenOutAmt);
        _fundApprove(user, RW_NO_WHITELIST_TOKEN, USDC_DELEGATE, q.tokenInAmt);
        IMultiliquidSwap.SwapInputs[] memory legs = new IMultiliquidSwap.SwapInputs[](1);
        legs[0] = IMultiliquidSwap.SwapInputs(3, RW_NO_WHITELIST_ID, USDC_ID, USDC_ID, q.tokenInAmt, amountOut);
        IMultiliquidSwap.ApprovalPermit memory permit;
        vm.prank(user);
        swap.swap(user, user, legs, permit);
    }
}

interface ITSYDelegateView {
    function credits(address) external view returns (uint256);
    function totalWithheldCredits(address) external view returns (uint256);
    function getYieldAmount(address,uint256,bool) external view returns (uint256);
}

interface ITSYDelegateErrors {
    error InsufficientCredits(uint256 requested, uint256 available);
}

contract AuditYieldInputTest is BaseForkTest {
    function _fundApprove(address user, address token, address spender, uint256 amount) internal {
        IMintableERC20(token).mint(user, amount);
        vm.prank(user);
        IERC20Minimal(token).approve(spender, amount);
    }

    function test_tsyInput_usesOutputDelegateWithoutCredits() public {
        address user = address(0xE0E0);
        uint256 usdcIn = 100e6;

        // Buy TSY through the normal USDC-delegate route.
        _fundApprove(user, USDC, USDC_DELEGATE, usdcIn);
        IMultiliquidSwap.SwapInputs[] memory buy = new IMultiliquidSwap.SwapInputs[](1);
        buy[0] = IMultiliquidSwap.SwapInputs(10, USDC_ID, TSY_ID, USDC_ID, usdcIn, 0);
        IMultiliquidSwap.ApprovalPermit memory permit;
        vm.prank(user);
        swap.swap(user, user, buy, permit);

        uint256 tsyBal = IERC20Minimal(TSY).balanceOf(user);
        uint256 creditsBefore = ITSYDelegateView(TSY_DELEGATE).credits(user);
        uint256 withheldBefore = ITSYDelegateView(TSY_DELEGATE).totalWithheldCredits(user);
        console2.log("after buy tsy", tsyBal);
        console2.log("credits", creditsBefore);
        console2.log("withheld", withheldBefore);
        console2.log("getYield", ITSYDelegateView(TSY_DELEGATE).getYieldAmount(user, tsyBal, true));

        // Sell TSY with USDC as the output-side delegate.
        vm.prank(user);
        IERC20Minimal(TSY).approve(USDC_DELEGATE, tsyBal);
        IMultiliquidSwap.SwapInputs[] memory sell = new IMultiliquidSwap.SwapInputs[](1);
        sell[0] = IMultiliquidSwap.SwapInputs(6, TSY_ID, USDC_ID, USDC_ID, tsyBal, 0);
        IMultiliquidSwap.SwapResolved memory q;
        vm.prank(user);
        q = swap.quoteSwap(user, sell[0]);
        console2.log("sell quote in", q.tokenInAmt, "out", q.tokenOutAmt);
        uint256 usdcBefore = IERC20Minimal(USDC).balanceOf(user);
        vm.prank(user);
        swap.swap(user, user, sell, permit);
        console2.log("usdc received", IERC20Minimal(USDC).balanceOf(user) - usdcBefore);
        console2.log("tsy after", IERC20Minimal(TSY).balanceOf(user));
        console2.log("credits after", ITSYDelegateView(TSY_DELEGATE).credits(user));
        console2.log("withheld after", ITSYDelegateView(TSY_DELEGATE).totalWithheldCredits(user));
    }
}


contract AuditSpreadFloorTest is BaseForkTest {
    function test_zeroTakeChargesOneBpOnRoute0() public {
        assertEq(swap.spreadProtocolTakeRate(), 0, "expected live zero take");

        RouteSpec memory s = routeSpec(0);
        IMultiliquidSwap.SwapResolved memory liveQuote = _quoteExactIn(s, 100e6, TEST_USER);
        assertEq(liveQuote.spreadFeeAmt, 10_000, "live quote should charge 1 bp");

        // Fork-local control: exempting USDC removes the spread floor. This is
        // not a live state change; it isolates the 1 bp the live config charges.
        _setProtocolFeeExempt(USDC_ID, true);
        IMultiliquidSwap.SwapResolved memory noSpreadQuote = _quoteExactIn(s, 100e6, TEST_USER);
        assertEq(noSpreadQuote.spreadFeeAmt, 0, "exempt quote should have no spread fee");
        assertGt(noSpreadQuote.tokenOutAmt, liveQuote.tokenOutAmt, "1 bp should reduce user output");

        console2.log("live spread fee (6dp)", liveQuote.spreadFeeAmt);
        console2.log("live tokenOut", liveQuote.tokenOutAmt);
        console2.log("no-spread tokenOut", noSpreadQuote.tokenOutAmt);
        console2.log("output delta", noSpreadQuote.tokenOutAmt - liveQuote.tokenOutAmt);
    }
}
