const { ethers } = require("hardhat");
const { kovan: network_ } = require("../../parameters");

module.exports = async ({ deployments }) => {
  const { deploy } = deployments;
  const [deployer] = await ethers.getSigners();

  console.log("Now deploying DAOvvipUpgradeable on Kovan...");

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

  console.log("Now deploying DAOvvipUpgradeableProxy on Kovan...");
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
module.exports.tags = ["kovan_DAOvvipUpgradeable_deploy"];
