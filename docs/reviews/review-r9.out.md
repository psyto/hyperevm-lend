## Findings

- **Low — testnet-only is not enforced.** `TestnetPricedMarket` deploys unchanged on HyperEVM mainnet (chain ID 999) and its deployer can set any price. The naming, `src/testing/` location, and comments are good, and no script deploys it by default, but they are the only barrier. Root cause: no chain-ID check in the constructor. Fix: whitelist testnet (`block.chainid == 998`) and revert otherwise; update tests to set chain ID 998. HyperEVM documents mainnet as 999 and testnet as 998. [HyperEVM docs](https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/hyperevm)

  PoC: [TestnetPricedMarketMainnet.t.sol](test/poc/TestnetPricedMarketMainnet.t.sol:11) successfully deploys it with chain ID 999 and changes the price.

- **Informational — zero price has inconsistent failure semantics.** `guardedPrice()` returns zero, so borrowing or withdrawing collateral with debt reverts later as `Unhealthy(type(uint256).max)`; `liquidationPrice()` instead immediately reverts `NoPrice()`. No unsafe state persists because failed transactions roll back. Root cause: only the liquidation override checks zero. Fix: make `guardedPrice()` also revert `NoPrice()` for zero, or reject zero in the constructor/setter if a paused-price state is not intended.

  PoC confirms both paths in [TestnetPricedMarketMainnet.t.sol](test/poc/TestnetPricedMarketMainnet.t.sol:24).

Verified: making the two base methods `virtual` does not alter base-market behavior; all internal risk pricing routes through `_requireHealthy → guardedPrice()` or `liquidate → liquidationPrice()`. The subclass consistently replaces both with the same storage price, and only the immutable deployer can change it. Its `0/0/2` and zero bounds do not matter because neither overridden route reads a precompile.

`forge test -vvv`: **29 passed, 0 failed, 0 skipped**.

VERDICT: CHANGES