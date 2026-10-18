You are Codex, reviewing code Claude (another model) wrote. Do not defer to it. Round 2, narrow: the fixes for your round 1.

Your round 1 (docs/reviews/r1.md, review-r1.out.md, PoCs in r1-poc.t.sol.txt) found 3 issues in src/LendingMarket.sol. Claude's fix is the latest commit (`git show HEAD`):
(1) `liquidationPrice()` = max(oracle 0x807, mark 0x806), no bounds; liquidation checks health and computes the seize at that price.
(2) interest compounds per second: `_rpow(WAD + rate / YEAR, dt)`, the index multiplies by it, reserves grow by `totalDebtShares * (newIndex - index) / WAD * 10%`.
(3) `_reduceDebt` returns the value of the shares it burns (`_mulUp(burn, index)` <= amount) and reverts if it burns none; repay and liquidate pay that amount.
Also: when collateral is short, liquidation now takes all of it (`takesAll`) so rounding cannot leave dust that blocks the bad-debt write-off.

Review only these changes and what they touch. Write any PoC under test/poc/, run `forge test`, report numbers. Only add files under test/poc/.

1. Do the fixes close the findings, including variants: the mark alone falling (or pushed down through the book) — can a liquidator now use a mark push? Mark up / oracle down asymmetry; both at 0.
2. `_rpow`: precision and overflow (long dt, high rate at 100%+ utilisation, WAD + rate/YEAR rounding: is rate/YEAR truncation material?), the reserve formula vs the debt actually added, gas for large dt.
3. `_reduceDebt` and `takesAll`: can repay now be stuck (e.g. a borrower who cannot fully repay because of rounding), can `paid` be 0 with burn > 0, can `takesAll` be triggered on a position with enough collateral to seize more for the same repay, does the bad-debt write-off still fire only when it should.
4. Anything else in the diff.

Output: findings with severity, PoC and result, root cause, fix. End with exactly one line: `VERDICT: APPROVE` or `VERDICT: CHANGES`.
