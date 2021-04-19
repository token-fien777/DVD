// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.7.6;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IDVGToken.sol";

interface IERC20_E {
    function decimals() external view returns (uint8);
}

contract AnyDVGWrapper {
    using SafeERC20 for IERC20;
    string public constant name = "Anyswap-DVG-Wrapper";
    string public constant symbol = "AnyDVGWrapper";
    uint8  public immutable decimals;

    address public immutable underlying;

    // init flag for setting immediate vault, needed for CREATE2 support
    bool private _init;

    // flag to enable/disable swapout vs vault.burn so multiple events are triggered
    bool private _vaultOnly;

    // configurable delay for timelock functions
    uint public delay = 2*24*3600;

    // set of minters, can be this bridge or other bridges
    mapping(address => bool) public isMinter;
    address[] public minters;

    // primary controller of the token contract
    address public vault;

    address public pendingMinter;
    uint public delayMinter;

    address public pendingVault;
    uint public delayVault;

    uint public pendingDelay;
    uint public delayDelay;


    modifier onlyAuth() {
        require(isMinter[msg.sender], "AnyswapV4ERC20: FORBIDDEN");
        _;
    }

    modifier onlyVault() {
        require(msg.sender == mpc(), "AnyswapV3ERC20: FORBIDDEN");
        _;
    }

    function owner() public view returns (address) {
        return mpc();
    }

    function mpc() public view returns (address) {
        if (block.timestamp >= delayVault) {
            return pendingVault;
        }
        return vault;
    }

    function setVaultOnly(bool enabled) external onlyVault {
        _vaultOnly = enabled;
    }

    function initVault(address _vault) external onlyVault {
        require(_init);
        vault = _vault;
        pendingVault = _vault;
        isMinter[_vault] = true;
        minters.push(_vault);
        delayVault = block.timestamp;
        _init = false;
    }

    function setMinter(address _auth) external onlyVault {
        pendingMinter = _auth;
        delayMinter = block.timestamp + delay;
    }

    function setVault(address _vault) external onlyVault {
        pendingVault = _vault;
        delayVault = block.timestamp + delay;
    }

    function applyVault() external onlyVault {
        require(block.timestamp >= delayVault);
        vault = pendingVault;
    }

    function applyMinter() external onlyVault {
        require(block.timestamp >= delayMinter);
        isMinter[pendingMinter] = true;
        minters.push(pendingMinter);
    }

    // No time delay revoke minter emergency function
    function revokeMinter(address _auth) external onlyVault {
        isMinter[_auth] = false;
    }

    function getAllMinters() external view returns (address[] memory) {
        return minters;
    }


    function changeVault(address newVault) external onlyVault returns (bool) {
        require(newVault != address(0), "AnyswapV3ERC20: address(0x0)");
        pendingVault = newVault;
        delayVault = block.timestamp + delay;
        emit LogChangeVault(vault, pendingVault, delayVault);
        return true;
    }

    function changeMPCOwner(address newVault) public onlyVault returns (bool) {
        require(newVault != address(0), "AnyswapV3ERC20: address(0x0)");
        pendingVault = newVault;
        delayVault = block.timestamp + delay;
        emit LogChangeMPCOwner(vault, pendingVault, delayVault);
        return true;
    }

    function mint(address to, uint256 amount) external onlyAuth returns (bool) {
        IDVGToken(underlying).mint(to, amount);
        return true;
    }

    function burn(address from, uint256 amount) external onlyAuth returns (bool) {
        IDVGToken(underlying).burn(from, amount);
        return true;
    }

    function Swapin(bytes32 txhash, address account, uint256 amount) external onlyAuth returns (bool) {
        IDVGToken(underlying).mint(account, amount);
        emit LogSwapin(txhash, account, amount);
        return true;
    }

    function Swapout(uint256 amount, address bindaddr) external returns (bool) {
        require(!_vaultOnly, "AnyswapV4ERC20: onlyAuth");
        require(bindaddr != address(0), "AnyswapV3ERC20: address(0x0)");
        IDVGToken(underlying).burn(msg.sender, amount);
        emit LogSwapout(msg.sender, bindaddr, amount);
        return true;
    }

    function balanceOf(address account) external view returns (uint256) {
        return IERC20(underlying).balanceOf(account);
    }

    event LogChangeVault(address indexed oldVault, address indexed newVault, uint indexed effectiveTime);
    event LogChangeMPCOwner(address indexed oldOwner, address indexed newOwner, uint indexed effectiveHeight);
    event LogSwapin(bytes32 indexed txhash, address indexed account, uint amount);
    event LogSwapout(address indexed account, address indexed bindaddr, uint amount);
    event LogAddAuth(address indexed auth, uint timestamp);

    constructor(address _underlying, address _vault) {
        require(_underlying != address(0x0), "Invalid DVG token address");
        underlying = _underlying;
        decimals = IERC20_E(_underlying).decimals();

        // Use init to allow for CREATE2 accross all chains
        _init = true;

        // Disable/Enable swapout for v1 tokens vs mint/burn for v3 tokens
        _vaultOnly = false;

        vault = _vault;
        pendingVault = _vault;
        delayVault = block.timestamp;
    }
}
