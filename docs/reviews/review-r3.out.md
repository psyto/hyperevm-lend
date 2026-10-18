Found 2 low-severity issues. Added [Round3Fixes.t.sol](test/poc/Round3Fixes.t.sol:1) only.

1. Low — sub-$1 collateral can still block liquidation and bad-debt write-off.

   PoC: `test_POC_subDollarCollateralCanStillBlockWriteoffBeforeDustRule` passes. After 28 years at 100% utilization, a 50 HYPE position priced at $0.0198 ($0.99 total collateral) reverts `Zero()`. The collateral-backed repayment cannot burn one now-coarse debt share, so execution never reaches the `DUST_USDC` branch. Collateral and all 1,000,000,000 debt shares remain stranded.

   Root cause: `_reduceDebt` runs before the dust branch and rejects a zero-share burn.

   Fix: explicitly permit a zero-payment full seizure/write-off only when all collateral is below `DUST_USDC`, or use sufficiently fine-grained debt shares. Keep the branch bounded by the dust-value threshold and skip `_pull(0)`.

2. Low — `_rpow` still overflows for a representable result after roughly 102 years.

   PoC: `test_POC_rpowStillOverflowsForRepresentableResultAtAboutOneHundredTwoYears` passes by observing the expected revert at `3 * 2^30` seconds. The intended result is approximately `e^102`, whose WAD value fits in `uint256`, but `z * x` overflows before division by `WAD`.

   Root cause: skipping the final unused square fixes the 68-year case, but ordinary fixed-point multiply-then-divide still requires an unnecessarily large intermediate.

   Fix: use a full-precision `mulDiv(z, x, WAD)` for both exponentiation multiplications, reverting only when the final scaled result cannot fit.

Confirmed: the dust rule can transfer 4,749 extra HYPE at a $0.0001 price, but that is only 474,900 USDC base units ($0.4749); it cannot repeat on that position because collateral is set to zero before write-off. The write-off fires only after collateral is actually zero. `_rpow` is correct for `n = 0, 1, 2`; at `2^31` seconds it returns `374825720898507921312148219043545287711` USDC base units without reverting.

`forge test -vvv`: 22 passed, 0 failed.

VERDICT: CHANGES