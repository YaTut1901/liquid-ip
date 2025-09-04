//SPDX-License-Identifier: MIT
pragma solidity =0.8.26;

import {PoolManager} from "@v4-core/PoolManager.sol";
import {console} from "forge-std/console.sol";
import "./DeployHelpers.s.sol";

contract DeployUniswapV4 is ScaffoldETHDeploy {
    function run() external ScaffoldEthDeployerRunner {
        PoolManager poolManager = new PoolManager(address(this));
        deployments.push(Deployment({name: "PoolManager", addr: address(poolManager)}));
        console.log("PoolManager:", address(poolManager));
    }
}
