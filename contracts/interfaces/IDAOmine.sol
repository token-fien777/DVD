// SPDX-License-Identifier: MIT
pragma solidity >= 0.7.0 < 0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

/// DAOmine token interface
interface IDAOmine {
    
    /**
     * @dev This function will be called from contracts.
     */
    function depositByProxy(address _account, uint256 _pid, uint256 _amount) external;

    /**
     * @dev This function will be called from contracts.
     */
    function withdrawByProxy(address _account, uint256 _pid, uint256 _amount) external returns (uint256);

    /**
     * @dev Returns the pid of xDVD pool in DAOmine.
     */
    function xdvdPid() external view returns(uint256);

    /**
     * @dev Returns the DAOvvip address.
     */
    function daoVvip() external view returns(address);

    /**
     * @dev Returns the pid of DAOvvip pool in DAOmine.
     */
    function daoVvipPid() external view returns(uint256);
}