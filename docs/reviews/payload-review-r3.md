You are Codex, reviewing code Claude (another model) wrote. Do not defer to it. Round 3, narrow: the fixes for your round 2.

Your round 2 (docs/reviews/r2.md, review-r2.out.md, PoCs in r2-poc.t.sol.txt) found 2 low issues. Claude's fix is the latest commit (`git show HEAD`): in `liquidate`, the seize is now `_seizeFor(paid, price)` computed on what `_reduceDebt` actually burned, and the whole collateral goes only if the seize already covers it or what would be left is worth under DUST_USDC (1 USDC) at the liquidation price; `_rpow` no longer squares after the last bit. Your two PoCs now fail (37,964 HYPE seized, not 50,000; no overflow).

Review only this change. Write any PoC under test/poc/, run `forge test`, report numbers. Only add files under test/poc/. Check: can the DUST_USDC rule now over-seize meaningfully (e.g. a cheap price making many HYPE worth < 1 USDC, or repeated liquidations each taking dust), can it leave collateral dust that blocks the bad-debt write-off, does the write-off still fire only when collateral is truly gone, and is `_rpow` still correct for n = 0, 1, 2 and large n.

Output: findings with severity, PoC and result, root cause, fix. End with exactly one line: `VERDICT: APPROVE` or `VERDICT: CHANGES`.
