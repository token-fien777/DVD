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
  const dvg = await DVGToken.deploy("0xd91Fbc9b431464D737E1BC4e76900D43405a639b", new BN("0").toString());

  await dvg.deployed();

  console.log("DVG token smart contract address:", dvg.address);
  console.log("DVG token name:", await dvg.name());
  console.log("DVG token symbol:", await dvg.symbol());
  console.log("DVG token decimals:", await dvg.decimals());
  console.log("DVG token total supply:", (await dvg.totalSupply()).toString());
  console.log("DVG token amount of account:", (await dvg.balanceOf("0xd91Fbc9b431464D737E1BC4e76900D43405a639b")).toString());


  // const AnyDVGWrapper = await hre.ethers.getContractFactory("AnyDVGWrapper");
  // const dvgWrapper = await AnyDVGWrapper.deploy(dvg.address, "MPC address");

  // await dvgWrapper.deployed();

  // console.log("AnyDVGWrapper smart contract address:", dvgWrapper.address);
  // console.log("AnyDVGWrapper name:", await dvgWrapper.name());
  // console.log("AnyDVGWrapper symbol:", await dvgWrapper.symbol());
  // console.log("AnyDVGWrapper decimals:", await dvgWrapper.decimals());
  // console.log("AnyDVGWrapper DVG token:", await dvgWrapper.underlying());
  // console.log("AnyDVGWrapper vault:", await dvgWrapper.vault());

  // await dvg.addMinter(dvgWrapper.address);
  // console.log("DVG token minters:", await dvg.getAllMinters());
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
