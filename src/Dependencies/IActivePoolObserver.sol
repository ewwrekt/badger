// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.25;

interface IActivePoolObserver {
    function observe() external view returns (uint256);
}
