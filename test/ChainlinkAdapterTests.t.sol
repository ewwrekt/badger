// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import {tBTCChainlinkAdapter, AggregatorV3Interface} from "../src/tBTCChainlinkAdapter.sol";
import {MockAssetOracle} from "./mocks/MockAssetOracle.sol";


contract tBTCChainlinkAdapterTests is Test {

    MockAssetOracle internal usdtBtcAggregator;
    MockAssetOracle internal btcUsdAggregator;
    tBTCChainlinkAdapter internal tBTCchainlinkAdapter;

    function setUp() public {
        usdtBtcAggregator = new MockAssetOracle(8);
        btcUsdAggregator = new MockAssetOracle(8);
        tBTCchainlinkAdapter = new tBTCChainlinkAdapter(usdtBtcAggregator, btcUsdAggregator);
    }

    function testGetLatestRound() public {
        usdtBtcAggregator.setLatestRoundId(110680464442257320247);
        usdtBtcAggregator.setPrevRoundId(110680464442257320246);
        usdtBtcAggregator.setPrice(3983705362408);
        usdtBtcAggregator.setUpdateTime(1706208946);

        btcUsdAggregator.setLatestRoundId(110680464442257320665);
        btcUsdAggregator.setPrevRoundId(110680464442257320664);
        btcUsdAggregator.setPrice(221026137517);
        btcUsdAggregator.setUpdateTime(1706208947);

        (
            ,
            int256 answer,
            ,
            uint256 updatedAt,
        ) = tBTCchainlinkAdapter.latestRoundData();

        assertEq(answer, 55482551396170026);
        assertEq(updatedAt, 1706208946);
    }
    
    //test that the conversion is correct using known numbers
    function testConversionWorks() public {
        // tBTC > BTC
        // tBTC
        usdtBtcAggregator.setLatestRoundId(1);
        usdtBtcAggregator.setPrice(2);
        // BTC
        btcUsdAggregator.setLatestRoundId(1);
        btcUsdAggregator.setPrice(1);// half the price

        (
            ,
            int256 answer,,,
        ) = tBTCchainlinkAdapter.latestRoundData();

        assertEq(answer, 500000000000000000);// (tBTC/BTC) * ADAPTER_PRECISION

        // tBTC < BTC
        // tBTC
        usdtBtcAggregator.setLatestRoundId(1);
        usdtBtcAggregator.setPrice(1);
        
        // BTC
        btcUsdAggregator.setLatestRoundId(1);        
        btcUsdAggregator.setPrice(2);// double the price
        
        (
            ,
            answer,,,
        ) = tBTCchainlinkAdapter.latestRoundData();

        assertEq(answer, 2000000000000000000);// (tBTC/BTC) * ADAPTER_PRECISION
    }

    function testWithRealData() public {
        string memory rpcUrl = vm.envString("RPC_URL");
        uint256 forkId = vm.createFork(rpcUrl);
        vm.selectFork(forkId);
        // test that reading the prices work by rolling to a block in mainnet that actually 
        // we know the prices and confirm the conversion works
        address tBtcUsdFeed = 0x8350b7De6a6a2C1368E7D4Bd968190e13E354297;
        address btcUsdFeed = 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c;
        
        tBTCChainlinkAdapter adapter = new tBTCChainlinkAdapter(AggregatorV3Interface(tBtcUsdFeed), AggregatorV3Interface(btcUsdFeed));
        
        (uint80 roundID, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) = adapter.latestRoundData();
        emit log_named_int("Converted tBTC to BTC price", answer);
        assertTrue(answer > 0, "Conversion should yield a positive number");
    }
}
