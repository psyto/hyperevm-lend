// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {LendingMarket, IERC20} from "../LendingMarket.sol";

/// @notice TESTNET ONLY. The same market with the HYPE price set by its deployer instead of read
/// from HyperCore, so liquidation and interest can be exercised on testnet, where the oracle cannot
/// be moved. Everything else is LendingMarket unchanged. Never deploy this anywhere real: the
/// deployer can set any price and liquidate anyone.
contract TestnetPricedMarket is LendingMarket {
    address public immutable priceSetter;
    uint256 public price; // 1e18 USD per HYPE

    error NotPriceSetter();
    error NotTestnet(uint256 chainId);

    uint256 internal constant HYPEREVM_TESTNET = 998;

    constructor(IERC20 usdc_, uint256 price_)
        LendingMarket(usdc_, 0, 0, 2, 0, 0, 0)
    {
        // enforced, not only named (review r9): HyperEVM testnet is chain 998, mainnet 999
        if (block.chainid != HYPEREVM_TESTNET) revert NotTestnet(block.chainid);
        priceSetter = msg.sender;
        price = price_;
    }

    function setPrice(uint256 price_) external {
        if (msg.sender != priceSetter) revert NotPriceSetter();
        price = price_;
    }

    function guardedPrice() public view override returns (uint256) {
        if (price == 0) revert NoPrice(); // same as liquidationPrice (review r9)
        return price;
    }

    function liquidationPrice() public view override returns (uint256) {
        if (price == 0) revert NoPrice();
        return price;
    }
}
