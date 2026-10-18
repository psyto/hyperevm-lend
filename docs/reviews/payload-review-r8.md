You are Codex, reviewing code Claude (another model) wrote. Do not defer to it. Round 8: a full arithmetic audit, not a narrow check.

Rounds 2, 3, 6 and 7 (docs/reviews/) each found one more overflow or rounding edge in src/LendingMarket.sol after long accrual or extreme inputs. After r7 Claude changed liquidation to choose its path by comparing USDC amounts (`repayAmt >= cover`) and moved every product with the debt to `FullMath.mulDiv`. Instead of finding the next single expression, enumerate them all at once.

For EVERY arithmetic expression in src/LendingMarket.sol (every `*`, `/`, `+`, `-`, `mulDiv`, `mulDivUp`, `_rpow`), state the largest operand values reachable under these bounds: szDecimals <= 6 (constructor), raw prices any uint64, collateral up to 1e27 wei (HYPE's 1B max supply), USDC totals up to 1e18 base units (1T USDC), and any elapsed time up to the point where `borrowIndex` itself would overflow. For each, say whether it can overflow/underflow (or divide by zero) before the borrow index does, and whether a revert there would freeze something users need (repay, withdraw, liquidate, withdrawCollateral, supply). Write a Foundry PoC under test/poc/ only for real failures; run `forge test` and report numbers. Only add files under test/poc/.

Then state the time horizon (at a 100% rate and at the 5% base rate) after which the market cannot operate because the index itself overflows, and whether anything should be done about it (e.g. documenting it is enough for a learning project).

Output: the table of expressions, findings with severity, PoC results, fixes. End with exactly one line: `VERDICT: APPROVE` or `VERDICT: CHANGES`.
