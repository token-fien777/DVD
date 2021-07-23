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
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using AddressUpgradeable for address;
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


    event SetWalletAddress(address indexed treasuryWalletAddr, address indexed communityWalletAddr);
    event SetDVD(DAOventuresTokenImplementation indexed dvd);
    event SetXDVD(IxDVD indexed xdvd);
    event SetXDVDPid(uint256 xdvdpid);
    event TransferDVDOwnership(address indexed newOwner);
    event AddPool(address indexed lpTokenAddress, uint256 indexed poolWeight, uint256 indexed lastRewardBlock);
    event SetPoolWeight(uint256 indexed poolId, uint256 indexed poolWeight, uint256 totalPoolWeight);
    event UpdatePool(uint256 indexed poolId, uint256 indexed lastRewardBlock, uint256 totalDVD);
    event Deposit(address indexed user, uint256 indexed poolId, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed poolId, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed poolId, uint256 amount);

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
        IxDVD _xdvd
    ) public initializer {
        __Ownable_init();

        periodDVDPerBlock[1] = 30 ether;

        for (uint256 i = 2; i <= PERIOD_AMOUNT; i++) {
            periodDVDPerBlock[i] = periodDVDPerBlock[i.sub(1)].mul(9650).div(10000);
        }

        setWalletAddress(_treasuryWalletAddr, _communityWalletAddr);

        setDVD(_dvd);
        setXDVD(_xdvd);
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
        dvd = _dvd;
        emit SetDVD(dvd);
    }

    /**
     * @notice Set DVD token address. Can only be called by owner
     */
    function setXDVD(IxDVD _xdvd) public onlyOwner {
        xdvd = _xdvd;
        emit SetXDVD(xdvd);

        Pool memory _pool = poolMap[address(_xdvd)];
        if (_pool.lpTokenAddress != address(0)) {
            xdvdPid = _pool.pid;
            emit SetXDVDPid(xdvdPid);
        }
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
    function pendingDVD(uint256 _pid, address _user) external view returns(uint256) {
        Pool storage pool_ = pool[_pid];
        User storage user_ = user[_pid][_user];
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

        Pool memory newPool = Pool({
            lpTokenAddress: _lpTokenAddress,
            poolWeight: _poolWeight,
            lastRewardBlock: lastRewardBlock,
            accDVDPerLP: 0,
            pid: pool.length
        });

        pool.push(newPool);
        poolMap[_lpTokenAddress] = newPool;

        emit AddPool(_lpTokenAddress, _poolWeight, lastRewardBlock);

        if (address(xdvd) == _lpTokenAddress) {
            xdvdPid = newPool.pid;
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

    function depositByProxy(address _user, uint256 _pid, uint256 _amount) external onlyContract {
        require(_user != address(0), "Invalid user address");
        _deposit(msg.sender, _user, _pid, _amount);
    }

    function _deposit(address _proxy, address _user, uint256 _pid, uint256 _amount) internal {
        Pool storage pool_ = pool[_pid];
        User storage user_ = user[_pid][_user];

        updatePool(_pid);

        // Due to the security issue, we will transfer DVD rewards in only case of users directly deposit.
        if (_proxy == _user && user_.lpAmount > 0) {
            uint256 pendingDVD_ = user_.lpAmount.mul(pool_.accDVDPerLP).div(1 ether).sub(user_.finishedDVD);
            if(pendingDVD_ > 0) {
                _safeDVDTransfer(_user, pendingDVD_);
            }
        }

        if(_amount > 0) {
            IERC20Upgradeable(pool_.lpTokenAddress).safeTransferFrom(address(_proxy), address(this), _amount);
            user_.lpAmount = user_.lpAmount.add(_amount);
        }

        user_.finishedDVD = user_.lpAmount.mul(pool_.accDVDPerLP).div(1 ether);

        emit Deposit(_user, _pid, _amount);
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
            _safeDVDTransfer(msg.sender, pendingDVD_);
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

    uint256[40] private __gap;
}