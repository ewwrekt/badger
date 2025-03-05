
// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {Asserts} from "@chimera/Asserts.sol";
import { BeforeAfter } from "./BeforeAfter.sol";

abstract contract Properties is BeforeAfter, Asserts {

    function property_observe_always_same() public {
        uint256 valueFromActivePool = activePoolObserver.observe();
        uint256 valueFromTwap = twapWeightedObserver.observe();

        eq(valueFromActivePool, valueFromTwap, "Observe values should be the same");
    }

    // If we get to the end of the week and data doesn't change,
    // then every new second and observation will result in the same value
    function property_observation_consistent_past_update_period() public {
        if (
            // check that it's been a week since the last observation
            block.timestamp - twapWeightedObserver.getData().lastObserved >= twapWeightedObserver.PERIOD() && 
            // check that the data hasn't changed since the last observation
            cachedLastObservedAverage == twapWeightedObserver.getData().lastObservedAverage
            ) 
        {
            // make a new observation
            activePoolObserver.observe();
            uint128 newLastObservedAverage = twapWeightedObserver.getData().lastObservedAverage;

            eq(newLastObservedAverage, cachedLastObservedAverage, "Observed value should be the same as the last observed average");
        }
    }

    // Any time the accumulator increases, the time / acc should increase at the same rate
    function property_time_accumulator_ratio_is_correct() public {
        uint256 ratioDelta = (_after.lastObserved / _after.accumulator) - (_before.lastObserved / _before.accumulator);
        uint256 accumulatorDelta = _after.accumulator - _before.accumulator;

        // Precondition: the accumulator has increased
        if(_before.accumulator < _after.accumulator) {
            eq(accumulatorDelta, ratioDelta, "Accumulator should increase at the same rate as the time / acc");
        }
    }
}
