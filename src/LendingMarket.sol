// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {HLPriceGuard} from "hl-price-guard/HLPriceGuard.sol";
import {HLPrecompiles} from "hl-price-guard/HLPrecompiles.sol";
import {FullMath} from "./FullMath.sol";

interface IERC20 {
    function balanceOf(address who) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

/// @notice One isolated market on HyperEVM: borrow USDC against native HYPE.
///
/// The books, interest and liquidations all live on the EVM and settle synchronously. HyperCore
/// is only read: the HYPE price is the perp oracle (0x807). HyperCore's own borrow/lend cannot
/// serve this: borrowing there is implicit under portfolio margin and a borrowed balance cannot
/// leave the account (README).
///
/// Prices: anything that adds risk (borrowing, taking collateral out) needs the oracle to pass
/// hl-price-guard's checks against the mark and the book. Liquidation uses the higher of the
/// oracle and the mark, with no bounds: a borrower is liquidated only if unhealthy at both, and
/// paid out at the higher one (review r1: the bare oracle alone let a liquidator take collateral
/// the mark said was healthy). A real crash moves both, so it cannot block liquidation.
contract LendingMarket {
    // ---------------------------------------------------------------- parameters

    uint256 internal constant WAD = 1e18;
    uint256 internal constant BPS = 10_000;
    uint256 internal constant YEAR = 365 days;
    /// Virtual shares and assets, so the first supplier cannot inflate the share price.
    uint256 internal constant VIRTUAL_SHARES = 1e6;
    uint256 internal constant VIRTUAL_ASSETS = 1;
    /// Debt shares are counted this much finer than the index, so even after decades of interest
    /// one share stays a negligible amount of USDC (review r3: coarse shares stranded dust).
    uint256 internal constant SHARE_SCALE = 1e18;
    uint256 internal constant SHARE_UNIT = WAD * SHARE_SCALE;

    uint256 public constant MAX_LTV_BPS = 6_000; // borrow up to 60% of collateral value
    uint256 public constant LIQ_LTV_BPS = 7_500; // liquidatable above 75%
    uint256 public constant LIQ_BONUS_BPS = 500; // liquidator gets 5% more HYPE than it repays
    uint256 public constant CLOSE_FACTOR_BPS = 5_000; // at most half the debt per liquidation
    uint256 public constant RESERVE_FACTOR_BPS = 1_000; // 10% of interest kept as a buffer
    uint256 public constant DUST_USDC = 1e6; // collateral worth less than 1 USDC is not left behind
    /// Rate model, yearly, in WAD: BASE until KINK utilisation, then up by JUMP to 100%.
    /// Same shape as HyperCore's stablecoin rate (0.05 + 4.75 * max(0, u - 0.8)).
    uint256 public constant BASE_RATE = 0.05e18;
    uint256 public constant KINK = 0.8e18;
    uint256 public constant JUMP_RATE = 4.75e18;

    IERC20 public immutable usdc; // 6 decimals
    uint32 public immutable perpDex;
    uint32 public immutable perpIndex; // HYPE perp: testnet 135, mainnet 159
    uint8 public immutable szDecimals; // HYPE perp: 2
    uint16 public immutable maxMarkOracleBps;
    uint16 public immutable maxMidOracleBps;
    uint16 public immutable maxSpreadBps;

    // ---------------------------------------------------------------- state

    uint256 public totalSupplyShares;
    mapping(address => uint256) public supplyShares;

    uint256 public borrowIndex = WAD; // debt per debt share, grows with interest
    uint256 public totalDebtShares;
    mapping(address => uint256) public debtShares;
    uint256 public reserves; // USDC owed to the protocol buffer, part of the debt side
    uint256 public lastAccrual;

    mapping(address => uint256) public collateral; // HYPE, 18 decimals

    uint256 private locked = 1;

    // ---------------------------------------------------------------- events, errors

    event Supply(address indexed who, uint256 usdc, uint256 shares);
    event Withdraw(address indexed who, uint256 usdc, uint256 shares);
    event Collateral(address indexed who, int256 hype);
    event Borrow(address indexed who, uint256 usdc);
    event Repay(address indexed payer, address indexed borrower, uint256 usdc);
    event Liquidate(address indexed liquidator, address indexed borrower, uint256 repaid, uint256 seized, uint256 badDebt);

    error Locked();
    error Zero();
    error NotEnoughCash(uint256 cash);
    error Unhealthy(uint256 ltvBps);
    error Healthy(uint256 ltvBps);
    error NoPrice();
    error TransferFailed();

    constructor(
        IERC20 usdc_,
        uint32 perpDex_,
        uint32 perpIndex_,
        uint8 szDecimals_,
        uint16 maxMarkOracleBps_,
        uint16 maxMidOracleBps_,
        uint16 maxSpreadBps_
    ) {
        usdc = usdc_;
        perpDex = perpDex_;
        perpIndex = perpIndex_;
        szDecimals = szDecimals_;
        maxMarkOracleBps = maxMarkOracleBps_;
        maxMidOracleBps = maxMidOracleBps_;
        maxSpreadBps = maxSpreadBps_;
        lastAccrual = block.timestamp;
    }

    modifier nonReentrant() {
        if (locked != 1) revert Locked();
        locked = 2;
        _;
        locked = 1;
    }

    // ---------------------------------------------------------------- views

    /// USDC held by the market and free to lend or withdraw.
    function cash() public view returns (uint256) {
        return usdc.balanceOf(address(this));
    }

    function totalDebt() public view returns (uint256) {
        (uint256 index,) = _accrued();
        return _mulUp(totalDebtShares, index);
    }

    function debtOf(address who) public view returns (uint256) {
        (uint256 index,) = _accrued();
        return _mulUp(debtShares[who], index);
    }

    /// What suppliers own: cash plus what borrowers owe, less the protocol buffer.
    function totalAssets() public view returns (uint256) {
        (uint256 index, uint256 res) = _accrued();
        return cash() + _mulUp(totalDebtShares, index) - res;
    }

    function utilisation() public view returns (uint256) {
        uint256 debt = totalDebt();
        uint256 c = cash();
        return debt == 0 ? 0 : debt * WAD / (c + debt);
    }

    /// Yearly borrow rate, WAD.
    function borrowRate() public view returns (uint256) {
        return _rate(_mulUp(totalDebtShares, borrowIndex), cash());
    }

    /// The HYPE price checked against the mark and the book (1e18 USD per HYPE).
    function guardedPrice() public view returns (uint256) {
        HLPriceGuard.Asset memory a = HLPriceGuard.Asset(perpDex, perpIndex, szDecimals);
        HLPriceGuard.Bounds memory b = HLPriceGuard.Bounds(maxMarkOracleBps, maxMidOracleBps, maxSpreadBps, 0);
        return HLPriceGuard.read(a, b, HLPriceGuard.Ref(0, 0, 0));
    }

    /// The price for liquidations: the higher of the oracle (0x807) and the mark (0x806), which
    /// Hyperliquid itself uses for margining and liquidations. 1e18 USD per HYPE.
    function liquidationPrice() public view returns (uint256 px) {
        uint32 perp = HLPrecompiles.perpIndex(perpDex, perpIndex);
        uint256 o = HLPrecompiles.oracle(perp, szDecimals);
        uint256 m = HLPrecompiles.mark(perp, szDecimals);
        px = o > m ? o : m;
        if (o == 0 || m == 0) revert NoPrice();
    }

    /// Debt over collateral value, in bps, at `price`. type(uint256).max with debt and no collateral.
    function ltvBps(address who, uint256 price) public view returns (uint256) {
        uint256 debt = debtOf(who);
        if (debt == 0) return 0;
        uint256 value = _value(collateral[who], price);
        return value == 0 ? type(uint256).max : _divUp(debt * BPS, value);
    }

    // ---------------------------------------------------------------- suppliers

    function supply(uint256 amount) external nonReentrant returns (uint256 shares) {
        if (amount == 0) revert Zero();
        _accrue();
        shares = amount * (totalSupplyShares + VIRTUAL_SHARES) / (totalAssets() + VIRTUAL_ASSETS);
        if (shares == 0) revert Zero();
        totalSupplyShares += shares;
        supplyShares[msg.sender] += shares;
        _pull(amount);
        emit Supply(msg.sender, amount, shares);
    }

    function withdraw(uint256 shares) external nonReentrant returns (uint256 amount) {
        if (shares == 0) revert Zero();
        _accrue();
        amount = shares * (totalAssets() + VIRTUAL_ASSETS) / (totalSupplyShares + VIRTUAL_SHARES);
        uint256 c = cash();
        if (amount > c) revert NotEnoughCash(c);
        supplyShares[msg.sender] -= shares;
        totalSupplyShares -= shares;
        _sendUsdc(msg.sender, amount);
        emit Withdraw(msg.sender, amount, shares);
    }

    // ---------------------------------------------------------------- borrowers

    function depositCollateral() external payable nonReentrant {
        if (msg.value == 0) revert Zero();
        collateral[msg.sender] += msg.value;
        emit Collateral(msg.sender, int256(msg.value));
    }

    function withdrawCollateral(uint256 amount) external nonReentrant {
        if (amount == 0) revert Zero();
        _accrue();
        collateral[msg.sender] -= amount;
        if (debtShares[msg.sender] != 0) _requireHealthy(msg.sender, MAX_LTV_BPS);
        _sendHype(msg.sender, amount);
        emit Collateral(msg.sender, -int256(amount));
    }

    function borrow(uint256 amount) external nonReentrant {
        if (amount == 0) revert Zero();
        _accrue();
        uint256 c = cash();
        if (amount > c) revert NotEnoughCash(c);
        uint256 s = FullMath.mulDivUp(amount, SHARE_UNIT, borrowIndex); // round the debt up
        debtShares[msg.sender] += s;
        totalDebtShares += s;
        _requireHealthy(msg.sender, MAX_LTV_BPS);
        _sendUsdc(msg.sender, amount);
        emit Borrow(msg.sender, amount);
    }

    /// Repay up to `amount` of `borrower`'s debt; returns what was taken.
    function repay(address borrower, uint256 amount) external nonReentrant returns (uint256 paid) {
        _accrue();
        paid = _reduceDebt(borrower, amount);
        if (paid == 0) revert Zero();
        _pull(paid);
        emit Repay(msg.sender, borrower, paid);
    }

    // ---------------------------------------------------------------- liquidation

    /// Repay up to `amount` (and at most `CLOSE_FACTOR_BPS` of the debt) of a borrower above
    /// `LIQ_LTV_BPS`, and take that value in HYPE plus `LIQ_BONUS_BPS`. If that empties the
    /// collateral and debt is left, the rest is written off: against the reserves first, then
    /// suppliers.
    function liquidate(address borrower, uint256 amount) external nonReentrant returns (uint256 seized) {
        _accrue();
        uint256 price = liquidationPrice();
        uint256 ltv = ltvBps(borrower, price);
        if (ltv <= LIQ_LTV_BPS) revert Healthy(ltv);

        uint256 debt = debtOf(borrower);
        uint256 maxRepay = _divUp(debt * CLOSE_FACTOR_BPS, BPS);
        uint256 repayAmt = amount < maxRepay ? amount : maxRepay;
        uint256 coll = collateral[borrower];
        if (_seizeFor(repayAmt, price) >= coll) {
            // not enough collateral for the bonus: repay only what all of it covers
            repayAmt = coll * price / WAD * BPS / (BPS + LIQ_BONUS_BPS) / 1e12;
        }
        uint256 paid;
        if (repayAmt == 0 && _value(coll, price) < DUST_USDC) {
            // the collateral is worth less than DUST_USDC and buys nothing: take it and write the
            // debt off below, rather than leave the position stuck (review r3)
            seized = coll;
        } else {
            paid = _reduceDebt(borrower, repayAmt); // what the burned debt shares are worth
            seized = _seizeFor(paid, price);
        }
        // Decided on what was actually paid (review r2). What is left after the seize: all of it
        // goes when it is worth under DUST_USDC, so rounding cannot leave dust that blocks the
        // bad-debt write-off, and the liquidator can never get more than that for free.
        if (seized >= coll || _value(coll - seized, price) < DUST_USDC) seized = coll;
        collateral[borrower] = coll - seized;

        uint256 badDebt;
        if (collateral[borrower] == 0 && debtShares[borrower] != 0) {
            badDebt = _mulUp(debtShares[borrower], borrowIndex);
            totalDebtShares -= debtShares[borrower];
            debtShares[borrower] = 0;
            // the buffer takes the loss first, suppliers the rest
            reserves -= badDebt < reserves ? badDebt : reserves;
        }
        if (paid > 0) _pull(paid);
        _sendHype(msg.sender, seized);
        emit Liquidate(msg.sender, borrower, paid, seized, badDebt);
    }

    /// HYPE (18) for `usdcAmt` (6) at `price` (1e18 USD), plus the bonus.
    function _seizeFor(uint256 usdcAmt, uint256 price) internal pure returns (uint256) {
        return usdcAmt * 1e12 * (BPS + LIQ_BONUS_BPS) / BPS * WAD / price;
    }

    // ---------------------------------------------------------------- internals

    function _requireHealthy(address who, uint256 limitBps) internal view {
        uint256 ltv = ltvBps(who, guardedPrice());
        if (ltv > limitBps) revert Unhealthy(ltv);
    }

    /// Reduce `borrower`'s debt by up to `amount` USDC; returns the USDC that the burned debt
    /// shares are worth, which is what the caller then pays (review r1: paying `amount` while
    /// burning fewer shares took dust for nothing). Reverts if nothing would be burned.
    function _reduceDebt(address borrower, uint256 amount) internal returns (uint256 paid) {
        uint256 s = debtShares[borrower];
        uint256 debt = _mulUp(s, borrowIndex);
        uint256 burn;
        if (amount >= debt) {
            (burn, paid) = (s, debt);
        } else {
            burn = FullMath.mulDiv(amount, SHARE_UNIT, borrowIndex); // round the shares burned down
            paid = _mulUp(burn, borrowIndex); // <= amount
        }
        if (burn == 0) revert Zero();
        debtShares[borrower] = s - burn;
        totalDebtShares -= burn;
    }

    function _accrue() internal {
        (borrowIndex, reserves) = _accrued();
        lastAccrual = block.timestamp;
    }

    /// The borrow index and reserves as of now, without writing them.
    function _accrued() internal view returns (uint256 index, uint256 res) {
        index = borrowIndex;
        res = reserves;
        uint256 dt = block.timestamp - lastAccrual;
        if (dt == 0 || totalDebtShares == 0) return (index, res);
        uint256 debt = _mulUp(totalDebtShares, index);
        uint256 rate = _rate(debt, cash());
        // compounded per second, so the result does not depend on how often anyone calls
        // (review r1: simple interest per call let anyone compound a borrower's debt faster)
        uint256 factor = _rpow(WAD + rate / YEAR, dt);
        uint256 newIndex = FullMath.mulDiv(index, factor, WAD);
        uint256 interest = FullMath.mulDiv(totalDebtShares, newIndex - index, SHARE_UNIT);
        index = newIndex;
        res = res + interest * RESERVE_FACTOR_BPS / BPS;
    }

    /// x^n for x in WAD, by squaring.
    function _rpow(uint256 x, uint256 n) internal pure returns (uint256 z) {
        z = WAD;
        while (n > 0) {
            // full-precision products: revert only if the result itself cannot fit (review r2, r3)
            if (n & 1 == 1) z = FullMath.mulDiv(z, x, WAD);
            n >>= 1;
            if (n > 0) x = FullMath.mulDiv(x, x, WAD); // no square after the last bit
        }
    }

    function _rate(uint256 debt, uint256 c) internal pure returns (uint256) {
        if (debt == 0) return BASE_RATE;
        uint256 u = debt * WAD / (c + debt);
        return u <= KINK ? BASE_RATE : BASE_RATE + JUMP_RATE * (u - KINK) / WAD;
    }

    /// HYPE (18) at `price` (1e18 USD) in USDC (6).
    function _value(uint256 hype, uint256 price) internal pure returns (uint256) {
        return hype * price / WAD / 1e12;
    }

    /// USDC worth of `shares` debt shares at `index`, rounded up.
    function _mulUp(uint256 shares, uint256 index) internal pure returns (uint256) {
        return FullMath.mulDivUp(shares, index, SHARE_UNIT);
    }

    function _divUp(uint256 a, uint256 b) internal pure returns (uint256) {
        return a == 0 ? 0 : (a - 1) / b + 1;
    }

    function _pull(uint256 amount) internal {
        if (!usdc.transferFrom(msg.sender, address(this), amount)) revert TransferFailed();
    }

    function _sendUsdc(address to, uint256 amount) internal {
        if (!usdc.transfer(to, amount)) revert TransferFailed();
    }

    function _sendHype(address to, uint256 amount) internal {
        (bool ok,) = to.call{value: amount}("");
        if (!ok) revert TransferFailed();
    }
}
