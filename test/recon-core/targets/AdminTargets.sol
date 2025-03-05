// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";
import {OpType, BeforeAfter} from "../BeforeAfter.sol";
import {Properties} from "../Properties.sol";
import {vm} from "@chimera/Hevm.sol";
import "../../../src/ERC4626Escrow.sol";
import {RateLimitingConstraint} from "../../../src/RateLimitingConstraint.sol";

contract MockAlwaysTrueAuthority {
    function canCall(address user, address target, bytes4 functionSig) external view returns (bool) {
        return true;
    }
}

abstract contract AdminTargets is BaseTargetFunctions, Properties {
    /// === Escrow === ///
    function escrow_depositToExternalVault_rekt(uint256 assetsToDeposit, uint256 expectedShares)
        public
        updateGhosts
        asTechops
    {
        require(ALLOWS_REKT, "Allows rekt");
        escrow.depositToExternalVault(assetsToDeposit, expectedShares);
    }
    /// === Escrow === ///

    function escrow_depositToExternalVault_not_rekt(uint256 assetsToDeposit, uint256 expectedShares)
        public
        updateGhosts
    {
        require(!ALLOWS_REKT, "Must not allow rekt");

        uint256 balanceB4 = escrow.totalBalance();

        // asTechops
        vm.prank(address(techOpsMultisig));
        escrow.depositToExternalVault(assetsToDeposit, expectedShares);

        uint256 balanceAfter = escrow.totalBalance();

        require(balanceAfter >= balanceB4, "Prevent Self Rekt");
    }

    function escrow_redeemFromExternalVault(uint256 sharesToRedeem, uint256 expectedAssets)
        public
        updateGhosts
        asTechops
    {
        escrow.redeemFromExternalVault(sharesToRedeem, expectedAssets);
    }

    function escrow_onMigrateTarget(uint256 amount) public updateGhosts asTechops {
        escrow.onMigrateTarget(amount);
    }

    function escrow_claimProfit() public updateGhostsWithType(OpType.CLAIM) asTechops {
        escrow.claimProfit();
    }

    function inlined_withdrawProfitTest_liquid() public {
        uint256 amt = escrow.feeProfit();
        uint256 balB4Escrow = escrow.totalBalance();

        uint256 liquidBal = escrow.ASSET_TOKEN().balanceOf(address(escrow));
        if(amt > liquidBal) {
            revert("Other test");
        }

        uint256 balB4 = (escrow.ASSET_TOKEN()).balanceOf(address(escrow.FEE_RECIPIENT()));
        escrow_claimProfit();
        uint256 balAfter = (escrow.ASSET_TOKEN()).balanceOf(address(escrow.FEE_RECIPIENT()));

        uint256 deltaFees = balAfter - balB4;

        // Since there is no conversion all checks are exact
        gte(deltaFees, amt, "Recipient got exactly expected");
        eq(escrow.totalBalance(), balB4Escrow - amt, "Escrow balance decreases exactly by profit");
        eq(escrow.feeProfit(), 0, "Profit should be 0");
    }

    function inlined_withdrawProfitTest() public {
        uint256 amt = escrow.feeProfit();
        uint256 balB4Escrow = escrow.totalBalance();
        
        uint256 liquidBal = escrow.ASSET_TOKEN().balanceOf(address(escrow));
        uint256 toWithdraw = amt - liquidBal;
        if(amt > liquidBal) {
            // This is the case we explore
        } else {
            revert("Other test");
        }

        // Expected lower
        uint256 shares = escrow.EXTERNAL_VAULT().convertToShares(toWithdraw);
        uint256 expected = escrow.EXTERNAL_VAULT().previewRedeem(shares) + liquidBal;

        uint256 balB4 = (escrow.ASSET_TOKEN()).balanceOf(address(escrow.FEE_RECIPIENT()));
        escrow_claimProfit();
        uint256 balAfter = (escrow.ASSET_TOKEN()).balanceOf(address(escrow.FEE_RECIPIENT()));

        // The test is a bound as some slippage loss can happen, we take the worst slippage and the exact amt and check against those
        uint256 deltaFees = balAfter - balB4;

        gte(deltaFees, expected, "Recipient got at least expected");
        lte(deltaFees, amt, "Delta fees is at most profit");

        // Total Balance of Vualt should also move correctly | // TODO: Make these checks tighter
        // convertToAssets(shares) -> Rounds down by 1, so profit should be understated by 1
        // Claiming profit will instead round a SHARE by 1 
        // So the loss should be share value - 1
        // And that should be calculatable
        gte(escrow.totalBalance(), balB4Escrow - amt, "Escrow balance decreases at most by profit");
        lte(escrow.totalBalance(), balB4Escrow - expected, "Escrow balance decreases at least by expected");

        // Profit should be 0
        // NOTE: Profit can be unable to withdraw the last share due to rounding errors
        // As such profit doesn't reset to 0, but down to 1 wei of a share
        uint256 maxLoss = escrow.EXTERNAL_VAULT().previewRedeem(1);
        lte(escrow.feeProfit(), maxLoss, "Profit should be 0");
    }

    /// === BSM === ///
    function bsmTester_pause() public updateGhosts asTechops {
        bsmTester.pause();
    }

    function bsmTester_setFeeToBuy(uint256 _feeToBuyAssetBPS) public updateGhosts asTechops {
        bsmTester.setFeeToBuy(_feeToBuyAssetBPS);
    }

    function bsmTester_setFeeToSell(uint256 _feeToBuyEbtcBPS) public updateGhosts asTechops {
        bsmTester.setFeeToSell(_feeToBuyEbtcBPS);
    }

    function bsmTester_setMintingConfig(uint256 _mintingCapBPS) public updateGhosts asTechops {
        rateLimitingConstraint.setMintingConfig(
            address(bsmTester), RateLimitingConstraint.MintingConfig(_mintingCapBPS, 0, false)
        );
    }

    function bsmTester_unpause() public updateGhosts asTechops {
        bsmTester.unpause();
    }

    // Custom handler
    function bsmTester_updateEscrow() public updateGhostsWithType(OpType.MIGRATE) {
        // Replace
        escrow = new ERC4626Escrow(
            address(externalVault),
            address(mockAssetToken),
            address(bsmTester),
            address(new MockAlwaysTrueAuthority()),
            escrow.FEE_RECIPIENT()
        );

        uint256 balB4 = (escrow.ASSET_TOKEN()).balanceOf(address(escrow.FEE_RECIPIENT()));

        vm.prank(address(techOpsMultisig));
        bsmTester.updateEscrow(address(escrow));
    }

    // Stateless test
    /// @dev maybe the name is too long for medusa?
    /*   function doomsday_bsmTester_updateEscrow_always_works() public {
        try this.bsmTester_updateEscrow() {

        } catch {
            t(false, "doomsday_bsmTester_updateEscrow_always_works");
        }

        revert("stateless");
    }  */

    function bsmTester_updateEscrow_always_works() public {
        try this.bsmTester_updateEscrow() {}
        catch {
            t(false, "doomsday_bsmTester_updateEscrow_always_works");
        }

        revert("stateless");
    }
}
