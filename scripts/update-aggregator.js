const {
    CHAINLINK
} = require("../config/mainnet-fork-test-config")
const {
    impersonates
} = require('../utils/contract-utils-usd')
const {
    send
} = require('@openzeppelin/test-helpers')

const Vault = hre.artifacts.require('Vault')
const ValueInterpreter = hre.artifacts.require('ValueInterpreter')
const ChainlinkPriceFeed = hre.artifacts.require('ChainlinkPriceFeed')

const admin = '0xc791B4A9B10b1bDb5FBE2614d389f0FE92105279'
const vaultAddr = '0xd5C7A01E49ab534e31ABcf63bA5a394fF1E5EfAC'

const main = async () => {
    let vault
    let valueInterpreter
    let chainlinkPriceFeed

    vault = await Vault.at(vaultAddr);
    const valueInterpreterAddr = await vault.valueInterpreter()
    valueInterpreter = await ValueInterpreter.at(valueInterpreterAddr)
    const chainlinkPriceFeedAddr = await valueInterpreter.getPrimitivePriceFeed()

    chainlinkPriceFeed = await ChainlinkPriceFeed.at(chainlinkPriceFeedAddr)
    
    await impersonates([admin])
    const accounts = await ethers.getSigners()
    const nextManagement = accounts[0].address
    await send.ether(nextManagement, admin, 10 * (10 ** 18))
    
    let primitives = []
    let aggregators = []
    let heartbeats = []

    for (const key in CHAINLINK.aggregators) {
        if (Object.hasOwnProperty.call(CHAINLINK.aggregators, key)) {
            const aggregator = CHAINLINK.aggregators[key]
            if (await chainlinkPriceFeed.isSupportedAsset(aggregator.primitive)) {
                primitives.push(aggregator.primitive)
                aggregators.push(aggregator.aggregator)
                heartbeats.push(60 * 60 * 24 * 365)
                console.log(`will update ${aggregator.primitive} aggregator`)
            }
        }
    }
    
    await chainlinkPriceFeed.updatePrimitives(primitives, aggregators, heartbeats, {
        from: admin
    })

    await chainlinkPriceFeed.setEthUsdAggregator('0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419', 60 * 60 * 24 * 365, {
        from: admin
    })
    
    console.log('update aggregator successfully')
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });