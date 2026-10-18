You are Codex, reviewing code Claude (another model) wrote. Do not defer to it. Round 7, narrow: the fix for your round 6.

Your round 6 (docs/reviews/r6.md, review-r6.out.md) found that an unbounded `szDecimals` let `price * BPS` overflow. Claude's fix is the latest commit (`git show HEAD`): the constructor reverts `BadConfig()` when `szDecimals_ > 6`.

Review only this change. Write any PoC under test/poc/, run `forge test`, report numbers. Only add files under test/poc/. Check: with szDecimals <= 6 and any uint64 raw price from the precompiles, can any product in `LendingMarket` that is not routed through FullMath (price * BPS, _seizeFor, _value, ltvBps, debt * BPS, coll * price) still overflow for realistic or extreme-but-possible inputs (collateral up to the HYPE supply, debts after long accrual)? Is 6 the right bound for Hyperliquid perps (cite)? Anything else in the diff.

Output: findings with severity, PoC and result, root cause, fix. End with exactly one line: `VERDICT: APPROVE` or `VERDICT: CHANGES`.
