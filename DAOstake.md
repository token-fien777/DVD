# DAOstake

## 介绍

DAOstake是DAOventures的Liquidity mining流动性挖矿智能合约，用户通过将他们的ERC20 LP Token质押到相应的Pool里，从而来获得DVG奖励。用户越早质押、质押的时间越长、质押的数量越多，其能获得的DVG奖励就会越多。

管理员将会在DAOstake上面为每种ERC20 LP Token创建相应的Pool (ERC20 LP Token <-> DVG)，每个Pool有相应的权重，所有Pool的权重相加总和等于100%。

整个Liquidity mining流动性挖矿过程将会分为多个周期，每个周期的时间以及区块数量都相同。在第一个周期中，每个区块将会挖出20个DVG，之后每个区块挖出的DVG数量将会每个周期减少2%，这就意味着，第二个周期的每个区块将会挖出19.6个DVG，第三个周期的每个区块将会挖出19.208个DVG，以此类推......

每个区块挖出的DVG的分配规则如下：
- 24.5%的DVG将会分配到Community Wallet，用于社区建设
- 24.5%的DVG将会分配到Treasury Wallet
- 51%的DVG将会作为奖励分配给每个Liquidity provider用户，分配规则：
  - 首先按Pool的权重，将这51%的DVG分配到相应的每个Pool
  - 然后再按用户存入的ERC20 LP Token数量占相应Pool所拥有的总的ERC20 LP Token数量的比例来将DVG分配给每个Liquidity provider用户



## 函数

### 用户函数：

`deposit(uint256 _pid, uint256 _amount)`: 用户将ERC20 LP Token存入到相应的Pool中从而参与流动性挖矿来获取DVG奖励
`withdraw(uint256 _pid, uint256 _amount)`: 用户从相应的Pool中取出ERC20 LP Token
`emergencyWithdraw(uint256 _pid)`: 用户从指定的Pool中一次性取出他所有的ERC20 LP Token，注意：将不会获得DVG奖励

### 管理员函数:

`setWalletAddress(address _treasuryWalletAddr, address _communityWalletAddr)`: 设置Treasury Wallet和Community Wallet的钱包地址
`addPool(address _lpTokenAddress, uint256 _poolWeight, bool _withUpdate)`: 增加一个新的Pool
`setPoolWeight(uint256 _pid, uint256 _poolWeight, bool _withUpdate)`: 设置更改Pool的权重

### 信息查看函数：

`poolLength()`: 查看Pool数量
`getMultiplier(uint256 _from, uint256 _to)`: 查看从\_from区块到\_to区块所挖出的总的DVG数量
`pendingDVG(uint256 _pid, address _user)`: 查看用户在指定Pool中可获取的DVG奖励数量

### 信息更新函数：

`updatePool(uint256 _pid)`: 用于更新指定Pool的信息，使其数据记录保持最新
`massUpdatePools()`: 一次性批处理更新全部Pool的信息



