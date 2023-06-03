import "@nomicfoundation/hardhat-toolbox";
import "dotenv/config"; // Don't forget to import dotenv
import { HardhatUserConfig } from "hardhat/config";

// Go to https://infura.io, sign up, create a new API key
// in its dashboard, and replace "KEY" with it
const INFURA_API_KEY = "71e3c46743934adaa7512cfe2d25c5ec";

// Replace this private key with your Sepolia account private key
// To export your private key from Coinbase Wallet, go to
// Settings > Developer Settings > Show private key
// To export your private key from Metamask, open Metamask and
// go to Account Details > Export Private Key
// Beware: NEVER put real Ether into testing accounts
const SEPOLIA_PRIVATE_KEY = process.env.SEPOLIA_PRIVATE_KEY!;

console.log("SEPOLIA_PRIVATE_KEY", SEPOLIA_PRIVATE_KEY)

const config: HardhatUserConfig = {
  solidity: "0.8.18",
  mocha: {
    timeout: 100000000,
  },
  networks: {
    sepolia: {
      url: `https://sepolia.infura.io/v3/${INFURA_API_KEY}`,
      accounts: [SEPOLIA_PRIVATE_KEY]
    }
  }
};

export default config;