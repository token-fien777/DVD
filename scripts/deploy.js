const { ethers, upgrades } = require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();

  const DAOventuresTokenImplementation = await ethers.getContractFactory("DAOventuresTokenImplementation");
  const dvd = await upgrades.deployProxy(DAOventuresTokenImplementation, ["DAOventuresDeFi", "DVD", process.env.ACCOUNT, await ethers.utils.parseEther("100")]);  
  await dvd.deployed();

  console.log("deployer:", deployer.address);
  console.log(
    "Token address:", dvd.address,
    "\nToken owner:", await dvd.owner(),
    "\nToken name:", await dvd.name(),
    "\nToken symbol:", await dvd.symbol(),
    "\nToken decimals:", await dvd.decimals(),
    "\nToken initial supply:", await ethers.utils.formatEther(await dvd.totalSupply()),
    "\nToken balance of account:", await ethers.utils.formatEther(await dvd.balanceOf(process.env.ACCOUNT))
  );
};

main()
.then(() => process.exit(0))
.catch(error => {
  console.error(error);
  process.exit(1);
});