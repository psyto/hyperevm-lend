Found 2 issues. Added PoCs in [Round4Fixes.t.sol](test/poc/Round4Fixes.t.sol:1).

- Medium — zero-amount self-liquidation writes off debt for free.

  `liquidate(borrower, 0)` forces `repayAmt == 0`. For liquidatable collateral worth under `DUST_USDC`, the new branch seizes all collateral and writes off all debt without payment—even when the collateral has positive repay value. The borrower can self-liquidate; splitting across accounts makes the per-position dust bound sybilable.

  PoC passes: $0.75 collateral, $0.60 debt, `paid == 0`, all debt erased.  
  Root cause: `repayAmt == 0` conflates a caller-supplied zero amount with arithmetic rounding to zero.  
  Fix: reject `amount == 0` in `liquidate`; gate the no-payment route on the collateral-derived maximum repayment actually rounding to zero, not on caller input.

- Low — fixed 1e18 share refinement still strands non-dust collateral after sufficient accrual.

  At 100% utilization after 56 years, the index is high enough that a ~$0.95 collateral-backed repayment burns zero shares. The position has exactly $1 collateral, so it cannot enter the dust write-off branch, and liquidation reverts `Zero()`.

  PoC passes: collateral `1,000,000` USDC base units; debt `2,091,657,634,677,870,960,454,054,982,379` base units.  
  Root cause: `SHARE_SCALE` is fixed while `borrowIndex` is unbounded; eventually `repayAmt * SHARE_UNIT / borrowIndex == 0`.  
  Fix: explicitly allow a full-collateral seizure/write-off for an underwater zero-share-burn liquidation, or impose/correctly manage an index bound; further fixed scaling only postpones recurrence.

Confirmed: `FullMath.mulDiv` is a faithful Uniswap v3/Remco Bloemen implementation, and `mulDivUp` correctly increments only on a nonzero remainder. Borrow/share-value rounding remains market-favouring; burn is down and collection is bounded by requested amount. At initial index, debt-share overflow requires a single borrow above roughly `1.16e53` USDC, so no practical headroom issue.

`forge test`: 22 passed, 0 failed.

VERDICT: CHANGES