// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseForkTest} from "./BaseForkTest.sol";
import {IMultiliquidSwap} from "../src/IMultiliquidSwap.sol";
import {console2} from "forge-std/console2.sol";

contract BaselineTest is BaseForkTest {
    function test_forkAndConfig() public view {
        assertEq(block.chainid, 11155111, "not Sepolia");
        assertGt(address(swap).code.length, 0, "no code at swap proxy");
        assertFalse(swap.paused(), "swap is paused");

        assertEq(swap.stablecoinUSDValue(USDC_ID), 1e18, "USDC USD value");
        assertEq(swap.stablecoinUSDValue(TSY_ID), 1e18, "TSY USD value");
        assertGt(_rwaUsd(RW_NO_WHITELIST_ID), 0, "RW0 price missing");
        assertGt(_rwaUsd(RW_WHITELIST_ID), 0, "RW1 price missing");

        console2.log("fork block", block.number);
        console2.log("fork id", forkId);
        console2.log("USDC/USD", swap.stablecoinUSDValue(USDC_ID));
        console2.log("TSY/USD", swap.stablecoinUSDValue(TSY_ID));
        console2.log("RW0/USD", _rwaUsd(RW_NO_WHITELIST_ID));
        console2.log("RW1/USD", _rwaUsd(RW_WHITELIST_ID));
        console2.log("spreadProtocolTakeRate", swap.spreadProtocolTakeRate());
        console2.log("issuerFee(USDC)", swap.issuerPaidProtocolFeeRates(USDC_ID));
        console2.log("discount(USDC,RW0)", swap.discountRates(USDC_ID, RW_NO_WHITELIST_ID));
        console2.log("redemption(USDC,RW0)", swap.redemptionFees(USDC_ID, RW_NO_WHITELIST_ID));
        console2.log("protocolFeeExempt(USDC)", swap.protocolFeeExempt(USDC_ID));
        console2.log("protocolFeeExempt(TSY)", swap.protocolFeeExempt(TSY_ID));
        console2.log("autoLiquidity(USDC)", vm.toString(swap.autoLiquidityStablecoinIDs(USDC_ID)));
    }

    function test_route0_quote_smoke() public view {
        RouteSpec memory s = routeSpec(0);
        IMultiliquidSwap.SwapResolved memory q = _quoteExactIn(s, 100e6, TEST_USER);

        console2.log("route0 100 USDC -> RW0");
        console2.log("tokenInAmt", q.tokenInAmt);
        console2.log("tokenOutAmt", q.tokenOutAmt);
        console2.log("issuerFeeAmt", q.issuerFeeAmt);
        console2.log("spreadFeeAmt", q.spreadFeeAmt);
        console2.log("lpFeeAmt", q.lpFeeAmt);
        console2.log("residual USD WAD", uint256(_residual(q, s)));

        assertEq(q.tokenInAmt, 100e6, "tokenIn");
        assertGt(q.tokenOutAmt, 0, "tokenOut");
        assertEq(q.issuerFeeAmt, 0, "issuer fee should be zero at live config");
    }

    function test_storageSlots_matchGetters() public view {
        // Scalar slot 18.
        assertEq(
            uint256(vm.load(address(swap), bytes32(SLOT_SPREAD_PROTOCOL_TAKE_RATE))),
            swap.spreadProtocolTakeRate(),
            "spread take slot"
        );

        // Scalar slot 22.
        uint256 maxLegs = uint256(vm.load(address(swap), bytes32(SLOT_MAX_SWAP_LEGS)));
        assertGt(maxLegs, 0, "max swap legs slot");
        assertLe(maxLegs, 100, "implausible max swap legs");

        // Nested mapping slot 1: discountRates[USDC][RW0].
        assertEq(
            uint256(vm.load(address(swap), _mappingSlot2(USDC_ID, RW_NO_WHITELIST_ID, SLOT_DISCOUNT_RATES))),
            swap.discountRates(USDC_ID, RW_NO_WHITELIST_ID),
            "discount slot"
        );

        // Nested mapping slot 2: redemptionFees[USDC][RW0].
        assertEq(
            uint256(vm.load(address(swap), _mappingSlot2(USDC_ID, RW_NO_WHITELIST_ID, SLOT_REDEMPTION_FEES))),
            swap.redemptionFees(USDC_ID, RW_NO_WHITELIST_ID),
            "redemption slot"
        );

        // Mapping slot 17: issuerPaidProtocolFeeRates[USDC].
        assertEq(
            uint256(vm.load(address(swap), _mappingSlot(USDC_ID, SLOT_ISSUER_PAID_PROTOCOL_FEE_RATES))),
            swap.issuerPaidProtocolFeeRates(USDC_ID),
            "issuer fee slot"
        );

        // Mapping slot 16: protocolFeeExempt[USDC].
        assertEq(
            uint256(vm.load(address(swap), _mappingSlot(USDC_ID, SLOT_PROTOCOL_FEE_EXEMPT))),
            swap.protocolFeeExempt(USDC_ID) ? 1 : 0,
            "exempt slot"
        );

        // Mapping slot 21: autoLiquidityStablecoinIDs[USDC].
        assertEq(
            vm.load(address(swap), _mappingSlot(USDC_ID, SLOT_AUTO_LIQUIDITY)),
            swap.autoLiquidityStablecoinIDs(USDC_ID),
            "auto liquidity slot"
        );

        console2.log("storage-slot derivation verified against live getters");
    }
}
