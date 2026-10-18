You are Codex, reviewing code Claude (another model) wrote. Do not defer to it. Round 9, narrow.

To exercise liquidation and interest on testnet (where the HyperCore oracle cannot be moved), Claude made the two price reads of src/LendingMarket.sol `virtual` (`guardedPrice`, `liquidationPrice`) and added src/testing/TestnetPricedMarket.sol, a subclass whose deployer sets the HYPE price. See `git show HEAD`. It is meant for testnet only and is about to be deployed and used there.

Review only this change. Write any PoC under test/poc/, run `forge test`, report numbers. Only add files under test/poc/. Check:
1. LendingMarket's behaviour is unchanged by `virtual` (no other function changed meaning; every internal use of a price goes through these two functions, so the subclass cannot leave a path still reading the precompiles inconsistently, or the reverse).
2. TestnetPricedMarket: is it consistent (both prices from the same storage, price 0 handling for borrow/withdrawCollateral vs liquidate), any way someone other than the deployer changes the price, constructor arguments (dex/index/szDecimals passed as 0/0/2 with bounds 0) that matter now that the precompiles are not read.
3. Risk of it being mistaken for the real market: naming, comments, location, anything in the repo (scripts, README) that would deploy it by default. Suggest guards if cheap (e.g. refusing a mainnet chain id).

Output: findings with severity, PoC and result, root cause, fix. End with exactly one line: `VERDICT: APPROVE` or `VERDICT: CHANGES`.
