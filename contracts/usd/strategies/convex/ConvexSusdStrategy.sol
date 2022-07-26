// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "../../../external/curve/ICurveLiquidityPool.sol";

import "./ConvexBaseStrategy.sol";

contract ConvexSusdStrategy is ConvexBaseStrategy {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    ICurveLiquidityPool private constant CURVE_POOL =
        ICurveLiquidityPool(address(0xA5407eAE9Ba41422680e2e00537571bcC53efBfD));

    address private constant CRV = address(0xD533a949740bb3306d119CC777fa900bA034cd52);
    address private constant CVX = address(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);
    address private constant SNX = address(0xC011a73ee8576Fb46F5E1c5751cA3B9Fe0af2a6F);

    function initialize(address _vault, address _harvester) public {
        address[] memory _wants = new address[](4);
        // the oder is same with underlying coins
        // DAI
        _wants[0] = address(0x6B175474E89094C44Da98b954EedeAC495271d0F);
        // USDC
        _wants[1] = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
        // USDT
        _wants[2] = address(0xdAC17F958D2ee523a2206206994597C13D831ec7);
        // sUSD
        _wants[3] = address(0x57Ab1ec28D129707052df4dF418D58a2D46d5f51);
        super._initialize(
            _vault,
            _harvester,
            _wants
        );
    }

    function getVersion() external pure override returns (string memory) {
        return "1.0.0";
    }

    function name() external pure override returns (string memory) {
        return "ConvexSusdStrategy";
    }

    function getRewardPool() internal pure override returns(IConvexReward) {
        return IConvexReward(address(0x22eE18aca7F3Ee920D01F25dA85840D12d98E8Ca));
    }

    function getWantsInfo()
        public
        view
        override
        returns (address[] memory _assets, uint256[] memory _ratios)
    {
        _assets = wants;
        _ratios = new uint256[](_assets.length);
        int128 index = 0;
        for (uint256 i = 0; i < _assets.length; i++) {
            _ratios[i] = CURVE_POOL.balances(index);
            index++;
        }
    }

    function getPositionDetail()
        public
        view
        override
        returns (
            address[] memory _tokens,
            uint256[] memory _amounts,
            bool isUsd,
            uint256 usdValue
        )
    {
        _tokens = wants;
        _amounts = new uint256[](_tokens.length);
        // curve LP token amount = convex LP token amount
        uint256 lpAmount = balanceOfLpToken();
        // curve LP total supply
        uint256 totalSupply = IERC20Upgradeable(lpToken).totalSupply();
        // calc balances
        int128 index = 0;
        for (uint256 i = 0; i < _tokens.length; i++) {
            uint256 depositedTokenAmount = (CURVE_POOL.balances(index) * lpAmount) / totalSupply;
            _amounts[i] = balanceOfToken(_tokens[i]) + depositedTokenAmount;
            index++;
        }
    }

    function get3rdPoolAssets() external view override returns (uint256) {
        address[] memory _assets = wants;
        uint256 thirdPoolAssets;
        int128 index = 0;
        for (uint256 i = 0; i < _assets.length; i++) {
            uint256 thirdPoolAssetBalance = CURVE_POOL.balances(index);
            thirdPoolAssets += queryTokenValue(_assets[i], thirdPoolAssetBalance);
            index++;
        }
        return thirdPoolAssets;
    }

    function curveAddLiquidity(address[] memory _assets, uint256[] memory _amounts)
        internal
        override
        returns (uint256)
    {
        for (uint256 i = 0; i < _assets.length; i++) {
            if (_amounts[i] > 0) {
                IERC20Upgradeable(_assets[i]).safeApprove(address(CURVE_POOL), 0);
                IERC20Upgradeable(_assets[i]).safeApprove(address(CURVE_POOL), _amounts[i]);
            }
        }
        CURVE_POOL.add_liquidity([_amounts[0], _amounts[1], _amounts[2], _amounts[3]], 0);
        uint256 lpAmount = balanceOfToken(lpToken);
        return lpAmount;
    }

    function curveRemoveLiquidity(uint256 liquidity) internal override {
        CURVE_POOL.remove_liquidity(liquidity, [uint256(0), uint256(0), uint256(0), uint256(0)]);
    }

    function claimRewards()
        internal
        override
        returns (address[] memory _rewardTokens, uint256[] memory _claimAmounts)
    {
        getRewardPool().getReward();
        _rewardTokens = new address[](3);
        _rewardTokens[0] = CRV;
        _rewardTokens[1] = CVX;
        _rewardTokens[2] = SNX;
        _claimAmounts = new uint256[](3);
        _claimAmounts[0] = balanceOfToken(CRV);
        _claimAmounts[1] = balanceOfToken(CVX);
        _claimAmounts[2] = balanceOfToken(SNX);
    }
}