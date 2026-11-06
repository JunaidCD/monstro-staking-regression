# Multiliquid V2 Fork-Test Suite (Ethereum Sepolia)

Independent, black-box Foundry fork tests for the deployed Multiliquid V2 swap
proxy. The suite exercises quote-level fee accounting, exact-in/exact-out
equivalence, fee monotonicity, all 12 route IDs, live settlement through the
reachable aliases, and the current 4-field EIP-712 permit layout against live
Sepolia state.

This repository is not affiliated with Multiliquid, Uniform Labs, or Cantina.
It performs no live-network writes: every state change happens on a local fork
and is never broadcast.

## Target and fork configuration

| Item | Value |
| --- | --- |
| Chain | Ethereum Sepolia, chain ID `11155111` |
| Pinned fork block | `12067842` (override with `SEPOLIA_FORK_BLOCK`) |
| `MultiliquidSwap` proxy | `0x0cc2ff62B7d5f3584045e12490eA9f5c06Fce43F` |
| Current proxy implementation (EIP-1967) | `0x7d88aea1993d0d86da9f1af9fdb2dd247f366905` |
| Docs-listed older implementation | `0x51A69a70f247968DB4144d325519aCAEe0287480` |
| USDC delegate | `0x8De2F6a2A012a4e5A7C73e8ADA7141B0F380B4B0` |
| TSY delegate | `0x23ddF02Cc519FBE1c22fC4b0A59c166f2F29faed` |
| Treasury delegate | `0x2Eb8EC371E1e76b6718CCD59567c9E158F46a905` |
| Treasury/USDC custody | `0x00D02037a99de8b15E2CbF4889DFa07788E206C0` |

The proxy has been upgraded since some documentation was written. The tests use
the current implementation reached through the proxy, including its 4-field
`ApprovalPermit(deadline, signature, nonce, unordered)` layout. The older
2-field permit layout is intentionally not tested.

### Assets used

| Asset | Token | Decimals | ID | Live USD value |
| --- | --- | --- | --- | --- |
| USDC | `0x092BB220f7Ec652EB871D395D5f957F5f06E1e2D` | 6 | `0x0d29c0df...b2e1dbf` | 1.00 |
| Mock RWA whitelist (`RW1`) | `0x1b2F0A294a3B8162FB4cB5356c689d296B750609` | 6 | `0x6d09dcd8...132b9d` | 1.19 |
| Mock RWA no-whitelist (`RW0`) | `0x063EE9692eB3E4328a279961922d2e41CB9DAAA8` | 18 | `0x35fd2714...da9b7196` | 3.08 |
| TSY | `0x072Db736308c58465e9FB0961327bFd4bF28E809` | 18 | `0x06aa0396...e83edb7` | 1.00 |

### Live configuration observed at the pinned block

- `paused = false`
- `spreadProtocolTakeRate = 0`
- `issuerPaidProtocolFeeRates[USDC] = 0`
- `discountRates[USDC][RW0] = discountRates[USDC][RW1] = 1e15` (0.1%)
- `redemptionFees[USDC][RW0] = redemptionFees[USDC][RW1] = 1e15` (0.1%)
- `stablecoinAcceptanceFees` and `stablecoinRedemptionFees` are zero
- `protocolFeeExempt[USDC] = false`, `protocolFeeExempt[TSY] = true`
- `autoLiquidityStablecoinIDs[USDC] = TSY_ID`
- `_maxSwapLegs = 8`
- No `rwaWhitelistAdapters` configured for the mock RWAs

## Test groups

### Baseline (`test/Baseline.t.sol`)

Confirms the fork is live, the proxy has code, the contract is not paused, the
expected assets and prices are present, and the empirically derived storage
slots match the live getters. It also records a first route-0 quote.

### 1. Fee-accounting fuzz invariant (`test/FeeAccounting.t.sol`)

For every route ID, fuzz a bounded input/output amount and evaluate accounting
in USD WAD:

```text
tokenInUsd - tokenOutUsd - reportedFeesUsd == implicitDiscount + dust
```

