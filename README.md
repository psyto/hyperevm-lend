# hyperevm-lend

Learning HyperEVM by building a lending market (HypurrFi-style): borrow USDC against HYPE.

Status (2026-10-18): step 1 done, Codex review rounds 1–3 fixed (`docs/reviews/`). A minimal
market (`src/LendingMarket.sol`, 20 tests) ran on
testnet: supply, collateral, borrow, repay, withdraw (`docs/step1-market.md`). A learning
project, not audited, not for real funds.

## The market
- Supply USDC; deposit native HYPE as collateral; borrow USDC up to 60% of its value.
- Above 75% anyone can liquidate up to half the debt and take that value in HYPE plus 5%.
- Interest: HyperCore's own stablecoin curve, 5% a year plus 4.75 × utilisation above 80%,
  compounded per second (so how often anyone calls does not change it); 10% kept as a reserve
  that absorbs bad debt before suppliers do.
- HYPE price: the perp oracle (0x807). Borrowing and taking collateral out need it to pass
  hl-price-guard's checks against the mark and the book. Liquidation uses the higher of the
  oracle and the mark with no bounds: one of them falling alone cannot liquidate anyone, and a
  real crash, which moves both, cannot be blocked by a messy book.

Why the lending runs on the EVM and not on HyperCore's own borrow/lend: on HyperCore, borrowing
happens only implicitly under portfolio margin (when an order needs more than the balance), a
borrowed balance cannot be withdrawn or transferred, and CoreWriter exposes only supply and
withdraw. So a market that lends USDC to users' wallets keeps its books on the EVM, reads prices
from Core's precompiles, and keeps liquidation synchronous on the EVM (the lesson of
[hyperevm-amm](https://github.com/psyto/hyperevm-amm): a contract is never told what happened on
Core, so nothing critical should wait for it).

Dependencies (git submodules, pinned): `lib/hyperevm-amm` (CoreWriter and precompile helpers),
`lib/hl-price-guard` (guarded HyperCore price reads).

```
forge test
```

## License
Apache-2.0
