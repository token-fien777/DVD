const { solidity } = require("ethereum-waffle");

require("@nomiclabs/hardhat-waffle");
require("@nomiclabs/hardhat-truffle5");
require("@nomiclabs/hardhat-web3");

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  defaultNetwork:"hardhat",

  networks: {
    kovan: {
      url:"The url of the node",
      from:"Your account address",
      accounts: {
        mnemonic: "mnemonic mnemonic mnemonic mnemonic mnemonic mnemonic mnemonic mnemonic mnemonic mnemonic mnemonic mnemonic"
      }
    },

    mainnet: {
      url:"The url of the node",
      from:"Your account address",
      accounts: {
        mnemonic: "mnemonic mnemonic mnemonic mnemonic mnemonic mnemonic mnemonic mnemonic mnemonic mnemonic mnemonic mnemonic"
      }
    }
  },

  solidity: {
    version: "0.7.6"
  }
};

