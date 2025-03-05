// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "./BSMTestBase.sol";
import "../src/BaseEscrow.sol";
import "../src/ERC4626Escrow.sol";
import "@openzeppelin/contracts/mocks/token/ERC4626Mock.sol";

contract MigrateAssetVaultTest is BSMTestBase {
    ERC4626Escrow internal newEscrow;
    
    function setUp() public virtual override {
        super.setUp();

        newEscrow = new ERC4626Escrow(
            address(externalVault),
            address(bsmTester.ASSET_TOKEN()),
            address(bsmTester),
            address(bsmTester.authority()),
            address(escrow.FEE_RECIPIENT())
        );
        mockAssetToken.mint(techOpsMultisig, 10e18);
        vm.prank(techOpsMultisig);
        mockAssetToken.approve(address(bsmTester), type(uint256).max);
    }

    function testBasicScenario() public {
        vm.expectEmit();
        emit IEbtcBSM.EscrowUpdated(address(bsmTester.escrow()), address(newEscrow));
        
        vm.prank(techOpsMultisig);
        bsmTester.updateEscrow(address(newEscrow));

        assertEq(address(bsmTester.escrow()), address(newEscrow));  
    }

    function testMigrationAssets() public {
        uint256 totalAssets = 5e18;
        uint256 assetAmount = 3e18;
        uint256 endAssetAmount = totalAssets - assetAmount;
        vm.prank(testMinter);
        bsmTester.sellAsset(5e18, testMinter, 0);

        vm.prank(testBuyer);
        assertEq(bsmTester.buyAsset(assetAmount, testBuyer, 0), assetAmount);

        uint256 prevTotalDeposit = escrow.totalAssetsDeposited();
        uint256 prevBalance = escrow.totalBalance();
        assertEq(prevTotalDeposit, endAssetAmount);
        assertGt(prevBalance, 0);

        vm.prank(techOpsMultisig);
        bsmTester.updateEscrow(address(newEscrow));

        uint256 crtTotalDeposit = escrow.totalAssetsDeposited();
        uint256 crtBalance = escrow.totalBalance();
        assertEq(crtTotalDeposit, 0);
        assertEq(crtBalance, 0);

        uint256 totalDeposit = newEscrow.totalAssetsDeposited();
        uint256 balance = newEscrow.totalBalance();
        assertEq(totalDeposit, endAssetAmount);
        assertEq(balance, endAssetAmount);
    }

    function testMigrationWithProfit() public {
        // make profit
        vm.prank(techOpsMultisig);
        bsmTester.setFeeToSell(100);

        vm.prank(testMinter);
        assertEq(bsmTester.sellAsset(1.01e18, testMinter, 0), 1e18);

        uint256 profit = escrow.feeProfit();
        uint256 prevFeeRecipientBalance = escrow.ASSET_TOKEN().balanceOf(escrow.FEE_RECIPIENT());
        // migrate escrow
        vm.prank(techOpsMultisig);
        bsmTester.updateEscrow(address(newEscrow));
        uint256 feeRecipientBalance = escrow.ASSET_TOKEN().balanceOf(escrow.FEE_RECIPIENT());
        
        assertEq(escrow.totalBalance(), escrow.totalAssetsDeposited());
        assertEq(escrow.feeProfit(), 0);
        assertEq(feeRecipientBalance, profit);
        assertGt(feeRecipientBalance, prevFeeRecipientBalance);
    }

    function testRevertScenarios() public {
        vm.expectRevert(abi.encodeWithSelector(BaseEscrow.CallerNotBSM.selector));
        escrow.onMigrateTarget(1e18);
        vm.expectRevert(abi.encodeWithSelector(BaseEscrow.CallerNotBSM.selector));
        escrow.onMigrateSource(address(newEscrow));
        
        vm.expectRevert("Auth: UNAUTHORIZED");
        bsmTester.updateEscrow(address(newEscrow));

        vm.prank(techOpsMultisig);
        vm.expectRevert();
        bsmTester.updateEscrow(address(0));
    }

    function testMigrationWithExtLending() public {
        uint256 assetAmount = 2e18;
        // operations including selling, and buying assets, as well as external lending
        vm.prank(techOpsMultisig);
        bsmTester.sellAsset(assetAmount, address(this), 0);

        uint256 shares = externalVault.previewDeposit(assetAmount);
        vm.prank(techOpsMultisig);
        escrow.depositToExternalVault(assetAmount, shares);

        vm.prank(testBuyer);
        bsmTester.buyAsset(assetAmount / 2, testBuyer, 0);

        assertGt(escrow.totalAssetsDeposited(), 0);
        assertGt(externalVault.balanceOf(address(escrow)), 0);
        
        vm.prank(techOpsMultisig);
        escrow.redeemFromExternalVault(shares / 2 , assetAmount / 2);
        // Migrate escrow
        uint256 totalAssetsDeposited = escrow.totalAssetsDeposited();
        uint256 escrowBalance = externalVault.balanceOf(address(escrow));
        vm.prank(techOpsMultisig);
        bsmTester.updateEscrow(address(newEscrow));
        
        assertEq(escrow.totalAssetsDeposited(), 0);
        assertEq(newEscrow.totalAssetsDeposited(), totalAssetsDeposited);
        assertEq(externalVault.balanceOf(address(escrow)), 0);
        assertEq(externalVault.balanceOf(address(newEscrow)), escrowBalance);
    }

    function testProfitAndExtLending() public {
        uint256 assetAmount = 2e18;
        vm.prank(techOpsMultisig);
    	bsmTester.setFeeToSell(100);

        // operations including selling, and buying assets, as well as external lending
        vm.prank(techOpsMultisig);
        bsmTester.sellAsset(assetAmount, address(this), 0);
        uint256 profit = escrow.feeProfit();

        assertGt(profit, 0);

        uint256 shares = externalVault.previewDeposit(assetAmount);
        vm.prank(techOpsMultisig);
        escrow.depositToExternalVault(assetAmount, shares);

        vm.prank(testBuyer);
        bsmTester.buyAsset(assetAmount / 2, testBuyer, 0);

        assertGt(escrow.totalAssetsDeposited(), 0);
        assertGt(externalVault.balanceOf(address(escrow)), 0);
        
        vm.prank(techOpsMultisig);
        escrow.redeemFromExternalVault(shares / 2 , assetAmount / 2);
        // Migrate escrow
        uint256 totalAssetsDeposited = escrow.totalAssetsDeposited();
        uint256 escrowBalance = externalVault.balanceOf(address(escrow));
        vm.prank(techOpsMultisig);
        bsmTester.updateEscrow(address(newEscrow));
        
        assertEq(escrow.totalAssetsDeposited(), 0);
        assertEq(newEscrow.totalAssetsDeposited(), totalAssetsDeposited);
        assertEq(externalVault.balanceOf(address(escrow)), 0);
        assertEq(externalVault.balanceOf(address(newEscrow)), escrowBalance);
    }

    function testMigrationWithExternalVaultLoss() public {
        uint256 assetAmount = 2e18;

        // operations including selling, and buying assets, as well as external lending
        vm.prank(techOpsMultisig);
        bsmTester.sellAsset(assetAmount, address(this), 0);

        uint256 shares = externalVault.previewDeposit(assetAmount);
        vm.prank(techOpsMultisig);
        escrow.depositToExternalVault(assetAmount, shares);

        // 50% external vault loss
        vm.prank(address(externalVault));
        mockAssetToken.transfer(vm.addr(0xdead), assetAmount / 2);

        vm.prank(techOpsMultisig);
        bsmTester.updateEscrow(address(newEscrow));

        assertEq(mockAssetToken.balanceOf(address(newEscrow)), assetAmount / 2);
        assertEq(newEscrow.totalAssetsDeposited(), assetAmount);
    }
}