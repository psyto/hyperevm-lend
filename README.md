# hyperevm-lend

Learning HyperEVM by building a lending market (HypurrFi-style): borrow USDC against HYPE, with
the books on the EVM and the prices from HyperCore.

Status (2026-10-19): a learning project, not audited, not for real funds.
- The first version ran on HyperEVM testnet: supply, collateral, borrow, repay, withdraw
  (`docs/step1-market.md`). That deployment predates the review fixes.
- Codex reviewed it adversarially nine times; every finding was fixed or, for three that need
  half a century at 100% utilisation, accepted as a documented limit. Reviews stop there.
- Interest and both liquidation paths ran on testnet with a testnet-only market whose price is
  set by hand (`docs/step2-liquidation-testnet.md`): interest matched e^(rt) to a base unit, the
  short path wrote off the rest of the debt with the reserve taking the loss first, and the
  supplier then withdrew exactly what was left.

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
  alone cannot liquidate anyone, and a wide or empty book does not block it. A fall counts only
  once both show it (see Known limits).
- **Rounding.** Supplier shares carry virtual shares against inflation; debt shares are counted
  1e18 times finer than the index, and all share/index maths and every product with the debt use
  a 512-bit `mulDiv`, so decades of interest cannot make one share coarse or a liquidation
  overflow. Rounding always favours the market: debt up, repayments down.

| Parameter | Value |
|---|---|
| Max borrow (LTV) | 60% |
| Liquidatable above | 75% |
| Liquidation bonus | 5% |
| Close factor | 50% of the debt per liquidation |
| Interest | 5% a year, + 4.75 × utilisation above 80%, compounded per second |
| Reserve factor | 10% of interest |
| Price checks for borrow / withdraw collateral | constructor bounds on mark/oracle, mid/oracle, spread (0 = off; testnet uses 0) |

## Known limits
Only after decades at 100% utilisation (every USDC lent out; the rate is then 100% a year):
- The borrow index itself overflows after about 136 years at a 100% rate (2,720 years at the 5%
  base rate). The market cannot operate past that.
- Before that: from about 55 years a 1T-USDC deposit buys less than one supply share, and from
  about 83 years no repayment up to 1T USDC burns a debt share (liquidation of underwater
  positions still works). Three total-loss-and-recapitalise cycles can also make `supply`
  overflow. Fixing these needs share rebasing, which this learning project does not do
  (docs/reviews/r8.md).
- No timestamp is available for the oracle precompile, so an upstream oracle outage cannot be
  detected on-chain.
- **Liquidation can be held back.** It waits until both the oracle and the mark have fallen. The
  mark follows HL's book, so a borrower (or anyone) who pushes the HYPE book up keeps the mark,
  and so the liquidation price, high for as long as they pay to hold the push; a real fall that
  the mark lags waits the same way. Meanwhile the position can sink below its debt, and the
  reserve, then suppliers, pay the difference. Behind the price checks instead, a pushed book
  would stop liquidations outright. Neither delay is measured or bounded here (hl-price-guard
  docs/safe-limits.md section 5).

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
| `src/testing/TestnetPricedMarket.sol` | testnet only (refuses any chain but 998): the market with a hand-set price, to exercise liquidation |
| `src/FullMath.sol` | Remco Bloemen's 512-bit `mulDiv` (MIT), as in Uniswap v3 |
| `test/` | 28 tests; HyperCore precompiles mocked at their real addresses |
| `docs/step1-market.md` | the first testnet run and the testnet HYPE prices |
| `docs/step2-liquidation-testnet.md` | interest and both liquidation paths on testnet |
| `docs/reviews/` | Codex review rounds: payloads, outputs, PoCs, and what was fixed (`r1.md`–`r9.md`) |
| `lib/hyperevm-amm`, `lib/hl-price-guard` | pinned git submodules: CoreWriter/precompile helpers, guarded price reads |

## Things this taught (testnet, 2026-10-18)
- HyperCore's borrow/lend is visible from the EVM: precompile 0x812 returns a token's rates,
  utilisation, borrow oracle and LTV. 0x811 (a user's state) reverts for an account with no
  borrow/lend history.
- Core's borrow/lend values HYPE at the mark (51.80), not the oracle (40.48).
- The testnet HYPE perp is not a usable price: the mark was 28% off the oracle and the book 38%
  wide, so the testnet deployment runs with the price bounds off. Mainnet HYPE perp: index 159.

## Reviews
Codex, adversarial, a failing test for every finding (`docs/reviews/`).

| Round | Scope | Findings | Outcome |
|---|---|---|---|
| 1 | whole market | 2 high, 1 low | liquidation at max(oracle, mark); per-second compounding; no dust repay |
| 2 | r1 fixes | 2 low | seize on what was paid; `_rpow` overflow |
| 3 | r2 fixes | 2 low | finer debt shares, 512-bit `mulDiv` |
| 4 | r3 fixes | 1 medium, 1 low | short-collateral liquidation rebuilt without share burns; zero amount refused |
| 5 | rebuilt path | 1 low | short-path payment rounded up |
| 6 | r5 fix | 1 low | `szDecimals <= 6` |
| 7 | r6 fix | 1 low | paths chosen on USDC amounts; `mulDiv` for every product with the debt |
| 8 | full arithmetic audit | 6 low | 3 fixed, 3 accepted (Known limits) |
| 9 | the testnet-only priced market | 1 low, 1 info | refuses any chain but testnet; zero price reverts in both reads |

## Next
- Optionally lend idle USDC into HyperCore's borrow/lend (blocked on testnet: USDC sent EVM → Core
  does not reach a contract's Core account).

## Run
```
git clone --recurse-submodules https://github.com/psyto/hyperevm-lend
forge test
```

## License
Apache-2.0 (`src/FullMath.sol`: MIT)
