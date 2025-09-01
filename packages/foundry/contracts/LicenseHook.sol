// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {BaseHook} from "@v4-periphery/utils/BaseHook.sol";
import {IPoolManager} from "@v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "@v4-core/libraries/Hooks.sol";
import {PoolId, PoolKey} from "@v4-core/types/PoolId.sol";
import {Currency} from "@v4-core/types/Currency.sol";
import {IHooks} from "@v4-core/interfaces/IHooks.sol";
import {TickMath} from "@v4-core/libraries/TickMath.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {LicenseERC20} from "./LicenseERC20.sol";
import {SafeCastLib} from "@solady/utils/SafeCastLib.sol";
import {FullMath} from "@v4-core/libraries/FullMath.sol";
import {LiquidityAmounts} from "@v4-core-test/utils/LiquidityAmounts.sol";
import {ModifyLiquidityParams, SwapParams} from "@v4-core/types/PoolOperation.sol";
import {TransientStateLibrary} from "@v4-core/libraries/TransientStateLibrary.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@v4-core/types/BeforeSwapDelta.sol";
import {StateLibrary} from "@v4-core/libraries/StateLibrary.sol";
import {console} from "forge-std/console.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IEpochLiquidityAllocationManager} from "./interfaces/IEpochLiquidityAllocationManager.sol";
import {IRehypothecationManager} from "./interfaces/IRehypothecationManager.sol";
import {PatentMetadataVerifier} from "./PatentMetadataVerifier.sol";
import {FHE, euint32, euint128, euint256, inEuint32, inEuint128, inEuint256} from "@fhenixprotocol/cofhe-contracts/contracts/FHE.sol";
import {Permissioned} from "@fhenix/access/Permissioned.sol";

struct PoolState {
    int24 startingTick; // upper tick of the curve, price is declining over time
    int24 curveTickRange; // length of the curve in ticks
    int24 epochTickRange; // length of the epoch in ticks
    uint256 startingTime; // starting time of the campaign
    uint256 endingTime; // ending time of the campaign
    uint24 epochDuration; // duration of the epoch in seconds
    uint24 currentEpoch; // current epoch of the campaign
    uint24 totalEpochs; // total number of epochs
    uint256 tokensToSell; // total number of tokens to be sold during the campaign
    IEpochLiquidityAllocationManager epochLiquidityAllocationManager; // address of the contract which is responsible for allocating liquidity to the epoch
    IRehypothecationManager rehypothecationManager; // address of the contract which is responsible for rehypothecation of token0 liquidity after epoch ends
}

struct Position {
    int24 tickLower;
    int24 tickUpper;
    int256 liquidity;
}

struct EncryptedPoolState {
    euint32 startingTick; // encrypted upper tick of the curve, price is declining over time
    euint32 curveTickRange; // encrypted length of the curve in ticks
    euint32 epochTickRange; // encrypted length of the epoch in ticks
    uint256 startingTime; // starting time of the campaign (kept public for epoch calculations)
    uint256 endingTime; // ending time of the campaign (kept public for epoch calculations)
    uint24 epochDuration; // duration of the epoch in seconds (kept public for timing)
    uint24 currentEpoch; // current epoch of the campaign (kept public for state tracking)
    uint24 totalEpochs; // total number of epochs (kept public for validation)
    euint256 tokensToSell; // encrypted total number of tokens to be sold during the campaign
    IEpochLiquidityAllocationManager epochLiquidityAllocationManager; // address kept public for interface calls
    IRehypothecationManager rehypothecationManager; // address kept public for interface calls
    string publicInfo; // public information field for flexibility
}

struct EncryptedPosition {
    euint32 tickLower; // encrypted tick lower
    euint32 tickUpper; // encrypted tick upper
    euint256 liquidity; // encrypted liquidity amount
}

