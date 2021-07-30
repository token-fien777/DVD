// SPDX-License-Identifier: MIT
pragma solidity >= 0.7.0 < 0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

/// xDVD token interface
interface IxDVD is IERC20Upgradeable {
    
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

    function setDAOmine(address _daoMine) external;

    function setTierAmount(uint[] memory) external;

    function getTier(address _account) external view returns (uint8, uint256);

    /**
     * @dev Retrieves the tier of `_addr` at the `_blockNumber`.
     */
    function tierAt(address _addr, uint256 _blockNumber) external view returns (uint8, uint256, uint256);

}