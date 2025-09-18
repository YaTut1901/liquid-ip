// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IV4Router} from "@v4-periphery/interfaces/IV4Router.sol";

interface ISimpleV4Router {
    function swapExactInSingleToSender(IV4Router.ExactInputSingleParams calldata params) external payable;

    function configureDefaultPoolKey(PoolKey calldata poolKey) external;

    function swapExactInDefault(uint128 amountIn, uint128 amountOutMinimum) external payable;
}


