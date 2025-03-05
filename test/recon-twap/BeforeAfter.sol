// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {Setup} from "./Setup.sol";

// ghost variables for tracking state variable values before and after function calls
abstract contract BeforeAfter is Setup {
    struct Vars {
        uint128 accumulator;
        uint64 lastObserved;
    }

    Vars internal _before;
    Vars internal _after;

    modifier updateGhosts() {
        __before();
        _;
        __after();
    }

    function __before() internal {
        _before.accumulator = twapWeightedObserver.getLatestAccumulator();
        _before.lastObserved = twapWeightedObserver.getData().lastObserved;
    }

    function __after() internal {
        _after.accumulator = twapWeightedObserver.getLatestAccumulator();
        _after.lastObserved = twapWeightedObserver.getData().lastObserved;
    }
}
