# MonstroStaking Regression Tests

Regression harness for the Hashlock Monstro Staking audit findings:

- **H-01** — new stakers inherit historical emissions
- **H-02** — emissions allocated beyond the physical budget
- **M-01** — `getPenaltyInfo` previews a smaller penalty than `withdraw`

## Source provenance

| Role | Source | Commit |
| --- | --- | --- |
| Vulnerable | `reference/monstro-vuln/staking/MonstroStaking.sol` | `1651bc5521ce6cb7c7d2a41ddd415d3d8a1099c8` |
| Fixed | `reference/monstro-fix/staking/MonstroStaking.sol` | `a270edc5cef63f328ca2ea2798ee37af163b214b` |
| Active source | `src/MonstroStaking.sol` | fixed version (left in place) |

The test file is `test/MonstroStakingRegression.t.sol`. It defines a small
`MockMonstro` ERC-20 with `mint` and `burn`, then deploys the staking contract
with:

- treasury: `makeAddr("treasury")`
- emissions: `1e18` per second
- total emissions: `10_000_000e18`
- pools: `0`
- Merkle roots: `bytes32(0)`
- expiries: `0`

Treasury unpauses the contract and the staking contract is funded with
`10_000_000e18`. Alice and Bob are funded and approve the staking contract.
Both base stakes are `100_000e18` (H-02 adds a `1e18` top-up), all below the
`300_000e18` Vault threshold, so no tier bonus applies.

## Tests

1. **`test_H01_NewStakerEarnsNothingImmediately`**
   - Alice stakes `100_000e18`.
   - Warp 30 days.
   - Bob stakes `100_000e18`.
   - Assert Bob's `earned()` is at most 10 wei.

2. **`test_H02_EmissionsNeverOverAllocated`**
   - Alice and Bob each stake `100_000e18`.
   - Warp 100 days.
   - Alice calls `stake(1e18)` to settle rewards into storage without claiming.
   - Warp 30 more days; nominal cumulative emissions are `11_232_000e18`,
     above the `10_000_000e18` budget.
   - Record both `earned()` values.
   - Bob claims, then Alice claims.
   - Assert total paid is at most `10_000_000e18` and both users received their
     recorded `earned()` amounts, with a 1e6 wei rounding tolerance.

3. **`test_M01_GetPenaltyInfoMatchesWithdraw`**
   - Alice stakes `100_000e18`.
   - Warp 100 days + 7 seconds.
   - Read `getPenaltyInfo(alice, 0)` and record `earned(alice)`.
   - Withdraw all, then compute:
     `actualPenalty = 100_000e18 - (balanceIncrease - earnedBefore)`.
   - Assert `actualPenalty == penaltyAmount` and
     `100_000e18 - penaltyAmount == afterPenaltyAmount`.

## Reproduction

```bash
cd /home/junaid/web3-workspace/monstro-staking-regression

# 1. Vulnerable version: all 3 tests must fail.
cp reference/monstro-vuln/staking/MonstroStaking.sol src/MonstroStaking.sol
forge test -vvv

# 2. Fixed version: all 3 tests must pass.
cp reference/monstro-fix/staking/MonstroStaking.sol src/MonstroStaking.sol
forge test -vvv
```

Logs are in `test-output/vulnerable.log` and `test-output/fixed.log`.

## Results

### Vulnerable version

Command: `forge test -vvv`

```text
Suite result: FAILED. 0 passed; 3 failed; 0 skipped
```

| Test | Result | Failure |
| --- | --- | --- |
| H-01 | FAIL | Bob earned `2_592_000e18` immediately after staking |
| H-02 | FAIL | Alice earned `5_616_006.479967600161998380e18`, but was paid `4_384_006.479967600162e18` (short by ~`1_232_000e18`) |
| M-01 | FAIL | `getPenaltyInfo` returned `64_720e18`; withdraw charged `64_726.019073439878234398e18` |

Key failure messages:

```text
[FAIL: new staker inherited historical emissions: 2592000000000000000000000 > 10]
[FAIL: alice was shortchanged: 4384006479967600162000000 !~= 5616006479967600161998380]
[FAIL: getPenaltyInfo penalty != withdraw penalty: 64726019073439878234398 != 64720000000000000000000]
```

### Fixed version

Command: `forge test -vvv`

```text
Suite result: ok. 3 passed; 0 failed; 0 skipped
```

| Test | Result |
| --- | --- |
| H-01 | PASS |
| H-02 | PASS |
| M-01 | PASS |

## Which assertion catches which bug

| Finding | Assertion that catches the vulnerable behavior | Why it fails on the vulnerable code |
| --- | --- | --- |
| H-01 | `assertLe(staking.earned(bob), 10)` | New stake leaves `rewardPerTokenPaid` at zero; Bob's `earned()` includes 30 days of pre-existing emissions (`2_592_000e18`). |
| H-02 | `assertApproxEqAbs(alicePaid, aliceEarned, 1e6)` | The vulnerable `rewardPerToken()` keeps using the full `remainingEmissions` after rewards are allocated. Total nominal allocation reaches `11_232_000e18`; Bob claims first, Alice receives only the remaining `~4.384M` instead of her `~5.616M` recorded reward. The total-paid assertion alone still passes because the last claim is capped at `remainingEmissions`; the full-earned assertion is the one that exposes the shortfall. |
| M-01 | `assertEq(actualPenalty, penaltyAmount)` | `getPenaltyInfo` floors `penaltyBps` and then floors the penalty again, while `calculatePenalty` uses one combined formula. The preview is `6.019073439878234398e18` tokens smaller than the amount actually charged. |

## Deviations and notes

- The H-01 tolerance is 10 wei, per the “few wei okay” instruction.
- The H-02 full-earned assertions use a `1e6` wei tolerance for integer rounding.
- M-01 observed a `~6.019e18` token mismatch, not `~2` tokens. This is a
  consequence of the exact requested setup (`100_000e18` stake at
  `100 days + 7 seconds`); the mismatch remains small relative to the stake and
  is sufficient to fail the vulnerable version and pass the fixed version.
- The H-02 top-up makes Alice's stake `100_001e18` and total staked
  `200_001e18`; both remain below the `300_000e18` Vault threshold.
- `MockMonstro.burn` burns from `msg.sender`, matching the staking contract's
  `monstroToken.burn(burnAmount)` penalty call.
- Merkle, auto-stake, gift-stake, transfer-stake, compound, and tier-bonus paths
  are intentionally not exercised.
- The fixed source is currently installed at `src/MonstroStaking.sol`.
