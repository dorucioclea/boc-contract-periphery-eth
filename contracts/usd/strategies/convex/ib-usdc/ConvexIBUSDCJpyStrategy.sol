// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "./ConvexIBUSDCBaseStrategy.sol";

contract ConvexIBUSDCJpyStrategy is ConvexIBUSDCBaseStrategy {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    function initialize(address _vault, address _harvester) public initializer {
        super._initialize(
            _vault,
            _harvester
        );
    }

    function getVersion() external pure override returns (string memory) {
        return "1.0.0";
    }

    function name() public pure override returns (string memory) {
        return "ConvexIBUSDCJpyStrategy";
    }

    function getCollateralCToken() public pure override returns(CTokenInterface){
        return CTokenInterface(0x76Eb2FE28b36B3ee97F3Adae0C69606eeDB2A37c);
    }
    function getCollateralToken() public pure override returns(address){
        return 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    }
    function getBorrowCToken() public pure override returns(CTokenInterface){
        return CTokenInterface(0x215F34af6557A6598DbdA9aa11cc556F5AE264B1);
    }
    function getCurvePool() public pure override returns(address){
        return 0xEB0265938c1190Ab4E3E1f6583bC956dF47C0F93;
    }
    function getRewardPool() public pure override returns(address){
        return 0x58563C872c791196d0eA17c4E53e77fa1d381D4c;
    }
    function getPId() public pure override returns(uint256){
        return 88;
    }
}
