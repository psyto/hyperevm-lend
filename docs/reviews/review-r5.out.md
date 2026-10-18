Found 1 low-severity issue.

- Low — short-path payment rounds down to zero for one USDC base unit of collateral. A self-liquidator can clear all debt, recover all collateral, and pay nothing when the 5%-discounted value is below one USDC base unit. PoC: [Round5ShortPath.t.sol](test/poc/Round5ShortPath.t.sol:1) passes with collateral valued at 1 base unit, `paid = 0`, and `badDebt = 1`.

  Root cause: short-path `paid` uses floor rounding while transferring all collateral.

  Fix: round the short-path payment up to USDC base units (using full-precision math), capped at debt. This bounds market-favouring rounding correctly and removes the zero-payment route.

Checked otherwise: the short path requires roughly 190% LTV under the 50% close factor, so a position only just above 75% cannot trigger it; a one-price-tick boundary test confirms this. The `paid > debt` cap is defensive/unreachable under the branch inequality. Reserve accounting is correct: after one year, `157,066,969` bad debt consumed `1,230,506` reserves first, for supplier loss `155,836,463`. Long and ordinary short self-liquidations pull their respective payments, and max-amount liquidation remains unstuck after long accrual.

`forge test`: 27 passed, 0 failed.

VERDICT: CHANGES