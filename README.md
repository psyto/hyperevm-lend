# hyperevm-lend

Learning HyperEVM by building a lending market (HypurrFi-style): borrow USDC against HYPE.

Status (2026-10-18): starting. A learning project, not audited, not for real funds.

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
