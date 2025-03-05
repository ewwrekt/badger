# Invariants

## Base Escrow

-> Profit is balance above sum deposits

-> Sum deposits is inductive valid
-> Total balance is inductive valid (withdrawals)

-> Migration always works

-> Claiming profit always works if there's > 0 amt

## ERC4626 Vault

-> Withdraw profit never reverts
-> withdrawing below total always works, never decreases the PPFS

-------------

# Undefined

## Should there be some mechanism to sell the tokens or smth

Could be helpful if they are paused

Is fine to ack and mark as a known issue

# MED

## Should specify actual exact IMPL and Monitor for attacks here

https://github.com/ebtc-protocol/ebtc-bsm/blob/b64a08ea9527ad8e13b1d2512e449daf424f4d78/src/ERC4626AssetVault.sol#L37-L51

```solidity
    /// @notice Pull liquidity from the external lending vault if necessary
    function _ensureLiquidity(uint256 amountRequired) private {
        /// @dev super._totalBalance() returns asset balance for this contract
        uint256 liquidBalance = super._totalBalance();

        if (amountRequired > liquidBalance) {
            uint256 deficit;
            unchecked {
                deficit = amountRequired - liquidBalance;
            }

            EXTERNAL_VAULT.withdraw(deficit, address(this), address(this)); /// @audit Similar small loss on yield capture
        }
    }

```

I think this could be made to lock in losses but the cost to rebase:
- Euler is impossible
- Morpho is prob too high
- AAVE and OZ can be different but prob too high as well

Meaning that line is in theory vulnerable, but in practice should be fine

# QA

## Can improve CEI by transferring the Token last

## Can add Slippage checks in buy and sell functions

https://github.com/ebtc-protocol/ebtc-bsm/blob/b64a08ea9527ad8e13b1d2512e449daf424f4d78/src/EbtcBSM.sol#L114-L115

```solidity
    function buyEbtcWithAsset(uint256 _assetAmountIn) external whenNotPaused returns (uint256 _ebtcAmountOut) {

```

Adding a param for slippage or deadline could prevent long tail edge cases

Or ack it

## Approve is OK because we use tBTC

https://github.com/ebtc-protocol/ebtc-bsm/blob/b64a08ea9527ad8e13b1d2512e449daf424f4d78/src/BaseAssetVault.sol#L26-L34

```solidity
    constructor(address _assetToken, address _bsm, address _governance, address _feeRecipient) {
        ASSET_TOKEN = IERC20(_assetToken);
        BSM = _bsm;
        FEE_RECIPIENT = _feeRecipient;
        _initializeAuthority(_governance);

        // allow the BSM to transfer asset tokens
        ASSET_TOKEN.approve(BSM, type(uint256).max);
    }
```

## Small losses on yield claims

https://github.com/ebtc-protocol/ebtc-bsm/blob/b64a08ea9527ad8e13b1d2512e449daf424f4d78/src/ERC4626AssetVault.sol#L36-L51

```solidity

    /// @notice Pull liquidity from the external lending vault if necessary
    function _ensureLiquidity(uint256 amountRequired) private {
        /// @dev super._totalBalance() returns asset balance for this contract
        uint256 liquidBalance = super._totalBalance();

        if (amountRequired > liquidBalance) {
            uint256 deficit;
            unchecked {
                deficit = amountRequired - liquidBalance;
            }

            EXTERNAL_VAULT.withdraw(deficit, address(this), address(this)); /// @audit Similar small loss on yield capture
        }
    }

```


## `deposit` can cause the loss of a small amount of value

https://github.com/ebtc-protocol/ebtc-bsm/blob/b64a08ea9527ad8e13b1d2512e449daf424f4d78/src/ERC4626AssetVault.sol#L68-L74

```solidity
    function depositToExternalVault(uint256 assetsToDeposit, uint256 expectedShares) external requiresAuth {
        ASSET_TOKEN.safeIncreaseAllowance(address(EXTERNAL_VAULT), assetsToDeposit);
        uint256 shares = EXTERNAL_VAULT.deposit(depositAmount, address(this)); /// @audit this can cause a bit of a loss, but not a lot
        if (shares < expectedShares) {
            revert TooFewSharesReceived(expectedShares, shares);
        }
    }
```

If you can mint 1 share with X
And you can mint 2 shares with 2X
Then if you deposit X < Y < 2X you'll still mint only 1 share

This is a negligible loss for strategies that cause yield

Although it can be quickly fixed by using `mint` and ensuring the amount used doesn't exceed the intended assets


## Could have admin pass the expected amount out to make migration smoother

https://github.com/ebtc-protocol/ebtc-bsm/blob/b64a08ea9527ad8e13b1d2512e449daf424f4d78/src/ERC4626AssetVault.sol#L63-L67

```solidity
    /// @notice Redeem all shares
    function _beforeMigration() internal override {
        EXTERNAL_VAULT.redeem(EXTERNAL_VAULT.balanceOf(address(this)), address(this), address(this));
    }

```


# Oracle

## in lack of this you can use a boundary check | Which has gotchas due to deviation threshold

https://github.com/ebtc-protocol/ebtc-bsm/blob/b64a08ea9527ad8e13b1d2512e449daf424f4d78/src/OracleModule.sol#L35-L45

```solidity
    function _getAssetPrice() private view returns (uint256) {
        (, int256 answer, , uint256 updatedAt, ) = ASSET_FEED.latestRoundData();

        if (answer <= 0) revert BadOraclePrice(answer);

        if ((block.timestamp - updatedAt) > oracleFreshnessSeconds) {
            revert StaleOraclePrice(updatedAt);
        }

        return (uint256(answer) * 1e18) / ASSET_FEED_PRECISION;
    }
```