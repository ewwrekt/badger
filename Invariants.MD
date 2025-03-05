# Crit

https://github.com/GalloDaSballo/ebtc-bsm/blob/354f929a08823cc1cd3fc1d66d034a3c59f23364/src/ERC4626AssetVault.sol#L56-L62

The code was

```solidity
    function _withdrawProfit(uint256 profitAmount) internal override {
        _ensureLiquidity(profitAmount);

        super.withdrawProfit();
    }

```

Which was causing an infinite loop

The fix

```solidity

    function _withdrawProfit(uint256 profitAmount) internal override {
        _ensureLiquidity(profitAmount);

        super._withdrawProfit(profitAmount);
    }

```

Found due to stack overflow errors in invariant testing

# Trophies


## QA

### `withdrawProfit` requires `auth` so it can revert

https://github.com/GalloDaSballo/ebtc-bsm/blob/354f929a08823cc1cd3fc1d66d034a3c59f23364/src/BaseAssetVault.sol#L68-L71

```solidity
    /// @notice Allows the BSM to migrate liquidity to a new vault
    function migrateTo(address newVault) external onlyBSM {
        /// @dev take profit first (totalBalance == totalAssetsDeposited after)
        withdrawProfit();
```



With the current test setup the function will fail

#### Mitigation

https://github.com/GalloDaSballo/ebtc-bsm/blob/354f929a08823cc1cd3fc1d66d034a3c59f23364/src/BaseAssetVault.sol#L91-L103

```solidity

    function withdrawProfit() public requiresAuth {
        _doWithdrawProfit();
    }

    function _doWithdrawProfit() internal {
        uint256 profit = feeProfit();
        if (profit > 0) {
            _withdrawProfit(profit);
            // INVARIANT: total balance must be >= deposit amount
            require(_totalBalance() >= totalAssetsDeposited);
        }
    }
```