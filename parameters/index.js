module.exports = {
  mainnet: {
    Global: {
      proxyAdmin: "0x59E83877bD248cBFe392dbB5A8a29959bcb48592",
      treasuryWalletAddr: "0x59E83877bD248cBFe392dbB5A8a29959bcb48592",  // TODO: Update with correct value
      communityWalletAddr: "0xdd6c35aFF646B2fB7d8A8955Ccbe0994409348d0",  // TODO: Update with correct value
    },
    DVD: {
      tokenAddress: "0x77dcE26c03a9B833fc2D7C31C22Da4f42e9d9582",
      ownerAddress: "0xcab7a9239b94a51908d6CF522cE72B5Be5058402",  // This is used only hardhat test, no needed for deployment
      vaultAddress: "0xcab7a9239b94a51908d6CF522cE72B5Be5058402",  // This is used only hardhat test, no needed for deployment
    },
    xDVD: {
      tokenAddress: "0x1193c036833B0010fF80a3617BBC94400A284338",  // TODO: Update after DVD deployed on Mainnet
    },
    DAOmine: {
      startBlock: 12910300,  // TODO: Update with correct value. First block that DAOstake will start from
      xdvdPoolWeight: 200,
      tierBonusRate: [0, 20, 30, 50],  // Tier multiplier: 1x(no xDVD), 1.2x, 1.3x, 1.5x
      earlyWithdrawalPenaltyPeriod: 259200,  // 3 days in second
      earlyWithdrawalPenaltyPercent: 50,  // 50%
    }
  },
  kovan: {
    Global: {
      proxyAdmin: "0x59E83877bD248cBFe392dbB5A8a29959bcb48592",
      treasuryWalletAddr: "0x59E83877bD248cBFe392dbB5A8a29959bcb48592",  // TODO: Update with correct value
      communityWalletAddr: "0xdd6c35aFF646B2fB7d8A8955Ccbe0994409348d0",  // TODO: Update with correct value
    },
    DVD: {
      tokenAddress: "0x77dcE26c03a9B833fc2D7C31C22Da4f42e9d9582",
      ownerAddress: "0xcab7a9239b94a51908d6CF522cE72B5Be5058402",  // This is used only hardhat test, no needed for deployment
      vaultAddress: "0xcab7a9239b94a51908d6CF522cE72B5Be5058402",  // This is used only hardhat test, no needed for deployment
    },
    xDVD: {
      tokenAddress: "0x1193c036833B0010fF80a3617BBC94400A284338",  // TODO: Update after DVD deployed on Mainnet
    },
    DAOmine: {
      startBlock: 12910350,  // TODO: Update with correct value. First block that DAOstake will start from
      xdvdPoolWeight: 200,
      tierBonusRate: [0, 20, 30, 50],  // Tier multiplier: 1x(no xDVD), 1.2x, 1.3x, 1.5x
      earlyWithdrawalPenaltyPeriod: 259200,  // 3 days in second
      earlyWithdrawalPenaltyPercent: 50,  // 50%
    }
  },
};
