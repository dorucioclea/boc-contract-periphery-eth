// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

import "./ETHBaseStrategy.sol";

abstract contract ETHBaseClaimableStrategy is ETHBaseStrategy {
    /// @notice Collect the rewards from 3rd protocol
    function claimRewards()
        internal
        virtual
        returns (
            bool claimIsWorth,
            address[] memory _rewardsTokens,
            uint256[] memory _claimAmounts
        );

    function swapRewardsToWants() internal virtual;

    /// @notice Harvests the Strategy, recognizing any profits or losses and adjusting the Strategy's position.
    function harvest() public virtual override returns (address[] memory _rewardsTokens, uint256[] memory _claimAmounts){
        // sell reward token
        (bool claimIsWorth, address[] memory __rewardsTokens,uint256[] memory __claimAmounts ) = claimRewards();
        _rewardsTokens = __rewardsTokens;
        _claimAmounts = __claimAmounts;
        console.log("claimIsWorth:", claimIsWorth);
        if (claimIsWorth) {
            swapRewardsToWants();
            reInvest();
        }

        vault.report(_rewardsTokens,_claimAmounts);
    }

    function reInvest() internal {
        address[] memory wantsCopy = wants;
        address[] memory _assets = new address[](wantsCopy.length);
        uint256[] memory _amounts = new uint256[](wantsCopy.length);
        uint256 totalBalance = 0;
        for (uint8 i = 0; i < wantsCopy.length; i++) {
            address want = wantsCopy[i];
            uint256 tokenBalance = balanceOfToken(want);
            _assets[i] = want;
            _amounts[i] = tokenBalance;
            totalBalance += tokenBalance;
        }
        if (totalBalance > 0) {
            depositTo3rdPool(_assets, _amounts);
        }
    }

    /// @notice Strategy repay the funds to vault
    /// @param _repayShares Numerator
    /// @param _totalShares Denominator
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
}
