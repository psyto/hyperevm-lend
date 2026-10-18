Found six real pre-index failures. Added [Round8ArithmeticPoC.t.sol](test/poc/Round8ArithmeticPoC.t.sol:1).

Bounds used: `M = 2^256-1 ≈ 1.158e77`, `Pmax = (2^64-1)*1e18 ≈ 1.845e37`, collateral `C ≤ 1e27`, live USDC `U ≤ 1e18`, initial debt shares `DS ≤ 1e36`, normal initial supply shares `S ≈ 1e24`.

| Expression(s) | Largest reachable operands | Result / failure before index overflow | Affected action |
|---|---:|---|---|
| `WAD * SHARE_SCALE` | `1e18 * 1e18` | `1e36`, safe | — |
| `cash() + debt - reserves` | `cash ≤ 1e18`, `debt < M`, `reserves ≤ debt` | Safe before earlier accrual failures; no underflow by accounting invariant | supply, withdraw |
| `debt * WAD / (cash + debt)` | `debt < M`, denominator nonzero when used | `mulDiv` result `≤ 1e18`; safe | utilisation, rate |
| `debt * BPS / value` (`ltvBps`) | `debt < M`, `value = 1…1.845e34` | `mulDivUp` reverts if true LTV exceeds `uint256`; real at value `1` after 126.79 years at 100% | liquidate; potentially withdrawCollateral/borrow |
| `amount * (totalSupplyShares + VIRTUAL_SHARES)` | `amount ≤ 1e18`; after repeated total-loss recapitalizations, `S ≈ 2.5e59` | Checked multiplication overflows (`≈2.5e77`) | supply |
| `totalSupplyShares + VIRTUAL_SHARES`; supply share additions | `S ≈2.5e59` before preceding product fails | Safe before the product failure | supply |
| `totalAssets() + VIRTUAL_ASSETS` | `< M` before earlier accrual failures | Safe, nonzero | supply |
| `shares * (totalAssets + VIRTUAL_ASSETS)` | ordinary `shares≈1e24`, assets exceed `≈1.16e53` | Checked multiplication overflows after 80.84 years at 100% | withdraw |
| `totalSupplyShares + VIRTUAL_SHARES` in withdraw | nonzero virtual shares | Safe; denominator never zero | withdraw |
| supply/withdraw `+=`, `-=` share balances | ownership and total-share invariants | No underflow; additions are pre-empted by the supply-product failure | supply, withdraw |
| `collateral += msg.value`; `collateral -= amount`; `-int256(amount)` | total collateral `≤1e27` | Safe | depositCollateral, withdrawCollateral |
| `amount * SHARE_UNIT / borrowIndex` | `1e18 * 1e36`, `index ≥1e18` | `mulDivUp` result `≤1e36`; safe | borrow |
| debt-share additions | total live debt shares `≤1e36` under the stated pool bound | Safe | borrow |
| `debt * CLOSE_FACTOR_BPS / BPS` | debt `<M` | `mulDivUp` result `≤ debt`; safe | liquidate |
| `price * BPS` | `1.845e37 * 1e4 = 1.845e41` | Safe | liquidate |
| `WAD * (BPS + bonus) * 1e12` | `1e18 * 10500 * 1e12 = 1.05e34` | Safe, nonzero | liquidate |
| `coll * (price * BPS) / denominator` | `1e27 * 1.845e41`; result `≤1.76e34` | FullMath handles intermediate; safe | liquidate |
| `debt - paid`; debt-share subtractions | `paid ≤ debt`, borrower shares `≤ total` | Safe by branch invariants | liquidate |
| `collateral - seized`; `reserves - min(badDebt,reserves)` | `seized ≤ collateral`; subtrahend `≤ reserves` | Safe | liquidate |
| `1e12 * (BPS + bonus) * WAD / BPS` | constant `1.05e30` | Safe | `_seizeFor` |
| `_seizeFor: paid * 1.05e30 / price` | price is nonzero after `liquidationPrice`; enough-collateral branch guarantees result `≤ collateral ≤1e27` | FullMath safe | liquidate |
| repayment burn: `amount * SHARE_UNIT / borrowIndex` | `amount ≤1e18`, index eventually `>1e54` | No overflow, but floors to zero after ~82.9 years at 100%; `Zero()` reverts | repay |
| debt-share subtractions in `_reduceDebt` | `burn ≤ borrower shares ≤ total` | Safe | repay |
| `block.timestamp - lastAccrual` | monotonic timestamps | Safe | accrual |
| `WAD + rate / YEAR` | `rate ≤1e18`; quotient `≤31,709,791,983` | Safe | accrual |
| `_rpow` products | `z,x ≤ M`, denominator `1e18` | FullMath prevents intermediate overflow; first failure coincides with unrepresentable index/factor | accrual |
| `index * factor / WAD` | result `<M` until index horizon | Safe until the index itself cannot fit | accrual |
| `newIndex - index` | nondecreasing index | Safe | accrual |
| `totalDebtShares * indexDelta / SHARE_UNIT` | `1e36 * (<M) / 1e36` | Interest fits while index fits | accrual |
| `interest * RESERVE_FACTOR_BPS / BPS` | interest exceeds `M/1000` after 129.09 years at 100% | Checked product overflows | repay, withdraw, liquidate, withdrawCollateral, supply |
| `reserves + reserveCut` | reserve balance remains about 10% of debt | Safe if reserve cut is computed safely | accrual |
| `c + debt`, `u - KINK`, `JUMP_RATE * (...) / WAD`, base-rate addition | `u≤1e18`, excess `≤2e17` | Largest jump product `9.5e35`; safe | rate |
| `_value: hype * price / WAD / 1e12` | `1e27 * 1.845e37 = 1.845e64` | Safe | LTV |
| `_mulUp: shares * index / SHARE_UNIT` | `1e36 * (<M) / 1e36` | FullMath safe while index fits | debt conversion |
| `_divUp: (a - 1) / b + 1` | unused | Safe for `a=0` or `b>0`; would divide by zero for `a>0,b=0`, but has no call site | — |

