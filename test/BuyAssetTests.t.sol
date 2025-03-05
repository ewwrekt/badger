// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "./BSMTestBase.sol";
import {IEbtcBSM} from "../src/Dependencies/IEbtcBSM.sol";

contract BuyAssetTests is BSMTestBase {

    event AssetBought(uint256 ebtcAmountIn, uint256 assetAmountOut, uint256 feeAmount);
    event FeeToBuyUpdated(uint256 oldFee, uint256 newFee);

    function testBuyAssetSuccess() public {
        vm.prank(testMinter);
        bsmTester.sellAsset(5e18, testMinter, 0);

        assertEq(mockAssetToken.balanceOf(testBuyer), 0);
        assertEq(mockEbtcToken.balanceOf(testBuyer), 10e18);

        vm.recordLogs();
        vm.prank(testBuyer);

        assertEq(bsmTester.buyAsset(3e18, testBuyer, 0), 3e18);
        Vm.Log[] memory entries = vm.getRecordedLogs();

        assertEq(entries[0].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(entries[1].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(entries[2].topics[0], keccak256("AssetBought(uint256,uint256,uint256)"));
        assertEq(mockAssetToken.balanceOf(testBuyer), 3e18);
        assertEq(mockEbtcToken.balanceOf(testBuyer), 7e18);
    }

    function testBuyAssetFee() public {
        // 1% fee
        vm.prank(techOpsMultisig);
        vm.expectEmit(false, true, false, false);
        emit FeeToBuyUpdated(0, 100);
        bsmTester.setFeeToBuy(100);

        vm.recordLogs();
        vm.prank(testMinter);
        bsmTester.sellAsset(5e18, testMinter, 0);

        Vm.Log[] memory entries = vm.getRecordedLogs();

        assertEq(entries[0].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(entries[1].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(entries[2].topics[0], keccak256("AssetSold(uint256,uint256,uint256)"));
        assertEq(mockAssetToken.balanceOf(testBuyer), 0);
        assertEq(mockEbtcToken.balanceOf(testBuyer), 10e18);

        vm.prank(testBuyer);
        vm.expectEmit(true, false, false, false);
        emit AssetBought(1e18, 0, 0);

        assertEq(bsmTester.buyAsset(1e18, testBuyer, 0), 0.99e18);

        assertEq(mockAssetToken.balanceOf(testBuyer), 0.99e18);
        assertEq(mockEbtcToken.balanceOf(testBuyer), 9e18);

        assertEq(escrow.feeProfit(), 0.01e18);
        assertEq(escrow.totalAssetsDeposited(), 4e18);

        vm.prank(techOpsMultisig);
        escrow.claimProfit();

        assertEq(mockAssetToken.balanceOf(defaultFeeRecipient), 0.01e18);
        assertEq(escrow.feeProfit(), 0);
    }

    function testBuyAssetFeeAuthorizedUser() public {
        // 1% fee
        vm.prank(techOpsMultisig);
        bsmTester.setFeeToBuy(100);

        vm.prank(testMinter);
        bsmTester.sellAsset(5e18, testMinter, 0);

        vm.expectEmit();
        emit IEbtcBSM.AssetBought(1e18, 1e18, 0);

        vm.prank(testAuthorizedUser);
        assertEq(bsmTester.buyAssetNoFee(1e18, testAuthorizedUser, 0), 1e18);
    }

    function testBuyAssetFailAboveTotalAssetsDeposited() public {
        vm.expectRevert(abi.encodeWithSelector(EbtcBSM.InsufficientAssetTokens.selector, 1e18, escrow.totalAssetsDeposited()));
        bsmTester.buyAsset(1e18, address(this), 0);
    }

    function testBuyAssetFailSlippageCheck() public {
        // 1% fee
        vm.prank(techOpsMultisig);
        bsmTester.setFeeToBuy(100);

        vm.prank(testMinter);
        bsmTester.sellAsset(5e18, testMinter, 0);

        // TEST: fail if actual < expected
        vm.expectRevert(abi.encodeWithSelector(EbtcBSM.BelowExpectedMinOutAmount.selector, 1e18, 0.99e18));
        vm.prank(testBuyer);
        bsmTester.buyAsset(1e18, testBuyer, 1e18);

        // TEST: pass if actual >= expected
        vm.prank(testBuyer);
        assertEq(bsmTester.buyAsset(1e18, testMinter, 0.99e18), 0.99e18);
    }

    function testPreviewBuyAssetAndLiquidity() public {
        uint256 withdrawAmount = 3e18;
        // With liquidity
        vm.prank(testMinter);
        bsmTester.sellAsset(5e18, testMinter, 0);
        
        uint256 liquidBalance = mockAssetToken.balanceOf(address(escrow));
        // Ensure liquidity surplus
        assertGt(liquidBalance, withdrawAmount);
        // Preview withdraw does not redeem
        uint256 beforeShares = externalVault.balanceOf(address(escrow));
        uint256 amtOut = bsmTester.previewBuyAsset(withdrawAmount);
        vm.prank(testBuyer);
        uint256 realOut = bsmTester.buyAsset(withdrawAmount, testBuyer, 0);
        uint256 afterShares = externalVault.balanceOf(address(escrow));

        assertEq(amtOut, realOut);
        assertEq(afterShares, beforeShares);// No redeem happened

        // With no liquidity
        withdrawAmount = 2e18;
        uint256 shares = externalVault.previewDeposit(2e18);
        vm.prank(techOpsMultisig);
        escrow.depositToExternalVault(withdrawAmount, shares);
        liquidBalance = mockAssetToken.balanceOf(address(escrow));
        // Ensure liquidity deficit
        assertGt(withdrawAmount, liquidBalance);

        // Preview withdraw should take into account redeem amount
        beforeShares = externalVault.balanceOf(address(escrow));
        amtOut = bsmTester.previewBuyAsset(withdrawAmount);
        vm.prank(testBuyer);
        realOut = bsmTester.buyAsset(withdrawAmount, testBuyer, 0);

        afterShares = externalVault.balanceOf(address(escrow));

        assertEq(amtOut, realOut);
        assertLt(afterShares, beforeShares);// Redeem happened
    }
}
