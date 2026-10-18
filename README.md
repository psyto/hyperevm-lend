# hyperevm-lend

Learning HyperEVM by building a lending market (HypurrFi-style): borrow USDC against HYPE, with
the books on the EVM and the prices from HyperCore.

Status (2026-10-18): a learning project, not audited, not for real funds. The first version ran
on HyperEVM testnet (supply, collateral, borrow, repay, withdraw: `docs/step1-market.md`). Codex
has reviewed it adversarially four times (3 findings, 2 low, 2 low, then 1 medium and 1 low, all
fixed); round 5 is in progress. Liquidation and interest are covered by tests but not yet exercised on testnet.

## How it works
- **One isolated market.** Supply USDC; deposit native HYPE as collateral; borrow USDC up to 60%
  of its value; repay; withdraw.
- **Liquidation.** Above 75% anyone can repay up to half the debt and take that value in HYPE plus
  5%. If the collateral cannot cover that, the liquidator pays what all of it is worth (less the
  bonus) and takes it all, and the rest of the debt is written off: against the reserve first,
  then suppliers. That path burns no debt shares, so no amount of accrued interest can block it.
- **Interest.** HyperCore's own stablecoin curve: 5% a year, plus 4.75 × utilisation above 80%,
  compounded per second, so how often anyone calls does not change what a borrower owes. 10% of
  it is kept as the reserve.
- **Prices.** The HYPE perp oracle (0x807). Borrowing and taking collateral out need it to pass
  [hl-price-guard](https://github.com/fabrknt/hl-price-guard)'s checks against the mark and the
  book. Liquidation uses the higher of the oracle and the mark with no bounds: one of them falling
  alone cannot liquidate anyone, and a real crash, which moves both, cannot be blocked by a messy
  book.
- **Rounding.** Supplier shares carry virtual shares against inflation; debt shares are counted
  1e18 times finer than the index and all share/index maths uses a 512-bit `mulDiv`, so decades of
  interest cannot make one share coarse. Rounding always favours the market: debt up, repayments
  down.

## Why not HyperCore's own borrow/lend
On HyperCore, borrowing happens only implicitly under portfolio margin (when an order needs more
than the balance), a borrowed balance cannot be withdrawn or transferred, and CoreWriter exposes
only supply and withdraw ([Hyperliquid: portfolio margin](https://hyperliquid.gitbook.io/hyperliquid-docs/trading/portfolio-margin)).
A market that lends USDC to users' wallets therefore keeps its books on the EVM, reads prices
from Core, and keeps liquidation synchronous on the EVM. That is also the lesson of
[hyperevm-amm](https://github.com/psyto/hyperevm-amm): a contract is never told what happened on
Core, so nothing critical should wait for it.

## Layout
| Path | What |
|---|---|
| `src/LendingMarket.sol` | the market |
| `src/FullMath.sol` | Remco Bloemen's 512-bit `mulDiv` (MIT), as in Uniswap v3 |
| `test/LendingMarket.t.sol` | 23 tests; HyperCore precompiles mocked at their real addresses |
| `docs/step1-market.md` | the testnet run and the testnet HYPE prices |
| `docs/reviews/` | Codex review rounds: payloads, outputs, PoCs, and what was fixed (`r1.md`–`r4.md`) |
| `lib/hyperevm-amm`, `lib/hl-price-guard` | pinned git submodules: CoreWriter/precompile helpers, guarded price reads |

## Things this taught (testnet, 2026-10-18)
- HyperCore's borrow/lend is visible from the EVM: precompile 0x812 returns a token's rates,
  utilisation, borrow oracle and LTV. 0x811 (a user's state) reverts for an account with no
  borrow/lend history.
- Core's borrow/lend values HYPE at the mark (51.80), not the oracle (40.48).
- The testnet HYPE perp is not a usable price: the mark was 28% off the oracle and the book 38%
  wide, so the testnet deployment runs with the price bounds off. Mainnet HYPE perp: index 159.

## Run
```
git clone --recurse-submodules https://github.com/psyto/hyperevm-lend
forge test
```

## License
Apache-2.0 (`src/FullMath.sol`: MIT)
