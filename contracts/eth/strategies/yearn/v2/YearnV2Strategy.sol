// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "../../../enums/ProtocolEnum.sol";
import "../../ETHBaseStrategy.sol";
import "../../../../external/yearn/IYearnVaultV2.sol";

contract YearnV2Strategy is ETHBaseStrategy {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    IYearnVaultV2 public yVault;

    function initialize(
        address _vault,
        string memory _name,
        address _yVault,
        address _token
    ) external initializer {
        yVault = IYearnVaultV2(_yVault);
        address[] memory _wants = new address[](1);
        _wants[0] = _token;
        super._initialize(_vault, uint16(ProtocolEnum.YearnV2), _name, _wants);
    }

    function getVersion() external pure virtual override returns (string memory) {
        return "1.0.0";
    }

    function getWantsInfo()
        external
        view
        virtual
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
        OutputInfo memory info = outputsInfo[0];
        info.outputCode = 0;
        info.outputTokens = wants;
    }

    function getPositionDetail()
        public
        view
        virtual
        override
        returns (
            address[] memory _tokens,
            uint256[] memory _amounts,
            bool isETH,
            uint256 ethValue
        )
    {
        _tokens = wants;
        _amounts = new uint256[](1);
        IYearnVaultV2 _yVault = yVault;
        uint256 balanceOf = _yVault.balanceOf(address(this));
        uint256 pricePerShare = _yVault.pricePerShare();
        _amounts[0] = balanceOfToken(_tokens[0]) + (balanceOf * pricePerShare) / 1e18;
    }

    function get3rdPoolAssets() external view override returns (uint256) {
        return queryTokenValueInETH(wants[0], yVault.totalAssets());
    }

    function depositTo3rdPool(address[] memory _assets, uint256[] memory _amounts)
        internal
        override
    {
        require(_amounts[0] > 0);
        address yVaultAddress = address(yVault);
        address token = yVault.token();
        IERC20Upgradeable(token).safeApprove(yVaultAddress, 0);
        IERC20Upgradeable(token).safeApprove(yVaultAddress, _amounts[0]);
        yVault.deposit(_amounts[0]);
    }

    function withdrawFrom3rdPool(
        uint256 _withdrawShares,
        uint256 _totalShares,
        uint256 _outputCode
    ) internal override {
        IYearnVaultV2 _yVault = yVault;
        uint256 balanceOf = yVault.balanceOf(address(this));
        uint256 pricePerShare = yVault.pricePerShare();
        yVault.withdraw((balanceOf * _withdrawShares) / _totalShares);
    }
}