// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {AbstractLicenseHook} from "./AbstractLicenseHook.sol";
import {IPoolManager} from "@v4-core/interfaces/IPoolManager.sol";
import {PatentMetadataVerifier} from "../PatentMetadataVerifier.sol";
import {PoolKey} from "@v4-core/types/PoolKey.sol";
import {PoolId} from "@v4-core/types/PoolId.sol";
import {PublicCampaignConfig} from "../lib/PublicCampaignConfig.sol";
import {BaseHook} from "@v4-periphery/utils/BaseHook.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@v4-core/types/BeforeSwapDelta.sol";
import {SwapParams, ModifyLiquidityParams} from "@v4-core/types/PoolOperation.sol";
import {LicenseERC20} from "../token/LicenseERC20.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

contract PublicLicenseHook is AbstractLicenseHook {
    using PublicCampaignConfig for bytes;

    struct Position {
        int24 tickLower;
        int24 tickUpper;
        int256 liquidity;
    }

    struct Epoch {
        uint64 startingTime;
        uint32 durationSeconds;
    }

    mapping(PoolId poolId => bool isConfigInitialized) internal isConfigInitialized;
    mapping(PoolId poolId => uint16 currentEpoch) internal currentEpoch;
    mapping(PoolId poolId => mapping(uint16 epochNumber => mapping(uint8 index => Position position)))
        internal positions;
    mapping(PoolId poolId => mapping(uint16 epochNumber => Epoch epoch))
        internal epochTiming;
    mapping(PoolId poolId => mapping(uint16 epochNumber => bool initialized))
        internal isEpochInitialized;

    constructor(
        IPoolManager _manager,
        PatentMetadataVerifier _verifier,
        address _owner
    ) AbstractLicenseHook(_manager, _verifier, _owner) {}

    function _initializeState(
        PoolKey memory poolKey,
        bytes calldata config
    ) internal override {
        if (isConfigInitialized[poolKey.toId()]) {
            revert ConfigAlreadyInitialized();
        }

        uint16 epochs = config.numEpochs();
        PoolId poolId = poolKey.toId();
        for (uint16 e = 0; e < epochs; ) {
            epochTiming[poolId][e] = Epoch({
                startingTime: config.epochStartingTime(e),
                durationSeconds: config.durationSeconds(e)
            });

            uint8 count = config.numPositions(e);
            for (uint8 i = 0; i < count; ) {
                int24 tickLower = config.tickLower(e, i);
                int24 tickUpper = config.tickUpper(e, i);

                positions[poolId][e][i] = Position({
                    tickLower: tickLower,
                    tickUpper: tickUpper,
                    liquidity: _computeLiquidity(
                        tickLower,
                        tickUpper,
                        config.amountAllocated(e, i),
                        false
                    )
                });
                i++;
            }
            e++;
        }

        isConfigInitialized[poolId] = true;
    }

    /// @notice Checks that the sender is the LicenseHook contract otherwise reverts
    function _beforeInitialize(
        address sender,
        PoolKey calldata key,
        uint160
    ) internal view override returns (bytes4) {
        if (sender != owner()) {
            revert UnauthorizedPoolInitialization();
        }

        PoolId poolId = key.toId();

        if (!isConfigInitialized[poolId]) {
            revert ConfigNotInitialized();
        }

        return BaseHook.beforeInitialize.selector;
    }

    function _beforeSwap(
        address,
        PoolKey calldata key,
        SwapParams calldata params,
        bytes calldata
    ) internal override returns (bytes4, BeforeSwapDelta, uint24) {
        PoolId poolId = key.toId();
        Epoch memory zeroEpoch = epochTiming[poolId][0];

        if (block.timestamp < zeroEpoch.startingTime) {
            revert CampaignNotStarted();
        }

        if (block.timestamp > zeroEpoch.startingTime + zeroEpoch.durationSeconds) {
            revert CampaignEnded();
        }

        uint16 epochIndex = _calculateCurrentEpochIndex(poolId);

        if (!params.zeroForOne) {
            revert RedeemNotAllowed();
        }

        if (isEpochInitialized[poolId][epochIndex]) {
            return (
                BaseHook.beforeSwap.selector,
                BeforeSwapDeltaLibrary.ZERO_DELTA,
                0
            );
        }

        currentEpoch[poolId] = epochIndex;
        _cleanUpOldPositions(key, poolId, epochIndex);
        _applyNewPositions(key, poolId, epochIndex);
        _handleDeltas(key);

        uint256 tokenId = LicenseERC20(Currency.unwrap(key.currency0))
            .patentId();
        verifier.validate(tokenId);

        emit LiquidityAllocated(poolId, epochIndex);

        return (
            BaseHook.beforeSwap.selector,
            BeforeSwapDeltaLibrary.ZERO_DELTA,
            0
        );
    }

    function _applyNewPositions(
        PoolKey memory key,
        PoolId poolId,
        uint16 epochIndex
    ) internal {
        for (uint8 i = 0; i < type(uint8).max; i++) {
            Position memory position = positions[poolId][epochIndex][i];
            if (position.liquidity == 0) {
                break;
            }

            poolManager.modifyLiquidity(
                key,
                ModifyLiquidityParams({
                    tickLower: position.tickLower,
                    tickUpper: position.tickUpper,
                    liquidityDelta: position.liquidity,
                    salt: keccak256(abi.encodePacked(epochIndex, i))
                }),
                ""
            );
        }

        isEpochInitialized[poolId][epochIndex] = true;
    }

    function _cleanUpOldPositions(
        PoolKey memory key,
        PoolId poolId,
        uint16 epochIndex
    ) internal {
        for (uint16 epoch = 0; epoch < epochIndex; epoch++) {
            if (!isEpochInitialized[poolId][epoch]) {
                continue;
            }

            for (uint8 i = 0; i < type(uint8).max; i++) {
                Position memory position = positions[poolId][epoch][i];
                if (position.liquidity == 0) {
                    break;
                }

                poolManager.modifyLiquidity(
                    key,
                    ModifyLiquidityParams({
                        tickLower: position.tickLower,
                        tickUpper: position.tickUpper,
                        liquidityDelta: -position.liquidity,
                        salt: keccak256(abi.encodePacked(epoch, i))
                    }),
                    ""
                );
            }

            isEpochInitialized[poolId][epoch] = false;
        }
    }

    function _calculateCurrentEpochIndex(
        PoolId poolId
    ) internal view returns (uint16) {
        uint16 idx = 0;
        while (true) {
            Epoch memory ep = epochTiming[poolId][idx];
            if (ep.startingTime == 0) {
                break;
            }
            if (block.timestamp < ep.startingTime) {
                break;
            }
            uint256 epochEnd = uint256(ep.startingTime) +
                uint256(ep.durationSeconds);
            if (block.timestamp < epochEnd) {
                return idx;
            }
            idx++;
        }
        if (idx == 0) return 0;
        return idx - 1;
    }
}
