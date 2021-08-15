const { ethers, network } = require("hardhat");
const { mainnet: network_ } = require("../../parameters");

module.exports = async ({ deployments }) => {
  const [deployer] = await ethers.getSigners();

  await network.provider.request({method: "hardhat_impersonateAccount", params: [network_.DVD.ownerAddress]});

  const daoMineArtifact = await deployments.getArtifact("DAOmineUpgradeable");
  const daoMineProxyContract = await ethers.getContract("DAOmineUpgradeableProxy")
  const daoMine = new ethers.Contract(daoMineProxyContract.address, daoMineArtifact.abi, deployer);

  const daoVvipArtifact = await deployments.getArtifact("DAOvvipUpgradeable");
  const daoVvipProxyContract = await ethers.getContract("DAOvvipUpgradeableProxy")
  const daoVvip = new ethers.Contract(daoVvipProxyContract.address, daoVvipArtifact.abi, deployer);

  await daoMine.addPool(daoVvip.address, network_.DAOmine.xdvdPoolWeight, true);
  await daoMine.setDAOvvip(daoVvip.address);
  await daoMine.setBonusForLockedCapital(network_.DAOvvip.lockDays, network_.DAOvvip.lockBonusRate);
  await daoMine.setEarlyHarvestPenalty(network_.DAOvvip.earlyHarvestPenaltyPeriod, network_.DAOvvip.earlyHarvestPenaltyPercent);

  await daoVvip.setDAOmine(daoMine.address);
};
module.exports.tags = ["hardhat_DAOmine_DAOvvip"];
module.exports.dependencies = [
  "hardhat_DAOmine_DAOvip",
];
