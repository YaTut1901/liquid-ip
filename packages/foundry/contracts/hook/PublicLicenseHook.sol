// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {AbstractLicenseHook} from "./AbstractLicenseHook.sol";
import {IPoolManager} from "@v4-core/interfaces/IPoolManager.sol";
import {PatentMetadataVerifier} from "../PatentMetadataVerifier.sol";
import {IRehypothecationManager} from "../interfaces/IRehypothecationManager.sol";
import {PoolKey} from "@v4-core/types/PoolKey.sol";
import {PoolId} from "@v4-core/types/PoolId.sol";
import {PublicCampaignConfig} from "../lib/PublicCampaignConfig.sol";
import {BaseHook} from "@v4-periphery/utils/BaseHook.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@v4-core/types/BeforeSwapDelta.sol";
import {SwapParams, ModifyLiquidityParams} from "@v4-core/types/PoolOperation.sol";
import {LicenseERC20} from "../token/LicenseERC20.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {TickMath} from "@v4-core/libraries/TickMath.sol";

contract PublicLicenseHook is AbstractLicenseHook {
    using PublicCampaignConfig for bytes;

    struct PoolState {
        uint16 numEpochs;
        uint16 currentEpoch;
    }

    struct Position {
        int24 tickLower;
        int24 tickUpper;
        int256 liquidity;
    }

    struct Epoch {
        uint64 startingTime;
        uint32 durationSeconds;
        int24 epochStartingTick;
    }

    mapping(PoolId poolId => bool isConfigInitialized)
        internal isConfigInitialized;
    mapping(PoolId poolId => PoolState poolState) internal poolState;
    mapping(PoolId poolId => mapping(uint16 epochNumber => mapping(uint8 index => Position position)))
        internal positions;
    mapping(PoolId poolId => mapping(uint16 epochNumber => Epoch epoch))
        internal epochs;
    mapping(PoolId poolId => mapping(uint16 epochNumber => bool initialized))
        internal isEpochInitialized;
    mapping(PoolId poolId => bool anchoring) internal isAnchoring;

    constructor(
        IPoolManager _manager,
        PatentMetadataVerifier _verifier,
        IRehypothecationManager _rehypothecationManager,
        address _owner
    ) AbstractLicenseHook(_manager, _verifier, _rehypothecationManager, _owner) {}

    function _initializeState(
        PoolKey memory poolKey,
        bytes calldata config
    ) internal override {
        if (isConfigInitialized[poolKey.toId()]) {
            revert ConfigAlreadyInitialized();
        }

        uint16 numEpochs = config.numEpochs();

        poolState[poolKey.toId()] = PoolState({
            numEpochs: numEpochs,
            currentEpoch: 0
        });

        PoolId poolId = poolKey.toId();
        for (uint16 e = 0; e < numEpochs; ) {
            epochs[poolId][e] = Epoch({
                startingTime: config.epochStartingTime(e),
                durationSeconds: config.durationSeconds(e),
                epochStartingTick: config.epochStartingTick(e)
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

        // initalize campaign in rehyp manager
        if (address(rehypothecationManager) != address(0)) {
            uint256 totalDuration = 0;
            for (uint16 e = 0; e < numEpochs; e++) {
                totalDuration += epochs[poolId][e].durationSeconds;
            }
            Currency numeraire = poolKey.currency0;

            rehypothecationManager.initializeCampaign(
                poolId,
                numeraire,           // numeraire currency
                owner(),             // campaign owner
                totalDuration
            );
        }
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
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        bytes calldata
    ) internal override returns (bytes4, BeforeSwapDelta, uint24) {
        PoolId poolId = key.toId();

        if (block.timestamp < epochs[poolId][0].startingTime) {
            revert CampaignNotStarted();
        }
        
        uint16 numEpochs = poolState[poolId].numEpochs;
        uint256 campaignEnd = epochs[poolId][
            numEpochs - 1
        ].startingTime +
            epochs[poolId][numEpochs - 1]
                .durationSeconds;

        if (block.timestamp > campaignEnd) {
            revert CampaignEnded();
        }

        if (isAnchoring[poolId]) {
            return (
                BaseHook.beforeSwap.selector,
                BeforeSwapDeltaLibrary.ZERO_DELTA,
                0
            );
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

        poolState[poolId].currentEpoch = epochIndex;
        _cleanUpOldPositions(key, poolId, epochIndex);
        _adjustTick(key, poolId, epochIndex);
        _applyNewPositions(key, poolId, epochIndex);
        _handleDeltas(key, epochIndex);

        uint256 tokenId = LicenseERC20(Currency.unwrap(key.currency1))
            .patentId();
        verifier.validate(tokenId);

        emit LiquidityAllocated(poolId, epochIndex);

        return (
            BaseHook.beforeSwap.selector,
            BeforeSwapDeltaLibrary.ZERO_DELTA,
            0
        );
    }

    function _adjustTick(
        PoolKey memory key,
        PoolId poolId,
        uint16 epochIndex
    ) internal {
        isAnchoring[poolId] = true;
        Epoch memory epoch = epochs[poolId][epochIndex];

        (, int24 currentTick,,) = StateLibrary.getSlot0(poolManager, poolId);
        int24 spacing = key.tickSpacing;

        int24 currentAligned = _alignToSpacing(currentTick, spacing);
        int24 targetAligned = _alignToSpacing(epoch.epochStartingTick, spacing);

        if (targetAligned == currentAligned) {
            return;
        }

        bool moveRight = targetAligned > currentAligned; 

        int24 tickLower = moveRight ? currentAligned : targetAligned;
        int24 tickUpper = moveRight ? targetAligned : currentAligned + spacing;
        if (tickUpper <= tickLower) {
            tickUpper = tickLower + spacing;
        }

        uint256 anchorAmount = 1e12; 
        int256 liquidityDelta = _computeLiquidity(
            tickLower,
            tickUpper,
            anchorAmount,
            moveRight
        );
        if (liquidityDelta == 0) {
            liquidityDelta = _computeLiquidity(
                tickLower,
                tickUpper,
                anchorAmount * 1e6,
                moveRight
            );
            if (liquidityDelta == 0) return;
        }

        bytes32 salt = keccak256("ANCHOR_TICK");

        poolManager.modifyLiquidity(
            key,
            ModifyLiquidityParams({
                tickLower: tickLower,
                tickUpper: tickUpper,
                liquidityDelta: liquidityDelta,
                salt: salt
            }),
            ""
        );

        uint160 limit = moveRight
            ? TickMath.getSqrtPriceAtTick(targetAligned)
            : TickMath.getSqrtPriceAtTick(targetAligned - 1);

        poolManager.swap(
            key,
            SwapParams({
                zeroForOne: !moveRight,
                amountSpecified: -int256(1e30),
                sqrtPriceLimitX96: limit
            }),
            ""
        );

        poolManager.modifyLiquidity(
            key,
            ModifyLiquidityParams({
                tickLower: tickLower,
                tickUpper: tickUpper,
                liquidityDelta: -liquidityDelta,
                salt: salt
            }),
            ""
        );

        isAnchoring[poolId] = false;
    }

    function _alignToSpacing(int24 tick, int24 spacing) internal pure returns (int24) {
        int24 quotient = tick / spacing;
        int24 remainder = tick % spacing;
        if (remainder != 0 && tick < 0) {
            quotient -= 1;
        }
        return quotient * spacing;
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
                _handleDeltas(key, epoch);
            }

            _rehypothecation(poolId, epoch, key.currency0);

            isEpochInitialized[poolId][epoch] = false;
        }
    }

    function _calculateCurrentEpochIndex(
        PoolId poolId
    ) internal view returns (uint16) {
        uint16 idx = 0;
        while (true) {
            Epoch memory ep = epochs[poolId][idx];
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
