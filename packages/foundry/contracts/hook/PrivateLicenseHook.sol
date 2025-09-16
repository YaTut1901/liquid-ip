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

contract PrivateLicenseHook is AbstractLicenseHook {
    using PrivateCampaignConfig for bytes;
    using CurrencySettler for Currency;
    using BalanceDeltaLibrary for BalanceDelta;
    using SafeCast for uint256;
    using SafeCast for int128;

    error ExactOutputNotAllowed();
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
    mapping(PoolId poolId => uint16) internal currentEpoch;
    mapping(PoolId poolId => mapping(uint16 epochNumber => mapping(uint8 index => Position)))
        internal positions;
    mapping(PoolId poolId => mapping(uint16 epochNumber => Epoch))
        internal epochTiming;
    // are new positions applied to the pool manager
    mapping(PoolId poolId => mapping(uint16 epochNumber => bool))
        internal isEpochInitialized;
    mapping(PoolId poolId => mapping(uint16 epochNumber => bool))
        internal isDecryptionRequested;
    mapping(PoolId poolId => PendingSwap[]) internal pendingSwaps;

    constructor(
        IPoolManager _manager,
        PatentMetadataVerifier _verifier,
        IRehypothecationManager _rehypothecationManager,
        address _owner
    ) AbstractLicenseHook(_manager, _verifier, _rehypothecationManager, _owner) {}

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

    function _initializeState(
        PoolKey memory poolKey,
        bytes calldata config
    ) internal override {
        PoolId poolId = poolKey.toId();
        if (isConfigInitialized[poolId]) {
            revert ConfigAlreadyInitialized();
        }

        uint16 epochs = config.numEpochs();

        for (uint16 e = 0; e < epochs; e++) {
            uint8 numPositions = config.numPositions(e);

            epochTiming[poolId][e] = Epoch({
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

    function _beforeSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        bytes calldata
    ) internal override returns (bytes4, BeforeSwapDelta, uint24) {
        PoolId poolId = key.toId();
        Epoch memory zeroEpoch = epochTiming[poolId][0];

        // send patent validation request
        uint256 tokenId = LicenseERC20(Currency.unwrap(key.currency0))
            .patentId();
        verifier.validate(tokenId);

        // check if campaign has started
        if (block.timestamp < zeroEpoch.startingTime) {
            revert CampaignNotStarted();
        }

        // check if campaign has ended
        if (block.timestamp > zeroEpoch.startingTime + zeroEpoch.durationSeconds) {
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
        currentEpoch[poolId] = epochIndex;

        _cleanUpOldPositions(key, poolId, epochIndex);
        _applyNewPositions(key, poolId, epochIndex);
        _handleDeltas(key, epochIndex);

        emit LiquidityAllocated(poolId, epochIndex);
        return (
            BaseHook.beforeSwap.selector,
            BeforeSwapDeltaLibrary.ZERO_DELTA,
            0
        );
    }

    function _executePendingSwaps(PoolId poolId, PoolKey memory key) internal {
        PendingSwap[] storage swaps = pendingSwaps[poolId];

        for (uint16 i = 0; i < swaps.length; i++) {
            _executePendingSwap(poolId, key, swaps[i]);
        }

        delete pendingSwaps[poolId];
    }

    function _executePendingSwap(
        PoolId poolId,
        PoolKey memory key,
        PendingSwap memory pendingSwap
    ) internal {
        key.currency0.settle(
            poolManager,
            address(this),
            uint256(-pendingSwap.params.amountSpecified),
            true
        );
        key.currency0.settle(
            poolManager,
            address(this),
            uint256(-pendingSwap.params.amountSpecified),
            false
        );
    }

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

        pendingSwaps[poolId].push(
            PendingSwap({sender: sender, params: params})
        );
    }

    function _requestDecryption(PoolId poolId, uint16 epochIndex) internal {
        Epoch memory epoch = epochTiming[poolId][epochIndex];

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

    // checks the last requested field on last position of epoch, assuming that decryption of all types takes constant time
    function _isDecryptionResultReady(
        PoolId poolId,
        uint16 epochIndex
    ) internal view returns (bool) {
        Epoch memory epoch = epochTiming[poolId][epochIndex];
        Position memory position = positions[poolId][epochIndex][
            epoch.numPositions - 1
        ];
        (, bool ready) = FHE.getDecryptResultSafe(position.amountAllocated);
        return ready;
    }

    function _applyNewPositions(
        PoolKey memory key,
        PoolId poolId,
        uint16 epochIndex
    ) internal {
        for (uint8 i = 0; i < type(uint8).max; i++) {
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
                break;
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
                    break;
                }

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
            }

            // Flush pending rehypothecation for this ended epoch (numeraire only)
            _flushRehypothecation(poolId, epoch, key.currency1);

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
