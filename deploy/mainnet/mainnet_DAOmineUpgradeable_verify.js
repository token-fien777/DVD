const { ethers, run } = require("hardhat");
const { mainnet: network_ } = require("../../parameters");

module.exports = async ({ deployments }) => {
  const impl = await ethers.getContract("DAOmineUpgradeable");
  try {
    await run("verify:verify", {
      address: impl.address,
      contract: "contracts/DAOmine/DAOmineUpgradeable.sol:DAOmineUpgradeable",
    });
  } catch (e) {
  }

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

  const proxy = await ethers.getContract("DAOmineUpgradeableProxy");
  try {
    await run("verify:verify", {
      address: proxy.address,
      constructorArguments: [
        impl.address,
        network_.Global.proxyAdmin,
        data,
      ],
      contract: "contracts/DAOmine/DAOmineUpgradeableProxy.sol:DAOmineUpgradeableProxy",
    });
  } catch (e) {
  }
};
module.exports.tags = ["mainnet_DAOmineUpgradeable_verify"];
