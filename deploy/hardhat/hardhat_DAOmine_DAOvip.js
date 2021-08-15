const { ethers, network } = require("hardhat");
const { mainnet: network_ } = require("../../parameters");
const EIP173Proxy_ABI = require('../../abis/EIP173Proxy_ABI.json');

module.exports = async ({ deployments }) => {
  const [deployer] = await ethers.getSigners();

  const impl = await ethers.getContract("xDVD");

  await network.provider.request({method: "hardhat_impersonateAccount", params: [network_.DVD.ownerAddress]});
  await network.provider.request({method: "hardhat_impersonateAccount", params: [network_.xDVD.proxyAdmin]});

  const proxyAdmin = await ethers.getSigner(network_.xDVD.proxyAdmin);
  const xdvdProxy = new ethers.Contract(network_.xDVD.tokenAddress, EIP173Proxy_ABI, deployer);
  await xdvdProxy.connect(proxyAdmin).upgradeTo(impl.address);

  const owner = await ethers.getSigner(network_.xDVD.ownerAddress);
  const implArtifact = await deployments.getArtifact("xDVD");
  const xdvd = new ethers.Contract(network_.xDVD.tokenAddress, implArtifact.abi, deployer);
  await xdvd.connect(owner).initOwner(owner.address);

  await xdvd.connect(owner).setTierAmount([
    "1000000000000000000000", // 1K
    "10000000000000000000000", // 10K
  ]);
};
module.exports.tags = ["hardhat_DAOmine_DAOvip"];
module.exports.dependencies = [
  "hardhat_reset",
  "mainnet_xDVD_v2_deploy",
  "mainnet",
];
