Found 3 issues. Added reproducible tests in [LendingMarketRound1.t.sol](test/poc/LendingMarketRound1.t.sol:61).

1. **High — bare oracle can liquidate a position the guard rejects**

   PoC: `test_POC_bareOracleLetsLiquidatorTakeHealthyCollateral` — passes.

   `liquidate()` uses only `0x807`, while borrowing/withdrawal requires oracle/mark/book agreement. In the PoC, a borrower at 60% LTV using the $40 mark/book is liquidated when only the oracle reports $30. The liquidator pays $120 and receives 4.2 HYPE, worth $168 at the still-$40 mark/book.

   Root cause: [liquidate](src/LendingMarket.sol:235) calls bare `oraclePrice()` rather than a guarded or independently corroborated price. Hyperliquid describes mark as the fair-price input used for margining and liquidations, while oracle and mark update separately. [Hyperliquid robust price indices](https://hyperliquid.gitbook.io/hyperliquid-docs/trading/robust-price-indices)

   Fix: require bounded oracle/mark/book agreement (and ideally a timestamped independent reference) before liquidation, or introduce an explicit emergency liquidation mode with conservative limits and governance controls. This is conditional on an erroneous/delayed oracle; I found no way for an ordinary EVM user to directly control `0x807`.

2. **High — anyone can force excess compounding and make healthy borrowers liquidatable**

   PoC: `test_POC_externalCallsForceCompoundingAndLiquidationRisk` — passes.

   At 100% utilisation, a one-time annual accrual turns $1,000 debt into $2,000. A third party instead calls `supply(1)` daily, spending only 365 USDC base units ($0.000365), and raises the debt above $2,700. With $3,000 collateral, the first position is healthy at 66.67% LTV; the grieved one exceeds 90% and is liquidatable.

   Root cause: [_accrued](src/LendingMarket.sol:297) applies simple interest over each elapsed interval but writes the new index after every public state-changing action. The resulting effective annual rate is selected by call frequency, which is permissionless.

   Fix: make accrual cadence-independent, e.g. use a fixed per-second compounding factor (`rpow`) or a deterministic interval/index calculation. Calculate reserve growth from the exact debt-index delta.

3. **Low — accepted dust repayment transfers USDC without reducing debt**

   PoC: `test_POC_dustRepaymentTransfersUSDCWithoutReducingDebt` — passes.

   One second of interest makes `borrowIndex > 1e18`. Repaying one USDC base unit then computes zero burned shares, but the market still transfers that unit and reports it as paid.

   Root cause: [_reduceDebt](src/LendingMarket.sol:276) floors `burn` yet sets `paid = amount`.

   Fix: revert when `burn == 0`, or transfer only the amount corresponding to burned shares; make liquidation seizure use that actual paid amount too.

Other checks: I found no exploitable virtual-share inflation, zero-debt borrow, close-factor/seize rounding, reserve underflow, transfer-return, native-transfer reentrancy, or rejecting-recipient issue.

On staleness: HyperEVM precompiles provide the latest HyperCore state when the EVM block is built, and HyperCore says validators normally update oracle/mark roughly every three seconds. [HyperCore precompiles](https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/hyperevm/interacting-with-hypercore), [oracle timing](https://hyperliquid.gitbook.io/hyperliquid-docs/hypercore/oracle) The scalar precompile result has no update timestamp, however, so the contract cannot detect an upstream oracle heartbeat failure; a timestamped external reference is still advisable.

`forge test -vvv`: **16 passed, 0 failed** (13 existing + 3 PoCs). Only `test/poc/` was added.

VERDICT: CHANGES