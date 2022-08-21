// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../../external/uniswap/IUniswapV3.sol";
import "../../../external/uniswap/IQuoter.sol";
import "../uniswapv3/ETHUniswapV3BaseStrategy.sol";
import "../../../external/stakewise/IMerkleDistributor.sol";

contract StakeWiseEthSeth23000Strategy is ETHUniswapV3BaseStrategy {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    // https://info.uniswap.org/#/pools/0x7379e81228514a1d2a6cf7559203998e20598346
    address internal constant UNISWAP_V3_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address internal constant STAKE_WISE_MERKLE_DISTRIBUTOR_ADDRESS = 0xA3F21010e8b9a3930996C8849Df38f9Ca3647c20;
    address internal constant SETH2 = 0xFe2e637202056d30016725477c5da089Ab0A043A;
    address internal constant RETH2 = 0x20BC832ca081b91433ff6c17f85701B6e92486c5;
    address internal constant SWISE = 0x48C3399719B582dD63eB5AADf12A40B4C3f52FA2;

    function initialize(address _vault, string memory _name) public initializer {
        uniswapV3Initialize(0x7379e81228514a1D2a6Cf7559203998E20598346, 60, 60, 41400, 0, 100, 60, 60);
        address[] memory _wants = new address[](2);
        _wants[0] = token0;
        _wants[1] = token1;
        super._initialize(_vault, uint16(ProtocolEnum.StakeWise), _name, _wants);
    }

    function getOutputsInfo() external view virtual override returns (OutputInfo[] memory _outputsInfo){
        _outputsInfo = new OutputInfo[](1);
        OutputInfo memory _info = _outputsInfo[0];
        _info.outputCode = 0;
        _info.outputTokens = wants;
    }

    function claimRewards() internal override returns (bool _isWorth, address[] memory _assets, uint256[] memory _amounts) {
        (_isWorth, _assets, _amounts) = super.claimRewards();
        swapRewardsToWants();
    }

    function merkleDistributorClaim(uint256 _index, address _account, address[] calldata _tokens, uint256[] calldata _amounts, bytes32[] calldata _merkleProof) public {
        address[] memory _rewardsTokens = new address[](2);
        _rewardsTokens[0] = RETH2;
        _rewardsTokens[1] = SWISE;
        uint256[] memory _claimAmounts = new uint256[](2);
        _claimAmounts[0] = balanceOfToken(RETH2);
        _claimAmounts[1] = balanceOfToken(SWISE);
        IMerkleDistributor(STAKE_WISE_MERKLE_DISTRIBUTOR_ADDRESS).claim(_index, _account, _tokens, _amounts, _merkleProof);

        _claimAmounts[0] = balanceOfToken(RETH2) - _claimAmounts[0];
        _claimAmounts[1] = balanceOfToken(SWISE) - _claimAmounts[1];

        vault.report(_rewardsTokens,_claimAmounts);
    }

    function swapRewardsToWants() internal override {
        uint256 _balanceOfSwise = balanceOfToken(swise);
        if (_balanceOfSwise > 0) {
            IERC20(SWISE).approve(UNISWAP_V3_ROUTER, 0);
            IERC20(SWISE).approve(UNISWAP_V3_ROUTER, _balanceOfSwise);
            IUniswapV3.ExactInputSingleParams memory _params = IUniswapV3.ExactInputSingleParams(SWISE, SETH2, 3000, address(this), block.timestamp, _balanceOfSwise, 0, 0);
            IUniswapV3(UNISWAP_V3_ROUTER).exactInputSingle(_params);
        }

        uint256 _balanceOfRETH2 = balanceOfToken(RETH2);
        if (_balanceOfRETH2 > 0) {
            IERC20(RETH2).approve(UNISWAP_V3_ROUTER, 0);
            IERC20(RETH2).approve(UNISWAP_V3_ROUTER, _balanceOfRETH2);
            IUniswapV3.ExactInputSingleParams memory _params = IUniswapV3.ExactInputSingleParams(RETH2, SETH2, 500, address(this), block.timestamp, _balanceOfRETH2, 0, 0);
            IUniswapV3(UNISWAP_V3_ROUTER).exactInputSingle(_params);
        }
    }
}
