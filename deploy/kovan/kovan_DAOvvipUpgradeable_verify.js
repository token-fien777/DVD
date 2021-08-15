const { ethers, run } = require("hardhat");
const { kovan: network_ } = require("../../parameters");

module.exports = async ({ deployments }) => {
  const impl = await ethers.getContract("DAOvvipUpgradeable");
  try {
    await run("verify:verify", {
      address: impl.address,
      contract: "contracts/DAOvvip/DAOvvipUpgradeable.sol:DAOvvipUpgradeable",
    });
  } catch (e) {
  }

  const implArtifact = await deployments.getArtifact("DAOvvipUpgradeable");
  const iface = new ethers.utils.Interface(JSON.stringify(implArtifact.abi));
  const data = iface.encodeFunctionData("initialize", [
    network_.DVD.tokenAddress,
    network_.DAOvvip.tierAmounts,
  ]);

  const proxy = await ethers.getContract("DAOvvipUpgradeableProxy");
  try {
    await run("verify:verify", {
      address: proxy.address,
      constructorArguments: [
        impl.address,
        network_.Global.proxyAdmin,
        data,
      ],
      contract: "contracts/DAOmine/DAOvvipUpgradeableProxy.sol:DAOvvipUpgradeableProxy",
    });
  } catch (e) {
  }
};
module.exports.tags = ["kovan_DAOvvipUpgradeable_verify"];
