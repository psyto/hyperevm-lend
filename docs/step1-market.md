# Step 1: a minimal market, and HYPE prices from Core

HyperEVM testnet, 2026-10-18. `LendingMarket` at `0x00Aaeb42f8FaD9F8A1a79FaF0b9Fe76329Fb0C9e`, deployed and used by
`0xBA378703f3a71e99F51393Cc3589EBcbBa26B40E`.

## What the market does
One isolated market: supply USDC, deposit native HYPE as collateral, borrow USDC up to 60% of
its value, repay, withdraw; above 75% anyone can liquidate up to half the debt and take that value
in HYPE plus 5%. Interest follows HyperCore's own stablecoin curve (5% a year, plus 4.75 × the
utilisation above 80%), 10% of it kept as a reserve that absorbs bad debt first. Everything settles
on the EVM in one transaction; Core is only read.

## Prices on testnet (HYPE perp, index 135, szDecimals 2)
| Read | Value |
|---|---|
| oracle 0x807 | 40.48 |
| mark 0x806 | 51.80 |
| best bid / ask 0x80e | 42.50 / 58.50 |
| Core borrow/lend oracle for HYPE, 0x812 | 51.802 (matches the mark, not the oracle) |

The testnet perp book is thin: the mark is 28% off the oracle and the book is 38% wide. With
mainnet-style bounds (1%) every borrow would be refused, so this deployment passes 0 for all three
bounds (the guard then only checks that the book has both sides). Mainnet: index 159.

## Run
| Step | Result |
|---|---|
| `supply(10 USDC)` | ok |
| `depositCollateral{0.2 HYPE}` | $8.10 at 40.48 |
| `borrow(4 USDC)` | debt 4.000001 (rounded up), LTV 4941 bps, utilisation 40%, rate 5% |
| `repay(max)` | debt 0 |
| `withdrawCollateral(0.2)`, `withdraw(all shares)` | all back except 1 wei of rounding |

Not exercised on testnet yet: liquidation (needs the oracle to fall) and interest over time.