`reportedFeesUsd` includes issuer, spread, and LP/redemption fee fields.
`implicitDiscount` is the RWA-input discount that the contract deliberately
does not report in the fee fields. `dust` is bounded at `1e-5` USD.

- 12 fuzz tests, 32 runs each.
- A deterministic sweep prints the observed residual min/max and bps per route.

Observed at block `12067842`:

- Strict-closure routes (0/1, 6/7, 10/11): residual in
  `[-1.92e-6, +1e-18]` USD, inside the `±1e-5` USD dust bound.
- RWA-input routes (2/3, 4/5, 8/9): residual is positive and bounded by the
  configured 0.1% implicit discount (10 bps; 9 bps on route 3 due to rounding).

### 2. Exact-in / exact-out equivalence (`test/Equivalence.t.sol`)

For each even/odd route pair:

1. Quote exact-in `X -> Y`.
2. Quote exact-out `Y -> X'`.
3. Assert `|X - X'|` is at most `2e-6` USD.
4. Repeat in reverse: exact-out `Y -> X'`, then exact-in `X' -> Y'`, and
   assert `|Y - Y'| <= 2e-6` USD.

The bound is expressed in USD because the exact-out path rounds its computed
input at the route's 6-decimal stablecoin granularity, which is a different raw
unit size for 18-decimal legs. The largest observed delta was `9.998e-7` USD
(pair 6/7 and 10/11, reverse direction). This is below one USDC unit.

### 3. Fee monotonicity (`test/FeeMonotonicity.t.sol`)

Fee increases are simulated with `vm.store` on the fork. Every override is
checked against its public getter before quoting, so a wrong slot cannot produce
a false pass.

Covered fee changes:

- RWA redemption fee: route 0/1
- Spread take + discount: route 0/1
- Implicit input discount: routes 2/3 and 4/5
- Output redemption fee: routes 4/5
- Stablecoin redemption fee: routes 6/7
- Issuer fee: route 0/1 (reported but capital-provider funded)

Assertions: a higher fee must never increase exact-in output, and must never
decrease exact-out input. The issuer-fee test asserts user token amounts are
unchanged while `issuerFeeAmt` increases.

Additional documented behavior:

- With `spreadProtocolTakeRate = 0`, the contract still reports a minimum 1 bp
  spread fee (`10_000` units for 100 USDC). See finding F-01 below.
- The 1 bp floor is not a fuzz failure; it is an observable live-config
  behavior recorded by `test_zeroSpreadTakeStillChargesOneBpMinimum`.

### 4. Route coverage matrix (`test/RouteMatrix.t.sol`)

| Route | Family | Asset pair used |
| --- | --- | --- |
| 0 | exact-in | USDC -> RW0 (18 dec) |
| 1 | exact-out | USDC -> RW0 (18 dec) |
| 2 | exact-in | RW0 -> USDC |
| 3 | exact-out | RW0 -> USDC |
| 4 | exact-in | RW1 (6 dec) -> RW0 (18 dec) |
| 5 | exact-out | RW1 (6 dec) -> RW0 (18 dec) |
| 6 | exact-in | USDC -> TSY (USDC delegate) |
| 7 | exact-out | USDC -> TSY (USDC delegate) |
| 8 | exact-in, prefunded alias | RW0 -> USDC |
| 9 | exact-out, prefunded alias | RW0 -> USDC |
| 10 | exact-in, prefunded alias | USDC -> TSY |
| 11 | exact-out, prefunded alias | USDC -> TSY |

All 12 routes quote successfully at the pinned block. The test asserts exact-in
input echo, exact-out output echo, and non-zero amounts.

Negative cases:

- Unsupported route ID 12 -> `UnsupportedRouteId(12)`
- Identical input/output IDs -> `IdenticalAssets`
- Wrong delegate -> `InvalidStablecoinDelegateID(actual, expected)`
- Unaccepted RWA -> `RWANotAccepted`
- Unaccepted stablecoin -> `StablecoinNotAccepted`

Max-swap-legs boundary:

