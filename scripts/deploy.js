// We require the Hardhat Runtime Environment explicitly here. This is optional 
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
const hre = require("hardhat");
const BN = require('bn.js');

async function main() {
  // Hardhat always runs the compile task when running scripts with its command
  // line interface.
  //
  // If this script is run directly using `node` you may want to call compile 
  // manually to make sure everything is compiled
  // await hre.run('compile');

  // We get the contract to deploy
  const DVGToken = await hre.ethers.getContractFactory("DVGToken");
  const DAOstake = await hre.ethers.getContractFactory("DAOstake");

  const dvg = await DVGToken.deploy(process.env.KOVAN_ACCOUNT, new BN("10000000000000000000").toString());

  await dvg.deployed();

  console.log("DVG token smart contract address:", dvg.address);
  console.log("DVG token name:", await dvg.name());
  console.log("DVG token symbol:", await dvg.symbol());
  console.log("DVG token decimals:", await dvg.decimals());
  console.log("DVG token total supply:", (await dvg.totalSupply()).toString());
  console.log("DVG token amount of account:", (await dvg.balanceOf(process.env.KOVAN_ACCOUNT)).toString());


  const startBlock = await hre.ethers.provider.getBlockNumber() + 50;
  console.log("Start Block number:", startBlock);
  const daoStake = await DAOstake.deploy(
    startBlock,  // startBlock
    2,  // blockPerPeriod
    process.env.KOVAN_ACCOUNT,  // treasuryWalletAddr
    process.env.KOVAN_ACCOUNT,  // communityWalletAddr
    dvg.address,
    new BN("1000000000000000000").toString(),  // precision
    new BN("31000000000000000000").toString(),  // treasuryWalletPercent
    new BN("18000000000000000000").toString(),  // communityWalletPercent
    new BN("51000000000000000000").toString()  // poolPercent
  );

  await daoStake.deployed();

  console.log("DAOsatke smart contract address:", daoStake.address);
  
  await daoStake.setPeriodDVGPerBlock(1, new BN("20000000000000000000").toString());
  await daoStake.setPeriodDVGPerBlock(2, new BN("19600000000000000000").toString());
  await daoStake.setPeriodDVGPerBlock(3, new BN("19208000000000000000").toString());
  await daoStake.setPeriodDVGPerBlock(4, new BN("18823840000000000000").toString());

  await dvg.transferOwnership(daoStake.address);
  console.log("New owner of DVG token:", await dvg.owner());
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
