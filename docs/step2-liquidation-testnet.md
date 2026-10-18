# Step 2: interest and both liquidation paths on testnet

HyperEVM testnet, 2026-10-19. `TestnetPricedMarket` at `0x12297f893553998EbA1e395AdD5d7214cfE29b77` (testnet only: the deployer sets
the HYPE price, because the HyperCore oracle cannot be moved on testnet; everything else is
`LendingMarket`). One key, `0xBA378703f3a71e99F51393Cc3589EBcbBa26B40E`, played lender,
borrower and liquidator. This instance predates the review-r9 guards (chain-id check, zero-price
revert), which this run does not touch.

## Interest
Supplied 5 USDC, deposited 0.2 HYPE at a set price of 40 ($8), borrowed 4.8 USDC: utilisation
96%, rate 81% a year (0.05 + 4.75 × 0.16), LTV 60.01%.

| | Observed | Expected (4.8 USDC × e^(0.81 × t / year)) |
|---|---|---|
| after 931 s | debt 4.800115 USDC (+114 base units) | +114.78 base units |

## Liquidation, enough collateral (price 30)
| | Value |
|---|---|
| LTV before | 80.01% |
| repaid | 2.400059 USDC (half the debt, rounded up) |
| HYPE to the liquidator | 0.084002065 = 2.400059 × 1.05 / 30 |
| left | debt 2.400059, collateral 0.115997935 HYPE |
| reserve / suppliers' assets | 11 base units / 5.000107 USDC (the interest, net of the reserve) |

## Liquidation, collateral short (price 10)
| | Value |
|---|---|
| LTV before | 206.91% |
| liquidator paid | 1.104743 USDC = all the collateral's value / 1.05, rounded up |
| HYPE to the liquidator | all 0.115997935 |
| written off | 1.295316 USDC = 2.400059 − 1.104743 |
| reserve | 11 → 0 (absorbed first) |
| suppliers' assets | 5.000107 → 3.704802 (down 1.295305 = the write-off less the 11 the reserve took) |
| left | debt 0, debt shares 0, collateral 0, no HYPE in the market |

## Exit
The supplier withdrew all shares: 3.704802 USDC, exactly the assets left. The market ended with
no cash and no shares.
