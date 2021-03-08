const {balance, BN, constants, ether, expectEvent, expectRevert, send, time} = require("@openzeppelin/test-helpers");
const { assert, expect } = require("hardhat");
const { modules } = require("web3");
const { add } = require("mathjs");
const {Decimal} = require("decimal.js");

const DVGToken = artifacts.require("DVGToken");
const DAOstake = artifacts.require("DAOstake");
const LPTokenMockup = artifacts.require("LPTokenMockup");

const DVG_IN_ADVANCE = new BN("10000000000000000000");  // 10 DVGs

let dvg, daoStake, lpToken1, lpToken2, tx;


/*
 * Here the constant variables settings in DAOstake smart contract for the test:
 * uint256 public constant START_BLOCK = 50;
 * uint256 public constant END_BLOCK = 60;
 * uint256 public constant BLOCK_PER_PERIOD = 2;
 * uint256 public constant PERIOD_AMOUNT = 5;
 */ 
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

        daoStake = await DAOstake.new(
            TRASURY_WALLET_ADDRESS,  // treasuryWalletAddr
            COMMUNITY_WALLET_ADDRESS,  // communityWalletAddr
            dvg.address
        );

        await expectEvent.inConstruction(daoStake, "SetWalletAddress", {treasuryWalletAddr:TRASURY_WALLET_ADDRESS, communityWalletAddr:COMMUNITY_WALLET_ADDRESS});
        await expectEvent.inConstruction(daoStake, "SetDVG", {dvg:dvg.address});

        assert.equal(await daoStake.treasuryWalletAddr(), TRASURY_WALLET_ADDRESS, "The Treasury wallet address disagreement");
        assert.equal(await daoStake.communityWalletAddr(), COMMUNITY_WALLET_ADDRESS, "The Community wallet address disagreement");
        assert.equal(await daoStake.dvg(), dvg.address, "The DVG address disagreement");
        assert.equal(await daoStake.totalPoolWeight(), 0, "The total pool weight disagreement");

        for (let i = 1; i <= parseInt(await daoStake.PERIOD_AMOUNT()); i++) {
            assert.equal(parseInt(await daoStake.periodDVGPerBlock(i)), parseInt(ether((20 * (98 ** (i-1)) / (100 ** (i-1))).toString())), `The DVG amount per block for period ${i} disagreement`);
        }

        await dvg.transferOwnership(daoStake.address);
        assert.equal(await dvg.owner(), daoStake.address, "The owner of DVG should be DAOstake");
    });


    it("Should fail to set wallet address with wrong params", async() => {
        await expectRevert(daoStake.setWalletAddress(lpToken1.address, lpToken2.address), "Any wallet address should not be smart contract address");
    });


    it("Should fail to withdraw without enough balance", async () => {
        // add a new pool (pool 0 -> LP token 1, pool weight 1)
        await daoStake.addPool(lpToken1.address, 1, true);

        await lpToken1.approve(daoStake.address, new BN('100000000000000000'), {from:accounts[1]});
        await daoStake.deposit(0, new BN('100000000000000000'), {from:accounts[1]});

        await expectRevert(daoStake.withdraw(0, new BN('200000000000000000'), {from:accounts[1]}), "Not enough LP token balance");
    });


    it("Should fail to add new pool with wrong params", async () => {
        await expectRevert(daoStake.addPool(constants.ZERO_ADDRESS, 0, false), "LP token address should be smart contract address");
        await expectRevert(daoStake.addPool(accounts[0], 1, false), "LP token address should be smart contract address");
        
        await time.advanceBlockTo(await daoStake.END_BLOCK());
        await expectRevert(daoStake.addPool(lpToken1.address, 1, false), "Already ended");
    });
});