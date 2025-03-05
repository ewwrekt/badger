
// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";
import {Properties} from "./Properties.sol";
import {vm} from "@chimera/Hevm.sol";

abstract contract TargetFunctions is BaseTargetFunctions, Properties {

    function twapWeightedObserver_setValueAndUpdate(uint128 _value) public {
        // clamp value using the max possible eBTC debt in the ActivePool
        _value %= 21e24;

        // require that the value is greater than 0 or else it would cause false positives in the doomsday properties
        require(_value > 0, "Value must be greater than 0");

        vm.prank(address(twapWeightedObserver));
        twapWeightedObserver.setValueAndUpdate(_value);
    }

    function twapWeightedObserver_update() public {
        twapWeightedObserver.update();
    }

    function twapWeightedObserver_observe() public {
        // cache the last observed average before updating for comparison
        cachedLastObservedAverage = twapWeightedObserver.getData().lastObservedAverage;
        twapWeightedObserver.observe();
    } 

    function activePoolObserver_observe() public {
        // cache the last observed average before updating for comparison
        cachedLastObservedAverage = twapWeightedObserver.getData().lastObservedAverage;
        try activePoolObserver.observe() returns (uint256 currentValue) {
            // Doomsday: if observe returns 0, RateLimitingConstraint::canMint prevents minting new eBTC
            gt(currentValue, 0, "observe should never return 0");
        } catch {
            // Doomsday: if observe reverts, RateLimitingConstraint::canMint sellAsset fails
            t(false, "observe should never revert");
        }
    }
}
