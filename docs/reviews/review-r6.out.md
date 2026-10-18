## Finding

- Low — `price * BPS` can overflow before `FullMath` handles the multiplication. The constructor accepts unbounded `szDecimals`; at `62`, raw price `1` scales to `1e74`, and `price * 10_000 = 1e78` panics. An unhealthy short-path position then cannot be liquidated. PoC: [Round6PaymentMath.t.sol](test/poc/Round6PaymentMath.t.sol:107).

  Root cause: Solidity evaluates `price * BPS` eagerly at [LendingMarket.sol:265](src/LendingMarket.sol:265), outside the 512-bit `FullMath` operation.

  Fix: validate constructor configuration, e.g. require `szDecimals <= 41` (which bounds a maximum `uint64` raw price times `BPS` below `uint256.max`), or otherwise implement a safely decomposed calculation.

## Confirmed behavior

- The new formula is the intended single-rounding calculation:
  `ceil(coll * price * BPS / (WAD * (BPS + bonus) * 1e12))`.
  A collateral value of exactly 1 USDC base unit discounts to `20/21`, and correctly charges 1—not 0.
- Rounding up can exceed the exact undiscounted collateral value, but by strictly less than one base unit. PoC: exact value `1.0500001`, payment `2`, premium `0.9499999` base units.
- For standard HYPE `szDecimals = 2`, maximum `price * BPS` is about `1.8447e37`; the denominator is `1.05e34`. Both are safely below `uint256.max`.
- The short-path predicate implies `paid <= repayAmt <= debt`; the cap is defensive, and `badDebt = debt - paid` remains valid.

`forge test`: 27 passed, 0 failed.

VERDICT: CHANGES