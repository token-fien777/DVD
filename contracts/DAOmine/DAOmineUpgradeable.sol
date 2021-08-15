// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";

import "../DAOventuresTokenImplementation.sol";
import "../interfaces/IDAOmine.sol";
import "../interfaces/IxDVDBase.sol";
import "../interfaces/IxDVD.sol";
import "../interfaces/IDAOvvip.sol";

contract DAOmineUpgradeable is OwnableUpgradeable {
    using AddressUpgradeable for address;
    using SafeERC20Upgradeable for IERC20Upgradeable;
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
        uint256 finishedBlock;
        // Total amount of the received bonuses
        uint256 receivedBonus;
        // Timestamp of the last deposit or yield
        uint256 lastDepositTime;
        // Timestamp of the last withdrawal
        uint256 lastWithdrawalTime;
    }

    /* 
    END_BLOCK = START_BLOCK + BLOCK_PER_PERIOD * PERIOD_AMOUNT 
    */
    // First block that DAOstake will start from
    uint256 public START_BLOCK = 0;
    // First block that DAOstake will end from
    uint256 public END_BLOCK = 0;
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

    // Early withdrawal period in second
    uint256 public earlyWithdrawalPenaltyPeriod;
    // Percent of early withdrawal penalty. For example, 30 if the penalty is 30% rewards.
    uint256 public earlyWithdrawalPenaltyPercent;

    //
    // v2 variables
    //
    // DAOvvip contract
    IDAOvvip public daoVvip;
    // Pool ID for DAOvvip
    uint256 public daoVvipPid;
    // Locked period in days for DAOvvip
    uint32[] public lockDays;
    // Bonus rate per locked period for DAOvvip
    uint32[] public lockBonusRate;
    // Early harvest period in second
    uint256 public earlyHarvestPenaltyPeriod;
    // Percent of early harvest penalty. For example, 30 if the penalty is 30% rewards.
    uint256 public earlyHarvestPenaltyPercent;

    event SetWalletAddress(address indexed treasuryWalletAddr, address indexed communityWalletAddr);
    event SetDVD(DAOventuresTokenImplementation indexed dvd);
    event SetXDVD(IxDVD indexed xdvd, uint256 xdvdPid);
    event SetDAOvvip(IDAOvvip indexed daoVvip, uint256 daoVvipPid);
    event SetTierBonusRate(uint32[] _tierBonusRate);
    event SetEarlyWithdrawalPenalty(uint256 _period, uint256 _percent);
    event SetBonusForLockedCapital(uint32[] newLockDay, uint32[] newLockBonusRate);
    event SetEarlyHarvestPenalty(uint256 _period, uint256 _percent);
    event TransferDVDOwnership(address indexed newOwner);
    event AddPool(address indexed lpTokenAddress, uint256 indexed poolWeight, uint256 indexed lastRewardBlock);
    event SetPoolWeight(uint256 indexed poolId, uint256 indexed poolWeight, uint256 totalPoolWeight);
    event UpdatePool(uint256 indexed poolId, uint256 indexed lastRewardBlock, uint256 totalDVD);
    event Deposit(address indexed account, uint256 indexed poolId, uint256 amount);
    event Reward(address indexed account, uint256 indexed poolId, uint256 lpAmount, uint256 reward, uint256 bonus);
    event Yield(address indexed account, uint256 indexed poolId, uint256 lpAmount, uint256 reward, uint256 bonus);
    event Harvest(address indexed account, uint256 indexed poolId, uint256 lpAmount, uint256 reward, uint256 bonus);
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
        address _xdvd,
        uint256 _xdvdPoolWeight,
        uint32[] memory _tierBonusRate,
        uint256 _earlyWithdrawalPenaltyPeriod,
        uint256 _earlyWithdrawalPenaltyPercent,
        uint256 _startBlock
    ) public initializer {
        require(_tierBonusRate.length <= 11, "Tier range is from 0 to 10");
        for(uint i = 0; i < _tierBonusRate.length; i ++) {
            require(_tierBonusRate[i] <= TIER_BONUS_MAX_RATE, "The maximum rate is 400");
        }

        __Ownable_init();

        START_BLOCK = _startBlock;
        END_BLOCK = BLOCK_PER_PERIOD.mul(PERIOD_AMOUNT).add(_startBlock);

        periodDVDPerBlock[1] = 30 ether;
        for (uint256 i = 2; i <= PERIOD_AMOUNT; i++) {
            periodDVDPerBlock[i] = periodDVDPerBlock[i.sub(1)].mul(9650).div(10000);
        }

        setWalletAddress(_treasuryWalletAddr, _communityWalletAddr);

        addPool(_xdvd, _xdvdPoolWeight, false);
        setDVD(_dvd);
        setXDVD(_xdvd);

        setTierBonusRate(_tierBonusRate);
        setEarlyWithdrawalPenalty(_earlyWithdrawalPenaltyPeriod, _earlyWithdrawalPenaltyPercent);
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
    function setXDVD(address _xdvd) public onlyOwner {
        require(address(dvd) != address(0), "DVD address should be already set");
        require(_xdvd != address(0), "xDVD address should not be zero address");

        Pool memory _pool = poolMap[_xdvd];
        require(_pool.lpTokenAddress == _xdvd, "xDVD pool is not added yet");

        // Allow access xDVD because yield() calls xDVD.depositByProxy()
        if (address(xdvd) != address(0)) {
            dvd.approve(address(xdvd), 0);
        }
        dvd.approve(_xdvd, type(uint256).max);

        xdvd = IxDVD(_xdvd);
        xdvdPid = _pool.pid;
        emit SetXDVD(xdvd, xdvdPid);
    }

    /**
     * @notice Set DAOvvip token address. Can only be called by owner
     */
    function setDAOvvip(address _daoVvip) public onlyOwner {
        require(address(dvd) != address(0), "DVD address should be already set");
        require(_daoVvip != address(0), "DAOvvip address should not be zero address");

        Pool memory _pool = poolMap[_daoVvip];
        require(_pool.lpTokenAddress == _daoVvip, "DAOvvip pool is not added yet");

        daoVvip = IDAOvvip(_daoVvip);
        daoVvipPid = _pool.pid;
        emit SetDAOvvip(daoVvip, daoVvipPid);
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
     * @notice Set the period and rate of the early withdrawal penalty. Can only be called by owner
     *
     * @param _period       Period in second
     * @param _percent      Percent of penalty. For example, 30 if the penalty is 30% rewards.
     */
    function setEarlyWithdrawalPenalty(uint256 _period, uint256 _percent) public onlyOwner {
        require(_percent <= 100, "The rate should equal or less than 100");
        earlyWithdrawalPenaltyPeriod = _period;
        earlyWithdrawalPenaltyPercent = _percent;
        emit SetEarlyWithdrawalPenalty(earlyWithdrawalPenaltyPeriod, earlyWithdrawalPenaltyPercent);
    }

    /**
     * @notice Set locked period and bonus rate for DAOvvip
     */
    function setBonusForLockedCapital(uint32[] memory _days, uint32[] memory _bonusRate) public onlyOwner {
        require(0 < _days.length, "The count should be greater than 0");
        require(_days.length <= 10, "The count is limited by 10");
        require(_days.length == _bonusRate.length, "The length is mismatch");

        uint32 prevDay = 0;
        for(uint i = 0; i < _bonusRate.length; i ++) {
            require(_bonusRate[i] <= TIER_BONUS_MAX_RATE, "The maximum rate is 400");
            require(prevDay < _days[i], "The each periods should be greater that previous period");
            prevDay = _days[i];
        }

        lockDays = _days;
        lockBonusRate = _bonusRate;
        emit SetBonusForLockedCapital(lockDays, lockBonusRate);
    }

    /**
     * @notice Set the period and rate of the early harvest penalty on DAOvvip pool. Can only be called by owner
     *
     * @param _period       Period in second
     * @param _percent      Percent of penalty. For example, 30 if the penalty is 30% rewards.
     */
    function setEarlyHarvestPenalty(uint256 _period, uint256 _percent) public onlyOwner {
        require(_percent <= 100, "The rate should equal or less than 100");
        earlyHarvestPenaltyPeriod = _period;
        earlyHarvestPenaltyPercent = _percent;
        emit SetEarlyHarvestPenalty(earlyHarvestPenaltyPeriod, earlyHarvestPenaltyPercent);
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

        return _pendingTierBonus(_pid, _account, user_.finishedBlock, block.number, pendingDVD_);
    }

    /**
     * @notice Return tier bonus over given _from to _to block. [_from, _to)
     *
     * @param _from         From block number (included)
     * @param _to           To block number (exluded)
     * @param _pendingDVD   The pending reward of _account  from _from block to _to block
     */
    function _pendingTierBonus(uint256 _pid, address _account, uint256 _from, uint256 _to, uint256 _pendingDVD) internal view returns(uint256) {
        if (_from < START_BLOCK) {_from = START_BLOCK;}
        if (_to > END_BLOCK) {_to = END_BLOCK;}
        if (_from >= _to) return 0;

        IxDVDBase daoVip = (daoVvipPid == _pid && daoVvipPid != 0) ? IxDVDBase(daoVvip) : IxDVDBase(xdvd);

        uint256 pendingBonus_;
        uint256 pendingBlocks_ = _to.sub(_from);

        while(_from < _to) {
            (uint8 tier_, , uint256 endBlock_) = daoVip.tierAt(_account, _from);
            if (_to <= endBlock_) {
                // _to block is not contained in the pending DVD
                endBlock_ = _to.sub(1);
            }

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

    function pendingBonusForLockedCapital(address _account) public view returns(uint256) {
        User storage user_ = user[daoVvipPid][_account];
        if (user_.lpAmount == 0) return 0;

        uint256 pendingDVD_ = pendingDVD(daoVvipPid, _account);
        if (pendingDVD_ == 0) return 0;

        return _pendingBonusForLockedCapital(_account, pendingDVD_);
    }

    function _pendingBonusForLockedCapital(address _account, uint256 _pendingDVD) internal view returns(uint256) {
        User storage user_ = user[daoVvipPid][_account];
        uint32 days_  = uint32(uint256(block.timestamp).sub(user_.lastDepositTime).div(1 days));
        for (uint i = lockDays.length; 0 < i ; i --) {
            if (lockDays[i-1] <= days_) {
                return _pendingDVD.mul(lockBonusRate[i-1]).div(TIER_BONUS_RATE_DENOMINATOR);
            }
        }
        return 0;
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

    function depositByProxy(address _account, uint256 _pid, uint256 _amount) external onlyContract returns(uint256) {
        require(_account != address(0), "Invalid account address");
        _deposit(msg.sender, _account, _pid, _amount);
        return user[_pid][_account].lpAmount;
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
                uint256 bonus_ = _pendingTierBonus(_pid, _account, user_.finishedBlock, pool_.lastRewardBlock, pendingDVD_);
                _safeDVDTransfer(_account, pendingDVD_);
                if (0 < bonus_) dvd.mint(_account, bonus_);
                user_.finishedBlock = pool_.lastRewardBlock;
                user_.receivedBonus = user_.receivedBonus.add(bonus_);
                pendingDVD_ = 0;
                emit Reward(_account, _pid, user_.lpAmount, pendingDVD_, bonus_);
            }
        } else {
            user_.finishedBlock = block.number;
        }

        if(_amount > 0) {
            if (address(_proxy) != address(this)) {
                IERC20Upgradeable(pool_.lpTokenAddress).safeTransferFrom(address(_proxy), address(this), _amount);
            }
            user_.lpAmount = user_.lpAmount.add(_amount);
        }

        user_.finishedDVD = user_.lpAmount.mul(pool_.accDVDPerLP).div(1 ether).sub(pendingDVD_);
        user_.lastDepositTime = block.timestamp;

        emit Deposit(_account, _pid, _amount);
    }

    /** 
     * @notice Withdraw LP tokens
     *
     * @param _pid       Id of the pool to be withdrawn from
     * @param _amount    amount of LP tokens to be withdrawn
     */
    function withdraw(uint256 _pid, uint256 _amount) external onlyEOA {
        require(_pid != daoVvipPid, "This pool is not allowed to directly withdraw by user");
        _withdraw(msg.sender, msg.sender, _pid, _amount);
    }

    function withdrawByProxy(address _account, uint256 _pid, uint256 _amount) external onlyContract returns (uint256, uint256, uint256) {
        require(_pid == daoVvipPid, "This pool is not allowed to withdraw by proxy");
        require(pool[_pid].lpTokenAddress == msg.sender, "Withdrawal is only allowed to the LP token contract");
        require(_account != address(0), "Invalid account address");
        return _withdrawByDAOvvip(_account, _pid, _amount);
    }

    function _withdrawByDAOvvip(address _account, uint256 _pid, uint256 _amount) internal returns (uint256, uint256, uint256) {
        require(0 < lockDays.length, "The bonus is not set for the locked capital");

        User storage user_ = user[daoVvipPid][_account];
        uint32 days_  = uint32(uint256(block.timestamp).sub(user_.lastDepositTime).div(1 days));
        require(lockDays[0] < days_, "The capital is locked, try again in future");

        (uint256 pendingDVD_, uint256 bonus_) = _withdraw(msg.sender, _account, _pid, _amount);
        uint256 lockBonus_ = _pendingBonusForLockedCapital(_account, pendingDVD_);
        if (0 < lockBonus_) dvd.mint(msg.sender, lockBonus_);

        return (user[_pid][_account].lpAmount, pendingDVD_, bonus_.add(lockBonus_));
    }

    /** 
     * @notice Withdraw LP tokens
     *
     * @param _proxy     This should be user's address or trustable contract address
     * @param _pid       Id of the pool to be withdrawn from
     * @param _amount    amount of LP tokens to be withdrawn
     */
    function _withdraw(address _proxy, address _account, uint256 _pid, uint256 _amount) internal returns (uint256, uint256) {
        Pool storage pool_ = pool[_pid];
        User storage user_ = user[_pid][_account];

        require(user_.lpAmount >= _amount, "Not enough LP token balance");

        updatePool(_pid);

        uint256 pendingDVD_ = user_.lpAmount.mul(pool_.accDVDPerLP).div(1 ether).sub(user_.finishedDVD);
        uint256 bonus_;

        if(pendingDVD_ > 0) {
            if (block.timestamp < user_.lastDepositTime.add(earlyWithdrawalPenaltyPeriod)) {
                uint256 penalty_ = pendingDVD_.mul(earlyWithdrawalPenaltyPercent).div(100);
                if (0 < penalty_) {
                    dvd.burn(penalty_);
                    pendingDVD_ = pendingDVD_.sub(penalty_);
                }
            }
            bonus_ = _pendingTierBonus(_pid, _account, user_.finishedBlock, pool_.lastRewardBlock, pendingDVD_);
            _safeDVDTransfer(_proxy, pendingDVD_);
            if (0 < bonus_) dvd.mint(_proxy, bonus_);
            user_.finishedBlock = pool_.lastRewardBlock;
            user_.receivedBonus = user_.receivedBonus.add(bonus_);
            emit Reward(_account, _pid, user_.lpAmount, pendingDVD_, bonus_);
        }

        if(_amount > 0) {
            user_.lpAmount = user_.lpAmount.sub(_amount);
            IERC20Upgradeable(pool_.lpTokenAddress).safeTransfer(_proxy, _amount);
        }

        user_.finishedDVD = user_.lpAmount.mul(pool_.accDVDPerLP).div(1 ether);
        // user_.lastWithdrawalTime = block.number;

        emit Withdraw(_account, _pid, _amount);
        return (pendingDVD_, bonus_);
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
        require(_pid != daoVvipPid, "Please calls DAOvvipYield for DAOvvip");
        address account_ = msg.sender;
        (uint256 pendingDVD_, uint256 bonus_) = _harvest(account_, _pid);

        uint256 dvdAmount_ = pendingDVD_.add(bonus_);
        uint256 xdvdBalance_ = xdvd.balanceOf(address(this));
        xdvd.depositByProxy(account_, dvdAmount_);
        uint256 xdvdAmount_ = xdvd.balanceOf(address(this)).sub(xdvdBalance_);

        _deposit(address(this), account_, xdvdPid, xdvdAmount_);

        emit Yield(account_, _pid, user[_pid][account_].lpAmount, pendingDVD_, bonus_);
    }

    function _harvest(address _account, uint256 _pid) internal returns (uint256, uint256) {
        Pool storage pool_ = pool[_pid];
        User storage user_ = user[_pid][_account];
        require(0 < user_.lpAmount, "User should deposit on the pool before yielding");

        updatePool(_pid);

        uint256 pendingDVD_ = user_.lpAmount.mul(pool_.accDVDPerLP).div(1 ether).sub(user_.finishedDVD);
        require(0 < pendingDVD_, "User should have the pending DVD rewards");

        uint256 bonus_ = _pendingTierBonus(_pid, _account, user_.finishedBlock, pool_.lastRewardBlock, pendingDVD_);
        if (0 < bonus_) dvd.mint(address(this), bonus_);
        user_.finishedBlock = pool_.lastRewardBlock;
        user_.receivedBonus = user_.receivedBonus.add(bonus_);
        user_.finishedDVD = user_.finishedDVD.add(pendingDVD_);
        user_.lastDepositTime = block.timestamp;

        return (pendingDVD_, bonus_);
    }

    /**
     * @notice Take DVD rewards.
     *
     * @param _pid       Id of the pool to be deposited to
     */
    function harvestByProxy(address _account, uint256 _pid) external onlyContract returns (uint256, uint256, uint256) {
        require(_pid == daoVvipPid, "This pool is not allowed to withdraw by proxy");
        require(pool[_pid].lpTokenAddress == msg.sender, "Withdrawal is only allowed to the LP token contract");
        require(_account != address(0), "Invalid account address");
        return _harvestByDAOvvip(_account, _pid);
    }

    function _harvestByDAOvvip(address _account, uint256 _pid) internal returns (uint256, uint256, uint256) {
        User storage user_ = user[daoVvipPid][_account];

        (uint256 pendingDVD_, uint256 bonus_) = _harvest(_account, _pid);
        if (block.timestamp < user_.lastDepositTime.add(earlyHarvestPenaltyPeriod)) {
            uint256 penalty_ = pendingDVD_.mul(earlyHarvestPenaltyPercent).div(100);
            if (0 < penalty_) {
                dvd.burn(penalty_);
                pendingDVD_ = pendingDVD_.sub(penalty_);
            }
            penalty_ = bonus_.mul(earlyHarvestPenaltyPercent).div(100);
            if (0 < penalty_) {
                dvd.burn(penalty_);
                bonus_ = bonus_.sub(penalty_);
            }
        }
        uint256 lockBonus_ = _pendingBonusForLockedCapital(_account, pendingDVD_);
        if (0 < lockBonus_) dvd.mint(address(this), lockBonus_);

        _safeDVDTransfer(msg.sender, pendingDVD_.add(bonus_).add(lockBonus_));
        emit Harvest(_account, _pid, user[_pid][_account].lpAmount, pendingDVD_, bonus_.add(lockBonus_));

        return (user[_pid][_account].lpAmount, pendingDVD_, bonus_.add(lockBonus_));
    }

    uint256[29] private __gap;
}