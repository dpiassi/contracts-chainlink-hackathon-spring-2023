const { network, ethers } = require("hardhat")
const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers")
const { networkConfig, developmentChains } = require("../../helper-hardhat-config")
const { numToBytes32 } = require("../../helper-functions")
const { assert, expect } = require("chai")

const ContractName = "Shipping"
const CallbackEventName = "RequestFulfilled"

!developmentChains.includes(network.name)
    ? describe.skip
    : describe("Shipping (API Consumer) Unit Tests", async function () {
        //set log level to ignore non errors
        ethers.utils.Logger.setLogLevel(ethers.utils.Logger.levels.ERROR)

        // We define a fixture to reuse the same setup in every test.
        // We use loadFixture to run this setup once, snapshot that state,
        // and reset Hardhat Network to that snapshot in every test.
        async function deployAPIConsumerFixture() {
            const [deployer] = await ethers.getSigners()

            const chainId = network.config.chainId

            const linkTokenFactory = await ethers.getContractFactory("LinkToken")
            const linkToken = await linkTokenFactory.connect(deployer).deploy()

            const mockOracleFactory = await ethers.getContractFactory("MockOracle")
            const mockOracle = await mockOracleFactory.connect(deployer).deploy(linkToken.address)

            const jobId = ethers.utils.toUtf8Bytes(networkConfig[chainId]["jobId"])
            const fee = networkConfig[chainId]["fee"]

            const apiConsumerFactory = await ethers.getContractFactory(ContractName)
            const apiConsumer = await apiConsumerFactory
                .connect(deployer)
                .deploy(mockOracle.address, jobId, fee, linkToken.address)

            const fundAmount = networkConfig[chainId]["fundAmount"] || "1000000000000000000"
            await linkToken.connect(deployer).transfer(apiConsumer.address, fundAmount)

            return { apiConsumer, mockOracle }
        }

        async function deployAPIConsumerAndCreateOrderFixture() {
            const { apiConsumer, mockOracle } = await loadFixture(deployAPIConsumerFixture)
            const [deployer] = await ethers.getSigners()
            const transaction = await apiConsumer.createOrder(
                deployer.getAddress(),
                -23464796,
                -46915496,
                -23466680,
                -46915960,
                1688091844
            )
            const transactionReceipt = await transaction.wait(1)
            const newOrderHashRaw = transactionReceipt.events[0].topics[1]
            const newOrderHashString = newOrderHashRaw.toString()
            const newOrderHash = newOrderHashString.replace(/^0x0+/, "0x")
            return { apiConsumer, mockOracle, newOrderHash }
        }


        describe("#createOrder", async function () {
            describe("success", async function () {
                it("Should successfully create an order", async function () {
                    const { newOrderHash } = await loadFixture(deployAPIConsumerAndCreateOrderFixture)
                    console.log(`newOrderHash: ${newOrderHash}`)
                    expect(newOrderHash).to.not.be.null
                })
            })
        })

        describe("#lastCreatedOrder", async function () {
            describe("success", async function () {
                it("Should successfully get the last order address", async function () {
                    const { apiConsumer, newOrderHash } = await loadFixture(deployAPIConsumerAndCreateOrderFixture)
                    const lastCreatedOrder = await apiConsumer.lastCreatedOrder()
                    assert.equal(lastCreatedOrder.toString().toUpperCase(), newOrderHash.toString().toUpperCase())
                })
            })
        })

        describe("#deliverOrder", async function () {
            describe("success", async function () {
                it("Should successfully request last location of specified order as an attempt to mark it as delivered", async function () {
                    const { apiConsumer, newOrderHash } = await loadFixture(deployAPIConsumerAndCreateOrderFixture)
                    console.log(`newOrderHash: ${newOrderHash}`)
                    const transaction = await apiConsumer.deliverOrder(newOrderHash)
                    const transactionReceipt = await transaction.wait(1)
                    const requestId = transactionReceipt.events[0].topics[1]
                    expect(requestId).to.not.be.null
                })
            })
        })

        describe("#requestCurrentLocation", async function () {
            describe("success", async function () {
                it("Should successfully make an API request", async function () {
                    const { apiConsumer, newOrderHash } = await loadFixture(deployAPIConsumerAndCreateOrderFixture)
                    const transaction = await apiConsumer.deliverOrder(newOrderHash)
                    const transactionReceipt = await transaction.wait(1)
                    const requestId = transactionReceipt.events[0].topics[1]
                    expect(requestId).to.not.be.null
                })

                it("Should successfully make an API request and get a result", async function () {
                    const { apiConsumer, mockOracle, newOrderHash } = await loadFixture(
                        deployAPIConsumerAndCreateOrderFixture
                    )
                    const transaction = await apiConsumer.deliverOrder(newOrderHash)
                    const transactionReceipt = await transaction.wait(1)
                    const requestId = transactionReceipt.events[0].topics[1]
                    const callbackValue = 100788622832613250n
                    await mockOracle.fulfillOracleRequest(requestId, numToBytes32(callbackValue))
                    await new Promise(resolve => setTimeout(resolve, 30000))
                    const rawData = await apiConsumer.lastSerializedLocation()
                    console.log(`rawData: ${rawData}`)
                    console.log(`callbackValue: ${callbackValue}`)
                    assert.equal(rawData.toString(), callbackValue.toString())
                })

                // it("Our event should successfully fire event on callback", async function () {
                //     const { apiConsumer, mockOracle, newOrderHash } = await loadFixture(
                //         deployAPIConsumerAndCreateOrderFixture
                //     )
                //     const callbackValue = 100788622832613250n
                //     // we setup a promise so we can wait for our callback from the `once` function
                //     await new Promise(async (resolve, reject) => {
                //         // setup listener for our event
                //         apiConsumer.once(CallbackEventName, async () => {
                //             console.log(`${CallbackEventName} event fired!`)
                //             const rawData = await apiConsumer.lastSerializedLocation()
                //             // assert throws an error if it fails, so we need to wrap
                //             // it in a try/catch so that the promise returns event
                //             // if it fails.
                //             try {
                //                 assert.equal(rawData.toString(), callbackValue.toString())
                //                 resolve()
                //             } catch (e) {
                //                 reject(e)
                //             }
                //         })
                //         const transaction = await apiConsumer.deliverOrder(newOrderHash)
                //         const transactionReceipt = await transaction.wait(1)
                //         const requestId = transactionReceipt.events[0].topics[1]
                //         await mockOracle.fulfillOracleRequest(
                //             requestId,
                //             numToBytes32(callbackValue)
                //         )
                //     })
                // })
            })
        })
    })
