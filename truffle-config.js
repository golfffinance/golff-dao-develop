//++ define Wallet Provider
const HDWalletProvider = require('@truffle/hdwallet-provider')

const fs = require('fs');
const mnemonic = fs.readFileSync(".secret").toString().trim();

module.exports = {
  // See <http://truffleframework.com/docs/advanced/configuration>
  // for more about customizing your Truffle configuration!
  compilers: {
    solc: {
      version: "0.6.12",
      settings: {          // See the solidity docs for advice about optimization and evmVersion
        optimizer: {
          enabled: true,
          runs: 200
        },
        // evmVersion: "byzantium"
      }
    }
  },
  networks: {
    main: {
        provider: () => new HDWalletProvider(mnemonic, `https://bsc-dataseed2.ninicoin.io/`),
        network_id: 56,
        confirmations: 5,
        timeoutBlocks: 200,
        gasPrice: 5000000000,
        networkCheckTimeout: 60000,
        skipDryRun: true,
        // gas: 300000
    },
    test: {
        provider: () => new HDWalletProvider(mnemonic, `https://data-seed-prebsc-1-s1.binance.org:8545/`),
        network_id: 97,
        confirmations: 3,
        timeoutBlocks: 200,
        skipDryRun: true
    }
  }
};
