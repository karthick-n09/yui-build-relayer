require("@nomicfoundation/hardhat-toolbox");
require("@openzeppelin/hardhat-upgrades");
require("@matterlabs/hardhat-zksync-deploy");


const mnemonic =
  "math razor capable expose worth grape metal sunset metal sudden usage scheme";

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  solidity: {
    version: "0.8.20",
    settings: {
      optimizer: {
        enabled: true,
        runs: 9_999_999
      }
    },
  },
  networks: {
    ibc0: {
      url: "http://geth0-scaffold:8545",
      accounts: {
        mnemonic: mnemonic,
      },
      chainId: 2018,
    },
    ibc1: {
      url: "http://geth1-scaffold:8545",
      accounts: {
        mnemonic: mnemonic,
      },
      chainId: 2019,
    },
    testnet:{
      url: "http://127.0.0.1:1122/",
      accounts: ["0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"]
    },
    opnet:{
      url: "https://opt-sepolia.g.alchemy.com/v2/06FpnU4zuFmBgqTE-ziJPggMOEGlQ6mw",
      // accounts: ["e765b53056fac590db941b6192ee484503e965330222ca972ba44f107e57f1f5"]
      accounts: ["21b786729922c6c70ce0b6a8615c291811c76fb84c15c142a48f285648078dfe"]
    },
    basenet:{
      url: "https://base-sepolia.g.alchemy.com/v2/06FpnU4zuFmBgqTE-ziJPggMOEGlQ6mw",
      accounts: ["e765b53056fac590db941b6192ee484503e965330222ca972ba44f107e57f1f5"]
      // accounts: ["21b786729922c6c70ce0b6a8615c291811c76fb84c15c142a48f285648078dfe"]
    },
    zksyncnet:{
      url: "https://zksync-sepolia.g.alchemy.com/v2/06FpnU4zuFmBgqTE-ziJPggMOEGlQ6mw",
      accounts: ["e765b53056fac590db941b6192ee484503e965330222ca972ba44f107e57f1f5"]
    },
    zkTestnet: {
      url: "https://sepolia.era.zksync.dev",
      // ethNetwork: "https://zksync-sepolia.g.alchemy.com/v2/06FpnU4zuFmBgqTE-ziJPggMOEGlQ6mw", 
      ethNetwork: "sepolia", 
      zksync: true, 
    },
    dapoa: {
      url: "http://localhost:40000",
      accounts: ["21b786729922c6c70ce0b6a8615c291811c76fb84c15c142a48f285648078dfe"]
    },
    localhost: {
      url: "http://localhost:8545",
      accounts: ["0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"]
    },
    anvil: {
      url: "http://127.0.0.1:8545",
      accounts: ["0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"]
    }
  }
}
