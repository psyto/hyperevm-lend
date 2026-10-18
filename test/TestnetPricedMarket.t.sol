// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {IERC20, LendingMarket} from "../src/LendingMarket.sol";
import {TestnetPricedMarket} from "../src/testing/TestnetPricedMarket.sol";
import {MockUSDC} from "./LendingMarket.t.sol";

contract TestnetPricedMarketTest is Test {
    function test_setPriceDrivesLiquidation() public {
        vm.chainId(998);
        MockUSDC usdc = new MockUSDC();
        TestnetPricedMarket m = new TestnetPricedMarket(IERC20(address(usdc)), 40e18);
        usdc.mint(address(this), 100e6);
        usdc.approve(address(m), type(uint256).max);
        m.supply(10e6);
        m.depositCollateral{value: 0.2 ether}(); // $8
        m.borrow(4.8e6); // 60%
        vm.prank(address(0xBAD));
        vm.expectRevert(TestnetPricedMarket.NotPriceSetter.selector);
        m.setPrice(1);
        m.setPrice(30e18); // $6: 80%
        uint256 seized = m.liquidate(address(this), type(uint256).max);
        assertEq(seized, uint256(2.4e6) * 1e12 * 10_500 / 10_000 * 1e18 / 30e18); // 0.084 HYPE
    }

    /// r9: refuses any chain but HyperEVM testnet, and a zero price everywhere.
    function test_r9_testnetOnlyAndZeroPrice() public {
        MockUSDC usdc = new MockUSDC();
        vm.chainId(999);
        vm.expectRevert(abi.encodeWithSelector(TestnetPricedMarket.NotTestnet.selector, 999));
        new TestnetPricedMarket(IERC20(address(usdc)), 40e18);
        vm.chainId(998);
        TestnetPricedMarket m = new TestnetPricedMarket(IERC20(address(usdc)), 0);
        vm.expectRevert(LendingMarket.NoPrice.selector);
        m.guardedPrice();
        vm.expectRevert(LendingMarket.NoPrice.selector);
        m.liquidationPrice();
    }

    receive() external payable {}
}
