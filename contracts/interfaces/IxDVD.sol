// SPDX-License-Identifier: MIT
pragma solidity >= 0.7.0 < 0.8.0;

import "./IxDVDBase.sol";

/// xDVD token interface
interface IxDVD is IxDVDBase {
    
    /**
     * @dev Pay some DVDs. Earn some shares. Locks DVD and mints xDVD.
     *
     * @param _autoStake     Stake xDVD to the DAOmine if _autoStake is true
     */
    function deposit(uint256 _amount, bool _autoStake) external;

    /**
     * @dev This function will be called from DAOmine. The msg.sender is DAOmine.
     */
    function depositByProxy(address _user, uint256 _amount) external;

    // Claim back your DVDs. Unclocks the staked + gained DVD and burns xDVD
    function withdraw(uint256 _share) external;
}