const {BN, constants, expectEvent} = require('@openzeppelin/test-helpers');
const { ethers, upgrades } = require("hardhat");

let DAOventuresTokenImplementation, amount, dvd, deployer, user;

describe("DVD", function () {
  beforeEach(async () => {
    DAOventuresTokenImplementation = await ethers.getContractFactory("DAOventuresTokenImplementation");
    [deployer, user] = await ethers.getSigners();
    amount = await ethers.utils.parseEther("100");

    dvd = await upgrades.deployProxy(DAOventuresTokenImplementation, ["DAOventuresDeFi", "DVD", deployer.address, amount]);  
    await dvd.deployed();
  });

  it("Should successfully deploy DVD wiyh correct information", async () => {
    assert.equal(await dvd.name(), 'DAOventuresDeFi', 'DVD token name disagreement');
    assert.equal(await dvd.symbol(), 'DVD', 'DVD token symbol disagreement');
    assert.equal(await dvd.decimals(), 18, 'DVD token decimals disagreement');
    assert.equal((await dvd.totalSupply()).toString(), amount, 'DVD token supply disagreement');
    assert.equal(await dvd.owner(), deployer.address, 'DVD token owner disagreement');
    assert.equal((await dvd.balanceOf(deployer.address)).toString(), amount, 'should mint some DVDs to owner in advance when deploying');
  });

  it("Should successfully burn DVD", async () => {
    await dvd.burn(await ethers.utils.parseEther("10"));
    assert.equal((await dvd.balanceOf(deployer.address)).toString(), await ethers.utils.parseEther("90"), 'should burn some DVDs');

    await dvd.approve(user.address, await ethers.utils.parseEther("20"));
    assert.equal((await dvd.allowance(deployer.address, user.address)).toString(), await ethers.utils.parseEther("20"), 'should approve some DVDs to user');

    await dvd.connect(user).burnFrom(deployer.address, await ethers.utils.parseEther("10"));
    assert.equal((await dvd.allowance(deployer.address, user.address)).toString(), await ethers.utils.parseEther("10"), 'should decute allowance');
    assert.equal((await dvd.balanceOf(deployer.address)).toString(), await ethers.utils.parseEther("80"), 'should burn some DVDs from deployer');
  });

});
