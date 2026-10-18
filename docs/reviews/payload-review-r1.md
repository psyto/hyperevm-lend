You are Codex, reviewing code Claude (another model) wrote. Do not defer to it. Round 1.

This repo (worktree) is a lending market on HyperEVM: borrow USDC (6 decimals, ERC20) against native HYPE (18 decimals), one isolated market, src/LendingMarket.sol. README.md and docs/step1-market.md describe it. Prices come from HyperCore precompiles through the pinned library lib/hl-price-guard (HLPriceGuard.read for borrow/withdrawCollateral; the bare 0x807 oracle for liquidate). Tests in test/LendingMarket.t.sol mock the precompiles at their real addresses.

Review by breaking: for every finding, write a failing Foundry test under test/poc/ that demonstrates it, run `forge test`, report the numbers. Only add files under test/poc/; do not edit src/ or existing tests.

Attack, in order of value:
1. Loss of supplier or borrower funds: share pricing (virtual shares/assets, rounding direction on supply/withdraw), debt shares and borrowIndex rounding (can a borrower repay less than owed, or borrow and leave debt that rounds to zero), interest accrual (`_accrued` uses cash() and simple interest per accrual: can someone game accrual timing, utilisation via donations or flash supply/withdraw), reserves (can they exceed debt, underflow totalAssets, block withdrawals).
2. Liquidation: the seize math (USDC 6 -> USD 18 -> HYPE 18, bonus, close factor, the branch when collateral is short), self-liquidation for profit, liquidation of a borrower whose LTV is between MAX and LIQ, rounding that lets repayAmt be 0 or seized exceed collateral, the bad-debt write-off (reserves first, then suppliers) and whether it can be triggered on a healthy-ish position or abused to socialise losses.
3. Prices: guarded vs bare oracle split — can an attacker use the bare-oracle path to liquidate unfairly, or the guarded path to block liquidations/withdrawals; 0x807 scaling for szDecimals; staleness (none is checked: is that a problem for an oracle validators update every few seconds?); price 0.
4. Reentrancy and transfers: native HYPE sends via call, nonReentrant coverage, ERC20 return values, a borrower contract that rejects HYPE.
5. Anything about HyperEVM/HyperCore semantics the code gets wrong (cite sources).

Output: findings with severity (critical/high/medium/low), PoC name and result, root cause, concrete fix. End with exactly one line: `VERDICT: APPROVE` or `VERDICT: CHANGES`.
