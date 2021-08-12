// SPDX-License-Identifier: MIT
pragma solidity >= 0.7.0 < 0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

/// Base interface of xDVD token
interface IxDVDBase is IERC20Upgradeable {
    
    function setDAOmine(address _daoMine) external;

    function setTierAmount(uint[] memory) external;

    function getTier(address _account) external view returns (uint8, uint256);

    /**
     * @dev Retrieves the tier of `_addr` at the `_blockNumber`.
     */
    function tierAt(address _addr, uint256 _blockNumber) external view returns (uint8, uint256, uint256);
}