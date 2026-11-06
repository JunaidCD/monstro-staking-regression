// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {MonstroStaking} from "../src/MonstroStaking.sol";

contract MockMonstro is ERC20 {
    constructor() ERC20("Mock Monstro", "MONSTRO") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }
}

contract MonstroStakingRegressionTest is Test {
    uint256 private constant TOTAL_EMISSIONS = 10_000_000e18;
    uint256 private constant EMISSIONS_PER_SECOND = 1e18;
    uint256 private constant STAKE_AMOUNT = 100_000e18;
    uint256 private constant USER_BALANCE = 1_000_000e18;

    MockMonstro private token;
    MonstroStaking private staking;
    address private treasury;
    address private alice;
    address private bob;

    function setUp() public {
        token = new MockMonstro();
        treasury = makeAddr("treasury");
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        staking = new MonstroStaking(
            address(token),
            treasury,
            EMISSIONS_PER_SECOND,
            TOTAL_EMISSIONS,
            0,
            0,
            bytes32(0),
            bytes32(0),
            0,
            0
        );

        // The staking contract deploys paused; treasury is the owner.
        vm.prank(treasury);
        staking.togglePause();

        // Fund the emission pool.
        token.mint(address(staking), TOTAL_EMISSIONS);

        _fund(alice);
        _fund(bob);
    }

    function _fund(address user) private {
        token.mint(user, USER_BALANCE);
        vm.prank(user);
        token.approve(address(staking), type(uint256).max);
    }

    function _stake(address user, uint256 amount) private {
        vm.prank(user);
        staking.stake(amount);
    }

    /// H-01: a new staker must not inherit rewards emitted before they staked.
    function test_H01_NewStakerEarnsNothingImmediately() public {
        _stake(alice, STAKE_AMOUNT);
        vm.warp(block.timestamp + 30 days);

        _stake(bob, STAKE_AMOUNT);

        uint256 bobEarned = staking.earned(bob);
        assertLe(bobEarned, 10, "new staker inherited historical emissions");
    }

    /// H-02: allocated rewards must never exceed the physical emission budget.
    function test_H02_EmissionsNeverOverAllocated() public {
        _stake(alice, STAKE_AMOUNT);
        _stake(bob, STAKE_AMOUNT);

        // 100 days of emissions: 8.64M allocated so far.
        vm.warp(block.timestamp + 100 days);

        // Settle Alice's rewards into storage without claiming them, then add a
        // 1-token top-up. This exercises the allocation accounting.
        _stake(alice, 1e18);

        // 30 more days: cumulative nominal emissions 11.232M > 10M budget.
        vm.warp(block.timestamp + 30 days);

        uint256 aliceEarned = staking.earned(alice);
        uint256 bobEarned = staking.earned(bob);

        uint256 bobBefore = token.balanceOf(bob);
        vm.prank(bob);
        staking.claimRewards();
        uint256 bobPaid = token.balanceOf(bob) - bobBefore;

        uint256 aliceBefore = token.balanceOf(alice);
        vm.prank(alice);
        staking.claimRewards();
        uint256 alicePaid = token.balanceOf(alice) - aliceBefore;

        assertLe(bobPaid + alicePaid, TOTAL_EMISSIONS, "emissions over-allocated");
        assertApproxEqAbs(bobPaid, bobEarned, 1e6, "bob was shortchanged");
        assertApproxEqAbs(alicePaid, aliceEarned, 1e6, "alice was shortchanged");
    }

    /// M-01: getPenaltyInfo must preview exactly the penalty that withdraw charges.
    function test_M01_GetPenaltyInfoMatchesWithdraw() public {
        _stake(alice, STAKE_AMOUNT);
        vm.warp(block.timestamp + 100 days + 7 seconds);

        (uint256 penaltyAmount, uint256 afterPenaltyAmount,) = staking.getPenaltyInfo(alice, 0);
        uint256 earnedBefore = staking.earned(alice);

        uint256 before = token.balanceOf(alice);
        vm.prank(alice);
        staking.withdraw(0);
        uint256 balanceIncrease = token.balanceOf(alice) - before;

        uint256 actualPenalty = STAKE_AMOUNT - (balanceIncrease - earnedBefore);

        assertEq(actualPenalty, penaltyAmount, "getPenaltyInfo penalty != withdraw penalty");
        assertEq(STAKE_AMOUNT - penaltyAmount, afterPenaltyAmount, "afterPenaltyAmount mismatch");
    }
}
