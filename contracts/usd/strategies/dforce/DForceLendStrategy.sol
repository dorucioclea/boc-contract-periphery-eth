// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "hardhat/console.sol";

import "boc-contract-core/contracts/strategy/BaseClaimableStrategy.sol";

import "./../../enums/ProtocolEnum.sol";
import "../../../external/dforce/DFiToken.sol";
import "../../../external/dforce/IRewardDistributorV3.sol";

contract DForceLendStrategy is BaseClaimableStrategy {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    address internal constant DF = 0x431ad2ff6a9C365805eBaD47Ee021148d6f7DBe0;
    IRewardDistributorV3 internal constant rewardDistributorV3 =
        IRewardDistributorV3(0x8fAeF85e436a8dd85D8E636Ea22E3b90f1819564);

    address public iToken;

    function initialize(address _vault, address _harvester,string memory _name,address _underlyingToken,address _iToken) external initializer {
        address[] memory _wants = new address[](1);
        _wants[0] = _underlyingToken;
        iToken = _iToken;
        super._initialize(_vault, _harvester, _name,uint16(ProtocolEnum.DForce), _wants);
    }


    function getVersion() external pure override returns (string memory) {
        return "1.0.0";
    }

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

    function getOutputsInfo()
        external
        view
        virtual
        override
        returns (OutputInfo[] memory outputsInfo)
    {
        outputsInfo = new OutputInfo[](1);
        OutputInfo memory info0 = outputsInfo[0];
        info0.outputCode = 0;
        info0.outputTokens = wants;
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
        address iTokenTmp = iToken;
        _tokens = wants;
        _amounts = new uint256[](1);
        _amounts[0] =
            (balanceOfToken(iTokenTmp) * DFiToken(iTokenTmp).exchangeRateStored()) /
            1e18 +
            balanceOfToken(_tokens[0]);
    }

    function get3rdPoolAssets() external view override returns (uint256) {
        address iTokenTmp = iToken;
        uint256 iTokenTotalSupply = (DFiToken(iTokenTmp).totalSupply() *
            DFiToken(iTokenTmp).exchangeRateStored()) / 1e18;
        return iTokenTotalSupply != 0 ? queryTokenValue(wants[0], iTokenTotalSupply) : 0;
    }

    function claimRewards()
        internal
        override
        returns (address[] memory _rewardTokens, uint256[] memory _claimAmounts)
    {
        address[] memory holders = new address[](1);
        holders[0] = address(this);
        address[] memory iTokens = new address[](1);
        iTokens[0] = iToken;
        rewardDistributorV3.claimReward(holders, iTokens);
        _rewardTokens = new address[](1);
        _rewardTokens[0] = DF;
        _claimAmounts = new uint256[](1);
        _claimAmounts[0] = balanceOfToken(_rewardTokens[0]);
    }

    function depositTo3rdPool(address[] memory _assets, uint256[] memory _amounts)
        internal
        override
    {
        uint256 amount = _amounts[0];
        if (amount > 0) {
            address iTokenTmp = iToken;
            address asset = _assets[0];
            IERC20Upgradeable(asset).safeApprove(iTokenTmp, 0);
            IERC20Upgradeable(asset).safeApprove(iTokenTmp, amount);
            DFiToken(iTokenTmp).mint(address(this), amount);
        }
    }

    function withdrawFrom3rdPool(
        uint256 _withdrawShares,
        uint256 _totalShares,
        uint256 _outputCode
    ) internal override {
        address iTokenTmp = iToken;
        uint256 _lpAmount = (balanceOfToken(iTokenTmp) * _withdrawShares) / _totalShares;
        if (_lpAmount > 0) {
            DFiToken(iTokenTmp).redeem(address(this), _lpAmount);
        }
    }
}