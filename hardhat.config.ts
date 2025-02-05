import "dotenv/config"
import "@nomiclabs/hardhat-waffle"
import "@nomicfoundation/hardhat-foundry"

// This adds support for typescript paths mappings
import "tsconfig-paths/register"

const ALCHEMY_TOKEN = process.env.ALCHEMY_TOKEN || ""

module.exports = {
    networks: {
        hardhat: {
            forking: {
                chainId: 1,
                url: `https://eth-mainnet.g.alchemy.com/v2/${ALCHEMY_TOKEN}`,
                blockNumber: 17287570,
            },
        },
        base: {
            chainId: 8453,
            url: "https://mainnet.base.org",
        },
        base_sepolia: {
            chainId: 84532,
            url: "https://sepolia.base.org",
        },
    },
    solidity: {
        settings: {
            remappings: [
                "@openzeppelin/=lib/openzeppelin-contracts/",
                "@forge-std/=lib/forge-std/src/",
            ],
        },
        compilers: [
            {
                version: "0.8.21",
                settings: {
                    optimizer: {
                        enabled: true,
                        runs: 1000,
                    },
                },
            },
        ],
    },
}
