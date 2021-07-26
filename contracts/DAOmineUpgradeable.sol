// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";

import "./DAOventuresTokenImplementation.sol";
import "./interfaces/IxDVD.sol";

contract DAOmineUpgradeable is OwnableUpgradeable {
    using AddressUpgradeable for address;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeERC20Upgradeable for DAOventuresTokenImplementation;
    using SafeMathUpgradeable for uint256;

    /* 
    Basically, any point in time, the amount of DVDs entitled to a user but is pending to be distributed is:
    
    pending DVD = (user.lpAmount * pool.accDVDPerLP) - user.finishedDVD
    
    Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
    1. The pool's `accDVDPerLP` (and `lastRewardBlock`) gets updated.
    2. User receives the pending DVD sent to his/her address.
    3. User's `lpAmount` gets updated.
    4. User's `finishedDVD` gets updated.
    */
    struct Pool {
        // Address of LP token
        address lpTokenAddress;
        // Weight of pool           
        uint256 poolWeight;
        // Last block number that DVDs distribution occurs for pool
        uint256 lastRewardBlock; 
        // Accumulated DVDs per LP of pool
        uint256 accDVDPerLP; 
        // Pool ID of this pool
        uint256 pid;
    }

    struct User {
        // LP token amount that user provided
        uint256 lpAmount;     
        // Finished distributed DVDs to user
        uint256 finishedDVD;
        // Last block number that rewards transferred to this user
        uint256 fnishedBlock;
        // Total amount of the received tier bonus
        uint256 receivedTierBonus;
    }
    

    /* 
    END_BLOCK = START_BLOCK + BLOCK_PER_PERIOD * PERIOD_AMOUNT 
    */
    // First block that DAOstake will start from
    uint256 public constant START_BLOCK = 0;
    // First block that DAOstake will end from
    uint256 public constant END_BLOCK = 0;
    // Amount of block per period: 6500(blocks per day) * 14(14 days/2 weeks) = 91000
    uint256 public constant BLOCK_PER_PERIOD = 91000;
    // Amount of period
    uint256 public constant PERIOD_AMOUNT = 104;

    // Treasury wallet address
    address public treasuryWalletAddr;
    // Community wallet address
    address public communityWalletAddr;

    // DVD token
    DAOventuresTokenImplementation public dvd;
    // xDVD contract
    IxDVD public xdvd;
    // Pool ID for xDVD
    uint256 public xdvdPid;

    // Percent of DVD is distributed to treasury wallet per block: 24.5%
    uint256 public constant TREASURY_WALLET_PERCENT = 2450;
    // Percent of DVD is distributed to community wallet per block: 24.5%
    uint256 public constant COMMUNITY_WALLET_PERCENT = 2450;
    // Percent of DVD is distributed to pools per block: 51%
    uint256 public constant POOL_PERCENT = 5100;

    // Total pool weight / Sum of all pool weights
    uint256 public totalPoolWeight;
    // Array of pools
    Pool[] public pool;
    // LP token => pool
    mapping (address => Pool) public poolMap;

    // pool id => user address => user info
    mapping (uint256 => mapping (address => User)) public user;

    // period id => DVD amount per block of period
    mapping (uint256 => uint256) public periodDVDPerBlock;

    // Bonus rate for the tiers. The denominator is 100. For ex. x0.75 is 75
    uint32 public constant TIER_BONUS_RATE_DENOMINATOR = 100;
    // Maximum bonus is DVD reward x 4.
    uint32 public constant TIER_BONUS_MAX_RATE = 400;
    // Tier starts from 0, tier 0 means that user doesn't have xDVD, tierBonusRate[0] should be 0.
    uint32[] public tierBonusRate;

    event SetWalletAddress(address indexed treasuryWalletAddr, address indexed communityWalletAddr);
    event SetDVD(DAOventuresTokenImplementation indexed dvd);
    event SetXDVD(IxDVD indexed xdvd);
    event SetXDVDPid(uint256 xdvdpid);
    event SetTierBonusRate(uint32[] _tierBonusRate);
    event TransferDVDOwnership(address indexed newOwner);
    event AddPool(address indexed lpTokenAddress, uint256 indexed poolWeight, uint256 indexed lastRewardBlock);
    event SetPoolWeight(uint256 indexed poolId, uint256 indexed poolWeight, uint256 totalPoolWeight);
    event UpdatePool(uint256 indexed poolId, uint256 indexed lastRewardBlock, uint256 totalDVD);
    event Deposit(address indexed account, uint256 indexed poolId, uint256 amount);
    event Yield(address indexed account, uint256 indexed poolId, uint256 dvdAmount);
    event Withdraw(address indexed account, uint256 indexed poolId, uint256 amount);
    event EmergencyWithdraw(address indexed account, uint256 indexed poolId, uint256 amount);

    /// @dev Require that the caller must be an EOA account to avoid flash loans
    modifier onlyEOA() {
        require(msg.sender == tx.origin, "Not EOA");
        _;
    }

    modifier onlyContract() {
        require(AddressUpgradeable.isContract(msg.sender), "Not a contract");
        _;
    }

    /**
     * @notice Update DVD amount per block for each period when deploying. Be careful of gas spending!
     */
    function initialize(
        address _treasuryWalletAddr,
        address _communityWalletAddr,
        DAOventuresTokenImplementation _dvd,
        IxDVD _xdvd,
        uint32[] memory _tierBonusRate
    ) public initializer {
        require(_tierBonusRate.length <= 11, "Tier range is from 0 to 10");
        for(uint i = 0; i < _tierBonusRate.length; i ++) {
            require(_tierBonusRate[i] <= TIER_BONUS_MAX_RATE, "The maximum rate is 400");
        }

        __Ownable_init();

        periodDVDPerBlock[1] = 30 ether;

        for (uint256 i = 2; i <= PERIOD_AMOUNT; i++) {
            periodDVDPerBlock[i] = periodDVDPerBlock[i.sub(1)].mul(9650).div(10000);
        }

        setWalletAddress(_treasuryWalletAddr, _communityWalletAddr);

        setDVD(_dvd);
        setXDVD(_xdvd);
        setTierBonusRate(_tierBonusRate);
    }


    /** 
     * @notice Set all params about wallet address. Can only be called by owner
     * Remember to mint and distribute pending DVDs to wallet before changing address
     *
     * @param _treasuryWalletAddr     Treasury wallet address
     * @param _communityWalletAddr    Community wallet address
     */
    function setWalletAddress(address _treasuryWalletAddr, address _communityWalletAddr) public onlyOwner {
        require((_treasuryWalletAddr != address(0)) && (_communityWalletAddr != address(0)), "Any wallet address should not be zero address");
        
        treasuryWalletAddr = _treasuryWalletAddr;
        communityWalletAddr = _communityWalletAddr;
    
        emit SetWalletAddress(treasuryWalletAddr, communityWalletAddr);
    }

    /**
     * @notice Set DVD token address. Can only be called by owner
     */
    function setDVD(DAOventuresTokenImplementation _dvd) public onlyOwner {
        require(address(_dvd) != address(0), "DVD address should not be zero address");
        dvd = _dvd;
        emit SetDVD(dvd);
    }

    /**
     * @notice Set xDVD token address. Can only be called by owner
     */
    function setXDVD(IxDVD _xdvd) public onlyOwner {
        require(address(_xdvd) != address(0), "xDVD address should not be zero address");
        if (address(xdvd) != address(0)) {
            dvd.safeApprove(address(xdvd), 0);
        }
        dvd.safeApprove(address(_xdvd), type(uint256).max);
        xdvd = _xdvd;
        emit SetXDVD(xdvd);

        Pool memory _pool = poolMap[address(_xdvd)];
        if (_pool.lpTokenAddress != address(0)) {
            xdvdPid = _pool.pid;
            emit SetXDVDPid(xdvdPid);
        }
    }

    /**
     * @notice Set bonus rate for tiers. Can only be called by owner
     */
    function setTierBonusRate(uint32[] memory _tierBonusRate) public onlyOwner {
        require(_tierBonusRate.length <= 11, "Tier range is from 0 to 10");
        for(uint i = 0; i < _tierBonusRate.length; i ++) {
            require(_tierBonusRate[i] <= TIER_BONUS_MAX_RATE, "The maximum rate is 400");
        }

        tierBonusRate = _tierBonusRate;
        emit SetTierBonusRate(tierBonusRate);
    }

    /**
     * @notice Transfer ownership of DVD token. Can only be called by this smart contract owner
     *
     */
    function transferDVDOwnership(address _newOwner) public onlyOwner {
        dvd.transferOwnership(_newOwner);
        emit TransferDVDOwnership(_newOwner);
    }

    /** 
     * @notice Get the length/amount of pool
     */
    function poolLength() external view returns(uint256) {
        return pool.length;
    } 

    /** 
     * @notice Return reward multiplier over given _from to _to block. [_from, _to)
     * 
     * @param _from    From block number (included)
     * @param _to      To block number (exluded)
     */
    function getMultiplier(uint256 _from, uint256 _to) public view returns(uint256 multiplier) {
        if (_from < START_BLOCK) {_from = START_BLOCK;}
        if (_to > END_BLOCK) {_to = END_BLOCK;}

        uint256 periodOfFrom = _from.sub(START_BLOCK).div(BLOCK_PER_PERIOD).add(1);
        uint256 periodOfTo = _to.sub(START_BLOCK).div(BLOCK_PER_PERIOD).add(1);
        
        if (periodOfFrom == periodOfTo) {
            multiplier = _to.sub(_from).mul(periodDVDPerBlock[periodOfTo]);
        } else {
            uint256 multiplierOfFrom = BLOCK_PER_PERIOD.mul(periodOfFrom).add(START_BLOCK).sub(_from).mul(periodDVDPerBlock[periodOfFrom]);
            uint256 multiplierOfTo = _to.sub(START_BLOCK).mod(BLOCK_PER_PERIOD).mul(periodDVDPerBlock[periodOfTo]);
            multiplier = multiplierOfFrom.add(multiplierOfTo);
            for (uint256 periodId = periodOfFrom.add(1); periodId < periodOfTo; periodId++) {
                multiplier = multiplier.add(BLOCK_PER_PERIOD.mul(periodDVDPerBlock[periodId]));
            }
        }
    }

    /** 
     * @notice Get pending DVD amount of user in pool
     */
    function pendingDVD(uint256 _pid, address _account) public view returns(uint256) {
        Pool storage pool_ = pool[_pid];
        User storage user_ = user[_pid][_account];
        uint256 accDVDPerLP = pool_.accDVDPerLP;
        uint256 lpSupply = IERC20Upgradeable(pool_.lpTokenAddress).balanceOf(address(this));

        if (block.number > pool_.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool_.lastRewardBlock, block.number);
            uint256 dvgForPool = multiplier.mul(POOL_PERCENT).mul(pool_.poolWeight).div(totalPoolWeight).div(10000);
            accDVDPerLP = accDVDPerLP.add(dvgForPool.mul(1 ether).div(lpSupply));
        }

        return user_.lpAmount.mul(accDVDPerLP).div(1 ether).sub(user_.finishedDVD);
    }

    /** 
     * @notice Get pending tier bonus amount of user in pool
     */
    function pendingTierBonus(uint256 _pid, address _account) public view returns(uint256) {
        User storage user_ = user[_pid][_account];
        if (user_.lpAmount == 0) return 0;

        uint256 pendingDVD_ = pendingDVD(_pid, _account);
        if (pendingDVD_ == 0) return 0;

        return _pendingTierBonus(_account, user_.fnishedBlock, block.number, pendingDVD_);
    }

    /**
     * @notice Return tier bonus over given _from to _to block. [_from, _to)
     *
     * @param _from         From block number (included)
     * @param _to           To block number (exluded)
     * @param _pendingDVD   The pending reward of _account  from _from block to _to block
     */
    function _pendingTierBonus(address _account, uint256 _from, uint256 _to, uint256 _pendingDVD) internal view returns(uint256) {
        if (_from < START_BLOCK) {_from = START_BLOCK;}
        if (_to > END_BLOCK) {_to = END_BLOCK;}
        if (_from >= _to) return 0;

        uint256 pendingBonus_;
        uint256 pendingBlocks_ = _to.sub(_from);

        while(_from < _to) {
            (uint8 tier_, , uint256 endBlock_) = xdvd.tierAt(_account, _from);

            if (tier_ < tierBonusRate.length) {
                uint256 bonusRate_ = tierBonusRate[tier_];
                if (0 < bonusRate_) {
                    // blocks_t include endBlock_ block.
                    uint256 blocks_ = (endBlock_ < END_BLOCK) ? endBlock_.add(1).sub(_from) : END_BLOCK.sub(_from);
                    // It uses the average pending DVD per block to reduce operation.
                    uint256 bonus_ = _pendingDVD.mul(blocks_).div(pendingBlocks_);
                    pendingBonus_ = pendingBonus_.add(bonus_.mul(bonusRate_).div(TIER_BONUS_RATE_DENOMINATOR));
                }
            }
            _from = endBlock_.add(1);
        }
        return pendingBonus_;
    }

    /** 
     * @notice Add a new LP to pool. Can only be called by owner
     * DO NOT add the same LP token more than once. DVD rewards will be messed up if you do
     */
    function addPool(address _lpTokenAddress, uint256 _poolWeight, bool _withUpdate) public onlyOwner {
        require(block.number < END_BLOCK, "Already ended");
        require(_lpTokenAddress.isContract(), "LP token address should be smart contract address");
        require(poolMap[_lpTokenAddress].lpTokenAddress == address(0), "LP token already added");

        if (_withUpdate) {
            massUpdatePools();
        }
        
        uint256 lastRewardBlock = block.number > START_BLOCK ? block.number : START_BLOCK;
        totalPoolWeight = totalPoolWeight + _poolWeight;

        Pool memory newPool_ = Pool({
            lpTokenAddress: _lpTokenAddress,
            poolWeight: _poolWeight,
            lastRewardBlock: lastRewardBlock,
            accDVDPerLP: 0,
            pid: pool.length
        });

        pool.push(newPool_);
        poolMap[_lpTokenAddress] = newPool_;

        emit AddPool(_lpTokenAddress, _poolWeight, lastRewardBlock);

        if (address(xdvd) == _lpTokenAddress) {
            xdvdPid = newPool_.pid;
            emit SetXDVDPid(xdvdPid);
        }
    }

    /** 
     * @notice Update the given pool's weight. Can only be called by owner.
     */
    function setPoolWeight(uint256 _pid, uint256 _poolWeight, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }

        totalPoolWeight = totalPoolWeight.sub(pool[_pid].poolWeight).add(_poolWeight);
        pool[_pid].poolWeight = _poolWeight;

        emit SetPoolWeight(_pid, _poolWeight, totalPoolWeight);
    }

    /** 
     * @notice Update reward variables of the given pool to be up-to-date.
     */
    function updatePool(uint256 _pid) public {
        Pool storage pool_ = pool[_pid];

        if (block.number <= pool_.lastRewardBlock) {
            return;
        }

        uint256 totalDVD = getMultiplier(pool_.lastRewardBlock, block.number).mul(pool_.poolWeight).div(totalPoolWeight);

        uint256 lpSupply = IERC20Upgradeable(pool_.lpTokenAddress).balanceOf(address(this));
        if (lpSupply > 0) {
            uint256 dvgForPool = totalDVD.mul(POOL_PERCENT).div(10000);

            dvd.mint(treasuryWalletAddr, totalDVD.mul(TREASURY_WALLET_PERCENT).div(10000)); 
            dvd.mint(communityWalletAddr, totalDVD.mul(COMMUNITY_WALLET_PERCENT).div(10000));
            dvd.mint(address(this), dvgForPool);

            pool_.accDVDPerLP = pool_.accDVDPerLP.add(dvgForPool.mul(1 ether).div(lpSupply));
        } else {
            dvd.mint(treasuryWalletAddr, totalDVD.mul(TREASURY_WALLET_PERCENT).div(10000)); 
            dvd.mint(communityWalletAddr, totalDVD.mul(COMMUNITY_WALLET_PERCENT.add(POOL_PERCENT)).div(10000));
        }

        pool_.lastRewardBlock = block.number;

        emit UpdatePool(_pid, pool_.lastRewardBlock, totalDVD);
    }

    /** 
     * @notice Update reward variables for all pools. Be careful of gas spending!
     * Due to gas limit, please make sure here no significant amount of pools!
     */
    function massUpdatePools() public {
        uint256 length = pool.length;
        for (uint256 pid = 0; pid < length; pid++) {
            updatePool(pid);
        }
    }

    /** 
     * @notice Deposit LP tokens for DVD rewards
     * Before depositing, user needs approve this contract to be able to spend or transfer their LP tokens
     *
     * @param _pid       Id of the pool to be deposited to
     * @param _amount    Amount of LP tokens to be deposited
     */
    function deposit(uint256 _pid, uint256 _amount) external onlyEOA {
        _deposit(msg.sender, msg.sender, _pid, _amount);
    }

    function depositByProxy(address _account, uint256 _pid, uint256 _amount) external onlyContract {
        require(_account != address(0), "Invalid account address");
        _deposit(msg.sender, _account, _pid, _amount);
    }

    function _deposit(address _proxy, address _account, uint256 _pid, uint256 _amount) internal {
        Pool storage pool_ = pool[_pid];
        User storage user_ = user[_pid][_account];

        updatePool(_pid);

        uint256 pendingDVD_;
        if (user_.lpAmount > 0) {
            pendingDVD_ = user_.lpAmount.mul(pool_.accDVDPerLP).div(1 ether).sub(user_.finishedDVD);
            if(pendingDVD_ > 0 && _proxy == _account) {
                // Due to the security issue, we will transfer DVD rewards in only case of users directly deposit.
                uint256 bonus_ = _pendingTierBonus(_account, user_.fnishedBlock, pool_.lastRewardBlock, pendingDVD_);
                _safeDVDTransfer(_account, pendingDVD_.add(bonus_));
                user_.fnishedBlock = pool_.lastRewardBlock;
                user_.receivedTierBonus = user_.receivedTierBonus.add(bonus_);
                pendingDVD_ = 0;
            }
        } else {
            user_.fnishedBlock = block.number;
        }

        if(_amount > 0) {
            if (address(_proxy) != address(this)) {
                IERC20Upgradeable(pool_.lpTokenAddress).safeTransferFrom(address(_proxy), address(this), _amount);
            }
            user_.lpAmount = user_.lpAmount.add(_amount);
        }

        user_.finishedDVD = user_.lpAmount.mul(pool_.accDVDPerLP).div(1 ether).sub(pendingDVD_);

        emit Deposit(_account, _pid, _amount);
    }

    /** 
     * @notice Withdraw LP tokens
     *
     * @param _pid       Id of the pool to be withdrawn from
     * @param _amount    amount of LP tokens to be withdrawn
     */
    function withdraw(uint256 _pid, uint256 _amount) public {
        Pool storage pool_ = pool[_pid];
        User storage user_ = user[_pid][msg.sender];

        require(user_.lpAmount >= _amount, "Not enough LP token balance");

        updatePool(_pid);

        uint256 pendingDVD_ = user_.lpAmount.mul(pool_.accDVDPerLP).div(1 ether).sub(user_.finishedDVD);

        if(pendingDVD_ > 0) {
            uint256 bonus_ = _pendingTierBonus(msg.sender, user_.fnishedBlock, pool_.lastRewardBlock, pendingDVD_);
            _safeDVDTransfer(msg.sender, pendingDVD_.add(bonus_));
            user_.fnishedBlock = pool_.lastRewardBlock;
            user_.receivedTierBonus = user_.receivedTierBonus.add(bonus_);
        }

        if(_amount > 0) {
            user_.lpAmount = user_.lpAmount.sub(_amount);
            IERC20Upgradeable(pool_.lpTokenAddress).safeTransfer(address(msg.sender), _amount);
        }

        user_.finishedDVD = user_.lpAmount.mul(pool_.accDVDPerLP).div(1 ether);

        emit Withdraw(msg.sender, _pid, _amount);
    }

    /** 
     * @notice Withdraw LP tokens without caring about DVD rewards. EMERGENCY ONLY
     *
     * @param _pid    Id of the pool to be emergency withdrawn from
     */
    function emergencyWithdraw(uint256 _pid) public {
        Pool storage pool_ = pool[_pid];
        User storage user_ = user[_pid][msg.sender];

        uint256 amount = user_.lpAmount;

        user_.lpAmount = 0;
        user_.finishedDVD = 0;

        IERC20Upgradeable(pool_.lpTokenAddress).safeTransfer(address(msg.sender), amount);

        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }
     
    /** 
     * @notice Safe DVD transfer function, just in case if rounding error causes pool to not have enough DVDs
     *
     * @param _to        Address to get transferred DVDs
     * @param _amount    Amount of DVD to be transferred
     */
    function _safeDVDTransfer(address _to, uint256 _amount) internal {
        uint256 dvgBal = dvd.balanceOf(address(this));
        
        if (_amount > dvgBal) {
            dvd.transfer(_to, dvgBal);
        } else {
            dvd.transfer(_to, _amount);
        }
    }

    /**
     * @notice Take DVD rewards and redeposit it into xDVD pool.
     *
     * @param _pid       Id of the pool to be deposited to
     */
    function yield(uint256 _pid) external onlyEOA {
        address account_ = msg.sender;
        Pool storage pool_ = pool[_pid];
        User storage user_ = user[_pid][account_];
        require(0 < user_.lpAmount, "User should deposit on the pool before yielding");

        updatePool(_pid);

        uint256 pendingDVD_ = user_.lpAmount.mul(pool_.accDVDPerLP).div(1 ether).sub(user_.finishedDVD);
        require(0 < pendingDVD_, "User should have the pending DVD rewards");

        uint256 bonus_ = _pendingTierBonus(account_, user_.fnishedBlock, pool_.lastRewardBlock, pendingDVD_);
        user_.fnishedBlock = pool_.lastRewardBlock;
        user_.receivedTierBonus = user_.receivedTierBonus.add(bonus_);
        user_.finishedDVD = user_.finishedDVD.add(pendingDVD_);

        uint256 dvdAmount_ = pendingDVD_.add(bonus_);
        uint256 xdvdBalance_ = xdvd.balanceOf(address(this));
        xdvd.depositByProxy(account_, dvdAmount_);
        uint256 xdvdAmount_ = xdvd.balanceOf(address(this)).sub(xdvdBalance_);

        _deposit(address(this), account_, xdvdPid, xdvdAmount_);

        emit Yield(account_, _pid, dvdAmount_);
    }

    uint256[39] private __gap;
}