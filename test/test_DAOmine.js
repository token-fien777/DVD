const {balance, BN, constants, ether, expectEvent, expectRevert, send, time} = require("@openzeppelin/test-helpers");
const { assert, ethers, deployments, artifacts } = require("hardhat");
// const {Decimal} = require("decimal.js");
const { BigNumber } = require('bignumber.js');
BigNumber.config({
  EXPONENTIAL_AT: 1e+9,
  ROUNDING_MODE: BigNumber.ROUND_FLOOR,
})

const IxDVD = artifacts.require("IxDVD");
const DAOventuresTokenImplementation = artifacts.require("DAOventuresTokenImplementation");
const LPTokenMockup = artifacts.require("LPTokenMockup");

const { mainnet: network_ } = require("../parameters");

/*
 * Here the constant variables settings in DAOmine smart contract for the test:
 * uint256 public constant START_BLOCK = 200;
 * uint256 public constant END_BLOCK = 210;
 * uint256 public constant BLOCK_PER_PERIOD = 2;
 * uint256 public constant PERIOD_AMOUNT = 5;
 */ 
contract("DAOmine", async () => {
    let daoMine;
    let daoMineArtifact;
    let dvd, xdvd;
    let dvdOwner, user;
    let lpToken1, lpToken2, lpToken3, lpToken4, tx;

    before(async () => {
        [deployer, a1, a2, ...accounts] = await ethers.getSigners();
    
        daoMineArtifact = await deployments.getArtifact("DAOmineUpgradeable");
    
        dvdOwner = await ethers.getSigner(network_.DVD.ownerAddress);
        user = await ethers.getSigner(network_.DVD.vaultAddress);
        dvd = new ethers.Contract(network_.DVD.tokenAddress, DAOventuresTokenImplementation.abi, user);
        xdvd = new ethers.Contract(network_.xDVD.tokenAddress, IxDVD.abi, user);
    });
    
    beforeEach(async () => {
        await deployments.fixture(["hardhat"]);

        const proxyContract = await ethers.getContract("DAOmineUpgradeableProxy")
        daoMine = new ethers.Contract(proxyContract.address, daoMineArtifact.abi, user);

        // LP token 1     
        lpToken1 = await LPTokenMockup.new("LPToken1", "lp1");
        await lpToken1.mint(a1.address, new BN("1000000000000000000"));
        await lpToken1.mint(a2.address, new BN("2000000000000000000"));
        // LP token 2
        lpToken2 = await LPTokenMockup.new("LPToken2", "lp2");
        for (i = 0; i < 5; i++) {
            await lpToken2.mint(accounts[i].address, new BN((1000000000000000000 * i).toString()));
        }
        // LP token 3
        lpToken3 = await LPTokenMockup.new("LPToken3", "lp3");
        // LP token 4
        lpToken4 = await LPTokenMockup.new("LPToken4", "lp4");
        
        await dvd.connect(dvdOwner).transferOwnership(daoMine.address);
    });


    it("Should be set with correct initial vaule", async () => {
        assert.equal(await daoMine.treasuryWalletAddr(), network_.Global.treasuryWalletAddr, "The Treasury wallet address disagreement");
        assert.equal(await daoMine.communityWalletAddr(), network_.Global.communityWalletAddr, "The Community wallet address disagreement");
        assert.equal(await daoMine.dvd(), dvd.address, "The DVD address disagreement");
        assert.equal(await daoMine.xdvd(), xdvd.address, "The xDVD address disagreement");
        assert.equal(await daoMine.xdvdPid(), 0, "xdvdPid is incorrect");
        assert.equal(await daoMine.poolLength(), 1, "xDVD pool is not added by default");
        assert.equal(await daoMine.totalPoolWeight(), network_.DAOmine.xdvdPoolWeight, "xDVD pool is incorrect");
        assert.equal(await daoMine.earlyWithdrawalPenaltyPeriod(), network_.DAOmine.earlyWithdrawalPenaltyPeriod, "earlyWithdrawalPenaltyPeriod is incorrect");
        assert.equal(await daoMine.earlyWithdrawalPenaltyPercent(), network_.DAOmine.earlyWithdrawalPenaltyPercent, "earlyWithdrawalPenaltyPercent is incorrect");
        
        for (let i = 0; i < network_.DAOmine.tierBonusRate.length; i++) {
            assert.equal(await daoMine.tierBonusRate(i), network_.DAOmine.tierBonusRate[i], `tierBonusRate(${i}) is incorrect`);
        }

        const endBlock = network_.DAOmine.startBlock + parseInt(await daoMine.BLOCK_PER_PERIOD()) * parseInt(await daoMine.PERIOD_AMOUNT());
        assert.equal(await daoMine.START_BLOCK(), network_.DAOmine.startBlock, "startBlock is incorrect");
        assert.equal(await daoMine.END_BLOCK(), endBlock, "endBlock is incorrect");

        var dvdPerBlock = (new BigNumber(30)).shiftedBy(18);
        assert.equal(parseInt(await daoMine.periodDVDPerBlock(1)), dvdPerBlock.toNumber(), `The DVD amount per block for period 1 disagreement`);
        for (let i = 2; i <= parseInt(await daoMine.PERIOD_AMOUNT()); i++) {
            dvdPerBlock = dvdPerBlock.multipliedBy(9650).dividedBy(10000).integerValue();
            assert.equal(parseInt(await daoMine.periodDVDPerBlock(i)), dvdPerBlock.toNumber(), `The DVD amount per block for period ${i} disagreement`);
        }

        assert.equal(await dvd.owner(), daoMine.address, "The owner of DVD should be DAOmine");
    });

    it("Should succeed to do setups", async () => {
        tx = await daoMine.setWalletAddress(a1.address, a2.address);
        await expectEvent(tx, "SetWalletAddress", {treasuryWalletAddr:a1.address, communityWalletAddr:a2.address});
        assert.equal(await daoMine.treasuryWalletAddr(), a1.address, "The Treasury wallet address of DAOmine disagreement");
        assert.equal(await daoMine.communityWalletAddr(), a2.address, "The Community wallet address of DAOmine disagreement");
        
        tx = await daoMine.setDVD(lpToken1.address);
        await expectEvent(tx, "setDVD", {dvd:lpToken1.address});
        assert.equal(await daoMine.dvd(), lpToken1.address, "The DVG address of DAOmine disagreement");

        // add 4 new pools (pool 0 -> LP token 1, pool weight 1; pool 1 -> LP token 2, pool weight 2; pool 2 -> LP token 3, pool weight 3; pool 3 -> LP token 4, pool weight 4)
        await daoMine.addPool(lpToken1.address, 1, true);
        await daoMine.addPool(lpToken2.address, 2, true);
        await daoMine.addPool(lpToken3.address, 3, true);
        await daoMine.addPool(lpToken4.address, 4, true);

        tx = await daoMine.setPoolWeight(0, 2, false);
        await expectEvent(tx, "SetPoolWeight", {poolId:"0", poolWeight:"2", totalPoolWeight:"11"});
        assert.equal((await daoMine.pool(0)).poolWeight, 2, "The pool weight of pool 0 disagreement");
        assert.equal(await daoMine.totalPoolWeight(), 11, "The total weight of DAOmine disagreement");
    });


    // it("Should succeed to transfer DVG ownership", async () => {
    //     tx = await daoMine.transferDVGOwnership(accounts[1]);
    //     await expectEvent(tx, "TransferDVGOwnership", {newOwner:accounts[1]});
    // });
 
    
    // it("Should succeed to add new pools", async () => {
    //     assert.equal(await daoMine.totalPoolWeight(), 0, "DAOmine should have 0 pool weight when init");

    //     // add a new pool (pool 0 -> LP token 1, pool weight 1)
    //     tx = await daoMine.addPool(lpToken1.address, 1, true);
    //     expectEvent(tx, "AddPool", {lpTokenAddress:lpToken1.address, poolWeight:"1", lastRewardBlock:await daoMine.START_BLOCK()});
    //     assert.equal(await daoMine.poolLength(), 1, "DAOmine should have 1 pool");
    //     assert.equal(await daoMine.totalPoolWeight(), 1, "Stake smart contract should have 1 pool weight totally");

    //     const pool0 = await daoMine.pool(0);
    //     assert.equal(pool0["lpTokenAddress"], lpToken1.address, "The pool 0 should have correct LP token");
    //     assert.equal(pool0["poolWeight"], 1, "The pool 0 should have 1 pool weight");
    //     assert.equal(pool0["lastRewardBlock"], (await daoMine.START_BLOCK()).toString(), "The pool 0 should have correct lastRewardBlock");
    //     assert.equal(pool0["accDVGPerLP"], 0, "The pool 0 should have 0 accDVGPerLP");

    //     // add a new pool (pool 1 -> LP token 2, pool weight 2)
    //     tx = await daoMine.addPool(lpToken2.address, 2, true);
    //     expectEvent(tx, "AddPool", {lpTokenAddress:lpToken2.address, poolWeight:"2", lastRewardBlock:await daoMine.START_BLOCK()});
    //     assert.equal(await daoMine.poolLength(), 2, "DAOmine should have 2 pools");
    //     assert.equal(await daoMine.totalPoolWeight(), 3, "Stake smart contract should have 3 pool weights totally");

    //     const pool1 = await daoMine.pool(1);
    //     assert.equal(pool1["lpTokenAddress"], lpToken2.address, "The pool 1 should have correct LP token");
    //     assert.equal(pool1["poolWeight"], 2, "The pool 1 should have 1 pool weight");
    //     assert.equal(pool1["lastRewardBlock"], (await daoMine.START_BLOCK()).toString(), "The pool 1 should have correct lastRewardBlock");
    //     assert.equal(pool1["accDVGPerLP"], 0, "The pool 1 should have 0 accDVGPerLP");
    // });


    // it("Should succeed to deposit", async () => {
    //     // add 2 new pools (pool 0 -> LP token 1, pool weight 1; pool 1 -> LP token 2, pool weight 2)
    //     await daoMine.addPool(lpToken1.address, 1, true);
    //     await daoMine.addPool(lpToken2.address, 2, true);

    //     // user 1 deposits some (0.5) LP token 1
    //     await lpToken1.approve(daoMine.address, new BN("600000000000000000"), {from:accounts[1]});
    //     tx = await daoMine.deposit(0, new BN("500000000000000000"), {from:accounts[1]});
    //     expectEvent(tx, "Deposit", {user:accounts[1], poolId:"0", amount:new BN("500000000000000000")});
    //     assert.equal((await daoMine.user(0, accounts[1])).lpAmount.toString(), new BN("500000000000000000"), "The user 1 should have correct LP token balance in DAOmine");
    //     assert.equal((await daoMine.user(0, accounts[1])).finishedDVG.toString(), 0, "The user 1 should have correct finished DVG token amount in DAOmine");
    //     assert.equal((await lpToken1.balanceOf(accounts[1])).toString(), new BN("500000000000000000"), "The user 1 should have correct balance in LP token");
    //     assert.equal((await lpToken1.allowance(accounts[1], daoMine.address)).toString(), new BN("100000000000000000"), "The DAOmine should have correct allowance from user 1 in LP token");

    //     // user 2 deposits some (1) LP token 1
    //     await lpToken1.approve(daoMine.address, new BN("1000000000000000000"), {from:accounts[2]});
    //     tx = await daoMine.deposit(0, new BN("1000000000000000000"), {from:accounts[2]});
    //     expectEvent(tx, "Deposit", {user:accounts[2], poolId:"0", amount:new BN("1000000000000000000")});
    //     assert.equal((await daoMine.user(0, accounts[2])).lpAmount.toString(), new BN("1000000000000000000"), "The user 2 should have correct LP token balance in DAOmine");
    //     assert.equal((await daoMine.user(0, accounts[2])).finishedDVG.toString(), 0, "The user 2 should have correct finished DVG token amount in DAOmine");
    //     assert.equal((await lpToken1.balanceOf(accounts[2])).toString(), new BN("1000000000000000000"), "The user 2 should have correct balance in LP token");
    //     assert.equal((await lpToken1.allowance(accounts[2], daoMine.address)).toString(), 0, "The DAOmine should have correct allowance from user 2 in LP token");
        
    //     // user 1 deposits some (0.1) LP token 1 again
    //     tx = await daoMine.deposit(0, new BN("100000000000000000"), {from:accounts[1]});
    //     expectEvent(tx, "Deposit", {user:accounts[1], poolId:"0", amount:new BN("100000000000000000")});
    //     assert.equal((await daoMine.user(0, accounts[1])).lpAmount.toString(), new BN("600000000000000000"), "The user 1 should have correct LP token balance in DAOmine");
    //     assert.equal((await daoMine.user(0, accounts[1])).finishedDVG.toString(), 0, "The user 1 should have correct finished DVG token amount in DAOmine");
    //     assert.equal((await lpToken1.balanceOf(accounts[1])).toString(), new BN("400000000000000000"), "The user 1 should have correct balance in LP token");
    //     assert.equal((await lpToken1.allowance(accounts[1], daoMine.address)).toString(), 0, "The DAOmine should have correct allowance from user 1 in LP token");

    //     // check LP token 1 balance of DAOmine
    //     assert.equal((await lpToken1.balanceOf(daoMine.address)).toString(), new BN("1600000000000000000"), "The pool 0 should have correct balance in LP token");
    // });


    // it("Should succeed to withdraw", async () => {
    //     // add 2 new pools (pool 0 -> LP token 1, pool weight 1; pool 1 -> LP token 2, pool weight 2)
    //     await daoMine.addPool(lpToken1.address, 1, true);
    //     await daoMine.addPool(lpToken2.address, 2, true);


    //     // 2 users deposit some LP token 1 (user 1 -> 0.6, user 2 -> 1)
    //     await lpToken1.approve(daoMine.address, new BN("600000000000000000"), {from:accounts[1]});
    //     await daoMine.deposit(0, new BN("600000000000000000"), {from:accounts[1]});
    //     await lpToken1.approve(daoMine.address, new BN("1000000000000000000"), {from:accounts[2]});
    //     await daoMine.deposit(0, new BN("1000000000000000000"), {from:accounts[2]});

    //     // user 1 withdraws some (0.5) LP token 1
    //     tx = await daoMine.withdraw(0, new BN("500000000000000000"), {from:accounts[1]});
    //     expectEvent(tx, "Withdraw", {user:accounts[1], poolId:"0", amount:new BN("500000000000000000")});
    //     assert.equal((await daoMine.user(0, accounts[1])).lpAmount.toString(), new BN("100000000000000000"), "The user 1 should have correct LP token balance in DAOmine");
    //     assert.equal((await lpToken1.balanceOf(accounts[1])).toString(), new BN("900000000000000000"), "The user 1 should have correct balance in LP token");

    //     // user 2 withdraws all (1) LP token 1
    //     tx = await daoMine.withdraw(0, new BN("1000000000000000000"), {from:accounts[2]});
    //     expectEvent(tx, "Withdraw", {user:accounts[2], poolId:"0", amount:new BN("1000000000000000000")});
    //     assert.equal((await daoMine.user(0, accounts[2])).lpAmount.toString(), 0, "The user 2 should have correct LP token balance in DAOmine");
    //     assert.equal((await lpToken1.balanceOf(accounts[2])).toString(), new BN("2000000000000000000"), "The user 1 should have correct balance in LP token smart contract");

    //     // user 1 withdraws remaining (0.1) LP token 1
    //     tx = await daoMine.withdraw(0, new BN("100000000000000000"), {from:accounts[1]});
    //     expectEvent(tx, "Withdraw", {user:accounts[1], poolId:"0", amount:new BN("100000000000000000")});
    //     assert.equal((await daoMine.user(0, accounts[1])).lpAmount.toString(), 0, "The user 1 should have correct LP token balance in DAOmine");
    //     assert.equal((await lpToken2.balanceOf(accounts[1])).toString(), new BN("1000000000000000000"), "The user 1 should have correct balance in LP token smart contract");
        
    //     // check LP token 1 balance of DAOmine
    //     assert.equal((await lpToken1.balanceOf(daoMine.address)).toString(), 0, "The pool 0 should have correct balance in LP token");

    //     // user 1 deposits 0.1 LP token 1 again
    //     await lpToken1.approve(daoMine.address, new BN("100000000000000000"), {from:accounts[1]});
    //     tx = await daoMine.deposit(0, new BN("100000000000000000"), {from:accounts[1]});
    //     expectEvent(tx, "Deposit", {user:accounts[1], poolId:"0", amount:new BN("100000000000000000")});
    //     assert.equal((await daoMine.user(0, accounts[1])).lpAmount.toString(), new BN("100000000000000000"), "The user 1 should have correct LP token balance in DAOmine");
    //     assert.equal((await lpToken1.balanceOf(accounts[1])).toString(), new BN("900000000000000000"), "The user 1 should have correct balance in LP token");
        
    //     // check LP token 1 balance of DAOmine
    //     assert.equal((await lpToken1.balanceOf(daoMine.address)).toString(), new BN("100000000000000000"), "The pool 0 should have correct balance in LP token");
    // });

    
    // it("Should succeed to emergency withdraw", async () => {
    //     // add 1 new pool (pool 0 -> LP token 1, pool weight 1)
    //     await daoMine.addPool(lpToken1.address, 1, true);

    //     // user 1 deposits some (0.5) LP token 1 
    //     await lpToken1.approve(daoMine.address, new BN("600000000000000000"), {from:accounts[1]});
    //     await daoMine.deposit(0, new BN("500000000000000000"), {from:accounts[1]});
    //     assert.equal((await lpToken1.balanceOf(accounts[1])).toString(), new BN("500000000000000000"), "The user 1 should have correct balance in LP token");
    //     assert.equal((await daoMine.user(0, accounts[1])).lpAmount.toString(), new BN("500000000000000000"), "The user 1 should have correct LP token balance in DAOmine");

    //     // user 1 emergency withdraws LP token 1 
    //     tx = await daoMine.emergencyWithdraw(0, {from:accounts[1]});
    //     expectEvent(tx, "EmergencyWithdraw", {user:accounts[1], poolId:"0", amount:new BN("500000000000000000")});
    //     assert.equal((await lpToken1.balanceOf(accounts[1])).toString(), new BN("1000000000000000000"), "The user 1 should have correct balance in LP token");
    //     assert.equal((await daoMine.user(0, accounts[1])).lpAmount, 0, "The user 1 should have correct LP token balance in DAOmine");
    //     assert.equal((await daoMine.user(0, accounts[1])).finishedDVG, 0, "The user 1 should have zero finished DVG amount in DAOmine");
    // });


    // it("Should record, mint and distribute DVGs properly", async () => {
    //     // add 4 new pools (pool 0 -> LP token 1, pool weight 1; pool 1 -> LP token 2, pool weight 2; pool 2 -> LP token 3, pool weight 3; pool 3 -> LP token 4, pool weight 4)
    //     await daoMine.addPool(lpToken1.address, 1, true);
    //     await daoMine.addPool(lpToken2.address, 2, true);
    //     await daoMine.addPool(lpToken3.address, 3, true);
    //     await daoMine.addPool(lpToken4.address, 4, true);

    //     // 2 users deposit LP token 1 (user 1 -> 0.5, user 2 -> 1)
    //     await lpToken1.approve(daoMine.address, new BN("500000000000000000"), {from:accounts[1]});
    //     await daoMine.deposit(0, new BN("500000000000000000"), {from:accounts[1]});
    //     await lpToken1.approve(daoMine.address, new BN("1000000000000000000"), {from:accounts[2]});
    //     await daoMine.deposit(0, new BN("1000000000000000000"), {from:accounts[2]});

    //     // 5 users deposit LP token 2 (user 1 -> 0.5, user 2 -> 1, user 3 -> 1.5, user 4 -> 2, user 5 -> 2.5)
    //     for (i = 1; i < 6; i++) {
    //         await lpToken2.approve(daoMine.address, new BN((500000000000000000 * i).toString()), {from:accounts[i]});
    //         await daoMine.deposit(1, new BN((500000000000000000 * i).toString()), {from:accounts[i]});
    //     }

    //     await time.advanceBlockTo(await daoMine.START_BLOCK());

    //     tx = await daoMine.massUpdatePools();
    //     for (i = 0; i < 4; i++) {
    //         expectEvent(tx, "UpdatePool", {poolId:i.toString(), lastRewardBlock:(parseInt(await daoMine.START_BLOCK()) + 1).toString(), totalDVG:new BN((2000000000000000000 * (i + 1)).toString())});
    //     }
        
    //     // DVG amount for Treasury wallet: 20(dvgPerBlock) * 24.5%(treasuryWalletPercent) + 10(dvgInAdvance) = 14.9
    //     assert.equal((await dvg.balanceOf(network_.Global.treasuryWalletAddr)).toString(), new BN("14900000000000000000"), "The Treasury wallet should have correct balance of DVG");
        
    //     // DVG amount for Community wallet: because pool 3 and pool 4 have no user/LP token, so the DVGs distribuited to them will be distributed to Community wallet 
    //     // 20(dvgPerBlock) * 24.5%(communityWalletPercent) + 
    //     // 20(dvgPerBlock) * 51%(poolPercent) * (3/10)(pool2Weight/totalWeight) + 
    //     // 20(dvgPerBlock) * 51%(poolPercent) * (4/10)(pool3Weight/totalWeight) = 12.04
    //     assert.equal((await dvg.balanceOf(communityWallet.address)).toString(), new BN("12040000000000000000"), "The Community wallet should have correct balance of DVG");

    //     // DVG amount for pool: 20(dvgPerBlock) * 51%(poolPercent) * (1/10)(pool0Weight/totalWeight) + 20(dvgPerBlock) * 51%(poolPercent) * (2/10)(pool1Weight/totalWeight) = 3.06
    //     assert.equal((await dvg.balanceOf(daoMine.address)).toString(), new BN("3060000000000000000"), "The DAOmine should have correct balance of DVG"); 

    //     await time.advanceBlockTo(parseInt(await daoMine.START_BLOCK()) + 3);

    //     for (i = 1; i < 6; i++) {
    //         assert.equal(await dvg.balanceOf(accounts[i]), 0, `Should not mint and distribute DVGs to user ${i} if no deposit or withdrawal`);
    //     }

    //     // pending DVG amount for user 1 from pool 0:
    //     // 2(blockLength) * 20(dvgPerBlockOfPeriod1) * 51%(poolPercent) * (1/10)(pool0Weight/totalWeight) * (0.5/1.5)(lpToken/totalLPToken) +
    //     // 1(blockLength) * 19.6(dvgPerBlockOfPeriod2) * 51%(poolPercent) * (1/10)(pool0Weight/totalWeight) * (0.5/1.5)(lpToken/totalLPToken) = 1.0132
    //     // pending DVG amount for user 1 from pool 1:
    //     // 2(blockLength) * 20(dvgPerBlockOfPeriod1) * 51%(poolPercent) * (2/10)(pool1Weight/totalWeight) * (0.5/7.5)(lpToken/totalLPToken) +
    //     // 1(blockLength) * 19.6(dvgPerBlockOfPeriod2) * 51%(poolPercent) * (2/10)(pool1Weight/totalWeight) * (0.5/7.5)(lpToken/totalLPToken) = 0.40528
    //     // total pending DVG amount for user 1:
    //     // 1.0132(amount from pool 0) + 0.40528(amount from pool 1) = 1.41848
    //     assert.equal(Decimal.add((await daoMine.pendingDVD(0, accounts[1])).toString()/1e18, (await daoMine.pendingDVD(1, accounts[1])).toString()/1e18), 1.41848, "The user 1 should have correct pending DVG amount in DAOmine");

    //     // pending DVG amount for user 2 from pool 0:
    //     // 2(blockLength) * 20(dvgPerBlockOfPeriod1) * 51%(poolPercent) * (1/10)(pool0Weight/totalWeight) * (1/1.5)(lpToken/totalLPToken) +
    //     // 1(blockLength) * 19.6(dvgPerBlockOfPeriod2) * 51%(poolPercent) * (1/10)(pool0Weight/totalWeight) * (1/1.5)(lpToken/totalLPToken) = 2.0264
    //     // pending DVG amount for user 2 from pool 1:
    //     // 2(blockLength) * 20(dvgPerBlockOfPeriod1) * 51%(poolPercent) * (2/10)(pool1Weight/totalWeight) * (1/7.5)(lpToken/totalLPToken) +
    //     // 1(blockLength) * 19.6(dvgPerBlockOfPeriod2) * 51%(poolPercent) * (2/10)(pool1Weight/totalWeight) * (1/7.5)(lpToken/totalLPToken) = 0.81056
    //     // total pending DVG amount for user 2:
    //     // 2.0264(amount from pool 0) + 0.81056(amount from pool 1) = 2.83696
    //     assert.equal(Decimal.add((await daoMine.pendingDVD(0, accounts[2])).toString()/1e18, (await daoMine.pendingDVD(1, accounts[2])).toString()/1e18), 2.83696, "The user 2 should have correct pending DVG amount in DAOmine");
        
    //     // pending DVG amount for user 3 from pool 1:
    //     // 2(blockLength) * 20(dvgPerBlockOfPeriod1) * 51%(poolPercent) * (2/10)(pool1Weight/totalWeight) * (1.5/7.5)(lpToken/totalLPToken) +
    //     // 1(blockLength) * 19.6(dvgPerBlockOfPeriod2) * 51%(poolPercent) * (2/10)(pool1Weight/totalWeight) * (1.5/7.5)(lpToken/totalLPToken) = 1.21584
    //     assert.equal((await daoMine.pendingDVD(1, accounts[3])).toString()/1e18, 1.21584, "The user 3 should have correct pending DVG amount in DAOmine");

    //     // pending DVG amount for user 4 from pool 1:
    //     // 2(blockLength) * 20(dvgPerBlockOfPeriod1) * 51%(poolPercent) * (2/10)(pool1Weight/totalWeight) * (2/7.5)(lpToken/totalLPToken) +
    //     // 1(blockLength) * 19.6(dvgPerBlockOfPeriod2) * 51%(poolPercent) * (2/10)(pool1Weight/totalWeight) * (2/7.5)(lpToken/totalLPToken) = 1.62112
    //     assert.equal((await daoMine.pendingDVD(1, accounts[4])).toString()/1e18, 1.62112, "The user 4 should have correct pending DVG amount in DAOmine");

    //     // pending DVG amount for user 5 from pool 1:
    //     // 2(blockLength) * 20(dvgPerBlockOfPeriod1) * 51%(poolPercent) * (2/10)(pool1Weight/totalWeight) * (2.5/7.5)(lpToken/totalLPToken) +
    //     // 1(blockLength) * 19.6(dvgPerBlockOfPeriod2) * 51%(poolPercent) * (2/10)(pool1Weight/totalWeight) * (2.5/7.5)(lpToken/totalLPToken) = 2.0264
    //     assert.equal((await daoMine.pendingDVD(1, accounts[5])).toString()/1e18, 2.0264, "The user 5 should have correct pending DVG amount in DAOmine");

    //     // check the lastRewardBlock number of each pool
    //     for (i = 0; i < (await daoMine.poolLength()).toNumber(); i++) {
    //         assert.equal(((await daoMine.pool(i)).lastRewardBlock).toNumber(), parseInt(await daoMine.START_BLOCK()) + 1, "The pool should have correct lastRewardBlock number");
    //     }
    //     tx = await daoMine.deposit(0, 0, {from:accounts[1]});
    //     expectEvent(tx, "Deposit", {user:accounts[1], poolId:"0", amount:"0"});
    //     // DVG amount for user 1 from pool 0:
    //     // 2(blockLength) * 20(dvgPerBlockOfPeriod1) * 51%(poolPercent) * (1/10)(pool0Weight/totalWeight) * (0.5/1.5)(lpToken/totalLPToken) +
    //     // 2(blockLength) * 19.6(dvgPerBlockOfPeriod2) * 51%(poolPercent) * (1/10)(pool0Weight/totalWeight) * (0.5/1.5)(lpToken/totalLPToken) = 1.3464
    //     assert.equal((await dvg.balanceOf(accounts[1])).toString()/1e18, 1.3464, "Should mint and distribute DVGs to user 1 properly if he dposits to pool 0");
    //     assert.equal(((await daoMine.user(0, accounts[1])).finishedDVG).toString()/1e18, 1.3464, "User 1 should have correct finished DVG amount in pool 0");

    //     tx = await daoMine.withdraw(1, new BN("500000000000000000"), {from:accounts[1]});
    //     expectEvent(tx, "Withdraw", {user:accounts[1], poolId:"1", amount:new BN("500000000000000000")});
    //     // DVG amount for user 1 from pool 1:
    //     // 2(blockLength) * 20(dvgPerBlockOfPeriod1) * 51%(poolPercent) * (2/10)(pool1Weight/totalWeight) * (0.5/7.5)(lpToken/totalLPToken) +
    //     // 2(blockLength) * 19.6(dvgPerBlockOfPeriod2) * 51%(poolPercent) * (2/10)(pool1Weight/totalWeight) * (0.5/7.5)(lpToken/totalLPToken) + 
    //     // 1(blockLength) * 19.208(dvgPerBlockOfPeriod3) * 51%(poolPercent) * (2/10)(pool1Weight/totalWeight) * (0.5/7.5)(lpToken/totalLPToken) = 0.6691744
    //     // 0.6691744(amount from pool 1) + 1.3464(amount from pool 0) = 2.0155744
    //     assert.equal((await dvg.balanceOf(accounts[1])).toString()/1e18, 2.0155744, "Should mint and distribute DVGs to user 1 properly if he withdraws from pool 1");
    //     assert.equal(((await daoMine.user(1, accounts[1])).finishedDVG).toString()/1e18, 0, "User 1 should have correct finished DVG amount in pool 1");
    //     tx = await daoMine.deposit(1, 0, {from:accounts[1]});
    //     expectEvent(tx, "Deposit", {user:accounts[1], poolId:"1", amount:"0"});
    //     assert.equal((await dvg.balanceOf(accounts[1])).toString()/1e18, 2.0155744, "Should not mint and distribute more DVGs to user 1 because he has withdrawn all from pool 1");
        
    //     // pending DVG amount for user 1 in the third period from pool 0:
    //     // 2(blockLength) * 19.208(dvgPerBlockOfPeriod3) * 51%(poolPercent) * (1/10)(pool0Weight/totalWeight) * (0.5/1.5)(lpToken/totalLPToken) = 0.653072
    //     assert.equal((await daoMine.pendingDVD(0, accounts[1])).toString()/1e18, 0.653072, "The user 1 should have correct pending DVG amount from pool 0 in DAOmine");

    //     for (i = 2; i <= 5; i++) {
    //         assert.equal((await dvg.balanceOf(accounts[i])).toString()/1e18, 0, `Should not mint and distribute DVGs to user ${i} if no deposit or withdrawal`);
    //         assert.equal((await dvg.balanceOf(accounts[i])).toString()/1e18, 0, `The finished DVG amount of user ${i} should be zero`);
    //         // 20(dvgPerBlockOfPeriod1) * 51%(poolPercent) * (2/10)(pool1Weight/totalWeight) * 0.5 * i * (2 * 1 + 2 * 98% + 98% * 98%) / 7.5 
    //         // + 20(dvgPerBlockOfPeriod1) * 51%(poolPercent) * (2/10)(pool1Weight/totalWeight) * 0.5 * i * 98% * 98% / 7 = 0.8091184 * i
    //         assert.equal((await daoMine.pendingDVD(1, accounts[i])).toString()/1e18, (8091184 * i)/1e7, `The user ${i} should have correct pending DVG amount from pool 1 in DAOmine`);
    //     }

    //     // DVG amount for Treasury wallet:
    //     // pool 0: 20(dvgPerBlockOfPeriod1) * 24.5%(treasuryWalletPercent) * (1/10)(pool0Weight/totalWeight) 
    //     // + 2(blockLength) * 19.6(dvgPerBlockOfPeriod2) * 24.5%(treasuryWalletPercent) * (1/10)(pool0Weight/totalWeight) = 1.4504
    //     // pool 1: 20(dvgPerBlockOfPeriod1) * 24.5%(treasuryWalletPercent) * (2/10)(pool1Weight/totalWeight) 
    //     // + 2(blockLength) * 19.6(dvgPerBlockOfPeriod2) * 24.5%(treasuryWalletPercent) * (2/10)(pool1Weight/totalWeight) 
    //     // + 2(blockLength) * 19.208(dvgPerBlockOfPeriod3) * 24.5%(treasuryWalletPercent) * (2/10)(pool1Weight/totalWeight) = 4.783184
    //     // 14.9 + 1.4504 + 4.783184 = 21.133584
    //     assert.equal((await dvg.balanceOf(network_.Global.treasuryWalletAddr)).toString(), new BN("21133584000000000000"), "The Treasury wallet should have correct balance of DVG");

    //     tx = await daoMine.updatePool(2);
    //     expectEvent(tx, "UpdatePool", {poolId:"2", lastRewardBlock:(parseInt(await daoMine.START_BLOCK()) + 7).toString(), totalDVG:new BN("34931952000000000000")});
    //     // DVG amount for Community wallet:
    //     // pool 0: 20(dvgPerBlockOfPeriod1) * 24.5%(communityWalletPercent) * (1/10)(pool0Weight/totalWeight) 
    //     // + 2(blockLength) * 19.6(dvgPerBlockOfPeriod2) * 24.5%(communityWalletPercent) * (1/10)(pool0Weight/totalWeight) = 1.4504
    //     // pool 1: 20(dvgPerBlockOfPeriod1) * 24.5%(communityWalletPercent) * (2/10)(pool1Weight/totalWeight) 
    //     // + 2(blockLength) * 19.6(dvgPerBlockOfPeriod2) * 24.5%(communityWalletPercent) * (2/10)(pool1Weight/totalWeight) 
    //     // + 2(blockLength) * 19.208(dvgPerBlockOfPeriod3) * 24.5%(communityWalletPercent) * (2/10)(pool1Weight/totalWeight) = 4.783184
    //     // pool 2: 20(dvgPerBlockOfPeriod1) * (24.5%(communityWalletPercent) + 51%(poolPercent)) * (3/10)(pool2Weight/totalWeight) 
    //     // + 2(blockLength) * 19.6(dvgPerBlockOfPeriod2) * (24.5%(communityWalletPercent) + 51%(poolPercent)) * (3/10)(pool2Weight/totalWeight) 
    //     // + 2(blockLength) * 19.208(dvgPerBlockOfPeriod3) * (24.5%(communityWalletPercent) + 51%(poolPercent)) * (3/10)(pool2Weight/totalWeight)
    //     // + 18.82384(dvgPerBlockOfPeriod4) * (24.5%(communityWalletPercent) + 51%(poolPercent)) * (3/10)(pool2Weight/totalWeight) = 26.37362376
    //     // 12.04 + 1.4504 + 4.783184 + 26.37362376 = 44.64720776
    //     assert.equal((await dvg.balanceOf(communityWallet.address)).toString(), new BN("44647207760000000000"), "The Community wallet should have correct balance of DVG");
    // });
});