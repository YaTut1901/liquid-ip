// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Position} from "../LicenseHook.sol";

interface IEpochLiquidityAllocationManager {
    function allocate(uint256 epoch) external view returns (Position[] memory);
}