- 0 legs -> `InvalidLegCount`
- `_maxSwapLegs + 1` legs -> `InvalidLegCount`
- Exactly `_maxSwapLegs` legs pass the length check and fail later in route
  validation (`IdenticalAssets` for empty legs), proving the length boundary.
- Setting `_maxSwapLegs = 0` via `vm.store` makes a 1-leg call revert with
  `InvalidLegCount`.

The deployed ABI exposes only a single-leg `quoteSwap`; there is no batch quote
to exercise directly. The batch `swap` length check is therefore tested through
reverts before any settlement work.

### 5. EIP-712 permit (`test/Permit.t.sol`)

Uses the current 4-field permit and the current domain
(`MultiliquidSwap`, version `2`, chain ID, proxy address). The tests execute
real settlement on the fork:

- Ordered permit: nonce advances `0 -> 1`; 1 USDC is spent; receiver receives
  the quoted RW0 amount.
- Unordered permit: the chosen unordered nonce is consumed; the ordered nonce
  is unchanged; settlement succeeds.
- Wrong signer: reverts with `InvalidSignature`.

The domain/typehash constants are copied from the current verified
implementation source.

### 6. Settlement audit (`test/AuditSettlement.t.sol`)

This group tests settlement, not only quotes, at the pinned block:

- Routes 2/3 (RWA -> USDC) and 10/11 (USDC -> TSY) execute live `swap` calls
  and settle with the quoted amounts.
- Routes 8/9 (prefunded RWA -> USDC aliases) quote successfully but revert
  during auto-liquidity prefund because the custody address has TSY balance but
  zero TSY credits. The tests assert the exact `InsufficientCredits` revert.
- The zero-take spread-floor test compares a live route-0 quote with a
  fork-local no-spread control.
- The yield-input test buys TSY through the USDC delegate, then sells it back
  through the same delegate. It confirms those paths neither create nor consume
  TSY credits.

The TSY-delegate test path is permissioned: a non-whitelisted recipient reverts
at `Treasury.mint` with `AccountNotWhitelisted(address)`.

## Results

Pinned block `12067842`, `forge 1.7.1`, Solidity `0.8.35`, using the Tenderly
Sepolia gateway for historical state.

| Suite | Tests | Result |
| --- | --- | --- |
| Baseline | 3 | pass |
| FeeAccounting | 13 | pass |
| Equivalence | 13 | pass |
| FeeMonotonicity | 15 | pass |
| RouteMatrix | 7 | pass |
| Permit | 3 | pass |
| AuditSettlement | 8 | pass |
| **Total** | **62** | **62 passed, 0 failed, 0 skipped** |

Full logs:

- `test-output/baseline.log` — initial 3-test smoke run
- `test-output/final.log` — full 62-test `forge test -vv` run
- `test-output/final-54-tests.log` — earlier 54-test run, before the settlement audit
- `test-output/audit-settlement.log` — 8 settlement-audit tests
- `test-output/audit-prefund-revert.log` — focused route 8/9 prefund revert run

## Observations and disclosures

1. **No high/critical finding is claimed.** The suite is a regression and
   invariant harness. It documents current behavior; it does not prove the
   absence of bugs.
2. **Implicit RWA discount is not reported in fee fields.** On RWA-input
   routes, the 0.1% discount is reflected in the amount difference but not in
   `issuerFeeAmt`, `spreadFeeAmt`, or `lpFeeAmt`. The fee-accounting test bounds
   this separately. Do not treat the residual as an unaccounted leak without
   also accounting for this discount.
3. **Issuer fee is capital-provider funded.** Raising
   `issuerPaidProtocolFeeRates[USDC]` increases the reported `issuerFeeAmt` but
   does not change user token amounts in either exact-in or exact-out quotes.
4. **Minimum 1 bp spread fee at zero protocol take.** With
   `spreadProtocolTakeRate = 0`, the quote still reports a 1 bp spread fee. This
   is documented as finding F-01 below; the suite asserts the behavior rather
   than treating it as a fuzz failure.
5. **Exact-in/out deltas are rounding-scale.** The largest observed round-trip
   delta was `9.998e-7` USD, below one USDC unit. The test bound is `2e-6` USD.
