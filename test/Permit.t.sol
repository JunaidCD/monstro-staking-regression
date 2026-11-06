// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseForkTest} from "./BaseForkTest.sol";
import {IMultiliquidSwap} from "../src/IMultiliquidSwap.sol";
import {IERC20Minimal, IMintableERC20} from "../src/IERC20Minimal.sol";
import {console2} from "forge-std/console2.sol";

/// @notice Group 5: current 4-field EIP-712 ApprovalPermit layout.
/// @dev The proxy now points at 0x7d88...6905, whose permit is
///      (deadline, signature, nonce, unordered). The older 2-field permit
///      described in some docs is intentionally not tested. Settlement is
///      executed only on the fork; nothing is broadcast.
contract PermitTest is BaseForkTest {
    bytes32 internal constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 internal constant NAME_HASH = keccak256("MultiliquidSwap");
    bytes32 internal constant VERSION_HASH = keccak256("2");
    bytes32 internal constant SWAP_INPUT_TYPEHASH = keccak256(
        "SwapInput(uint256 routeId,bytes32 assetInID,bytes32 assetOutID,bytes32 stablecoinDelegateID,uint256 assetInAmt,uint256 assetOutAmt)"
    );
    bytes32 internal constant SWAP_BATCH_TYPEHASH = keccak256(
        "SwapBatchApproval(address user,address operator,address receiver,SwapInput[] inputs,uint256 nonce,uint256 deadline)SwapInput(uint256 routeId,bytes32 assetInID,bytes32 assetOutID,bytes32 stablecoinDelegateID,uint256 assetInAmt,uint256 assetOutAmt)"
    );
    bytes32 internal constant UNORDERED_SWAP_BATCH_TYPEHASH = keccak256(
        "UnorderedSwapBatchApproval(address user,address operator,address receiver,SwapInput[] inputs,uint256 nonce,uint256 deadline)SwapInput(uint256 routeId,bytes32 assetInID,bytes32 assetOutID,bytes32 stablecoinDelegateID,uint256 assetInAmt,uint256 assetOutAmt)"
    );

    struct PermitData {
        uint256 userPk;
        address user;
        address operator;
        address receiver;
        uint256 nonce;
        uint256 deadline;
        bool unordered;
    }

    function test_eip712_orderedPermit_settlesAndConsumesNonce() public {
        uint256 userPk = 0xA11CE;
        address user = vm.addr(userPk);
        address receiver = address(0xBEEF01);
        uint256 amountIn = 1e6; // 1 USDC

        RouteSpec memory s = routeSpec(0);
        IMultiliquidSwap.SwapResolved memory expected = _quoteExactIn(s, amountIn, user);
        assertGt(expected.tokenOutAmt, 0, "quote produced zero output");

        _fundAndApprove(user, amountIn);

        IMultiliquidSwap.SwapInputs[] memory legs = new IMultiliquidSwap.SwapInputs[](1);
        legs[0] = IMultiliquidSwap.SwapInputs({
            routeId: s.routeId,
            assetInID: s.assetInID,
            assetOutID: s.assetOutID,
            stablecoinDelegateID: s.delegateID,
            assetInAmt: amountIn,
            assetOutAmt: 0
        });

        uint256 nonce = swap.nonces(user);
        uint256 deadline = block.timestamp + 1 days;
        bytes memory signature =
            _signBatch(PermitData(userPk, user, address(this), receiver, nonce, deadline, false), legs);

        uint256 userBefore = IERC20Minimal(USDC).balanceOf(user);
        uint256 receiverBefore = IERC20Minimal(RW_NO_WHITELIST_TOKEN).balanceOf(receiver);

        swap.swap(
            user,
            receiver,
            legs,
            IMultiliquidSwap.ApprovalPermit({deadline: deadline, signature: signature, nonce: nonce, unordered: false})
        );

        assertEq(swap.nonces(user), nonce + 1, "ordered nonce not consumed");
        assertEq(IERC20Minimal(USDC).balanceOf(user), userBefore - amountIn, "user USDC balance mismatch");
        assertEq(
            IERC20Minimal(RW_NO_WHITELIST_TOKEN).balanceOf(receiver),
            receiverBefore + expected.tokenOutAmt,
            "receiver RWA balance mismatch"
        );

        console2.log("ordered 4-field permit settled");
        console2.log("  nonce", nonce);
        console2.log("  tokenOutAmt", expected.tokenOutAmt);
        console2.log("  receiver RWA delta", expected.tokenOutAmt);
    }

    function test_eip712_unorderedPermit_settlesAndConsumesNonce() public {
        uint256 userPk = 0xB0B;
        address user = vm.addr(userPk);
        address receiver = address(0xBEEF02);
        uint256 amountIn = 1e6;
        uint256 unorderedNonce = 12_345;

        RouteSpec memory s = routeSpec(0);
        IMultiliquidSwap.SwapResolved memory expected = _quoteExactIn(s, amountIn, user);

        _fundAndApprove(user, amountIn);

        IMultiliquidSwap.SwapInputs[] memory legs = new IMultiliquidSwap.SwapInputs[](1);
        legs[0] = IMultiliquidSwap.SwapInputs({
            routeId: s.routeId,
            assetInID: s.assetInID,
            assetOutID: s.assetOutID,
            stablecoinDelegateID: s.delegateID,
            assetInAmt: amountIn,
            assetOutAmt: 0
        });

        uint256 orderedNonceBefore = swap.nonces(user);
        uint256 deadline = block.timestamp + 1 days;
        bytes memory signature =
            _signBatch(PermitData(userPk, user, address(this), receiver, unorderedNonce, deadline, true), legs);

        uint256 receiverBefore = IERC20Minimal(RW_NO_WHITELIST_TOKEN).balanceOf(receiver);

        swap.swap(
            user,
            receiver,
            legs,
            IMultiliquidSwap.ApprovalPermit({
                deadline: deadline, signature: signature, nonce: unorderedNonce, unordered: true
            })
        );

        assertTrue(swap.usedUnorderedNonces(user, unorderedNonce), "unordered nonce not consumed");
        assertEq(swap.nonces(user), orderedNonceBefore, "ordered nonce changed");
        assertEq(
            IERC20Minimal(RW_NO_WHITELIST_TOKEN).balanceOf(receiver),
            receiverBefore + expected.tokenOutAmt,
            "receiver RWA balance mismatch"
        );

        console2.log("unordered 4-field permit settled");
        console2.log("  unordered_nonce", unorderedNonce);
        console2.log("  tokenOutAmt", expected.tokenOutAmt);
    }

    function test_eip712_wrongSignerReverts() public {
        uint256 userPk = 0xC0FFEE;
        uint256 attackerPk = 0xBAD;
        address user = vm.addr(userPk);
        address receiver = address(0xBEEF03);
        uint256 amountIn = 1e6;

        RouteSpec memory s = routeSpec(0);
        _fundAndApprove(user, amountIn);

        IMultiliquidSwap.SwapInputs[] memory legs = new IMultiliquidSwap.SwapInputs[](1);
        legs[0] = IMultiliquidSwap.SwapInputs({
            routeId: s.routeId,
            assetInID: s.assetInID,
            assetOutID: s.assetOutID,
            stablecoinDelegateID: s.delegateID,
            assetInAmt: amountIn,
            assetOutAmt: 0
        });

        uint256 nonce = swap.nonces(user);
        uint256 deadline = block.timestamp + 1 days;
        // Signed by the wrong key.
        bytes memory signature =
            _signBatch(PermitData(attackerPk, user, address(this), receiver, nonce, deadline, false), legs);

        vm.expectRevert(IMultiliquidSwap.InvalidSignature.selector);
        swap.swap(
            user,
            receiver,
            legs,
            IMultiliquidSwap.ApprovalPermit({deadline: deadline, signature: signature, nonce: nonce, unordered: false})
        );
    }

    function _fundAndApprove(address user, uint256 amount) internal {
        IMintableERC20(USDC).mint(user, amount);
        vm.startPrank(user);
        IERC20Minimal(USDC).approve(SWAP, amount);
        // The stablecoin delegate is the contract that pulls the user's input.
        IERC20Minimal(USDC).approve(USDC_DELEGATE, amount);
        vm.stopPrank();
    }

    function _signBatch(PermitData memory p, IMultiliquidSwap.SwapInputs[] memory legs)
        internal
        view
        returns (bytes memory)
    {
        bytes32 digest = _permitDigest(p, _hashInputs(legs));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(p.userPk, digest);
        return abi.encodePacked(r, s, v);
    }

    function _permitDigest(PermitData memory p, bytes32 inputsHash) internal view returns (bytes32) {
        bytes32 typehash = p.unordered ? UNORDERED_SWAP_BATCH_TYPEHASH : SWAP_BATCH_TYPEHASH;
        bytes32 structHash =
            keccak256(abi.encode(typehash, p.user, p.operator, p.receiver, inputsHash, p.nonce, p.deadline));
        bytes32 domainSeparator = keccak256(abi.encode(DOMAIN_TYPEHASH, NAME_HASH, VERSION_HASH, block.chainid, SWAP));
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }

    function _hashInputs(IMultiliquidSwap.SwapInputs[] memory legs) internal pure returns (bytes32) {
        bytes32[] memory hashes = new bytes32[](legs.length);
        for (uint256 i = 0; i < legs.length; i++) {
            IMultiliquidSwap.SwapInputs memory leg = legs[i];
            hashes[i] = keccak256(
                abi.encode(
                    SWAP_INPUT_TYPEHASH,
                    leg.routeId,
                    leg.assetInID,
                    leg.assetOutID,
                    leg.stablecoinDelegateID,
                    leg.assetInAmt,
                    leg.assetOutAmt
                )
            );
        }
        return keccak256(abi.encodePacked(hashes));
    }
}
