const {balance, BN, constants, ether, expectEvent, expectRevert, send, time} = require("@openzeppelin/test-helpers");
const { assert, expect, ethers, deployments, artifacts } = require("hardhat");
const { BigNumber } = require('bignumber.js');
BigNumber.config({
  EXPONENTIAL_AT: 1e+9,
  ROUNDING_MODE: BigNumber.ROUND_FLOOR,
})
const { advanceBlockTo } = require('./utils/Ethereum');

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
    let lpToken1, lpToken2, lpToken3, lpToken4;

    before(async () => {
        [deployer, a1, a2, ...accounts] = await ethers.getSigners();
    
        daoMineArtifact = await deployments.getArtifact("DAOmineUpgradeable");
    
        dvdOwner = await ethers.getSigner(network_.DVD.ownerAddress);
        user = await ethers.getSigner(network_.DVD.vaultAddress);
        dvd = new ethers.Contract(network_.DVD.tokenAddress, DAOventuresTokenImplementation.abi, deployer);
        xdvd = new ethers.Contract(network_.xDVD.tokenAddress, IxDVD.abi, deployer);
    });
    
    beforeEach(async () => {
        await deployments.fixture(["hardhat"]);

        const proxyContract = await ethers.getContract("DAOmineUpgradeableProxy")
        daoMine = new ethers.Contract(proxyContract.address, daoMineArtifact.abi, deployer);

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
        expect(await daoMine.owner()).equal(deployer.address);
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
        await daoMine.setWalletAddress(a1.address, a2.address);
        assert.equal(await daoMine.treasuryWalletAddr(), a1.address, "The Treasury wallet address of DAOmine disagreement");
        assert.equal(await daoMine.communityWalletAddr(), a2.address, "The Community wallet address of DAOmine disagreement");
        
        // add 4 new pools (pool 0 -> LP token 1, pool weight 1; pool 1 -> LP token 2, pool weight 2; pool 2 -> LP token 3, pool weight 3; pool 3 -> LP token 4, pool weight 4)
        await daoMine.addPool(lpToken1.address, 1, true);
        await daoMine.addPool(lpToken2.address, 2, true);
        await daoMine.addPool(lpToken3.address, 3, true);
        await daoMine.addPool(lpToken4.address, 4, true);
        assert.equal(await daoMine.poolLength(), 5, "xDVD pool is not added by default");

        await daoMine.setPoolWeight(0, 2, false);
        // await expectEvent(tx, "SetPoolWeight", {poolId:"0", poolWeight:"2", totalPoolWeight:"11"});
        assert.equal((await daoMine.pool(0)).poolWeight, 2, "The pool weight of pool 0 disagreement");
        assert.equal(await daoMine.totalPoolWeight(), 12, "The total weight of DAOmine disagreement");

        await daoMine.setDVD(lpToken1.address);
        assert.equal(await daoMine.dvd(), lpToken1.address, "The DVD address of DAOmine disagreement");

        await daoMine.setXDVD(lpToken2.address);
        assert.equal(await daoMine.xdvd(), lpToken2.address, "The xDVD address disagreement");
        assert.equal(await daoMine.xdvdPid(), 2, "xdvdPid is incorrect");

        await daoMine.setTierBonusRate([0, 100, 200, 300, 400]);
        assert.equal(await daoMine.tierBonusRate(0), 0, `tierBonusRate(0) is incorrect`);
        assert.equal(await daoMine.tierBonusRate(1), 100, `tierBonusRate(1) is incorrect`);
        assert.equal(await daoMine.tierBonusRate(2), 200, `tierBonusRate(2) is incorrect`);
        assert.equal(await daoMine.tierBonusRate(3), 300, `tierBonusRate(3) is incorrect`);
        assert.equal(await daoMine.tierBonusRate(4), 400, `tierBonusRate(4) is incorrect`);

        await daoMine.setEarlyWithdrawalPenalty(10000, 20);
        assert.equal(await daoMine.earlyWithdrawalPenaltyPeriod(), 10000, "earlyWithdrawalPenaltyPeriod is incorrect");
        assert.equal(await daoMine.earlyWithdrawalPenaltyPercent(), 20, "earlyWithdrawalPenaltyPercent is incorrect");
    });

    it("Should succeed to transfer DVD ownership", async () => {
        await daoMine.transferDVDOwnership(a1.address);
        assert.equal(await dvd.owner(), a1.address, "The owner of DVD should be changed");
    });

    it("Should succeed to add new pools", async () => {
        // add a new pool (pool 1 -> LP token 1, pool weight 1)
        tx = await daoMine.addPool(lpToken1.address, 1, true);
        assert.equal(await daoMine.poolLength(), 2, "DAOmine should have 2 pool");
        assert.equal(await daoMine.totalPoolWeight(), 201, "Stake smart contract should have 201 pool weight totally");

        const pool1 = await daoMine.pool(1);
        assert.equal(pool1["lpTokenAddress"], lpToken1.address, "The pool 1 should have correct LP token");
        assert.equal(pool1["poolWeight"], 1, "The pool 1 should have 1 pool weight");
        assert.equal(pool1["lastRewardBlock"], (await daoMine.START_BLOCK()).toString(), "The pool 1 should have correct lastRewardBlock");
        assert.equal(pool1["accDVDPerLP"], 0, "The pool 1 should have 0 accDVDPerLP");
        assert.equal(pool1["pid"], 1, "The pid should be correct");

        const _pool1 = await daoMine.poolMap(lpToken1.address);
        expect(_pool1["lpTokenAddress"]).equal(lpToken1.address);

        // add a new pool (pool 2 -> LP token 2, pool weight 2)
        tx = await daoMine.addPool(lpToken2.address, 2, true);
        assert.equal(await daoMine.poolLength(), 3, "DAOmine should have 3 pools");
        assert.equal(await daoMine.totalPoolWeight(), 203, "Stake smart contract should have 203 pool weights totally");

        const pool2 = await daoMine.pool(2);
        assert.equal(pool2["lpTokenAddress"], lpToken2.address, "The pool 2 should have correct LP token");
        assert.equal(pool2["poolWeight"], 2, "The pool 2 should have 1 pool weight");
        assert.equal(pool2["lastRewardBlock"], (await daoMine.START_BLOCK()).toString(), "The pool 1 should have correct lastRewardBlock");
        assert.equal(pool2["accDVDPerLP"], 0, "The pool 2 should have 0 accDVDPerLP");
        assert.equal(pool2["pid"], 2, "The pid should be correct");

        const _pool2 = await daoMine.poolMap(lpToken2.address);
        expect(_pool2["lpTokenAddress"]).equal(lpToken2.address);

        await expectRevert(daoMine.addPool(xdvd.address, 1, true), "LP token already added");
        await expectRevert(daoMine.addPool(a1.address, 1, true), "LP token address should be smart contract address");
    });

    it("Should succeed to deposit", async () => {
        // add 2 new pools (pool 1 -> LP token 1, pool weight 1; pool 2 -> LP token 2, pool weight 2)
        await daoMine.addPool(lpToken1.address, 1, true);
        await daoMine.addPool(lpToken2.address, 2, true);

        // user 1 deposits some (0.5) LP token 1
        await lpToken1.approve(daoMine.address, new BN("600000000000000000"), {from: a1.address});
        await daoMine.connect(a1).deposit(1, "500000000000000000");
        assert.equal((await daoMine.user(1, a1.address)).lpAmount.toString(), new BN("500000000000000000"), "The user 1 should have correct LP token balance in DAOmine");
        assert.equal((await daoMine.user(1, a1.address)).finishedDVD.toString(), 0, "The user 1 should have correct finished DVG token amount in DAOmine");
        assert.equal((await lpToken1.balanceOf(a1.address)).toString(), new BN("500000000000000000"), "The user 1 should have correct balance in LP token");
        assert.equal((await lpToken1.allowance(a1.address, daoMine.address)).toString(), new BN("100000000000000000"), "The DAOmine should have correct allowance from user 1 in LP token");

        // user 2 deposits some (1) LP token 1
        await lpToken1.approve(daoMine.address, new BN("1000000000000000000"), {from: a2.address});
        await daoMine.connect(a2).deposit(1, "1000000000000000000");
        assert.equal((await daoMine.user(1, a2.address)).lpAmount.toString(), new BN("1000000000000000000"), "The user 2 should have correct LP token balance in DAOmine");
        assert.equal((await daoMine.user(1, a2.address)).finishedDVD.toString(), 0, "The user 2 should have correct finished DVG token amount in DAOmine");
        assert.equal((await lpToken1.balanceOf(a2.address)).toString(), new BN("1000000000000000000"), "The user 2 should have correct balance in LP token");
        assert.equal((await lpToken1.allowance(a2.address, daoMine.address)).toString(), 0, "The DAOmine should have correct allowance from user 2 in LP token");
        
        // user 1 deposits some (0.1) LP token 1 again
        tx = await daoMine.connect(a1).deposit(1, "100000000000000000");
        assert.equal((await daoMine.user(1, a1.address)).lpAmount.toString(), new BN("600000000000000000"), "The user 1 should have correct LP token balance in DAOmine");
        assert.equal((await daoMine.user(1, a1.address)).finishedDVD.toString(), 0, "The user 1 should have correct finished DVG token amount in DAOmine");
        assert.equal((await lpToken1.balanceOf(a1.address)).toString(), new BN("400000000000000000"), "The user 1 should have correct balance in LP token");
        assert.equal((await lpToken1.allowance(a1.address, daoMine.address)).toString(), 0, "The DAOmine should have correct allowance from user 1 in LP token");

        // check LP token 1 balance of DAOmine
        assert.equal((await lpToken1.balanceOf(daoMine.address)).toString(), new BN("1600000000000000000"), "The pool 0 should have correct balance in LP token");
    });


    it("Should succeed to withdraw", async () => {
        // add 2 new pools (pool 1 -> LP token 1, pool weight 1; pool 2 -> LP token 2, pool weight 2)
        await daoMine.addPool(lpToken1.address, 1, true);
        await daoMine.addPool(lpToken2.address, 2, true);


        // 2 users deposit some LP token 1 (user 1 -> 0.6, user 2 -> 1)
        await lpToken1.approve(daoMine.address, new BN("600000000000000000"), {from:a1.address});
        await daoMine.connect(a1).deposit(1, "600000000000000000");
        await lpToken1.approve(daoMine.address, new BN("1000000000000000000"), {from:a2.address});
        await daoMine.connect(a2).deposit(1, "1000000000000000000");

        // user 1 withdraws some (0.5) LP token 1
        await daoMine.connect(a1).withdraw(1, "500000000000000000");
        assert.equal((await daoMine.user(1, a1.address)).lpAmount.toString(), new BN("100000000000000000"), "The user 1 should have correct LP token balance in DAOmine");
        assert.equal((await lpToken1.balanceOf(a1.address)).toString(), new BN("900000000000000000"), "The user 1 should have correct balance in LP token");

        // user 2 withdraws all (1) LP token 1
        await daoMine.connect(a2).withdraw(1, "1000000000000000000");
        assert.equal((await daoMine.user(1, a2.address)).lpAmount.toString(), 0, "The user 2 should have correct LP token balance in DAOmine");
        assert.equal((await lpToken1.balanceOf(a2.address)).toString(), new BN("2000000000000000000"), "The user 1 should have correct balance in LP token smart contract");

        // user 1 withdraws remaining (0.1) LP token 1
        await daoMine.connect(a1).withdraw(1, "100000000000000000");
        assert.equal((await daoMine.user(1, a1.address)).lpAmount.toString(), 0, "The user 1 should have correct LP token balance in DAOmine");
        assert.equal((await lpToken1.balanceOf(a1.address)).toString(), new BN("1000000000000000000"), "The user 1 should have correct balance in LP token smart contract");
        
        // check LP token 1 balance of DAOmine
        assert.equal((await lpToken1.balanceOf(daoMine.address)).toString(), 0, "The pool 0 should have correct balance in LP token");

        // user 1 deposits 0.1 LP token 1 again
        await lpToken1.approve(daoMine.address, new BN("100000000000000000"), {from:a1.address});
        await daoMine.connect(a1).deposit(1, "100000000000000000");
        assert.equal((await daoMine.user(1, a1.address)).lpAmount.toString(), new BN("100000000000000000"), "The user 1 should have correct LP token balance in DAOmine");
        assert.equal((await lpToken1.balanceOf(a1.address)).toString(), new BN("900000000000000000"), "The user 1 should have correct balance in LP token");
        
        // check LP token 1 balance of DAOmine
        assert.equal((await lpToken1.balanceOf(daoMine.address)).toString(), new BN("100000000000000000"), "The pool 0 should have correct balance in LP token");
    });

    
    it("Should succeed to emergency withdraw", async () => {
        // add 1 new pool (pool 0 -> LP token 1, pool weight 1)
        await daoMine.addPool(lpToken1.address, 1, true);

        // user 1 deposits some (0.5) LP token 1 
        await lpToken1.approve(daoMine.address, new BN("600000000000000000"), {from:a1.address});
        await daoMine.connect(a1).deposit(1, "500000000000000000");
        assert.equal((await lpToken1.balanceOf(a1.address)).toString(), new BN("500000000000000000"), "The user 1 should have correct balance in LP token");
        assert.equal((await daoMine.user(1, a1.address)).lpAmount.toString(), new BN("500000000000000000"), "The user 1 should have correct LP token balance in DAOmine");

        // user 1 emergency withdraws LP token 1 
        await daoMine.connect(a1).emergencyWithdraw(1);
        assert.equal((await lpToken1.balanceOf(a1.address)).toString(), new BN("1000000000000000000"), "The user 1 should have correct balance in LP token");
        assert.equal((await daoMine.user(1, a1.address)).lpAmount, 0, "The user 1 should have correct LP token balance in DAOmine");
        assert.equal((await daoMine.user(1, a1.address)).finishedDVD, 0, "The user 1 should have zero finished DVG amount in DAOmine");
    });


    it("Should record, mint and distribute DVDs properly", async () => {
        // add 4 new pools (pool 0 -> LP token 1, pool weight 1; pool 1 -> LP token 2, pool weight 2; pool 2 -> LP token 3, pool weight 3; pool 3 -> LP token 4, pool weight 4)
        await daoMine.addPool(lpToken1.address, 100, true);
        await daoMine.addPool(lpToken2.address, 200, true);
        await daoMine.addPool(lpToken3.address, 100, true);
        await daoMine.addPool(lpToken4.address, 200, true);

        // 2 users deposit LP token 1 (user 1 -> 0.5, user 2 -> 1)
        await lpToken1.approve(daoMine.address, new BN("500000000000000000"), {from:a1.address});
        await daoMine.connect(a1).deposit(1, "500000000000000000");
        await lpToken1.approve(daoMine.address, new BN("1000000000000000000"), {from:a2.address});
        await daoMine.connect(a2).deposit(1, "1000000000000000000");

        // 5 users deposit LP token 2 (user 1 -> 0.5, user 2 -> 1, user 3 -> 1.5, user 4 -> 2, user 5 -> 2.5)
        for (i = 0; i < 5; i++) {
            await lpToken2.approve(daoMine.address, new BN((500000000000000000 * i).toString()), {from:accounts[i].address});
            await daoMine.connect(accounts[i]).deposit(2, (500000000000000000 * i).toString());
        }

        await advanceBlockTo(await daoMine.START_BLOCK());

        await daoMine.massUpdatePools();
        for (i = 0; i < 5; i++) {
            const pool = await daoMine.pool(i);
            assert.equal(pool["lastRewardBlock"], parseInt(await daoMine.START_BLOCK()) + 1, "The pool should have correct lastRewardBlock");
        }
        
        // DVD amount for Treasury wallet: 30(dvgPerBlock) * 24.5%(treasuryWalletPercent) = 7.35
        assert.equal((await dvd.balanceOf(network_.Global.treasuryWalletAddr)).toString(), ethers.utils.parseEther("7.35"), "The Treasury wallet should have correct balance of DVD");
        
        // DVD amount for Community wallet: because pool 0, 3, 4 have no user/LP token, so the DVDs distribuited to them will be distributed to Community wallet 
        // 30(dvgPerBlock) * 24.5%(communityWalletPercent) + 
        // 30(dvgPerBlock) * 51%(poolPercent) * (200/800)(pool4Weight/totalWeight) +
        // 30(dvgPerBlock) * 51%(poolPercent) * (100/800)(pool3Weight/totalWeight) + 
        // 30(dvgPerBlock) * 51%(poolPercent) * (200/800)(pool4Weight/totalWeight) = 16.9125
        assert.equal((await dvd.balanceOf(network_.Global.communityWalletAddr)).toString(), ethers.utils.parseEther("16.9125"), "The Community wallet should have correct balance of DVD");

        // DVG amount for pool:
        // 30(dvgPerBlock) * 51%(poolPercent) * (100/800)(pool3Weight/totalWeight) + 
        // 30(dvgPerBlock) * 51%(poolPercent) * (200/800)(pool4Weight/totalWeight) = 5.7375
        assert.equal((await dvd.balanceOf(daoMine.address)).toString(), ethers.utils.parseEther("5.7375"), "The DAOmine should have correct balance of DVD"); 
    });
});