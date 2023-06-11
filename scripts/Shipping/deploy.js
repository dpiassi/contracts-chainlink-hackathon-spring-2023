const { ethers, network, run } = require("hardhat")
const {
    VERIFICATION_BLOCK_CONFIRMATIONS,
    networkConfig,
    developmentChains,
} = require("../../helper-hardhat-config")
const LINK_TOKEN_ABI = require("@chainlink/contracts/abi/v0.4/LinkToken.json")

// Loads environment variables from .env.enc file (if it exists)
require("@chainlink/env-enc").config()

async function deployApiConsumer(chainId) {
    //set log level to ignore non errors
    // ethers.utils.Logger.setLogLevel(ethers.utils.Logger.levels.ERROR)

    const accounts = await ethers.getSigners()
    const deployer = accounts[0]

    let linkToken
    let mockOracle
    let linkTokenAddress
    let oracleAddress

    if (chainId == 31337) {
        const linkTokenFactory = await ethers.getContractFactory("LinkToken")
        linkToken = await linkTokenFactory.connect(deployer).deploy()

        const mockOracleFactory = await ethers.getContractFactory("MockOracle")
        mockOracle = await mockOracleFactory.connect(deployer).deploy(linkToken.address)

        linkTokenAddress = linkToken.address
        oracleAddress = mockOracle.address
    } else {
        oracleAddress = networkConfig[chainId]["oracle"]
        linkTokenAddress = networkConfig[chainId]["linkToken"]
        linkToken = new ethers.Contract(linkTokenAddress, LINK_TOKEN_ABI, deployer)
    }

    const jobId = ethers.utils.toUtf8Bytes(networkConfig[chainId]["jobId"])
    const fee = networkConfig[chainId]["fee"]

    const apiConsumerFactory = await ethers.getContractFactory("Shipping")
    const apiConsumer = await apiConsumerFactory.deploy(oracleAddress, jobId, fee, linkTokenAddress)

    console.log(`Deploying contract with parameters:`)
    console.log(`- oracleAddress: ${oracleAddress}`)
    console.log(`- jobId: ${jobId}`)
    console.log(`- fee: ${fee}`)
    console.log(`- linkTokenAddress: ${linkTokenAddress}`)

    const waitBlockConfirmations = developmentChains.includes(network.name)
        ? 1
        : VERIFICATION_BLOCK_CONFIRMATIONS
    await apiConsumer.deployTransaction.wait(waitBlockConfirmations)

    console.log(`Shipping (APIConsumer) deployed to ${apiConsumer.address} on ${network.name}`)

    // if (!developmentChains.includes(network.name) && process.env.ETHERSCAN_API_KEY) {
    //     await run("verify:verify", {
    //         address: apiConsumer.address,
    //         constructorArguments: [oracleAddress, jobId, fee, linkTokenAddress],
    //     })
    // }

    // auto-funding
    const fundAmount = networkConfig[chainId]["fundAmount"]
    await linkToken.transfer(apiConsumer.address, fundAmount)

    console.log(`Shipping (APIConsumer) funded with ${fundAmount} JUELS`)
}

module.exports = {
    deployApiConsumer,
}