6. **Docs implementation is stale.** The proxy currently delegates to
   `0x7d88...6905`, not the docs-listed `0x51a6...7480`. The permit, storage
   layout, and fee math in this suite follow the current implementation.
7. **Unfunded yield-bearing input quotes zero.** During reconnaissance,
   route 6 with `assetIn = TSY` and `stablecoinDelegateID = TSY` returned zero
   output for an address with no ybTSY credits. The settlement audit later
   bought TSY through the USDC delegate, but that path does not create credits;
   the zero-yield quote is therefore still observed for a credited-path test
   and is not asserted as a correctness property.
8. **Fee monotonicity uses fork-local overrides.** The live deployment was not
   modified. The overrides are applied only inside an isolated Foundry fork and
   are verified against the public getters.
9. **Prefunded routes 8/9 are unfunded on the live deployment.** The custody
   address holds TSY but has zero TSY credits, so the prefund step reverts.
   This is documented as operational finding F-02 below.
10. **TSY credits do not follow token transfers.** The TSY mint path credits
    `params.user` and mints tokens to `params.receiver`; `Treasury` transfers do
    not move credits. A recipient of transferred TSY therefore has no redemption
    credits in the TSY delegate, while the sender retains them. This is recorded
    as an open accounting/design question, not a claimed exploit; the USDC
    delegate can still exchange TSY at par, and no credit-double-count was
    demonstrated in the tested paths.

## Candidate findings for review

These are candidate findings from the fork harness. They have not been
submitted to any program, and no high/critical severity is claimed.

### F-01 (Low): zero `spreadProtocolTakeRate` still charges the 1 bp floor

At block `12067842`, a 100 USDC route-0 quote reports `spreadFeeAmt = 10_000`
(0.01 USDC) even though `spreadProtocolTakeRate = 0`. The live output is
`32.431818181818181818` RW0; a fork-local no-spread control returns
`32.435064935064935064` RW0. The difference is `3_246_753_246_753_246` wei RW0,
about 0.01 USD at the mock RW0 price.

