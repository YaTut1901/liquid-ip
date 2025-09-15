// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {BaseHook} from "@v4-periphery/utils/BaseHook.sol";
import {IPoolManager} from "@v4-core/interfaces/IPoolManager.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {PatentMetadataVerifier} from "../PatentMetadataVerifier.sol";
import {IRehypothecationManager} from "../interfaces/IRehypothecationManager.sol";
import {Hooks} from "@v4-core/libraries/Hooks.sol";
import {PoolKey} from "@v4-core/types/PoolKey.sol";
import {PoolId} from "@v4-core/types/PoolId.sol";
import {ModifyLiquidityParams} from "@v4-core/types/PoolOperation.sol";
import {LiquidityAmounts} from "@v4-core-test/utils/LiquidityAmounts.sol";
import {TickMath} from "@v4-core/libraries/TickMath.sol";
import {SafeCastLib} from "@solady/utils/SafeCastLib.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {TransientStateLibrary} from "@v4-core/libraries/TransientStateLibrary.sol";

abstract contract AbstractLicenseHook is BaseHook, Ownable {
    using SafeCastLib for uint128;
    using TransientStateLibrary for IPoolManager;

    event PoolStateInitialized(PoolId poolId);
    event LiquidityAllocated(PoolId poolId, uint16 epochIndex);

    error ModifyingLiquidityNotAllowed();
    error DonatingNotAllowed();
    error UnauthorizedPoolInitialization();
    error ConfigNotInitialized();
    error CampaignNotStarted();
    error ConfigAlreadyInitialized();
    error RedeemNotAllowed();
    error CampaignEnded();

    PatentMetadataVerifier public immutable verifier;
    IRehypothecationManager public immutable rehypothecationManager;

    constructor(
        IPoolManager _manager,
        PatentMetadataVerifier _verifier,
        IRehypothecationManager _rehypothecationManager,
        address _owner
    ) BaseHook(_manager) Ownable(_owner) {
        verifier = _verifier;
        rehypothecationManager = _rehypothecationManager;
    }

    function getHookPermissions()
        public
        pure
        override
        virtual
        returns (Hooks.Permissions memory)
    {
        return
            Hooks.Permissions({
                beforeInitialize: true,
                afterInitialize: false,
                beforeAddLiquidity: true,
                beforeRemoveLiquidity: true,
                afterAddLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: true,
                afterSwap: false,
                beforeDonate: true,
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    function initializeState(
        PoolKey memory poolKey,
        bytes calldata state
    ) external onlyOwner {
        _initializeState(poolKey, state);
        emit PoolStateInitialized(poolKey.toId());
    }

    function _initializeState(
        PoolKey memory poolKey,
        bytes calldata state
    ) internal virtual {}

    function _computeLiquidity(
        int24 startingTick,
        int24 endingTick,
        uint256 amount,
        bool forAmount0
    ) internal virtual pure returns (int256) {
        if (forAmount0) {
            return
                LiquidityAmounts
                    .getLiquidityForAmount0(
                        TickMath.getSqrtPriceAtTick(startingTick),
                        TickMath.getSqrtPriceAtTick(endingTick),
                        amount
                    )
                    .toInt256();
        }

        return
            LiquidityAmounts
                .getLiquidityForAmount1(
                    TickMath.getSqrtPriceAtTick(startingTick),
                    TickMath.getSqrtPriceAtTick(endingTick),
                    amount
                )
                .toInt256();
    }

    function _handleDeltas(PoolKey memory key) internal {
        _handleDelta(key, key.currency0);
        _handleDelta(key, key.currency1);
    }

    function _handleDelta(PoolKey memory key, Currency currency) internal {
        int256 delta = poolManager.currencyDelta(address(this), currency);

        if (delta < 0) {
            poolManager.sync(currency);
            currency.transfer(address(poolManager), uint256(-delta));
            poolManager.settle();
        } else if (delta > 0) {
            poolManager.take(currency, address(this), uint256(delta));

            // rehypothecate
            if (address(rehypothecationManager) != address(0)) {
                PoolId poolId = key.toId();
                uint256 amount = uint256(delta);

                // eth send as msg.value
                if (Currency.unwrap(currency) == address(0)) {
                    rehypothecationManager.deposit{value: amount}(poolId, currency, amount);
                } else {
                    // Transfer tokens to RehypothecationManager first
                    currency.transfer(address(rehypothecationManager), amount);
                    rehypothecationManager.deposit(poolId, currency, amount);
                }
            }
        }
    }

    function _beforeAddLiquidity(
        address sender,
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        bytes calldata
    ) internal pure override returns (bytes4) {
        revert ModifyingLiquidityNotAllowed();
    }

    function _beforeRemoveLiquidity(
        address sender,
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        bytes calldata
    ) internal pure override returns (bytes4) {
        revert ModifyingLiquidityNotAllowed();
    }

    function _beforeDonate(
        address,
        PoolKey calldata,
        uint256,
        uint256,
        bytes calldata
    ) internal pure override returns (bytes4) {
        revert DonatingNotAllowed();
    }
}
