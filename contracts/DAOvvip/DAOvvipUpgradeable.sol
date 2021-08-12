// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/math/MathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";

import "../interfaces/IDAOmine.sol";
import "../interfaces/IDAOvvip.sol";

// This contract handles swapping to and from DAOvvip, DAOventures's vvip token
contract DAOvvipUpgradeable is OwnableUpgradeable, ERC20Upgradeable {
    using SafeMathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    struct User {
        uint256 amountDeposited; // The DVD amount deposited
    }

    struct TierSnapshots {
        uint256[] blockNumbers;
        uint8[] tiers;
    }

    // DVD token
    IERC20Upgradeable public dvd;
    // DAOmine contract address
    IDAOmine public daoMine;
    // ID of DAOvvip pool in DAOmine
    uint256 public poolId;

    mapping(address => User) private user;

    uint256[] public tierAmounts;
    mapping (address => TierSnapshots) private _accountTierSnapshots;


    event Deposit(address indexed user, uint256 DVDAmount, uint256 DAOvvipAmount);
    event Withdraw(address indexed user, uint256 DVDAmount, uint256 DAOvvipAmount, uint256 DVDRewards);
    event Yield(address indexed user, uint256 DVDAmount, uint256 DAOvvipAmount);
    event TierAmount(uint256[] newTierAmounts);
    event SetDAOmine(address indexed daoMaine);
    event Tier(address indexed user, uint8 prevTier, uint8 newTier);

    /// @dev Require that the caller must be an EOA account to avoid flash loans
    modifier onlyEOA() {
        require(msg.sender == tx.origin, "Not EOA");
        _;
    }

    modifier onlyContract() {
        require(AddressUpgradeable.isContract(msg.sender), "Not a contract");
        _;
    }

    //Define the DVD token contract
    function initialize(address _dvd, uint[] memory _tierAmounts) external initializer {
        require(_tierAmounts.length < 10, "Tier range is from 0 to 10");
        __ERC20_init("VVIP DVD", "DAOvvip");
        dvd = IERC20Upgradeable(_dvd);
        tierAmounts = _tierAmounts;
    }

    /**
     * @dev Pay some DVDs. Earn some shares. Locks DVD and mints DAOvvip.
     */
    function deposit(uint256 _amount) external onlyEOA {
        address account = msg.sender;

        // Lock the DVD in the contract
        dvd.safeTransferFrom(account, address(this), _amount);
        uint256 what = _deposit(account, _amount);
        emit Deposit(account, _amount, what);
    }

    function _deposit(address _account, uint256 _amount) internal returns(uint256) {
        user[_account].amountDeposited = user[_account].amountDeposited.add(_amount);
        _updateSnapshot(_account, user[_account].amountDeposited);

        // Gets the amount of DVD locked in the contract
        uint256 totalDVD = dvd.balanceOf(address(this));
        // Gets the amount of DAOvvip in existence
        uint256 totalShares = totalSupply();
        uint256 what;
        if (totalShares == 0) {
            // If no DAOvvip exists, mint it 1:1 to the amount put in
            what = _amount;
        } else {
            // Calculate and mint the amount of DAOvvip the DVD is worth. The ratio will change overtime
            what = _amount.mul(totalShares).div(totalDVD);
        }
        _mint(address(this), what);

        daoMine.depositByProxy(_account, poolId, what);
        return what;
    }

    // Claim back your DVDs. Unclocks the staked + gained DVD and burns DAOvvip
    function withdraw(uint256 _share) external onlyEOA {
        address account = msg.sender;

        uint256 dvdBalance = dvd.balanceOf(address(this));
        // Gets the amount of DAOvvip in existence
        uint256 totalShares = totalSupply();
        // Calculates the amount of DVD the DAOvvip is worth
        uint256 what = _share.mul(dvdBalance).div(totalShares);

        (uint256 leftShare, ,) = daoMine.withdrawByProxy(account, poolId, _share);
        uint256 dvdRewards = dvd.balanceOf(address(this)).sub(dvdBalance);

        user[msg.sender].amountDeposited = user[msg.sender].amountDeposited.mul(leftShare).div(leftShare.add(_share));
        _updateSnapshot(msg.sender, user[msg.sender].amountDeposited);

        _burn(address(this), _share);
        dvd.safeTransfer(msg.sender, what.add(dvdRewards));

        emit Withdraw(msg.sender, what, _share, dvdRewards);
    }

    /**
     * @notice Take DVD rewards and redeposit it into xDVD pool.
     */
    function yield() external onlyEOA {
        address account = msg.sender;

        uint256 dvdBalance = dvd.balanceOf(address(this));
        daoMine.harvestByProxy(account, poolId);
        uint256 dvdRewards = dvd.balanceOf(address(this)).sub(dvdBalance);

        uint256 what = _deposit(account, dvdRewards);
        emit Yield(account, dvdRewards, what);
    }

    function setTierAmount(uint[] memory _tierAmounts) external onlyOwner {
        require(_tierAmounts.length < 10, "Tier range is from 0 to 10");
        tierAmounts = _tierAmounts; 
        emit TierAmount(tierAmounts);
    }

    function setDAOmine(address _daoMine) external onlyOwner {
        require(address(_daoMine) != address(0), "Invalid address");
        require(address(daoMine) == address(0), "DAOmine is already set");

        daoMine = IDAOmine(_daoMine);
        require(address(this) == daoMine.daoVvip(), "DAOvvip should be set in DAOmine");
        poolId = daoMine.daoVvipPid();

        _approve(address(this), _daoMine, type(uint256).max);
        emit SetDAOmine(address(daoMine));
    }

    function _calculateTier(uint256 _depositedAmount) internal view returns (uint8) {
        if (_depositedAmount == 0) {
            // No tier bonus
            return 0;
        }
        for (uint8 i = 0; i < tierAmounts.length ; i ++) {
            if (_depositedAmount <= tierAmounts[i]) {
                return (i + 1);
            }
        }
        return uint8(tierAmounts.length) + 1;
    }

    function getTier(address _account) external view returns (uint8 _tier, uint256 _depositedAmount) {
        _depositedAmount = user[_account].amountDeposited;
        _tier = _calculateTier(_depositedAmount);
    }

    /**
     * @dev Retrieves the tier of `_account` at the `_blockNumber`.
     */
    function tierAt(address _account, uint256 _blockNumber) external view returns (uint8, uint256, uint256) {
        TierSnapshots storage snapshots = _accountTierSnapshots[_account];
        (bool snapshotted, uint8 tier, uint256 startBlock, uint256 endBlock) = _tierAt(_blockNumber, snapshots);
        if (snapshotted == false) {
            if (snapshots.blockNumbers.length == 0) {
                tier = _calculateTier(user[_account].amountDeposited);
                startBlock = 0;
                endBlock = block.number;
            } else {
                tier = 0;
                startBlock = 0;
                endBlock = snapshots.blockNumbers[0].sub(1);
            }
        }
        return (tier, startBlock, endBlock);
    }

    function _tierAt(uint256 blockNumber, TierSnapshots storage snapshots) internal view returns (bool, uint8, uint256, uint256) {
        uint8 tier;
        uint256 startBlock;
        uint256 endBlock;

        (bool found, uint256 index) = _findLowerBound(snapshots.blockNumbers, blockNumber);
        if (found == true) {
            tier = snapshots.tiers[index];
            startBlock = snapshots.blockNumbers[index];
            endBlock = (index < (snapshots.blockNumbers.length - 1)) ? (snapshots.blockNumbers[index + 1] - 1) : block.number;
        }
        return (found, tier, startBlock, endBlock);
    }

    function _updateSnapshot(address _account, uint256 _depositedAmount) private {
        TierSnapshots storage snapshots = _accountTierSnapshots[_account];
        uint8 prevTier = _lastSnapshotTier(snapshots.tiers);
        uint8 tier = _calculateTier(_depositedAmount);
        if (prevTier != tier) {
            snapshots.blockNumbers.push(block.number);
            snapshots.tiers.push(tier);
            emit Tier(_account, prevTier, tier);
        }
    }

    function _lastSnapshotTier(uint8[] storage _tiers) private view returns (uint8) {
        if (_tiers.length == 0) {
            return 0;
        } else {
            return _tiers[_tiers.length - 1];
        }
    }

   /**
     * @dev Searches a sorted `array` and returns the first index that contains
     * a value less or equal to `element`.
     *
     * `array` is expected to be sorted in ascending order, and to contain no
     * repeated elements.
     */
    function _findLowerBound(uint256[] storage array, uint256 element) internal view returns (bool, uint256) {
        if (array.length == 0) {
            // Nothing in the array
            return (false, 0);
        }
        if (element < array[0]) {
            // Out of array range
            return (false, 0);
        }

        uint256 low = 0;
        uint256 high = array.length;
        uint256 mid;

        // The looping is limited as 256. In fact, this looping will be early broken because the maximum slot count is 2^256
        for (uint16 i = 0; i < 256; i ++) {
            mid = MathUpgradeable.average(low, high);

            // Note that mid will always be strictly less than high (i.e. it will be a valid array index)
            // because Math.average rounds down (it does integer division with truncation).
            if (element < array[mid]) {
                high = mid;
            } else if (element == array[mid] || low == mid) {
                // Found the correct element
                // Or the array[low] is the less and the nearest value to the element
                break;
            } else {
                low = mid;
            }
        }
        return (true, mid);
    }

    uint256[44] private __gap;
}
