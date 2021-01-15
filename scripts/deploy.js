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
  const dvg = await DVGToken.deploy('Your account address', new BN('The amount of DVGs minted in advance').toString());

  await dvg.deployed();

  console.log("DVG token smart contract address:", dvg.address);
  console.log("DVG token name:", await dvg.name());
  console.log("DVG token symbol:", await dvg.symbol());
  console.log("DVG token decimals:", await dvg.decimals());
  console.log("DVG token total supply:", (await dvg.totalSupply()).toString());
  console.log("DVG token amount of account:", (await dvg.balanceOf('Your account address')).toString());
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
