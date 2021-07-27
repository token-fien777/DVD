const { ethers } = require("hardhat");
const { mainnet: network_ } = require("../../parameters");

module.exports = async ({ deployments }) => {
  const { deploy } = deployments;
  const [deployer] = await ethers.getSigners();

  console.log("Now deploying DAOmineUpgradeable on Mainnet...");

  const impl = await deploy("DAOmineUpgradeable", {
    from: deployer.address,
  });
  console.log("DAOmineUpgradeable impl address: ", impl.address);

  const implArtifact = await deployments.getArtifact("DAOmineUpgradeable");
  const iface = new ethers.utils.Interface(JSON.stringify(implArtifact.abi));
  const data = iface.encodeFunctionData("initialize", [
      network_.Global.treasuryWalletAddr,
      network_.Global.communityWalletAddr,
      network_.DVD.tokenAddress,
      network_.xDVD.tokenAddress,
      network_.DAOmine.xdvdPoolWeight,
      network_.DAOmine.tierBonusRate,
      network_.DAOmine.earlyWithdrawalPenaltyPeriod,
      network_.DAOmine.earlyWithdrawalPenaltyPercent,
      network_.DAOmine.startBlock,
  ]);

  const proxy = await deploy("DAOmineUpgradeableProxy", {
    from: deployer.address,
    args: [
      impl.address,
      network_.Global.proxyAdmin,
      data,
    ],
  });
  console.log("DAOmineUpgradeable proxy address: ", proxy.address);
};
module.exports.tags = ["mainnet_DAOmineUpgradeable_deploy"];
