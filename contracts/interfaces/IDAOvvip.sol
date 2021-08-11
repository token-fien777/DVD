// SPDX-License-Identifier: MIT
pragma solidity >= 0.7.0 < 0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

/// DAOvvip token interface
interface IDAOvvip is IERC20Upgradeable {
    
    function getTier(address _account) external view returns (uint8, uint256);

    /**
     * @dev Retrieves the tier of `_addr` at the `_blockNumber`.
     */
    function tierAt(address _addr, uint256 _blockNumber) external view returns (uint8, uint256, uint256);

}