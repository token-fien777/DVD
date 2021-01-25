const { solidity } = require("ethereum-waffle");

require("@nomiclabs/hardhat-waffle");
require("@nomiclabs/hardhat-truffle5");
require("@nomiclabs/hardhat-web3");
require('dotenv').config();

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  defaultNetwork:"hardhat",

  networks: {
    kovan: {
      url: process.env.KOVAN_URL,
      from: process.env.KOVAN_ACCOUNT,
      accounts: {
        mnemonic: process.env.KOVAN_ACCOUNT_MNEMONIC
      }
    },

    mainnet: {
      url: process.env.MAINNET_URL,
      from: process.env.MAINNET_ACCOUNT,
      accounts: {
        mnemonic: process.env.MAINNET_ACCOUNT_MNEMONIC
      }
    }
  },

  solidity: {
    version: "0.7.6"
  }
};

