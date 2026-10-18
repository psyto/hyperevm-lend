// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {LendingMarket, IERC20} from "../src/LendingMarket.sol";
import {HLPriceGuard} from "hl-price-guard/HLPriceGuard.sol";

contract MockUSDC {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 a) external {
        balanceOf[to] += a;
    }

    function approve(address s, uint256 a) external returns (bool) {
        allowance[msg.sender][s] = a;
        return true;
    }

    function transfer(address to, uint256 a) external returns (bool) {
        balanceOf[msg.sender] -= a;
        balanceOf[to] += a;
        return true;
    }

    function transferFrom(address f, address to, uint256 a) external returns (bool) {
        allowance[f][msg.sender] -= a;
        balanceOf[f] -= a;
        balanceOf[to] += a;
        return true;
    }
}

contract LendingMarketTest is Test {
    address constant MARK_PX = 0x0000000000000000000000000000000000000806;
    address constant ORACLE_PX = 0x0000000000000000000000000000000000000807;
    address constant BBO = 0x000000000000000000000000000000000000080e;
    uint32 constant HYPE_PERP = 135; // testnet; perp prices have 6 - szDecimals(2) = 4 decimals

    LendingMarket market;
    MockUSDC usdc;
    address lender = address(0x1E);
    address borrower = address(0xB0);
    address liquidator = address(0x11);

    function setUp() public {
        usdc = new MockUSDC();
        market = new LendingMarket(IERC20(address(usdc)), 0, HYPE_PERP, 2, 100, 100, 100);
        _setPrice(40e4); // 40.0000

        usdc.mint(lender, 1_000_000e6);
        vm.prank(lender);
        usdc.approve(address(market), type(uint256).max);
        vm.prank(lender);
        market.supply(1_000e6);

        vm.deal(borrower, 100 ether);
        usdc.mint(borrower, 1_000_000e6);
        vm.prank(borrower);
        usdc.approve(address(market), type(uint256).max);
        vm.prank(borrower);
        market.depositCollateral{value: 10 ether}(); // $400 at 40

        usdc.mint(liquidator, 1_000_000e6);
        vm.prank(liquidator);
        usdc.approve(address(market), type(uint256).max);
    }

    /// Oracle, mark and a tight book all at `px4` (4 decimals).
    function _setPrice(uint64 px4) internal {
        _setQuote(px4, px4, px4 - px4 / 2000, px4 + px4 / 2000);
    }

    function _setQuote(uint64 oracle4, uint64 mark4, uint64 bid4, uint64 ask4) internal {
        vm.mockCall(ORACLE_PX, abi.encode(HYPE_PERP), abi.encode(oracle4));
        vm.mockCall(MARK_PX, abi.encode(HYPE_PERP), abi.encode(mark4));
        vm.mockCall(BBO, abi.encode(HYPE_PERP), abi.encode(bid4, ask4));
    }

    // ------------------------------------------------------------ suppliers

    function test_supplyWithdraw() public {
        uint256 s = market.supplyShares(lender);
        vm.prank(lender);
        uint256 out = market.withdraw(s);
        assertApproxEqAbs(out, 1_000e6, 1);
        assertEq(market.totalSupplyShares(), 0);
    }

    function test_withdrawLimitedByCash() public {
        vm.prank(borrower);
        market.borrow(200e6);
        uint256 s = market.supplyShares(lender);
        vm.prank(lender);
        vm.expectRevert(abi.encodeWithSelector(LendingMarket.NotEnoughCash.selector, 800e6));
        market.withdraw(s);
    }

    /// The first supplier cannot inflate the share price to steal from the next one.
    function test_donationCannotStealFromNextSupplier() public {
        LendingMarket fresh = new LendingMarket(IERC20(address(usdc)), 0, HYPE_PERP, 2, 100, 100, 100);
        address attacker = address(0xA77);
        address victim = address(0x71C);
        usdc.mint(attacker, 1_000e6 + 1);
        usdc.mint(victim, 1_000e6);
        vm.startPrank(attacker);
        usdc.approve(address(fresh), type(uint256).max);
        fresh.supply(1);
        usdc.transfer(address(fresh), 1_000e6); // donation
        vm.stopPrank();
        vm.startPrank(victim);
        usdc.approve(address(fresh), type(uint256).max);
        uint256 s = fresh.supply(1_000e6);
        uint256 out = fresh.withdraw(s);
        vm.stopPrank();
        assertGt(out, 999e6);
    }

    // ------------------------------------------------------------ borrowing

    function test_borrowUpToMaxLtv() public {
        vm.startPrank(borrower);
        market.borrow(240e6); // 60% of $400
        assertEq(market.debtOf(borrower), 240e6);
        vm.expectRevert(abi.encodeWithSelector(LendingMarket.Unhealthy.selector, 6_001));
        market.borrow(0.01e6);
        vm.stopPrank();
    }

    function test_borrowNeedsGuardedPrice() public {
        _setQuote(40e4, 42e4, 39.98e4, 40.02e4); // mark 5% off the oracle
        vm.prank(borrower);
        vm.expectRevert(abi.encodeWithSelector(HLPriceGuard.PriceRejected.selector, HLPriceGuard.Breach.MarkOracle, 500, 100));
        market.borrow(100e6);
    }

    function test_withdrawCollateralKeepsHealth() public {
        vm.startPrank(borrower);
        market.borrow(120e6); // 30%
        market.withdrawCollateral(5 ether); // now 60% of $200
        vm.expectRevert(abi.encodeWithSelector(LendingMarket.Unhealthy.selector, 6_667));
        market.withdrawCollateral(0.5 ether);
        vm.stopPrank();
    }

    function test_repayAll() public {
        vm.startPrank(borrower);
        market.borrow(240e6);
        skip(30 days);
        uint256 debt = market.debtOf(borrower);
        assertGt(debt, 240e6);
        uint256 paid = market.repay(borrower, type(uint256).max);
        assertEq(paid, debt);
        assertEq(market.debtShares(borrower), 0);
        market.withdrawCollateral(10 ether);
        vm.stopPrank();
        assertEq(borrower.balance, 100 ether);
    }

    // ------------------------------------------------------------ interest

    /// 24% utilisation: the 5% base rate; suppliers get it less the 10% reserve.
    function test_interestAccrues() public {
        vm.prank(borrower);
        market.borrow(240e6); // utilisation 24%: base rate
        assertEq(market.borrowRate(), 0.05e18);
        skip(365 days);
        // compounded per second: 240 × e^0.05 = 252.305
        assertApproxEqAbs(market.debtOf(borrower), 252_305_000, 5_000);
        // suppliers: 1,000 + 12.305 interest − 10% reserve
        assertApproxEqAbs(market.totalAssets(), 1_011_074_000, 5_000);
    }

    function test_rateJumpsAboveKink() public {
        LendingMarket m = new LendingMarket(IERC20(address(usdc)), 0, HYPE_PERP, 2, 100, 100, 100);
        vm.prank(lender);
        usdc.approve(address(m), type(uint256).max);
        vm.prank(lender);
        m.supply(100e6);
        vm.startPrank(borrower);
        m.depositCollateral{value: 10 ether}();
        m.borrow(90e6); // 90% utilisation
        vm.stopPrank();
        // 0.05 + 4.75 × (0.9 − 0.8) = 0.525
        assertEq(m.borrowRate(), 0.525e18);
    }

    // ------------------------------------------------------------ liquidation

    function test_liquidateHalfWithBonus() public {
        vm.prank(borrower);
        market.borrow(240e6);
        _setPrice(30e4); // $300 collateral, 80% LTV
        vm.prank(liquidator);
        uint256 seized = market.liquidate(borrower, type(uint256).max);
        // half the debt, 120 USDC, for 120 × 1.05 / 30 = 4.2 HYPE
        assertEq(seized, 4.2 ether);
        assertEq(liquidator.balance, 4.2 ether);
        assertEq(market.debtOf(borrower), 120e6);
        assertEq(market.collateral(borrower), 5.8 ether);
    }

    function test_healthyCannotBeLiquidated() public {
        vm.prank(borrower);
        market.borrow(240e6);
        vm.prank(liquidator);
        vm.expectRevert(abi.encodeWithSelector(LendingMarket.Healthy.selector, 6_000));
        market.liquidate(borrower, 100e6);
    }

    /// Liquidation has no bounds: a messy book in a crash cannot block it. It prices at the
    /// higher of the oracle and the mark.
    function test_liquidationIgnoresTheGuard() public {
        vm.prank(borrower);
        market.borrow(240e6);
        _setQuote(30e4, 31e4, 25e4, 36e4); // 36% wide book; liquidation price 31, LTV 77%
        vm.prank(liquidator);
        uint256 seized = market.liquidate(borrower, 60e6);
        assertEq(market.debtOf(borrower), 180e6);
        assertEq(seized, uint256(60e6) * 1e12 * 10_500 / 10_000 * 1e18 / 31e18); // at 31, not 30
    }

    /// Underwater: collateral runs out, the rest is written off against the reserves, then suppliers.
    function test_badDebtWrittenOff() public {
        vm.prank(borrower);
        market.borrow(240e6);
        _setPrice(10e4); // $100 collateral for 240 debt
        vm.prank(liquidator);
        uint256 seized = market.liquidate(borrower, type(uint256).max);
        assertEq(seized, 10 ether);
        assertEq(market.collateral(borrower), 0);
        assertEq(market.debtShares(borrower), 0);
        // repaid 100 / 1.05 = 95.238..., written off 240 − 95.24 = 144.76
        assertApproxEqAbs(market.totalAssets(), 1_000e6 - 144_761_904, 2);
    }

    // ------------------------------------------------------------ review r1

    /// r1 high: the oracle alone falling cannot liquidate a borrower the mark says is healthy.
    function test_r1_oracleAloneCannotLiquidate() public {
        vm.prank(borrower);
        market.borrow(240e6);
        _setQuote(30e4, 40e4, 39.98e4, 40.02e4);
        vm.prank(liquidator);
        vm.expectRevert(abi.encodeWithSelector(LendingMarket.Healthy.selector, 6_000));
        market.liquidate(borrower, type(uint256).max);
    }

    /// r1 high: how often anyone calls does not change what a borrower owes (the r1 PoC:
    /// 100% utilisation, a dust supply every day for a year).
    function test_r1_interestIndependentOfCallFrequency() public {
        LendingMarket once = new LendingMarket(IERC20(address(usdc)), 0, HYPE_PERP, 2, 100, 100, 100);
        LendingMarket daily = new LendingMarket(IERC20(address(usdc)), 0, HYPE_PERP, 2, 100, 100, 100);
        LendingMarket[2] memory ms = [once, daily];
        vm.deal(borrower, 200 ether);
        for (uint256 i; i < 2; ++i) {
            vm.prank(lender);
            usdc.approve(address(ms[i]), type(uint256).max);
            vm.prank(lender);
            ms[i].supply(1_000e6);
            vm.startPrank(borrower);
            ms[i].depositCollateral{value: 50 ether}(); // $2,000
            ms[i].borrow(1_000e6); // 100% utilisation: a constant 100% rate
            vm.stopPrank();
        }
        address griefer = address(0x6E1F);
        usdc.mint(griefer, 1_000);
        vm.startPrank(griefer);
        usdc.approve(address(daily), type(uint256).max);
        for (uint256 i; i < 365; ++i) {
            skip(1 days);
            daily.supply(1);
        }
        vm.stopPrank();
        uint256 a = once.debtOf(borrower);
        uint256 b = daily.debtOf(borrower);
        assertApproxEqRel(b, a, 1e12); // equal to 0.0001% (was +35% before the fix)
        assertApproxEqRel(a, 2_718_281_828, 1e15); // 1,000 × e^1
    }

    /// r1 low: a repayment too small to burn a debt share is refused, not taken.
    function test_r1_dustRepayRefused() public {
        vm.prank(borrower);
        market.borrow(240e6);
        skip(1);
        uint256 before = usdc.balanceOf(borrower);
        vm.prank(borrower);
        vm.expectRevert(LendingMarket.Zero.selector);
        market.repay(borrower, 1);
        assertEq(usdc.balanceOf(borrower), before);
    }

    // ------------------------------------------------------------ review r2

    /// r2 low: after decades of interest one debt share is worth a lot, and a short liquidation
    /// must not hand over more collateral than the rounded payment buys.
    function test_r2_shortLiquidationSeizesOnlyWhatWasPaid() public {
        vm.prank(borrower);
        market.borrow(240e6);
        skip(28 * 365 days);
        _setPrice(1e4); // collateral worth 10 USDC against a huge debt
        uint256 coll = market.collateral(borrower);
        vm.prank(liquidator);
        uint256 seized = market.liquidate(borrower, type(uint256).max);
        // never more HYPE than the payment buys at the bonus, plus at most 1 USDC of dust
        uint256 paidUsdc = 1_000_000e6 - usdc.balanceOf(liquidator);
        uint256 bought = paidUsdc * 1e12 * 10_500 / 10_000 * 1e18 / 1e18;
        assertLe(seized, bought + 1 ether); // 1 HYPE = 1 USDC here
        assertLe(seized, coll);
    }

    /// r2 low: a market left alone for 68 years can still be read.
    function test_r2_rpowNoOverflowOnLongIdle() public {
        vm.prank(borrower);
        market.borrow(240e6);
        skip(2 ** 31);
        market.debtOf(borrower);
    }
}
