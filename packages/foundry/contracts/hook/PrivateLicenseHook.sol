// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {AbstractLicenseHook} from "./AbstractLicenseHook.sol";
import {IPoolManager} from "@v4-core/interfaces/IPoolManager.sol";
import {PatentMetadataVerifier} from "../PatentMetadataVerifier.sol";
import {IRehypothecationManager} from "../interfaces/IRehypothecationManager.sol";
import {PrivateCampaignConfig} from "../lib/PrivateCampaignConfig.sol";
import {InEuint32, InEuint128, euint32, euint128, euint64, euint16, ebool} from "@fhenixprotocol/cofhe-contracts/FHE.sol";
import {PoolId} from "@v4-core/types/PoolId.sol";
import {PoolKey} from "@v4-core/types/PoolKey.sol";
import {FHE} from "@fhenixprotocol/cofhe-contracts/FHE.sol";
import {BaseHook} from "@v4-periphery/utils/BaseHook.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@v4-core/types/BeforeSwapDelta.sol";
import {SwapParams, ModifyLiquidityParams} from "@v4-core/types/PoolOperation.sol";
import {LicenseERC20} from "../token/LicenseERC20.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {toBeforeSwapDelta} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {SafeCast} from "@uniswap/v4-core/src/libraries/SafeCast.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {CurrencySettler} from "@uniswap/v4-core/test/utils/CurrencySettler.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";

