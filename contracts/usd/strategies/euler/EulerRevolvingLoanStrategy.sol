// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "boc-contract-core/contracts/strategy/BaseStrategy.sol";

import "./../../enums/ProtocolEnum.sol";
import "../../../external/euler/IEulerDToken.sol";
import "../../../external/euler/IEulerEToken.sol";
import "../../../external/euler/IEulerMarkets.sol";
import "../../../external/uniswap/IUniswapV2Router2.sol";
import "../../../external/uniswap/IUniswapV3.sol";

/// @title EulerRevolvingLoanStrategy
/// @notice Investment strategy of investing in stablecoins and revolving lending through post-staking via EulerRevolvingLoan
/// @author Bank of Chain Protocol Inc
contract EulerRevolvingLoanStrategy is BaseStrategy {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    address internal constant EULER_ADDRESS = 0x27182842E098f60e3D576794A5bFFb0777E025d3;
    address internal constant EULER_MARKETS = 0x3520d5a913427E6F0D6A83E07ccD4A4da316e4d3;
    address internal constant UNISWAP_V3_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    IUniswapV2Router2 public constant UNIROUTER2 =
        IUniswapV2Router2(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    address public constant W_ETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant EUL = 0xd9Fcd98c322942075A5C3860693e9f4f03AAE07b;
    uint256 public constant BPS = 10000;

    address public eToken;
    address public dToken;

    uint256 public borrowFactor;
    uint256 public borrowFactorMax;
    uint256 public borrowFactorMin;
    uint256 public borrowCount;
    uint256 public leverage;
    uint256 public leverageMax;
    uint256 public leverageMin;

    /// @param _borrowFactor The new borrow factor
    event UpdateBorrowFactor(uint256 _borrowFactor);
    /// @param _borrowFactorMax The new max borrow factor
    event UpdateBorrowFactorMax(uint256 _borrowFactorMax);
    /// @param _borrowFactorMin The new min borrow factor
    event UpdateBorrowFactorMin(uint256 _borrowFactorMin);
    /// @param _borrowCount The new count Of borrow
    event UpdateBorrowCount(uint256 _borrowCount);
    /// @param _remainingAmount The amount of aToken will still be used as collateral to borrow eth
    /// @param _overflowAmount The amount of debt token that exceeds the maximum allowable loan
    event Rebalance(uint256 _remainingAmount, uint256 _overflowAmount);

    /// @param _strategy The specified strategy emitted this event
    /// @param _rewards The address list of reward tokens
    /// @param _rewardAmounts The amount list of of reward tokens
    /// @param _wants The address list of wantted tokens
    /// @param _wantAmounts The amount list of wantted tokens
    event SwapRewardsToWants(
        address _strategy,
        address[] _rewards,
        uint256[] _rewardAmounts,
        address[] _wants,
        uint256[] _wantAmounts
    );

    /// @notice Initialize this contract
    /// @param _vault The Vault contract
    /// @param _harvester The harvester contract address
    /// @param _name The name of strategy
    /// @param _underlyingToken The lending asset of the Vault contract
    function initialize(
        address _vault,
        address _harvester,
        string memory _name,
        address _underlyingToken
    ) external initializer {
        borrowCount = 10;
        borrowFactor = 8000;
        borrowFactorMax = 8400;
        borrowFactorMin = 7600;

        leverage = _calLeverage(8000, 10000, 10);
        leverageMax = _calLeverage(8400, 10000, 10);
        leverageMin = _calLeverage(7600, 10000, 10);

        address[] memory _wants = new address[](1);
        _wants[0] = _underlyingToken;

        IEulerMarkets eIEulerMarkets = IEulerMarkets(EULER_MARKETS);
        address _eToken = eIEulerMarkets.underlyingToEToken(_underlyingToken);
        eToken = _eToken;
        address _dToken = eIEulerMarkets.underlyingToDToken(_underlyingToken);
        dToken = _dToken;

        super._initialize(_vault, _harvester, _name, uint16(ProtocolEnum.Euler), _wants);
        IERC20Upgradeable(_underlyingToken).safeApprove(EULER_ADDRESS, type(uint256).max);
    }

    /// @notice Sets `_borrowFactor` to `borrowFactor`
    /// @param _borrowFactor The new value of `borrowFactor`
    /// Requirements: only vault manager can call
    function setBorrowFactor(uint256 _borrowFactor) external isVaultManager {
        require(
            _borrowFactor < BPS &&
                _borrowFactor >= borrowFactorMin &&
                _borrowFactor <= borrowFactorMax,
            "setting output the range"
        );
        borrowFactor = _borrowFactor;
        leverage = _getNewLeverage(_borrowFactor);

        emit UpdateBorrowFactor(_borrowFactor);
    }

    /// @notice Sets `_borrowFactorMax` to `borrowFactorMax`
    /// @param _borrowFactorMax The new value of `borrowFactorMax`
    /// Requirements: only vault manager can call
    function setBorrowFactorMax(uint256 _borrowFactorMax) external isVaultManager {
        require(
            _borrowFactorMax < BPS && _borrowFactorMax > borrowFactor,
            "setting output the range"
        );
        borrowFactorMax = _borrowFactorMax;
        leverageMax = _getNewLeverage(_borrowFactorMax);

        emit UpdateBorrowFactorMax(_borrowFactorMax);
    }

    /// @notice Sets `_borrowFactorMin` to `borrowFactorMin`
    /// @param _borrowFactorMin The new value of `borrowFactorMin`
    /// Requirements: only vault manager can call
    function setBorrowFactorMin(uint256 _borrowFactorMin) external isVaultManager {
        require(
            _borrowFactorMin < BPS && _borrowFactorMin < borrowFactor,
            "setting output the range"
        );
        borrowFactorMin = _borrowFactorMin;
        leverageMin = _getNewLeverage(_borrowFactorMin);

        emit UpdateBorrowFactorMin(_borrowFactorMin);
    }

    /// @notice Sets `_borrowCount` to `borrowCount`
    /// @param _borrowCount The new value of `borrowCount`
    /// Requirements: only keeper can call
    function setBorrowCount(uint256 _borrowCount) external isKeeper {
        require(_borrowCount <= 20, "setting output the range");
        borrowCount = _borrowCount;
        _updateAllLeverage();
        emit UpdateBorrowCount(_borrowCount);
    }

    /// @notice Return the version of strategy
    function getVersion() external pure override returns (string memory) {
        return "1.0.0";
    }

    /// @notice Return the underlying token list and ratio list needed by the strategy
    /// @return _assets the address list of token to deposit
    /// @return _ratios the ratios list of `_assets`.
    ///     The ratio is the proportion of each asset to total assets
    function getWantsInfo()
        public
        view
        override
        returns (address[] memory _assets, uint256[] memory _ratios)
    {
        _assets = wants;
        _ratios = new uint256[](1);
        _ratios[0] = 1e18;
    }

    /// @notice Return the output path list of the strategy when withdraw.
    function getOutputsInfo()
        external
        view
        virtual
        override
        returns (OutputInfo[] memory _outputsInfo)
    {
        _outputsInfo = new OutputInfo[](1);
        OutputInfo memory _info0 = _outputsInfo[0];
        _info0.outputCode = 0;
        _info0.outputTokens = wants;
    }

    /// @notice Returns the position details of the strategy.
    /// @return _tokens The list of the position token
    /// @return _amounts The list of the position amount
    /// @return _isUsd Whether to count in USD
    /// @return _usdValue The USD value of positions held
    function getPositionDetail()
        public
        view
        override
        returns (
            address[] memory _tokens,
            uint256[] memory _amounts,
            bool _isUsd,
            uint256 _usdValue
        )
    {
        _tokens = wants;
        _amounts = new uint256[](1);
        _amounts[0] =
            IEulerEToken(eToken).balanceOfUnderlying(address(this)) +
            balanceOfToken(_tokens[0]) -
            IEulerDToken(dToken).balanceOf(address(this));
    }

    /// @notice Return the third party protocol's pool total assets in USD.
    function get3rdPoolAssets() external view override returns (uint256) {
        uint256 _iTokenTotalSupply = IEulerEToken(eToken).totalSupplyUnderlying();
        return _iTokenTotalSupply != 0 ? queryTokenValue(wants[0], _iTokenTotalSupply) : 0;
    }

    /// @inheritdoc BaseStrategy
    function repay(
        uint256 _repayShares,
        uint256 _totalShares,
        uint256 _outputCode
    )
        public
        virtual
        override
        onlyVault
        returns (address[] memory _assets, uint256[] memory _amounts)
    {
        // if withdraw all need claim rewards
        if (_repayShares == _totalShares) {
            harvest();
        }
        return super.repay(_repayShares, _totalShares, _outputCode);
    }

    /// @inheritdoc BaseStrategy
    function harvest()
        public
        virtual
        override
        returns (address[] memory _rewardsTokens, uint256[] memory _claimAmounts)
    {
        // sell reward token
        (
            bool _claimIsWorth,
            address[] memory _rewardsTokens,
            uint256[] memory _claimAmounts,
            address[] memory _wantTokens,
            uint256[] memory _wantAmounts
        ) = _claimRewardsAndReInvest();
        if (_claimIsWorth) {
            vault.report(_rewardsTokens, _claimAmounts);
            emit SwapRewardsToWants(
                address(this),
                _rewardsTokens,
                _claimAmounts,
                _wantTokens,
                _wantAmounts
            );
        }
    }

    /// @notice Rebalance the collateral of this strategy
    /// Requirements: only keeper can call
    function rebalance() external isKeeper {
        (uint256 _remainingAmount, uint256 _overflowAmount) = _borrowInfo(
            eToken,
            dToken,
            borrowCount
        );
        _rebalance(_remainingAmount, _overflowAmount);
    }

    /// @notice Returns the info of borrow.
    /// @return _remainingAmount The amount of aToken will still be used as collateral to borrow
    /// @return _overflowAmount The amount of aToken that exceeds the maximum allowable loan
    function borrowInfo() public view returns (uint256 _remainingAmount, uint256 _overflowAmount) {
        (_remainingAmount, _overflowAmount) = _borrowInfo(eToken, dToken, borrowCount);
    }

    /// @notice Strategy deposit funds to third party pool.
    /// @param _assets the address list of token to deposit
    /// @param _amounts the amount list of token to deposit
    function depositTo3rdPool(address[] memory _assets, uint256[] memory _amounts)
        internal
        override
    {
        uint256 _amount = _amounts[0];
        if (_amount > 0) {
            address _eToken = eToken;
            IEulerEToken(_eToken).deposit(0, _amount);
            (uint256 _remainingAmount, uint256 _overflowAmount) = _borrowStandardInfo(
                _eToken,
                dToken,
                borrowCount
            );
            _rebalance(_remainingAmount, _overflowAmount);
        }
    }

    /// @notice Strategy withdraw the funds from third party pool
    /// @param _withdrawShares The amount of shares to withdraw
    /// @param _totalShares The total amount of shares owned by this strategy
    /// @param _outputCode The code of output
    function withdrawFrom3rdPool(
        uint256 _withdrawShares,
        uint256 _totalShares,
        uint256 _outputCode
    ) internal override {
        address _eToken = eToken;
        address _dToken = dToken;
        uint256 _collateralAmount = IEulerEToken(_eToken).balanceOfUnderlying(address(this));
        uint256 _redeemAmount = (_collateralAmount * _withdrawShares) / _totalShares;
        uint256 _debtAmount = IEulerDToken(_dToken).balanceOf(address(this));
        uint256 _repayBorrowAmount = (_debtAmount * _withdrawShares) / _totalShares;
        if (_redeemAmount > 0) {
            uint256 _leverage = leverage;
            uint256 _newDebtAmount = (_debtAmount - _repayBorrowAmount) * _leverage;
            uint256 _newCollateralAmount = (_collateralAmount - _redeemAmount) * (_leverage - BPS);
            if (_newDebtAmount > _newCollateralAmount) {
                uint256 _decreaseAmount = (_newDebtAmount - _newCollateralAmount) / BPS;
                _redeemAmount = _redeemAmount + _decreaseAmount;
                _repayBorrowAmount = _repayBorrowAmount + _decreaseAmount;
            } else {
                uint256 _increaseAmount = (_newCollateralAmount - _newDebtAmount) / BPS;
                _redeemAmount = _redeemAmount - _increaseAmount;
                _repayBorrowAmount = _repayBorrowAmount - _increaseAmount;
            }
            _repay(_redeemAmount, _repayBorrowAmount);
        }
    }

    /// @notice Collect the rewards from third party protocol,then swap from the reward tokens to wanted tokens and reInvest
    /// @return _claimIsWorth The boolean value to check the claim action is worth or not
    /// @return _rewardTokens The list of the reward token
    /// @return _claimAmounts The list of the reward amount claimed
    /// @return _wantTokens The address list of the wanted token
    /// @return _wantAmounts The amount list of the wanted token
    function _claimRewardsAndReInvest()
        internal
        returns (
            bool _claimIsWorth,
            address[] memory _rewardTokens,
            uint256[] memory _claimAmounts,
            address[] memory _wantTokens,
            uint256[] memory _wantAmounts
        )
    {
        //        address[] memory _holders = new address[](1);
        //        _holders[0] = address(this);
        //        address[] memory _iTokens = new address[](1);
        //        _iTokens[0] = eToken;
        //        IRewardDistributorV3(rewardDistributorV3).claimReward(_holders, _iTokens);
        //        _rewardTokens = new address[](1);
        //        _rewardTokens[0] = DF;
        //        _claimAmounts = new uint256[](1);
        //        _wantTokens = wants;
        //        _wantAmounts = new uint256[](1);
        //        uint256 _balanceOfDF = balanceOfToken(_rewardTokens[0]);
        //        _claimAmounts[0] = _balanceOfDF;
        //        if (_balanceOfDF > 0) {
        _claimIsWorth = true;
        //            // swap from DF to WETH
        //            //set up sell reward path
        //            address[] memory _dfSellPath = new address[](2);
        //            _dfSellPath[0] = DF;
        //            _dfSellPath[1] = W_ETH;
        //            UNIROUTER2.swapExactTokensForTokens(
        //                _balanceOfDF,
        //                0,
        //                _dfSellPath,
        //                address(this),
        //                block.timestamp
        //            );
        //            uint256 _balanceOfWETH = balanceOfToken(W_ETH);
        //            IUniswapV3(UNISWAP_V3_ROUTER).exactInputSingle(
        //                IUniswapV3.ExactInputSingleParams(
        //                    W_ETH,
        //                    _wantTokens[0],
        //                    500,
        //                    address(this),
        //                    block.timestamp,
        //                    _balanceOfWETH,
        //                    0,
        //                    0
        //                )
        //            );
        //            _wantAmounts[0] = balanceOfToken(_wantTokens[0]);
        //            DFiToken(_iTokens[0]).mint(address(this), _wantAmounts[0]);
        //        }
    }

    /// @notice repayBorrow and redeem collateral
    function _repay(uint256 _redeemAmount, uint256 _repayBorrowAmount) internal {
        if (_redeemAmount > _repayBorrowAmount) {
            IEulerEToken(eToken).burn(0, _repayBorrowAmount);
            IEulerEToken(eToken).withdraw(0, _redeemAmount - _repayBorrowAmount);
        } else {
            IEulerEToken(eToken).burn(0, _redeemAmount);
        }
    }

    /// @notice Rebalance the collateral of this strategy
    function _rebalance(uint256 _remainingAmount, uint256 _overflowAmount) internal {
        if (_remainingAmount > 0) {
            IEulerEToken(eToken).mint(0, _remainingAmount);
        } else if (_overflowAmount > 0) {
            _repay(_overflowAmount, _overflowAmount);
        }
        if (_remainingAmount + _overflowAmount > 0) {
            emit Rebalance(_remainingAmount, _overflowAmount);
        }
    }

    /// @notice Returns the info of borrow.
    /// @dev _needCollateralAmount = (_debtAmount * _leverage) / (_leverage - BPS);
    /// _debtAmount_now / _needCollateralAmount = （_leverage - 10000) / _leverage;
    /// _leverage = (capitalAmount + _debtAmount_now) *10000 / capitalAmount;
    /// _debtAmount_now = capitalAmount * (_leverage - 10000)
    /// @return _remainingAmount The amount of aToken will still be used as collateral to borrow eth
    /// @return _overflowAmount The amount of debt token that exceeds the maximum allowable loan
    function _borrowInfo(
        address _eToken,
        address _dToken,
        uint256 _borrowCount
    ) private view returns (uint256 _remainingAmount, uint256 _overflowAmount) {
        if (_borrowCount == 0) {
            _overflowAmount = IEulerDToken(_dToken).balanceOf(address(this));
        } else {
            uint256 _debtAmount = IEulerDToken(_dToken).balanceOf(address(this));
            uint256 _collateralAmount = IEulerEToken(_eToken).balanceOfUnderlying(address(this));
            uint256 _capitalAmount = _collateralAmount - _debtAmount;

            uint256 _BPS = BPS;
            uint256 _needCollateralAmount = (_capitalAmount * leverage) / _BPS;
            uint256 _needCollateralAmountMin = (_capitalAmount * leverageMin) / _BPS;
            uint256 _needCollateralAmountMax = (_capitalAmount * leverageMax) / _BPS;
            if (_needCollateralAmountMin > _collateralAmount) {
                _remainingAmount = _needCollateralAmount - _collateralAmount;
            } else if (_needCollateralAmountMax < _collateralAmount) {
                _overflowAmount = _collateralAmount - _needCollateralAmount;
            }
        }
    }

    /// @notice Returns the info of borrow with default borrowFactor
    /// @return _remainingAmount The amount of aToken will still be used as collateral to borrow
    /// @return _overflowAmount The amount of debt token that exceeds the maximum allowable loan
    function _borrowStandardInfo(
        address _eToken,
        address _dToken,
        uint256 _borrowCount
    ) private view returns (uint256 _remainingAmount, uint256 _overflowAmount) {
        if (_borrowCount == 0) {
            _overflowAmount = IEulerDToken(_dToken).balanceOf(address(this));
        } else {
            uint256 _debtAmount = IEulerDToken(_dToken).balanceOf(address(this));
            uint256 _collateralAmount = IEulerEToken(_eToken).balanceOfUnderlying(address(this));
            uint256 _capitalAmount = _collateralAmount - _debtAmount;
            uint256 _needCollateralAmount = (_capitalAmount * leverage) / BPS;
            if (_needCollateralAmount > _collateralAmount) {
                _remainingAmount = _needCollateralAmount - _collateralAmount;
            } else if (_needCollateralAmount < _collateralAmount) {
                _overflowAmount = _collateralAmount - _needCollateralAmount;
            }
        }
    }

    /// @notice Returns the new leverage with the fix borrowFactor
    /// @return _borrowFactor The borrow factor
    function _getNewLeverage(uint256 _borrowFactor) internal view returns (uint256) {
        return _calLeverage(_borrowFactor, BPS, borrowCount);
    }

    /// @notice update all leverage (leverage leverageMax leverageMin)
    function _updateAllLeverage() internal {
        uint256 _bps = BPS;
        uint256 _borrowCount = borrowCount;
        leverage = _calLeverage(borrowFactor, _bps, _borrowCount);
        leverageMax = _calLeverage(borrowFactorMax, _bps, _borrowCount);
        leverageMin = _calLeverage(borrowFactorMin, _bps, _borrowCount);
    }

    /// @notice Returns the leverage  with by _borrowFactor _bps  _borrowCount
    /// @return _borrowFactor The borrow factor
    function _calLeverage(
        uint256 _borrowFactor,
        uint256 _bps,
        uint256 _borrowCount
    ) private pure returns (uint256) {
        // q = borrowFactor/bps
        // n = borrowCount + 1;
        // _leverage = (1-q^n)/(1-q),(n>=1, q=0.8)
        uint256 _leverage = _bps;
        if (_borrowCount >= 1) {
            _leverage =
                (_bps * _bps - (_borrowFactor**(_borrowCount + 1)) / (_bps**(_borrowCount - 1))) /
                (_bps - _borrowFactor);
        }
        return _leverage;
    }
}