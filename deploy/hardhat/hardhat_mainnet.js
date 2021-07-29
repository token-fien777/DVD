const { network } = require("hardhat");
const { mainnet: network_ } = require("../../parameters");

module.exports = async () => {

  await network.provider.request({method: "hardhat_impersonateAccount", params: [network_.DVD.ownerAddress]});
};

module.exports.tags = ["hardhat"];
module.exports.dependencies = [
  "hardhat_reset",
  "mainnet"
];
