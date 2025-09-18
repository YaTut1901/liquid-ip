// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IPoolManager} from "@v4-core/interfaces/IPoolManager.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {V4Router} from "@v4-periphery/V4Router.sol";
import {ReentrancyLock} from "@v4-periphery/base/ReentrancyLock.sol";
import {IV4Router} from "@v4-periphery/interfaces/IV4Router.sol";
import {Actions} from "@v4-periphery/libraries/Actions.sol";
import {ActionConstants} from "@v4-periphery/libraries/ActionConstants.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title SimpleV4Router
/// @notice Minimal router exposing a single-hop exact-in swap to msg.sender.
/// @dev This wraps V4Router to provide an EOA-friendly entry point for testing hooks.
contract SimpleV4Router is V4Router, ReentrancyLock, Ownable {
    PoolKey private _defaultPoolKey;

    constructor(IPoolManager _poolManager) V4Router(_poolManager) Ownable(msg.sender) {}

    /// @notice Swap exact `amountIn` of currency0->currency1 or reverse, sending output to msg.sender.
    /// @dev Expects caller to have approved this contract to spend input token when ERC20.
    /// For native input, send ETH as msg.value equal to amountIn and set poolKey.currencies accordingly.
    function swapExactInSingleToSender(IV4Router.ExactInputSingleParams calldata params) external payable isNotLocked {
        bytes memory plan = _buildExactInSinglePlan(params);
        poolManager.unlock(plan);
    }

    /// @notice Configure a default pool key to simplify EOA calls.
    function configureDefaultPoolKey(PoolKey calldata poolKey) external onlyOwner {
        _defaultPoolKey = poolKey;
    }

    /// @notice Convenience: single-hop exact-in using the configured default pool key.
    function swapExactInDefault(uint128 amountIn, uint128 amountOutMinimum) external payable isNotLocked {
        IV4Router.ExactInputSingleParams memory p = IV4Router.ExactInputSingleParams({
            poolKey: _defaultPoolKey,
            zeroForOne: true,
            amountIn: amountIn,
            amountOutMinimum: amountOutMinimum,
            hookData: bytes("")
        });
        bytes memory plan = _buildExactInSinglePlan(p);
        poolManager.unlock(plan);
    }

    function _buildExactInSinglePlan(IV4Router.ExactInputSingleParams memory params) internal pure returns (bytes memory) {
        bytes memory actions = new bytes(3);
        bytes[] memory callParams = new bytes[](3);

        // 0: swap exact in single
        actions[0] = bytes1(uint8(Actions.SWAP_EXACT_IN_SINGLE));
        callParams[0] = abi.encode(params);

        // 1: settle all input to pool manager using OPEN_DELTA
        actions[1] = bytes1(uint8(Actions.SETTLE));
        callParams[1] = abi.encode(
            params.zeroForOne ? params.poolKey.currency0 : params.poolKey.currency1,
            ActionConstants.OPEN_DELTA,
            true
        );

        // 2: take all output to msg.sender using OPEN_DELTA
        actions[2] = bytes1(uint8(Actions.TAKE));
        callParams[2] = abi.encode(
            params.zeroForOne ? params.poolKey.currency1 : params.poolKey.currency0,
            ActionConstants.MSG_SENDER,
            ActionConstants.OPEN_DELTA
        );

        return abi.encode(actions, callParams);
    }

    function _pay(Currency token, address payer, uint256 amount) internal override {
        if (payer == address(this)) {
            token.transfer(address(poolManager), amount);
        } else {
            // ERC20 transferFrom path; Currency.unwrap(token) is ERC20 address when not native
            (bool success, bytes memory data) = Currency.unwrap(token).call(
                abi.encodeWithSignature("transferFrom(address,address,uint256)", payer, address(poolManager), amount)
            );
            require(success && (data.length == 0 || abi.decode(data, (bool))), "TRANSFER_FROM_FAILED");
        }
    }

    function msgSender() public view override returns (address) {
        return _getLocker();
    }

    receive() external payable {}
}


