const {balance, BN, constants, ether, expectEvent, expectRevert, send, time} = require("@openzeppelin/test-helpers");
const { assert, expect } = require("hardhat");
const { modules } = require("web3");
const { add } = require("mathjs");
const {Decimal} = require("decimal.js");

const DVGToken = artifacts.require("DVGToken");
const DAOstake = artifacts.require("DAOstake");
const LPTokenMockup = artifacts.require("LPTokenMockup");

const DVG_IN_ADVANCE = new BN("10000000000000000000");  // 10 DVGs

const PRECISION = new BN("1000000000000000000");  // 1e18
const TRASURY_WALLET_PERCENT = new BN("31000000000000000000");  // 31%
const COMMUNITY_WALLET_PERCENT = new BN("18000000000000000000");  // 18%
const POOL_PERCENT = new BN("51000000000000000000");  //51%

var dvg, daoStake, lpToken1, lpToken2, startBlock, tx;

contract("DAOstake for failure", async (accounts) => {
    const TRASURY_WALLET_ADDRESS = accounts[9];
    const COMMUNITY_WALLET_ADDRESS = accounts[10];

    
    beforeEach(async () => {   
        // LP token 1     
        lpToken1 = await LPTokenMockup.new("LPToken1", "lp1");
        await lpToken1.mint(accounts[1], new BN("1000000000000000000"));
        await lpToken1.mint(accounts[2], new BN("2000000000000000000"));
        // LP token 2
        lpToken2 = await LPTokenMockup.new("LPToken2", "lp2");
        for (i = 1; i < 6; i++) {
            await lpToken2.mint(accounts[i], new BN((1000000000000000000 * i).toString()));
        }
        // LP token 3
        lpToken3 = await LPTokenMockup.new("LPToken3", "lp3");
        // LP token 4
        lpToken4 = await LPTokenMockup.new("LPToken4", "lp4");
        
        dvg = await DVGToken.new(TRASURY_WALLET_ADDRESS, DVG_IN_ADVANCE);

        startBlock = (await time.latestBlock()).toNumber() + 30;
        daoStake = await DAOstake.new(
            startBlock,  // startBlock
            2,  // blockPerPeriod
            TRASURY_WALLET_ADDRESS,  // treasuryWalletAddr
            COMMUNITY_WALLET_ADDRESS,  // communityWalletAddr
            dvg.address,
            PRECISION,  // precision
            TRASURY_WALLET_PERCENT,  // treasuryWalletPercent
            COMMUNITY_WALLET_PERCENT,  // communityWalletPercent
            POOL_PERCENT  // poolPercent
        );
        await expectEvent.inConstruction(daoStake, "SetBlockPeriod", {startBlock:startBlock.toString(), blockPerPeriod:"2"});
        await expectEvent.inConstruction(daoStake, "SetWalletAddress", {treasuryWalletAddr:TRASURY_WALLET_ADDRESS, communityWalletAddr:COMMUNITY_WALLET_ADDRESS});
        await expectEvent.inConstruction(daoStake, "SetDVGAddress", {dvgAddr:dvg.address});
        await expectEvent.inConstruction(daoStake, "SetPrecision", {precision:new BN("1000000000000000000")});
        await expectEvent.inConstruction(daoStake, "SetPercent", {treasuryWalletPercent:TRASURY_WALLET_PERCENT, communityWalletPercent:COMMUNITY_WALLET_PERCENT, poolPercent:POOL_PERCENT});

        assert.equal(await daoStake.startBlock(), startBlock, "The startBlock disagreement");
        assert.equal(await daoStake.blockPerPeriod(), 2, "The blockPerPeriod disagreement");
        assert.equal(await daoStake.treasuryWalletAddr(), TRASURY_WALLET_ADDRESS, "The Treasury wallet address disagreement");
        assert.equal(await daoStake.communityWalletAddr(), COMMUNITY_WALLET_ADDRESS, "The Community wallet address disagreement");
        assert.equal(await daoStake.dvgAddr(), dvg.address, "The DVG address disagreement");
        assert.equal((await daoStake.precision()).toString(), PRECISION, "The precision disagreement");
        assert.equal((await daoStake.hundredPercent()).toString(), PRECISION * 100, "The hundred percent with precision disagreement");
        assert.equal((await daoStake.treasuryWalletPercent()).toString(), TRASURY_WALLET_PERCENT, "The Treasury wallet percent disagreement");        
        assert.equal((await daoStake.communityWalletPercent()).toString(), COMMUNITY_WALLET_PERCENT, "The Community wallet percent disagreement");
        assert.equal((await daoStake.poolPercent()).toString(),POOL_PERCENT, "The pool percent disagreement");
        assert.equal(await daoStake.totalPoolWeight(), 0, "The total pool weight disagreement");

        // mint and distribute 20 DVGs per block in the first period
        tx = await daoStake.setPeriodDVGPerBlock(1, new BN("20000000000000000000"));
        await expectEvent(tx, "SetPeriodDVGPerBlock", {periodId:"1", dvgPerBlock:new BN("20000000000000000000")});
        // mint and distribute 20 * 98% DVGs per block in the second period
        tx = await daoStake.setPeriodDVGPerBlock(2, new BN("19600000000000000000"));
        await expectEvent(tx, "SetPeriodDVGPerBlock", {periodId:"2", dvgPerBlock:new BN("19600000000000000000")});
        // mint and distribute 20 * 98% * 98% DVGs per block in the third period
        tx = await daoStake.setPeriodDVGPerBlock(3, new BN("19208000000000000000"));
        await expectEvent(tx, "SetPeriodDVGPerBlock", {periodId:"3", dvgPerBlock:new BN("19208000000000000000")});
        // mint and distribute 20 * 98% * 98% * 98% DVGs per block in the fourth period
        tx = await daoStake.setPeriodDVGPerBlock(4, new BN("18823840000000000000"));
        await expectEvent(tx, "SetPeriodDVGPerBlock", {periodId:"4", dvgPerBlock:new BN("18823840000000000000")});

        assert.equal((await daoStake.periodDVGPerBlock(1)).toString(), new BN("20000000000000000000"), "The DVG amount per block of period 1 disagreement");
        assert.equal((await daoStake.periodDVGPerBlock(2)).toString(), new BN("19600000000000000000"), "The DVG amount per block of period 2 disagreement");
        assert.equal((await daoStake.periodDVGPerBlock(3)).toString(), new BN("19208000000000000000"), "The DVG amount per block of period 3 disagreement");
        assert.equal((await daoStake.periodDVGPerBlock(4)).toString(), new BN("18823840000000000000"), "The DVG amount per block of period 4 disagreement");

        await dvg.transferOwnership(daoStake.address);
        assert.equal(await dvg.owner(), daoStake.address, "The owner of DVG should be DAOstake");
    });

    it("Should fail to set DVG per block of period with wrong params", async() => {
        await expectRevert(daoStake.setPeriodDVGPerBlock(0, 1), "Period id should larger than zero");
    });

    it("Should fail to set wallet address with wrong params", async() => {
        await expectRevert(daoStake.setWalletAddress(lpToken1.address, lpToken2.address), "Any wallet address should not be smart contract address");
    });

    it("Should fail to set DVG address with wrong params", async() => {
        await expectRevert(daoStake.setDVGAddress(constants.ZERO_ADDRESS), "DVG address should be a smart contract address");
        await expectRevert(daoStake.setDVGAddress(accounts[0]), "DVG address should be a smart contract address");
    });

    it("Should fail to set precision with wrong params", async() => {
        await expectRevert(daoStake.setPrecision(0), "Precision should larger than zero");
    });
    
    it("Should fail to set percent with wrong params", async() => {
        await expectRevert(daoStake.setPercent(new BN('100000000000000000000'), new BN('100000000000000000000'), new BN('100000000000000000000')), "Sum of three percents should be 100");
    });

    it("Should fail to add new pool with wrong params", async () => {
        await expectRevert(daoStake.addPool(constants.ZERO_ADDRESS, 0, false), "LP token address should be a smart contract address");
        await expectRevert(daoStake.addPool(accounts[0], 1, false), "LP token address should be a smart contract address");
    });

    it("Should fail to withdraw without enough balance", async () => {
        // add a new pool (pool 0 -> LP token 1, pool weight 1)
        await daoStake.addPool(lpToken1.address, 1, true);

        await lpToken1.approve(daoStake.address, new BN('100000000000000000'), {from:accounts[1]});
        await daoStake.deposit(0, new BN('100000000000000000'), {from:accounts[1]});

        await expectRevert(daoStake.withdraw(0, new BN('200000000000000000'), {from:accounts[1]}), "Not enough LP token balance");
    });
   

});