/// @title PrivateLicenseHook
/// @notice Uniswap v4 hook that applies epoch-based positions where parameters are provided encrypted (FHE).
/// @dev Defers swaps if decryption results are not yet available, anchoring price to the epoch starting tick,
///      and deposits proceeds via rehypothecation. Uses FHE to store and decrypt epoch configs on-chain.
contract PrivateLicenseHook is AbstractLicenseHook {
    using PrivateCampaignConfig for bytes;
    using CurrencySettler for Currency;
    using BalanceDeltaLibrary for BalanceDelta;
    using SafeCast for uint256;
    using SafeCast for int128;
    using TickMath for int24;
    using StateLibrary for IPoolManager;

    error ExactOutputNotAllowed();
    error OngoingMaintenance();

    struct PoolState {
        uint16 numEpochs;
        uint16 currentEpoch;
    }

    struct Position {
        euint32 tickLower;
        euint32 tickUpper;
        euint128 amountAllocated;
    }

    struct Epoch {
        uint64 startingTime;
        uint32 durationSeconds;
        uint8 numPositions;
    }

    struct PendingSwap {
        address sender;
        SwapParams params;
    }

    mapping(PoolId poolId => bool) internal isConfigInitialized;
    mapping(PoolId poolId => PoolState poolState) internal poolState;
    mapping(PoolId poolId => mapping(uint16 epochNumber => mapping(uint8 index => Position)))
        internal positions;
    mapping(PoolId poolId => mapping(uint16 epochNumber => Epoch))
        internal epochs;
    // are new positions applied to the pool manager
    mapping(PoolId poolId => mapping(uint16 epochNumber => bool))
        internal isEpochInitialized;
    mapping(PoolId poolId => mapping(uint16 epochNumber => bool))
        internal isDecryptionRequested;
    mapping(PoolId poolId => PendingSwap) internal pendingSwaps;
    mapping(PoolId poolId => bool anchoring) internal isAnchoring;

    constructor(
        IPoolManager _manager,
        PatentMetadataVerifier _verifier,
        IRehypothecationManager _rehypothecationManager,
        address _owner
    ) AbstractLicenseHook(_manager, _verifier, _rehypothecationManager, _owner) {}

    /// @inheritdoc AbstractLicenseHook
    function getHookPermissions()
        public
        pure
        virtual
        override
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
                beforeSwapReturnDelta: true,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    /// @inheritdoc AbstractLicenseHook
    function _initializeState(
        PoolKey memory poolKey,
        bytes calldata config
    ) internal override {
        PoolId poolId = poolKey.toId();
        if (isConfigInitialized[poolId]) {
            revert ConfigAlreadyInitialized();
        }

        uint16 numEpochs = config.numEpochs();

        poolState[poolId] = PoolState({
            numEpochs: numEpochs,
            currentEpoch: 0
        });

        for (uint16 e = 0; e < numEpochs; e++) {
            uint8 numPositions = config.numPositions(e);

            epochs[poolId][e] = Epoch({
                startingTime: config.epochStartingTime(e),
                durationSeconds: config.durationSeconds(e),
                numPositions: numPositions
            });

            for (uint8 i = 0; i < numPositions; i++) {
                positions[poolId][e][i] = Position({
                    tickLower: FHE.asEuint32(config.tickLower(e, i)),
                    tickUpper: FHE.asEuint32(config.tickUpper(e, i)),
                    amountAllocated: FHE.asEuint128(
                        config.amountAllocated(e, i)
                    )
                });
            }
        }

        isConfigInitialized[poolId] = true;
    }

    /// @notice Checks that the sender is the LicenseHook contract otherwise reverts
    function _beforeInitialize(
        address sender,
        PoolKey calldata key,
        uint160
    ) internal override returns (bytes4) {
        if (sender != owner()) {
            revert UnauthorizedPoolInitialization();
        }

        PoolId poolId = key.toId();

        if (!isConfigInitialized[poolId]) {
            revert ConfigNotInitialized();
        }

        _requestDecryption(poolId, 0);

        return BaseHook.beforeInitialize.selector;
    }

    /// @inheritdoc BaseHook
    function _beforeSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        bytes calldata
    ) internal override returns (bytes4, BeforeSwapDelta, uint24) {
        PoolId poolId = key.toId();

        // check if campaign has started
        if (block.timestamp < epochs[poolId][0].startingTime) {
            revert CampaignNotStarted();
        }

        // check if campaign has ended
        uint16 numEpochs = poolState[poolId].numEpochs;
        uint256 campaignEnd = epochs[poolId][numEpochs - 1].startingTime +
            epochs[poolId][numEpochs - 1].durationSeconds;

        if (block.timestamp > campaignEnd) {
            revert CampaignEnded();
        }

        // redeem not allowed
        if (!params.zeroForOne) {
            revert RedeemNotAllowed();
        }
        // exact output swaps are not allowed because async swaps are not possible with them
        if (params.amountSpecified > 0) {
            revert ExactOutputNotAllowed();
        }

        if (isAnchoring[poolId]) {
            return (
                BaseHook.beforeSwap.selector,
                BeforeSwapDeltaLibrary.ZERO_DELTA,
                0
            );
        }

        // execute previous epochs pending swaps
        _executePendingSwaps(poolId, key);

        uint16 epochIndex = _calculateCurrentEpochIndex(poolId);
        // if epoch is initialized then proceed with regular swap
        if (isEpochInitialized[poolId][epochIndex]) {
            return (
                BaseHook.beforeSwap.selector,
                BeforeSwapDeltaLibrary.ZERO_DELTA,
                0
            );
        }

        // send patent validation request
        uint256 tokenId = LicenseERC20(Currency.unwrap(key.currency1))
            .patentId();
        verifier.validate(tokenId);

        if (!_isDecryptionResultReady(poolId, epochIndex)) {
            // if it is not decrypted then save swap for async execution
            _savePendingSwap(poolId, sender, params, key);

            // if decryption is not requested then request it
            if (!isDecryptionRequested[poolId][epochIndex]) {
                _requestDecryption(poolId, epochIndex);
            }

            return (
                this.beforeSwap.selector,
                toBeforeSwapDelta(
                    uint256(-params.amountSpecified).toInt128(),
                    0
                ),
                0
            );
        }

        // initialize epoch
        poolState[poolId].currentEpoch = epochIndex;

        // if epoch has no positions, mark initialized and skip adjustments
        Epoch memory epoch = epochs[poolId][epochIndex];
        if (epoch.numPositions == 0) {
            isEpochInitialized[poolId][epochIndex] = true;
            emit LiquidityAllocated(poolId, epochIndex);
            return (
                BaseHook.beforeSwap.selector,
                BeforeSwapDeltaLibrary.ZERO_DELTA,
                0
            );
        }

        _cleanUpOldPositions(key, poolId, epochIndex);
        _adjustTick(key, poolId, epochIndex);
        _applyNewPositions(key, poolId, epochIndex);
        _handleDeltas(key, epochIndex);

        emit LiquidityAllocated(poolId, epochIndex);
        return (
            BaseHook.beforeSwap.selector,
            BeforeSwapDeltaLibrary.ZERO_DELTA,
            0
        );
    }

    /// @dev Computes epoch starting tick as the max upper tick among positions in the epoch.
    function _findEpochStartingTick(
        PoolId poolId,
        uint8 numPositions,
        uint16 epochIndex
    ) internal view returns (int24) {
        int24 maxUpper = type(int24).min;

        for (uint8 i = 0; i < numPositions; i++) {
            Position memory position = positions[poolId][epochIndex][i];
            int24 upperTick = int24(
                int32(FHE.getDecryptResult(position.tickUpper))
            );
            if (upperTick > maxUpper) {
                maxUpper = upperTick;
            }
        }
        return maxUpper;
    }

    /// @dev Anchors price toward target tick using a small liquidity position and a directional swap.
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
        int24 targetAligned = _alignToSpacing(_findEpochStartingTick(poolId, epoch.numPositions, epochIndex), spacing);

        if (targetAligned == currentAligned) {
            return;
        }

        bool moveRight = targetAligned > currentAligned; 

        int24 tickLower = moveRight ? currentAligned : targetAligned;
        int24 tickUpper = moveRight ? targetAligned : currentAligned + spacing;
        if (tickUpper <= tickLower) {
            tickUpper = tickLower + spacing;
        }

        uint256 anchorAmount = 1e6; 
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
                amountSpecified: -int256(anchorAmount),
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

    /// @dev Floors to the nearest tick aligned to spacing, handling negative numbers correctly.
    function _alignToSpacing(int24 tick, int24 spacing) internal pure returns (int24) {
        int24 quotient = tick / spacing;
        int24 remainder = tick % spacing;
        if (remainder != 0 && tick < 0) {
            quotient -= 1;
        }
        return quotient * spacing;
    }

    /// @dev Executes any swap that was deferred while waiting for decryption.
    function _executePendingSwaps(PoolId poolId, PoolKey memory key) internal {
        PendingSwap storage swap = pendingSwaps[poolId];

        if (swap.params.amountSpecified == 0) {
            return;
        }

        key.currency0.settle(
            poolManager,
            address(this),
            uint256(-swap.params.amountSpecified),
            true
        );
        key.currency0.settle(
            poolManager,
            swap.sender,
            uint256(-swap.params.amountSpecified),
            false
        );

        delete pendingSwaps[poolId];
    }

    /// @dev Stores a swap for later execution and mints claim tokens for numeraire specified by user.
    function _savePendingSwap(
        PoolId poolId,
        address sender,
        SwapParams calldata params,
        PoolKey memory key
    ) internal {
        // mint claim tokens for numeraire specified by user
        key.currency0.take(
            poolManager,
            address(this),
            uint256(-params.amountSpecified),
            true
        );

        pendingSwaps[poolId] = PendingSwap({sender: sender, params: params});
    }

    /// @dev Requests decryptions for all encrypted fields in the epoch positions.
    function _requestDecryption(PoolId poolId, uint16 epochIndex) internal {
        Epoch memory epoch = epochs[poolId][epochIndex];

        for (uint8 i = 0; i < epoch.numPositions; i++) {
            Position memory position = positions[poolId][epochIndex][i];
            FHE.allowThis(position.tickLower);
            FHE.decrypt(position.tickLower);
            FHE.allowThis(position.tickUpper);
            FHE.decrypt(position.tickUpper);
            FHE.allowThis(position.amountAllocated);
            FHE.decrypt(position.amountAllocated);
        }

        isDecryptionRequested[poolId][epochIndex] = true;
    }

    /// @dev Checks readiness by probing the last requested field of the last position of the epoch.
    function _isDecryptionResultReady(
        PoolId poolId,
        uint16 epochIndex
    ) internal view returns (bool) {
        Epoch memory epoch = epochs[poolId][epochIndex];
        if (epoch.numPositions == 0) {
            return true;
        }
        Position memory position = positions[poolId][epochIndex][
            epoch.numPositions - 1
        ];
        (, bool ready) = FHE.getDecryptResultSafe(position.amountAllocated);
        return ready;
    }

    /// @dev Applies all decrypted positions for the current epoch to the pool.
    function _applyNewPositions(
        PoolKey memory key,
        PoolId poolId,
        uint16 epochIndex
    ) internal {
        Epoch memory epoch = epochs[poolId][epochIndex];
        for (uint8 i = 0; i < epoch.numPositions; i++) {
            Position memory position = positions[poolId][epochIndex][i];

            int24 tickLower = int24(
                int32(FHE.getDecryptResult(position.tickLower))
            );
            int24 tickUpper = int24(
                int32(FHE.getDecryptResult(position.tickUpper))
            );
            uint128 amountAllocated = FHE.getDecryptResult(
                position.amountAllocated
            );

            if (amountAllocated == 0) {
                continue;
            }

            poolManager.modifyLiquidity(
                key,
                ModifyLiquidityParams({
                    tickLower: tickLower,
                    tickUpper: tickUpper,
                    liquidityDelta: _computeLiquidity(
                        tickLower,
                        tickUpper,
                        amountAllocated,
                        false
                    ),
                    salt: keccak256(abi.encodePacked(epochIndex, i))
                }),
                ""
            );
        }

        isEpochInitialized[poolId][epochIndex] = true;
    }

    /// @dev Removes positions of previous epochs and handles deltas and rehypothecation for each.
    function _cleanUpOldPositions(
        PoolKey memory key,
        PoolId poolId,
        uint16 epochIndex
    ) internal {
        for (uint16 epoch = 0; epoch < epochIndex; epoch++) {
            if (!isEpochInitialized[poolId][epoch]) {
                continue;
            }

            Epoch memory ep = epochs[poolId][epoch];
            for (uint8 i = 0; i < ep.numPositions; i++) {
                Position memory position = positions[poolId][epoch][i];

                uint128 amountAllocated = FHE.getDecryptResult(
                    position.amountAllocated
                );

                if (amountAllocated == 0) {
                    continue;
                }

                int24 tickLower = int24(
                    int32(FHE.getDecryptResult(position.tickLower))
                );
                int24 tickUpper = int24(
                    int32(FHE.getDecryptResult(position.tickUpper))
                );

                poolManager.modifyLiquidity(
                    key,
                    ModifyLiquidityParams({
                        tickLower: tickLower,
                        tickUpper: tickUpper,
                        liquidityDelta: -_computeLiquidity(
                            tickLower,
                            tickUpper,
                            amountAllocated,
                            false
                        ),
                        salt: keccak256(abi.encodePacked(epoch, i))
                    }),
                    ""
                );
                _handleDeltas(key, epoch);
            }

            _rehypothecation(poolId, epoch, key.currency1);

            isEpochInitialized[poolId][epoch] = false;
        }
    }

    /// @dev Determines the current epoch index based on timestamps.
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
