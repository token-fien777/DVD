const { ethers } = require("hardhat");
const { mainnet: network_ } = require("../../parameters");

module.exports = async ({ deployments }) => {
  const { deploy } = deployments;
  const [deployer] = await ethers.getSigners();

  console.log("Now deploying DAOvvipUpgradeable on Mainnet...");

  const impl = await deploy("DAOvvipUpgradeable", {
    from: deployer.address,
  });
  console.log("DAOvvipUpgradeable impl address: ", impl.address);

  const implArtifact = await deployments.getArtifact("DAOvvipUpgradeable");
  const iface = new ethers.utils.Interface(JSON.stringify(implArtifact.abi));
  const data = iface.encodeFunctionData("initialize", [
      network_.DVD.tokenAddress,
      network_.DAOvvip.tierAmounts,
  ]);

  console.log("Now deploying DAOvvipUpgradeableProxy on Mainnet...");
  const proxy = await deploy("DAOvvipUpgradeableProxy", {
    from: deployer.address,
    args: [
      impl.address,
      network_.Global.proxyAdmin,
      data,
    ],
  });
  console.log("DAOvvipUpgradeable proxy address: ", proxy.address);
};
module.exports.tags = ["mainnet_DAOvvipUpgradeable_deploy"];
