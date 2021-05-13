# DAOstake

## Introduction

DAOstake is the liquidity mining smart contract of DAOventures. Users can get DVG rewards by staking their ERC20 LP Tokens to the corresponding pool. The earlier the users stake and the more the amount they stake, the more DVG rewards they can get.

The administrator will create corresponding pools (ERC20 LP Token <->DVG) for each ERC20 LP Token on DAOstake. Each pool has corresponding weight, and the total weight of all pools equals 100%.

The whole liquidity mining process will be divided into multiple cycles, and the time and number of blocks of each cycle are the same. In the first cycle, each block will mine 20 DVGs, and then the number of DVGs mined in each block will be reduced by 2% in each cycle, which means that each block will mine 19.6 DVGs in the second cycle, and 19.208 DVGs in the third cycle, and so on.

The allocation rules for DVG mined in each block are as below:
- 24.5% of DVGs will be allocated to Community Wallet for community building.
- 24.5% of DVGs will be allocated to the Treasury Wallet.
- 51% of DVGs will be allocated to each liquidity provider user as a reward：
  - First, according to the weight of the pool, this is allocated to each pool.
  - Then, the DVG is allocated to each liquidity provider user according to the proportion of the number of ERC20 LP Tokens deposited by the user to the total number of ERC20 LP Tokens owned by the corresponding pool.



## Functions

### User functions:

`deposit(uint256 _pid, uint256 _amount)`: Users deposit ERC20 LP Tokens into the corresponding pool to participate in liquidity mining to get DVG rewards.

`withdraw(uint256 _pid, uint256 _amount)`: Users withdraw ERC20 LP Tokens from the corresponding pool.

`emergencyWithdraw(uint256 _pid)`: Users withdraw all ERC20 LP Tokens from the specified pool at one time. Note: No DVG reward will be given.

### Administrator functions:

`setWalletAddress(address _treasuryWalletAddr, address _communityWalletAddr)`: Set the wallet addresses of Treasury Wallet and Community Wallet.

`addPool(address _lpTokenAddress, uint256 _poolWeight, bool _withUpdate)`: Add a new pool.

`setPoolWeight(uint256 _pid, uint256 _poolWeight, bool _withUpdate)`: Set and change the weight of the pool.

### Information viewing functions:

`poolLength()`: Check the number of pools.

`getMultiplier(uint256 _from, uint256 _to)`: View the total number of DVGs mined from `_from` block to` _to` block.

`pendingDVG(uint256 _pid, address _user)`: View the number of DVG rewards users can get in the specified pool.

### Information update functions:

`updatePool(uint256 _pid)`: Used to update the information of the specified pool to keep its data records up-to-date.

`massUpdatePools()`: One time batch update of all pool information.