Findings:

1. Low — supplier deposits round to zero after roughly 55 years at 100% utilization under the 1T-USDC bound. A `1e18` deposit cannot obtain one supply share, so `supply` reverts `Zero()`.

2. Low — withdrawal overflows after 80.84 years at 100%. The ordinary `~1e24` initial supply shares multiplied by accrued assets exceeds `uint256`, permanently blocking `withdraw`.

3. Low — bounded repayments become impossible after roughly 82.9 years at 100%. `amount * SHARE_UNIT / borrowIndex` floors to zero for every `amount ≤ 1e18`, causing `repay` to revert `Zero()`.

4. Low — LTV calculation can overflow before the index. A debt against collateral valued at one USDC base unit makes `debt * 10,000 / value` unrepresentable after 126.79 years at 100%, blocking liquidation.

5. Low — reserve accounting freezes all accrual-dependent operations after 129.09 years at 100%. `interest * 1000` overflows although the new borrow index still fits.

6. Low — three bounded recapitalization/complete-loss cycles grow stale supply shares enough that the next `amount * totalSupplyShares` overflows. This blocks supply while maintaining at most `1e18` total circulating USDC.

PoC results: `forge test` passed: 32 tests total, including 6 new PoCs.

Recommended fixes:

- Replace supply/withdraw raw products with `FullMath.mulDiv`.
- Rebase supply shares, or redesign the share scale, so bounded deposits and repayments remain representable after large index growth.
- Use `FullMath.mulDiv(interest, RESERVE_FACTOR_BPS, BPS)` for reserve accrual.
- Do health checks by comparing against the LTV limit without constructing an unbounded LTV ratio; saturate the public LTV result to `type(uint256).max` if necessary.
- For a learning project, documenting the eventual index limit is reasonable only after fixing the earlier freezes.

Index horizon, assuming a constant rate and one uninterrupted accrual from `1e18`:

- 100%: first failing second is `4,288,869,154` seconds, or `135.99915` 365-day years.
- 5%: first failing second is `85,777,381,811` seconds, or `2719.98293` 365-day years.

At a real 5% starting utilization, debt growth eventually raises utilization and therefore the rate unless liquidity is continually added; the 5% figure is mathematical rather than a stable live-market trajectory.

VERDICT: CHANGES