The Solidity implementation applies a one-basis-point minimum in
`_calculateSpreadProtocolFeeRate`. The published SVM SDK documentation for
[`calculate_spread_protocol_fee_rate`](https://docs.rs/multiliquid-svm-sdk/latest/multiliquid_svm_sdk/math/fn.calculate_spread_protocol_fee_rate.html)
states that a zero protocol take bypasses that minimum. The two implementations
therefore disagree on a live-config path.

Impact is bounded to about one basis point on non-exempt routes: roughly 0.01
USD per 100 USDC. Recommendation: return zero when the take rate is zero, to
match the published SDK, or document that the EVM path intentionally enforces a
minimum. Regression test: `test_zeroTakeChargesOneBpOnRoute0`.

### F-02 (Low / operational): prefunded routes 8/9 quote but cannot settle

At block `12067842`, the custody address holds `30,319.948310312672147214` TSY
but its TSY-delegate `credits` are zero. The prefund step calls
`getAmountForTargetValue` and reverts with
`InsufficientCredits(requested, available)` (selector `0x685c5370`):

- Route 8: 10 RW0 -> 30,766,120 USDC quote; prefund requests
  `30.7692` TSY, available `0`.
- Route 9: 1 USDC out quote; prefund requests `1.000101` TSY, available `0`.

Routes 2/3, which are the non-prefund RWA -> USDC aliases, settle normally.
Routes 10/11 settle normally. The failure happens before the user leg, so it is
not user-specific; any caller of route 8/9 hits the same prefund revert. The
failure is a deployment/configuration gap rather than a logic bug in the prefund
math: custody has the token balance but not the credits the delegate requires.
Recommendation: seed custody TSY credits or change the auto-liquidity
configuration, and monitor prefund balances before enabling those aliases.

## Cantina report credit

The public Cantina portfolio is at:

<https://cantina.xyz/portfolio/92ee7667-c017-46fa-8882-416862c1365b>

The report lists 3 medium, 3 low, and 9 informational findings, with 8 fixed
and 1 acknowledged. Researchers credited there include **HickupHH3** and
**rvierdiiev**.

Finding 1 concerns an RWA-to-RWA exact-out fee overcharge, where the
redemption fee was based on gross input including the fee. The report states it
was fixed in PR 52, commit
`1ce7b929bd6508652b71dd2fce2419099a16e0f0`.

This repository is an independent black-box fork suite. It does not reproduce
the Cantina finding as a new issue and makes no ownership claim over that
report. The credit is included because the report and the current
implementation informed the test design.

## Limitations

- Sepolia mock tokens and mock prices may not match mainnet behavior.
- `quoteSwap` is single-leg. Batch behavior is only tested at the length-check
  boundary.
- No TSY minting, no RWA whitelist bypass, no admin/governance calls, and no
  upgrade tests are attempted.
- Permit coverage is ECDSA-only. ERC-1271 and EIP-7702 paths are not tested.
- Fuzz runs are bounded at 32 per test for runtime; this is not exhaustive.
- The storage-slot overrides depend on the current implementation layout. The
  suite asserts the slots against live getters and will fail loudly if the
  layout changes.
- The fork is pinned to block `12067842` for reproducibility. Running against
  the latest block may produce different values.
- `SEPOLIA_RPC_URL` falls back to the Tenderly gateway; rate limits can cause
  transient failures. PublicNode and some free RPCs prune block `12067842`.

## Reproduction

```bash
forge --version
# forge 1.7.1

export SEPOLIA_RPC_URL="https://sepolia.gateway.tenderly.co"
export SEPOLIA_FORK_BLOCK=12067842

forge test -vvv
```

A ready-to-copy `.env.example` is included. `SEPOLIA_RPC_URL` falls back to
the Tenderly gateway above when unset. Public RPC endpoints such as PublicNode
no longer serve historical state at block `12067842`; use an archive/Tenderly
endpoint for the pinned block.

To use the latest Sepolia block instead:

```bash
unset SEPOLIA_FORK_BLOCK   # or set it to 0
forge test -vvv
```

Useful subsets:

```bash
forge test --match-contract FeeAccountingTest -vvv
forge test --match-contract EquivalenceTest -vvv
forge test --match-contract FeeMonotonicityTest -vvv
forge test --match-contract RouteMatrixTest -vvv
forge test --match-contract PermitTest -vvv
```

## Repository layout

```text
src/
  IMultiliquidSwap.sol      Minimal current-ABI interface, structs, errors
  IERC20Minimal.sol         ERC-20 read/approve plus mock mint
  IPriceAdapter.sol         RWA price adapter read
  IStablecoinDelegate.sol   Delegate custody/whitelist reads
test/
  BaseForkTest.sol          Fork setup, route specs, USD helpers, vm.store helpers
  Baseline.t.sol            Smoke, live config, storage-slot verification
  FeeAccounting.t.sol       Group 1: 12-route fuzz invariant + distribution
  Equivalence.t.sol         Group 2: exact-in/out equivalence, both directions
  FeeMonotonicity.t.sol     Group 3: fee increases never help the user
  RouteMatrix.t.sol         Group 4: 12 routes, negative cases, max legs
  Permit.t.sol              Group 5: ordered/unordered 4-field EIP-712
  AuditSettlement.t.sol     Group 6: live settlement, prefund, spread floor
test-output/
  baseline.log              Real baseline forge output
  final.log                 Real 62-test full-suite forge output
  final-54-tests.log        Earlier 54-test run before the settlement audit
  audit-settlement.log      Real 8-test settlement-audit output
foundry.toml                Fuzz/invariant configuration
```

## Safety and ethics

- Everything runs on a local fork. No transaction is broadcast.
- No live state is modified.
- No access-control bypass is attempted. The role-gated TSY mint and RWA
  whitelist are left alone.
- No secrets are stored in this repository. The private keys in the permit
  tests (`0xA11CE`, `0xB0B`, `0xC0FFEE`, `0xBAD`) are deterministic, public,
  valueless test keys.
- Test code is MIT-licensed under the SPDX headers in each source file.
