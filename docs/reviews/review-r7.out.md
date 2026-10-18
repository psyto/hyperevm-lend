## Findings

- Low — `_seizeFor` still overflows after long accrual, freezing liquidation. With a fully utilized 1,000,000-USDC pool, an ordinary $40 HYPE price, and 1B HYPE collateral, 82 years of 100% APY produces debt of `409,399,162,746,631,392,187,323,137,563,237,720,769,455,825,704` base units. The close-factor repayment then overflows in `_seizeFor` before division by price.

  Root cause: `_seizeFor` evaluates `usdcAmt * 1e12 * 10500 / 10000 * 1e18 / price`; the intermediate exceeds `uint256` despite the final result being irrelevant because all collateral should be seized.

  Fix: use `FullMath.mulDiv`, e.g. calculate `FullMath.mulDiv(usdcAmt, 1e12 * (BPS + LIQ_BONUS_BPS) * WAD / BPS, price)`.

## PoC and result

Added [Round7ArithmeticPoC.t.sol](test/poc/Round7ArithmeticPoC.t.sol:1). It reproduces the panic during `liquidate`.

`forge test`: **26 passed, 0 failed**.

## Bound assessment

`szDecimals <= 6` is correct for Hyperliquid perps: official docs define perp `MAX_DECIMALS` as 6 and price decimal places as `6 - szDecimals`; the precompile conversion uses that same exponent. [Tick and lot size](https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/tick-and-lot-size), [HyperCore precompiles](https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/hyperevm/interacting-with-hypercore)

With `szDecimals = 6` and raw `uint64` maximum, `price * BPS` is only about `1.84e41`; even 1B HYPE (`1e27` wei) times price is about `1.84e64`, both below `uint256`. HYPE’s documented maximum supply is 1B. [Hyperliquid spot metadata](https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/info-endpoint/spot)

No other new functional defect in the diff. The range check does not verify that the configured value matches the selected perp’s on-chain metadata; that is pre-existing configuration risk.

VERDICT: CHANGES