// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.25;

interface IMintingConstraint {
    event MintingConstraintUpdated(address indexed oldConstraint, address indexed newConstraint);

    error MintingConstraintCheckFailed(address constraint, uint256 amount, address minter, bytes errData);

    function canMint(uint256 amount, address minter) external view returns (bool, bytes memory);
}