contract LicenseHook is BaseHook, Ownable {
    using SafeCastLib for int256;
    using SafeCastLib for uint256;
    using SafeCastLib for uint128;
    using StateLibrary for IPoolManager;
    using TransientStateLibrary for IPoolManager;
    using FHE for uint256; // This allows method syntax on all euint types

    error UnathorizedPoolInitialization();
    error ModifyingLiquidityNotAllowed();
    error DonatingNotAllowed();
    error RedeemNotAllowed();
    error PoolStateNotInitialized();
    error CampaignNotStarted(uint256 startingTime);

    event PoolStateInitialized(PoolId poolId);
    event LiquidityAllocated(
        PoolId poolId,
        uint24 epoch,
        int24 tickLower,
        int24 tickUpper
    );

    int24 public constant TICK_SPACING = 30;
    int256 public constant PRECISION = 1e18;
    uint256 public constant PRECISION_UINT = 1e18;

    PatentMetadataVerifier public immutable verifier;

    mapping(PoolId poolId => PoolState poolState) internal poolStates;
    mapping(bytes32 hash => Position position) internal positions;
    mapping(PoolId poolId => mapping(uint24 epoch => bool initialized))
        internal isEpochInitialized;
    
    // Private campaign mappings
    mapping(PoolId poolId => bool isPrivate) internal isPrivateCampaign;
    mapping(PoolId poolId => EncryptedPoolState encryptedState) internal encryptedPoolStates;
    mapping(bytes32 hash => EncryptedPosition encryptedPosition) internal encryptedPositions;

    constructor(
        IPoolManager _manager,
        PatentMetadataVerifier _verifier,
        address owner
    ) BaseHook(_manager) Ownable() {
        verifier = _verifier;
        _transferOwnership(owner);
    }

    function getHookPermissions()
        public
        pure
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
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    function initializeState(
        PoolKey memory poolKey,
        int24 startingTick,
        int24 curveTickRange,
        uint256 startingTime,
        uint256 endingTime,
        uint24 totalEpochs,
        uint256 tokensToSell,
        int24 epochTickRange,
        IEpochLiquidityAllocationManager epochLiquidityAllocationManager,
        IRehypothecationManager rehypothecationManager
    ) external onlyOwner {
        poolStates[poolKey.toId()] = PoolState({
            startingTick: startingTick,
            curveTickRange: curveTickRange, // length of curve in ticks
            epochTickRange: epochTickRange, // length of each epoch in ticks
            startingTime: startingTime,
            endingTime: endingTime,
            epochDuration: uint24((endingTime - startingTime) / totalEpochs), // duration of each epoch in seconds
            currentEpoch: 0, // currentEpoch is used to track the current epoch of the pool, which is a time period within overall duration of token sale and in scope of which certain price curve is used, initialized as 0 but will be set to 1 in unlockCallback
            tokensToSell: tokensToSell, // tokensToSell is used to track the total amount of tokens to be sold during campaign
            totalEpochs: totalEpochs,
            epochLiquidityAllocationManager: epochLiquidityAllocationManager,
            rehypothecationManager: rehypothecationManager
        });

        emit PoolStateInitialized(poolKey.toId());
    }

    function initializePrivateState(
        PoolKey memory poolKey,
        inEuint32 memory encryptedStartingTick,
        inEuint32 memory encryptedCurveTickRange,
        uint256 startingTime,
        uint256 endingTime,
        uint24 totalEpochs,
        inEuint256 memory encryptedTokensToSell,
        inEuint32 memory encryptedEpochTickRange,
        IEpochLiquidityAllocationManager epochLiquidityAllocationManager,
        IRehypothecationManager rehypothecationManager,
        string memory publicInfo
    ) external onlyOwner {
        PoolId poolId = poolKey.toId();
        
        // Convert encrypted inputs to euint types
        euint32 startingTick = FHE.asEuint32(encryptedStartingTick);
        euint32 curveTickRange = FHE.asEuint32(encryptedCurveTickRange);
        euint32 epochTickRange = FHE.asEuint32(encryptedEpochTickRange);
        euint256 tokensToSell = FHE.asEuint256(encryptedTokensToSell);
        
        // Grant contract permissions to use these encrypted values with CoFHE
        FHE.allowThis(startingTick);
        FHE.allowThis(curveTickRange);
        FHE.allowThis(epochTickRange);
        FHE.allowThis(tokensToSell);
        
        // Store encrypted state
        encryptedPoolStates[poolId] = EncryptedPoolState({
            startingTick: startingTick,
            curveTickRange: curveTickRange,
            epochTickRange: epochTickRange,
            startingTime: startingTime,
            endingTime: endingTime,
            epochDuration: uint24((endingTime - startingTime) / totalEpochs),
            currentEpoch: 0,
            totalEpochs: totalEpochs,
            tokensToSell: tokensToSell,
            epochLiquidityAllocationManager: epochLiquidityAllocationManager,
            rehypothecationManager: rehypothecationManager,
            publicInfo: publicInfo
        });
        
        // Mark as private campaign
        isPrivateCampaign[poolId] = true;
        
        emit PoolStateInitialized(poolId);
    }

    /// @notice Checks that the sender is the LicenseHook contract otherwise reverts
    function _beforeInitialize(
        address sender,
        PoolKey calldata key,
        uint160
    ) internal view override returns (bytes4) {
        if (sender != owner()) {
            revert UnathorizedPoolInitialization();
        }

        PoolId poolId = key.toId();
        
        // Check if it's a private campaign or public campaign
        if (isPrivateCampaign[poolId]) {
            if (encryptedPoolStates[poolId].startingTime == 0) {
                revert PoolStateNotInitialized();
            }
        } else {
            if (poolStates[poolId].startingTime == 0) {
                revert PoolStateNotInitialized();
            }
        }

        return BaseHook.beforeInitialize.selector;
    }

    function _beforeSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata swapParams,
        bytes calldata
    ) internal override returns (bytes4, BeforeSwapDelta, uint24) {
        if (!swapParams.zeroForOne) {
            revert RedeemNotAllowed();
        }

        PoolId poolId = key.toId();
        
        // Check if this is a private campaign
        if (isPrivateCampaign[poolId]) {
            return _beforeSwapPrivate(sender, key, swapParams, poolId);
        } else {
            return _beforeSwapPublic(sender, key, swapParams, poolId);
        }
    }

    function _beforeSwapPublic(
        address sender,
        PoolKey calldata key,
        SwapParams calldata swapParams,
        PoolId poolId
    ) internal returns (bytes4, BeforeSwapDelta, uint24) {
        PoolState storage state = poolStates[poolId];

        if (block.timestamp < state.startingTime) {
            revert CampaignNotStarted(state.startingTime);
        }

        uint24 currentEpoch = _calculateCurrentEpoch(state);

        if (currentEpoch == state.currentEpoch) {
            return (
                BaseHook.beforeSwap.selector,
                BeforeSwapDeltaLibrary.ZERO_DELTA,
                0
            );
        }

        state.currentEpoch = currentEpoch;
        _calculatePositions(state, poolId);
        _cleanUpOldEpochPositions(state, key, poolId);
        (int24 tickLower, int24 tickUpper) = _applyNewEpochPositions(
            state,
            key,
            poolId
        );
        _handleDeltas(key);

        uint256 tokenId = LicenseERC20(Currency.unwrap(key.currency0))
            .patentId();
        verifier.validate(tokenId);

        emit LiquidityAllocated(poolId, currentEpoch, tickLower, tickUpper);
        return (
            BaseHook.beforeSwap.selector,
            BeforeSwapDeltaLibrary.ZERO_DELTA,
            0
        );
    }

    function _beforeSwapPrivate(
        address sender,
        PoolKey calldata key,
        SwapParams calldata swapParams,
        PoolId poolId
    ) internal returns (bytes4, BeforeSwapDelta, uint24) {
        EncryptedPoolState storage encryptedState = encryptedPoolStates[poolId];

        if (block.timestamp < encryptedState.startingTime) {
            revert CampaignNotStarted(encryptedState.startingTime);
        }

        uint24 currentEpoch = _calculateCurrentEpochEncrypted(encryptedState);

        if (currentEpoch == encryptedState.currentEpoch) {
            return (
                BaseHook.beforeSwap.selector,
                BeforeSwapDeltaLibrary.ZERO_DELTA,
                0
            );
        }

        encryptedState.currentEpoch = currentEpoch;
        _calculatePositionsEncrypted(encryptedState, poolId);
        _cleanUpOldEpochPositionsEncrypted(encryptedState, key, poolId);
        (int24 tickLower, int24 tickUpper) = _applyNewEpochPositionsEncrypted(
            encryptedState,
            key,
            poolId
        );
        _handleDeltas(key);

        emit LiquidityAllocated(poolId, currentEpoch, tickLower, tickUpper);

        return (
            BaseHook.beforeSwap.selector,
            BeforeSwapDeltaLibrary.ZERO_DELTA,
            0
        );
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

    function _calculatePositions(
        PoolState storage state,
        PoolId poolId
    ) internal {
        uint24 currentEpoch = state.currentEpoch;

        try
            state.epochLiquidityAllocationManager.allocate(currentEpoch)
        returns (Position[] memory allocations) {
            for (uint256 i = 0; i < allocations.length; i++) {
                positions[
                    keccak256(abi.encode(poolId, currentEpoch, i))
                ] = allocations[i];
            }
        } catch {
            _fallbackCalculatePositions(state, poolId);
        }

        isEpochInitialized[poolId][currentEpoch] = true;
    }

    function _fallbackCalculatePositions(
        PoolState storage state,
        PoolId poolId
    ) internal {
        uint24 currentEpoch = state.currentEpoch;
        int24 startingTick = state.startingTick;
        int24 epochTickRange = state.epochTickRange;

        uint256 amountToSell = state.tokensToSell / state.totalEpochs;
        int24 tickLower = startingTick - epochTickRange * int24(currentEpoch);
        int24 tickUpper = startingTick -
            epochTickRange *
            int24(currentEpoch - 1);

        bytes32 positionHash = keccak256(abi.encode(poolId, currentEpoch, 0));

        positions[positionHash] = Position({
            tickLower: tickLower,
            tickUpper: tickUpper,
            liquidity: _computeLiquidity(
                tickLower,
                tickUpper,
                amountToSell,
                false
            )
        });
    }

    function _handleDeltas(PoolKey memory key) internal {
        _handleDelta(key.currency0);
        _handleDelta(key.currency1);
    }

    function _handleDelta(Currency currency) internal {
        int256 delta = poolManager.currencyDelta(address(this), currency);

        if (delta < 0) {
            poolManager.sync(currency);
            currency.transfer(address(poolManager), uint256(-delta));
            poolManager.settle();
        } else if (delta > 0) {
            // IRehypothecationManager.rehypothecate(currency, delta); - rehypothecate currency to other financial instruments
            poolManager.take(currency, address(this), uint256(delta));
        }
    }

    function _applyNewEpochPositions(
        PoolState storage state,
        PoolKey memory key,
        PoolId poolId
    ) internal returns (int24 tickLower, int24 tickUpper) {
        for (uint256 i = 0; i < type(uint256).max; i++) {
            bytes32 positionHash = keccak256(
                abi.encode(poolId, state.currentEpoch, i)
            );
            Position memory position = positions[positionHash];
            if (position.liquidity == 0) {
                tickUpper = positions[
                    keccak256(abi.encode(poolId, state.currentEpoch, i - 1))
                ].tickUpper;
                break;
            }

            if (i == 0) {
                tickLower = position.tickLower;
            }

            poolManager.modifyLiquidity(
                key,
                ModifyLiquidityParams({
                    tickLower: position.tickLower,
                    tickUpper: position.tickUpper,
                    liquidityDelta: position.liquidity,
                    salt: bytes32(uint256(i))
                }),
                ""
            );
        }
    }

    function _cleanUpOldEpochPositions(
        PoolState storage state,
        PoolKey memory key,
        PoolId poolId
    ) internal {
        for (uint24 epoch = 1; epoch < state.currentEpoch; epoch++) {
            if (!isEpochInitialized[poolId][epoch]) {
                continue;
            }

            for (uint256 i = 0; i < type(uint256).max; i++) {
                bytes32 positionHash = keccak256(abi.encode(poolId, epoch, i));
                Position memory position = positions[positionHash];
                if (position.liquidity == 0) {
                    break;
                }

                poolManager.modifyLiquidity(
                    key,
                    ModifyLiquidityParams({
                        tickLower: position.tickLower,
                        tickUpper: position.tickUpper,
                        liquidityDelta: -position.liquidity,
                        salt: bytes32(uint256(i))
                    }),
                    ""
                );

                delete positions[positionHash];
            }

            isEpochInitialized[poolId][epoch] = false;
        }
    }

    function _computeLiquidity(
        int24 startingTick,
        int24 endingTick,
        uint256 amount,
        bool forAmount0
    ) internal pure returns (int256) {
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

    function _calculateCurrentEpoch(
        PoolState storage state
    ) internal view returns (uint24) {
        uint256 elapsed = uint256(block.timestamp) -
            uint256(state.startingTime);
        uint256 epoch = elapsed / uint256(state.epochDuration) + 1;
        if (epoch > state.totalEpochs) {
            epoch = state.totalEpochs;
        }
        return uint24(epoch);
    }

    // ========== ENCRYPTED FUNCTIONS ==========

    function _calculateCurrentEpochEncrypted(
        EncryptedPoolState storage encryptedState
    ) internal view returns (uint24) {
        // Time calculations remain public since timing needs to be verifiable
        uint256 elapsed = uint256(block.timestamp) -
            uint256(encryptedState.startingTime);
        uint256 epoch = elapsed / uint256(encryptedState.epochDuration) + 1;
        if (epoch > encryptedState.totalEpochs) {
            epoch = encryptedState.totalEpochs;
        }
        return uint24(epoch);
    }

    function _calculatePositionsEncrypted(
        EncryptedPoolState storage encryptedState,
        PoolId poolId
    ) internal {
        uint24 currentEpoch = encryptedState.currentEpoch;

        try
            encryptedState.epochLiquidityAllocationManager.allocate(currentEpoch)
        returns (Position[] memory allocations) {
            // Convert public positions to encrypted positions
            for (uint256 i = 0; i < allocations.length; i++) {
                encryptedPositions[
                    keccak256(abi.encode(poolId, currentEpoch, i))
                ] = EncryptedPosition({
                    tickLower: FHE.asEuint32(uint32(int32(allocations[i].tickLower))),
                    tickUpper: FHE.asEuint32(uint32(int32(allocations[i].tickUpper))),
                    liquidity: FHE.asEuint256(uint256(allocations[i].liquidity))
                });
            }
        } catch {
            _fallbackCalculatePositionsEncrypted(encryptedState, poolId);
        }

        isEpochInitialized[poolId][currentEpoch] = true;
    }

    function _fallbackCalculatePositionsEncrypted(
        EncryptedPoolState storage encryptedState,
        PoolId poolId
    ) internal {
        uint24 currentEpoch = encryptedState.currentEpoch;
        
        // Decrypt necessary values for calculations (in production, use FHE arithmetic)
        euint32 startingTick = encryptedState.startingTick;
        euint32 epochTickRange = encryptedState.epochTickRange;
        euint256 tokensToSell = encryptedState.tokensToSell;
        
        // Using FHE method syntax - try static function approach first
        euint256 amountToSell = FHE.div(tokensToSell, FHE.asEuint256(encryptedState.totalEpochs));
        FHE.allowThis(amountToSell);
        
        // Calculate encrypted tick positions using FHE operations
        euint32 epochCurrentEncrypted = FHE.asEuint32(currentEpoch);
        euint32 epochOffset = FHE.mul(epochCurrentEncrypted, epochTickRange);
        FHE.allowThis(epochOffset);
        
        euint32 tickLower = FHE.sub(startingTick, epochOffset);
        FHE.allowThis(tickLower);
        
        euint32 epochPrevEncrypted = FHE.asEuint32(currentEpoch > 0 ? currentEpoch - 1 : 0);
        euint32 previousOffset = FHE.mul(epochPrevEncrypted, epochTickRange);
        FHE.allowThis(previousOffset);
        
        euint32 tickUpper = FHE.sub(startingTick, previousOffset);
        FHE.allowThis(tickUpper);
        
        bytes32 positionHash = keccak256(abi.encode(poolId, currentEpoch, 0));

        euint256 encryptedLiquidity = _computeLiquidityEncrypted(tickLower, tickUpper, amountToSell, false);
        FHE.allowThis(encryptedLiquidity);
        
        encryptedPositions[positionHash] = EncryptedPosition({
            tickLower: tickLower,
            tickUpper: tickUpper,
            liquidity: encryptedLiquidity
        });
    }

    function _computeLiquidityEncrypted(
        euint32 startingTick,
        euint32 endingTick, 
        euint256 amount,
        bool forAmount0
    ) internal pure returns (euint256) {
        // This is a simplified implementation
        // In production, we'd need to implement encrypted sqrt and liquidity calculations
        // For now, return the encrypted amount as a placeholder
        return amount;
    }

    function _cleanUpOldEpochPositionsEncrypted(
        EncryptedPoolState storage encryptedState,
        PoolKey memory key,
        PoolId poolId
    ) internal {
        for (uint24 epoch = 1; epoch < encryptedState.currentEpoch; epoch++) {
            if (!isEpochInitialized[poolId][epoch]) {
                continue;
            }

            for (uint256 i = 0; i < type(uint256).max; i++) {
                bytes32 positionHash = keccak256(abi.encode(poolId, epoch, i));
                EncryptedPosition memory encPosition = encryptedPositions[positionHash];
                
                // Check if position exists (simplified check)
                if (!FHE.isInitialized(encPosition.liquidity)) {
                    break;
                }

                // For now, we need to decrypt values to interact with Uniswap
                // In production, this would need a more sophisticated approach
                int24 tickLower = int24(int32(FHE.decrypt(encPosition.tickLower)));
                int24 tickUpper = int24(int32(FHE.decrypt(encPosition.tickUpper)));
                int256 liquidity = int256(FHE.decrypt(encPosition.liquidity));

                poolManager.modifyLiquidity(
                    key,
                    ModifyLiquidityParams({
                        tickLower: tickLower,
                        tickUpper: tickUpper,
                        liquidityDelta: -liquidity,
                        salt: bytes32(uint256(i))
                    }),
                    ""
                );

                delete encryptedPositions[positionHash];
            }

            isEpochInitialized[poolId][epoch] = false;
        }
    }

    function _applyNewEpochPositionsEncrypted(
        EncryptedPoolState storage encryptedState,
        PoolKey memory key,
        PoolId poolId
    ) internal returns (int24 tickLower, int24 tickUpper) {
        for (uint256 i = 0; i < type(uint256).max; i++) {
            bytes32 positionHash = keccak256(
                abi.encode(poolId, encryptedState.currentEpoch, i)
            );
            EncryptedPosition memory encPosition = encryptedPositions[positionHash];
            
            if (!FHE.isInitialized(encPosition.liquidity)) {
                if (i > 0) {
                    EncryptedPosition memory prevPosition = encryptedPositions[
                        keccak256(abi.encode(poolId, encryptedState.currentEpoch, i - 1))
                    ];
                    tickUpper = int24(int32(FHE.decrypt(prevPosition.tickUpper)));
                }
                break;
            }

            if (i == 0) {
                tickLower = int24(int32(FHE.decrypt(encPosition.tickLower)));
            }

            // Decrypt values for Uniswap interaction
            poolManager.modifyLiquidity(
                key,
                ModifyLiquidityParams({
                    tickLower: int24(int32(FHE.decrypt(encPosition.tickLower))),
                    tickUpper: int24(int32(FHE.decrypt(encPosition.tickUpper))),
                    liquidityDelta: int256(FHE.decrypt(encPosition.liquidity)),
                    salt: bytes32(uint256(i))
                }),
                ""
            );
        }
    }
}
