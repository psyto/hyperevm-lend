You are Codex, reviewing code Claude (another model) wrote. Do not defer to it. Round 6, narrow: the fix for your round 5.

Your round 5 (docs/reviews/r5.md, review-r5.out.md, PoCs in r5-poc.t.sol.txt) found that the short-path payment in `liquidate` was rounded down, so collateral worth 1 base unit could be taken for 0. Claude's fix is the latest commit (`git show HEAD`): `paid = FullMath.mulDivUp(coll, price * BPS, WAD * (BPS + LIQ_BONUS_BPS) * 1e12)`, then capped at the debt.

Review only this change. Write any PoC under test/poc/, run `forge test`, report numbers. Only add files under test/poc/. Check: the expression equals ceil(coll * price / WAD * BPS / (BPS + bonus) / 1e12) without intermediate truncation; overflow of `price * BPS` and of the denominator; whether rounding up can now make a liquidator pay more than the collateral is worth at the liquidation price in a way that matters (it should be at most one base unit); interaction with the `paid > debt` cap and `badDebt = debt - paid`.

Output: findings with severity, PoC and result, root cause, fix. End with exactly one line: `VERDICT: APPROVE` or `VERDICT: CHANGES`.
