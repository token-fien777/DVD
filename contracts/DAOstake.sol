pragma solidity >= 0.7.0 < 0.8.0;


import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IDVGToken.sol";
import "hardhat/console.sol";


contract DAOstake is Ownable {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;


    /* 
    Basically, any point in time, the amount of DVGs entitled to a user but is pending to be distributed is:
    
    pending DVG = (user.lpAmount * pool.accDVGPerLP) - user.finishedDVG
    
    Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
    1. The pool's `accDVGPerLP` (and `lastRewardBlock`) gets updated.
    2. User receives the pending DVG sent to his/her address.
    3. User's `lpAmount` gets updated.
    4. User's `finishedDVG` gets updated.
    */
    struct Pool {
        // Address of LP token
        address lpTokenAddress;
        // Weight of pool           
        uint256 poolWeight;
        // Last block number that DVGs distribution occurs for pool
        uint256 lastRewardBlock; 
        // Accumulated DVGs per LP of pool
        uint256 accDVGPerLP; 
    }

    struct User {
        // LP token amount that user provided
        uint256 lpAmount;     
        // Finished distributed DVGs to user
        uint256 finishedDVG;
    }
    

    /* Block Period */
    // Block number when start
    uint256 public startBlock;
    // Amount of block per period
    uint256 public blockPerPeriod;

    /* Wallet Address */
    // Treasury wallet address
    address public treasuryWalletAddr;
    // Community wallet address
    address public communityWalletAddr;

    // DVG token address
    address public dvgAddr;

    /* Precision and Percent */
    uint256 public precision; 
    uint256 public hundredPercent;

    /* Percent for three parts */
    // Percent of DVG is distributed to treasury wallet per block
    uint256 public treasuryWalletPercent;
    // Percent of DVG is distributed to community wallet per block
    uint256 public communityWalletPercent;
    // Percent of DVG is distributed to pools per block
    uint256 public poolPercent;

    /* Pool and User */
    // Total pool weight / Sum of all pool weights
    uint256 public totalPoolWeight = 0;
    Pool[] public pool;
    // pool id => user address => user info
    mapping (uint256 => mapping (address => User)) public user;

    // period id => DVG amount per block of period
    mapping (uint256 => uint256) public periodDVGPerBlock;


    event SetBlockPeriod(uint256 indexed startBlock, uint256 indexed blockPerPeriod);

    event SetPeriodDVGPerBlock(uint256 indexed periodId, uint256 dvgPerBlock);

    event SetWalletAddress(address indexed treasuryWalletAddr, address indexed communityWalletAddr);

    event SetDVGAddress(address indexed dvgAddr);

    event SetPrecision(uint256 indexed precision);

    event SetPercent(uint256 indexed treasuryWalletPercent, uint256 indexed communityWalletPercent, uint256 indexed poolPercent);

    event AddPool(address indexed lpTokenAddress, uint256 indexed poolWeight, uint256 indexed lastRewardBlock);

    event SetPoolWeight(uint256 indexed poolId, uint256 indexed poolWeight, uint256 indexed totalPoolWeight);

    event UpdatePool(uint256 indexed poolId, uint256 indexed lastRewardBlock, uint256 indexed totalDVG);

    event Deposit(address indexed user, uint256 indexed poolId, uint256 indexed amount);

    event Withdraw(address indexed user, uint256 indexed poolId, uint256 indexed amount);

    event EmergencyWithdraw(address indexed user, uint256 indexed poolId, uint256 indexed amount);


    constructor(
        uint256 _startBlock,
        uint256 _blockPerPeriod,
        address _treasuryWalletAddr,
        address _communityWalletAddr,
        address _dvgAddr,
        uint256 _precision,
        uint256 _treasuryWalletPercent,
        uint256 _communityWalletPercent,
        uint256 _poolPercent
    ) public {
        setBlockPeriod(_startBlock, _blockPerPeriod);

        setWalletAddress(_treasuryWalletAddr, _communityWalletAddr);

        setDVGAddress(_dvgAddr);

        setPrecision(_precision);

        setPercent(_treasuryWalletPercent, _communityWalletPercent, _poolPercent);
    }


    /** 
     * @notice Set all params about block/period. Can only be called by owner
     *
     * @param _startBlock        Block number when start
     * @param _blockPerPeriod    Amount of block per period
     */
    function setBlockPeriod(uint256 _startBlock, uint256 _blockPerPeriod) public onlyOwner {
        startBlock = _startBlock;
        blockPerPeriod = _blockPerPeriod;

        emit SetBlockPeriod(startBlock, blockPerPeriod);
    }

    /**
     * @notice Set DVG amount per block of period. Can only be called by owner
     *
     * @param _periodId       Id of period
     * @param _dvgPerBlock    DVG amount per block of period
     */
    function setPeriodDVGPerBlock(uint256 _periodId, uint256 _dvgPerBlock) public onlyOwner {
        require(_periodId > 0, "Period id should larger than zero");

        periodDVGPerBlock[_periodId] = _dvgPerBlock;

        emit SetPeriodDVGPerBlock(_periodId, _dvgPerBlock);
    }

    /** 
     * @notice Set all params about wallet address. Can only be called by owner
     * Remember to mint and distribute pending DVGs to wallet before changing address
     *
     * @param _treasuryWalletAddr     Treasury wallet address
     * @param _communityWalletAddr    Community wallet address
     */
    function setWalletAddress(address _treasuryWalletAddr, address _communityWalletAddr) public onlyOwner {
        require((!_treasuryWalletAddr.isContract()) && (!_communityWalletAddr.isContract()), "Any wallet address should not be smart contract address");
        
        treasuryWalletAddr = _treasuryWalletAddr;
        communityWalletAddr = _communityWalletAddr;
    
        emit SetWalletAddress(treasuryWalletAddr, communityWalletAddr);
    }

    /**
     * @notice Set DVG token address. Can only be called by owner
     */
    function setDVGAddress(address _dvgAddr) public onlyOwner {
        require(_dvgAddr.isContract(), "DVG address should be a smart contract address");

        dvgAddr = _dvgAddr;
    
        emit SetDVGAddress(dvgAddr);
    }

    /** 
     * @notice Set precision. Can only be called by owner
     */
    function setPrecision(uint256 _precision) public onlyOwner {
        require(_precision > 0, "Precision should larger than zero");

        precision = _precision;
        hundredPercent = precision.mul(100);

        emit SetPrecision(precision);
    }

    /** 
     * @notice Set all params about percent for three parts. Can only be called by owner
     *
     * @param _treasuryWalletPercent     Percent of DVG is distributed to treasury wallet per block
     * @param _communityWalletPercent    Percent of DVG is distributed to community wallet per block
     * @param _poolPercent               Percent of DVG is distributed to pools per block
     */
    function setPercent(
        uint256 _treasuryWalletPercent,
        uint256 _communityWalletPercent,
        uint256 _poolPercent
    ) public onlyOwner {
        require(_treasuryWalletPercent.add(_communityWalletPercent).add(_poolPercent) == hundredPercent, "Sum of three percents should be 100");

        treasuryWalletPercent = _treasuryWalletPercent;
        communityWalletPercent = _communityWalletPercent;
        poolPercent = _poolPercent;
 
        emit SetPercent(treasuryWalletPercent, communityWalletPercent, poolPercent);
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
        uint256 periodOfFrom = _from.sub(startBlock).div(blockPerPeriod).add(1);
        uint256 periodOfTo = _to.sub(startBlock).div(blockPerPeriod).add(1);
        
        if (periodOfFrom == periodOfTo) {
            multiplier = _to.sub(_from).mul(periodDVGPerBlock[periodOfTo]);
        } else {
            uint256 multiplierOfFrom = blockPerPeriod.mul(periodOfFrom).add(startBlock).sub(_from).mul(periodDVGPerBlock[periodOfFrom]);
            uint256 multiplierOfTo = _to.sub(startBlock).mod(blockPerPeriod).mul(periodDVGPerBlock[periodOfTo]);
            multiplier = multiplierOfFrom.add(multiplierOfTo);
            for (uint256 periodId = periodOfFrom.add(1); periodId < periodOfTo; periodId++) {
                multiplier = multiplier.add(blockPerPeriod.mul(periodDVGPerBlock[periodId]));
            }
        }
    }

    /** 
     * @notice Get pending DVG amount of user in pool
     */
    function pendingDVG(uint256 _pid, address _user) external view returns(uint256) {
        Pool storage pool_ = pool[_pid];
        User storage user_ = user[_pid][_user];
        uint256 accDVGPerLP = pool_.accDVGPerLP;
        uint256 lpSupply = IERC20(pool_.lpTokenAddress).balanceOf(address(this));

        if (block.number > pool_.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool_.lastRewardBlock, block.number);
            uint256 dvgForPool = multiplier.mul(poolPercent).mul(pool_.poolWeight).div(totalPoolWeight).div(hundredPercent);
            accDVGPerLP = accDVGPerLP.add(dvgForPool.mul(precision).div(lpSupply));
        }

        return user_.lpAmount.mul(accDVGPerLP).div(precision).sub(user_.finishedDVG);
    }

    /** 
     * @notice Add a new LP to pool. Can only be called by owner
     * DO NOT add the same LP token more than once. DVG rewards will be messed up if you do
     */
    function addPool(address _lpTokenAddress, uint256 _poolWeight, bool _withUpdate) public onlyOwner {
        require(_lpTokenAddress.isContract(), "LP token address should be a smart contract address");

        if (_withUpdate) {
            massUpdatePools();
        }
        
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalPoolWeight = totalPoolWeight + _poolWeight;

        pool.push(Pool({
            lpTokenAddress: _lpTokenAddress,
            poolWeight: _poolWeight,
            lastRewardBlock: lastRewardBlock,
            accDVGPerLP: 0
        }));

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

        uint256 totalDVG = getMultiplier(pool_.lastRewardBlock, block.number).mul(pool_.poolWeight).div(totalPoolWeight);

        uint256 lpSupply = IERC20(pool_.lpTokenAddress).balanceOf(address(this));
        if (lpSupply > 0) {
            uint256 dvgForPool = totalDVG.mul(poolPercent).div(hundredPercent);

            IDVGToken(dvgAddr).mint(treasuryWalletAddr, totalDVG.mul(treasuryWalletPercent).div(hundredPercent)); 
            IDVGToken(dvgAddr).mint(communityWalletAddr, totalDVG.mul(communityWalletPercent).div(hundredPercent));
            IDVGToken(dvgAddr).mint(address(this), dvgForPool);

            pool_.accDVGPerLP = pool_.accDVGPerLP.add(dvgForPool.mul(precision).div(lpSupply));
        } else {
            IDVGToken(dvgAddr).mint(treasuryWalletAddr, totalDVG.mul(treasuryWalletPercent).div(hundredPercent)); 
            IDVGToken(dvgAddr).mint(communityWalletAddr, totalDVG.mul(communityWalletPercent.add(poolPercent)).div(hundredPercent));
        }

        pool_.lastRewardBlock = block.number;

        emit UpdatePool(_pid, pool_.lastRewardBlock, totalDVG);
    }

    /** 
     * @notice Update reward variables for all pools. Be careful of gas spending!
     */
    function massUpdatePools() public {
        uint256 length = pool.length;
        for (uint256 pid = 0; pid < length; pid++) {
            updatePool(pid);
        }
    }

    /** 
     * @notice Deposit LP tokens for DVG rewards
     * Before depositing, user needs approve this contract to be able to spend or transfer their LP tokens
     *
     * @param _pid       Id of the pool to be deposited to
     * @param _amount    Amount of LP tokens to be deposited
     */
    function deposit(uint256 _pid, uint256 _amount) public {
        Pool storage pool_ = pool[_pid];
        User storage user_ = user[_pid][msg.sender];

        updatePool(_pid);

        if (user_.lpAmount > 0) {
            uint256 pendingDVG_ = user_.lpAmount.mul(pool_.accDVGPerLP).div(precision).sub(user_.finishedDVG);
            if(pendingDVG_ > 0) {
                _safeDVGTransfer(msg.sender, pendingDVG_);
            }
        }

        if(_amount > 0) {
            IERC20(pool_.lpTokenAddress).safeTransferFrom(address(msg.sender), address(this), _amount);
            user_.lpAmount = user_.lpAmount.add(_amount);
        }

        user_.finishedDVG = user_.lpAmount.mul(pool_.accDVGPerLP).div(precision);

        emit Deposit(msg.sender, _pid, _amount);
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

        uint256 pendingDVG_ = user_.lpAmount.mul(pool_.accDVGPerLP).div(precision).sub(user_.finishedDVG);

        if(pendingDVG_ > 0) {
            _safeDVGTransfer(msg.sender, pendingDVG_);
        }

        if(_amount > 0) {
            user_.lpAmount = user_.lpAmount.sub(_amount);
            IERC20(pool_.lpTokenAddress).safeTransfer(address(msg.sender), _amount);
        }

        user_.finishedDVG = user_.lpAmount.mul(pool_.accDVGPerLP).div(precision);

        emit Withdraw(msg.sender, _pid, _amount);
    }

    /** 
     * @notice Withdraw LP tokens without caring about DVG rewards. EMERGENCY ONLY
     *
     * @param _pid    Id of the pool to be emergency withdrawn from
     */
    function emergencyWithdraw(uint256 _pid) public {
        Pool storage pool_ = pool[_pid];
        User storage user_ = user[_pid][msg.sender];

        uint256 amount = user_.lpAmount;

        user_.lpAmount = 0;
        user_.finishedDVG = 0;

        IERC20(pool_.lpTokenAddress).safeTransfer(address(msg.sender), amount);

        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }
     
    /** 
     * @notice Safe DVG transfer function, just in case if rounding error causes pool to not have enough DVGs
     *
     * @param _to        Address to get transferred DVGs
     * @param _amount    Amount of DVG to be transferred
     */
    function _safeDVGTransfer(address _to, uint256 _amount) internal {
        uint256 dvgBal = IERC20(dvgAddr).balanceOf(address(this));
        
        if (_amount > dvgBal) {
            IERC20(dvgAddr).safeTransfer(_to, dvgBal);
        } else {
            IERC20(dvgAddr).safeTransfer(_to, _amount);
        }
    }


}