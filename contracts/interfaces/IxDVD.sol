// SPDX-License-Identifier: MIT
pragma solidity >= 0.7.0 < 0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

/// xDVD token interface
interface IxDVD is IERC20Upgradeable {
    
    /**
     * @dev This function will be called from DAOmine. The msg.sender is DAOmine.
     */
    function depositByProxy(address _user, uint256 _amount) external;

    /**
     * @dev Retrieves the tier of `_addr` at the `_blockNumber`.
     */
    function tierAt(address _addr, uint256 _blockNumber) external view returns (uint8, uint256, uint256);

}