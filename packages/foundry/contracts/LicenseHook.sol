// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

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

struct PoolState {
    int24 curveTickRange; 
    int256 tickAccumulator; 
    int24 startingTick; 
    int24 endingTick; 
    uint40 currentEpoch; 
    Position[] positions; 
    uint256 priceDiscoveryPositionsAmount; 
    uint256 tokensToSell; 
    uint256 startingTime; 
    uint256 endingTime; 
    uint256 epochLength; 
    int24 upperPositionRange;
}

struct Position {
    int24 tickLower;
    int24 tickUpper;
    uint128 liquidity;
}

struct CallbackData {
    PoolKey key;
    address sender;
    int24 tick;
}

contract LicenseHook is BaseHook {
    using SafeCastLib for int256;
    using SafeCastLib for uint256;

    error LicenseHook_NotOwnerOfPatent();
    error LicenseHook_AssetNotLicense();
    error LicenseHook_NumeraireNotAllowed();
    error LicenseHook_InvalidCurveTickRange();
    error LicenseHook_InvalidEpochLength();
    error LicenseHook_InvalidStartTime();
    error LicenseHook_InvalidTimeRange();
    error LicenseHook_InvalidTickRange();
    error LicenseHook_InvalidPriceDiscoveryPositionsAmount();
    error LicenseHook_UnathorizedPoolInitialization();

    int24 public constant TICK_SPACING = 30;
    uint256 public constant MAX_PRICE_DISCOVERY_SLUGS = 15;
    int256 public constant PRECISION = 1e18;
    uint256 public constant PRECISION_UINT = 1e18;
    address public immutable patentErc721;

    mapping(PoolId poolId => PoolState poolState) public poolStates;
    mapping(address numeraire => bool isAllowed) public isAllowedNumeraires;

    constructor(
        IPoolManager _manager,
        address _patentErc721,
        address[] memory _allowedNumeraires
    ) BaseHook(_manager) {
        patentErc721 = _patentErc721;

        for (uint256 i = 0; i < _allowedNumeraires.length; i++) {
            isAllowedNumeraires[_allowedNumeraires[i]] = true;
        }
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
                afterInitialize: true,
                beforeAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterAddLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: false,
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    /// @notice Creates a new licence distribution campaign, expects that patent is already registered as NFT and licence token is already emitted
    /// @dev Call PoolManager to create a pool, save provided parameters as this pool state
    /// @dev Doppler protocol assumes that asset token can be 0 or 1, but in this case asset is always 0 so further code has no assumptions about token order
    /// @param asset address of licence token, mandatory to be an address of contract with type LicenseERC20 and that msg.sender is an owner of NFT with licence patent id
    /// @param numeraire address of stablecoin which payment is made, mandatory to be one of whitelisted tokens
    /// @param startingTick tick where curve starts       0  1 [2  3  4  5] 6
    /// @param curveTickRange length of curve in ticks -> \  \  \  \  \  \  \ - curve is defined between 2nd and 5th tick, where all liquidity mandatory placed, other ticks are empty
    function initialize(
        address asset,
        address numeraire,
        int24 startingTick,
        int24 endingTick,
        int24 curveTickRange,
        uint256 tokensToSell,
        uint256 epochLength,
        uint256 startingTime,
        uint256 endingTime,
        uint256 priceDiscoveryPositionsAmount
    ) external {
        _validateInput(
            asset,
            numeraire,
            startingTick,
            endingTick,
            curveTickRange,
            epochLength,
            startingTime,
            endingTime,
            priceDiscoveryPositionsAmount
        );

        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(asset),
            currency1: Currency.wrap(numeraire),
            hooks: IHooks(this),
            fee: 0,
            tickSpacing: TICK_SPACING // constant TICK_SPACING is used for all pools
        });

        uint256 normalizedEpochDelta = FullMath.mulDiv(
            epochLength,
            PRECISION_UINT,
            endingTime - startingTime
        );

        poolStates[poolKey.toId()] = PoolState({
            curveTickRange: curveTickRange, // length of curve in ticks
            tickAccumulator: 0, // tickAccumulator is used to track the total amount of ticks that have been accumulated during rebalance, initially 0
            startingTick: startingTick,
            endingTick: endingTick,
            currentEpoch: 0, // currentEpoch is used to track the current epoch of the pool, which is a time period within overall duration of token sale and in scope of which certain price curve is used, initialized as 0 but will be set to 1 in unlockCallback
            positions: new Position[](0), // positions is used to track positions with which curve is defined, initially empty
            priceDiscoveryPositionsAmount: priceDiscoveryPositionsAmount, // amount of positions to discover the price of the asset token
            tokensToSell: tokensToSell, // tokensToSell is used to track the total amount of tokens to be sold during campaign
            epochLength: epochLength, // duration of each epoch in seconds
            upperPositionRange: FullMath.mulDiv(normalizedEpochDelta, uint256(int256(curveTickRange)), PRECISION_UINT).toInt24(), // upperPositionRange is used to track the upper position range, initially 0
            startingTime: startingTime,
            endingTime: endingTime
        });

        poolManager.initialize(
            poolKey,
            TickMath.getSqrtPriceAtTick(startingTick)
        );
    }

    function _validateInput(
        address asset,
        address numeraire,
        int24 startingTick,
        int24 endingTick,
        int24 curveTickRange,
        uint256 epochLength,
        uint256 startingTime,
        uint256 endingTime,
        uint256 priceDiscoveryPositionsAmount
    ) internal view {
        // Check that the asset is a license token
        uint256 patentId;
        try LicenseERC20(asset).patentId() returns (uint256 _patentId) {
            patentId = _patentId;
        } catch {
            revert LicenseHook_AssetNotLicense();
        }

        // Check that the sender is the owner of the patent
        require(
            IERC721(patentErc721).ownerOf(patentId) == msg.sender,
            LicenseHook_NotOwnerOfPatent()
        );

        uint256 timeDelta = endingTime - startingTime;
        // Check that the curve tick range is a multiple of the tick spacing
        require(
            curveTickRange % TICK_SPACING == 0,
            LicenseHook_InvalidCurveTickRange()
        );
        // Check that the curve tick range is positive
        require(curveTickRange > 0, LicenseHook_InvalidCurveTickRange());
        // Check that the epoch length is consistent with the curve tick range
        require(
            FullMath.mulDiv(
                FullMath.mulDiv(epochLength, PRECISION_UINT, timeDelta),
                uint256(int256(curveTickRange)),
                PRECISION_UINT
            ) != 0,
            LicenseHook_InvalidCurveTickRange()
        );
        // Check that the time delta is divisible by the epoch length
        require(timeDelta % epochLength == 0, LicenseHook_InvalidEpochLength());

        // Check that the numeraire is allowed
        require(
            isAllowedNumeraires[numeraire],
            LicenseHook_NumeraireNotAllowed()
        );

        // Check that the starting time is in the future
        require(block.timestamp < startingTime, LicenseHook_InvalidStartTime());
        require(startingTime < endingTime, LicenseHook_InvalidTimeRange());

        // Check that the starting tick is less than the ending tick in case if sales are not in a single tick range
        if (startingTick != endingTick) {
            require(startingTick > endingTick, LicenseHook_InvalidTickRange());
        }

        // Check that the price discovery positions amount is positive and less than the maximum allowed
        require(
            priceDiscoveryPositionsAmount > 0,
            LicenseHook_InvalidPriceDiscoveryPositionsAmount()
        );
        require(
            priceDiscoveryPositionsAmount <= MAX_PRICE_DISCOVERY_SLUGS,
            LicenseHook_InvalidPriceDiscoveryPositionsAmount()
        );
    }

    /// @notice Checks that the sender is the LicenseHook contract otherwise reverts
    function _beforeInitialize(
        address sender,
        PoolKey calldata,
        uint160
    ) internal view override returns (bytes4) {
        if (sender != address(this)) {
            revert LicenseHook_UnathorizedPoolInitialization();
        }

        return BaseHook.beforeInitialize.selector;
    }

    function _afterInitialize(
        address sender,
        PoolKey calldata key,
        uint160,
        int24 tick
    ) internal override returns (bytes4) {
        poolManager.unlock(
            abi.encode(CallbackData({key: key, sender: sender, tick: tick}))
        );
        return BaseHook.afterInitialize.selector;
    }

    function unlockCallback(
        bytes calldata data
    ) external onlyPoolManager returns (bytes memory) {
        CallbackData memory callbackData = abi.decode(data, (CallbackData));
        (PoolKey memory key, address sender, int24 tick) = (
            callbackData.key,
            callbackData.sender,
            callbackData.tick
        );

        PoolState storage state = poolStates[key.toId()];
        state.currentEpoch++; // increment the current epoch because with new curve defined the epoch starts

        // computes lower and upper ticks of the curve, tickLower is the same as starting tick at this moment
        (int24 tickLower, int24 tickUpper) = _getTicksBasedOnState(
            state.tickAccumulator,
            state.startingTick,
            state.curveTickRange
        );

        // creates lower position with 0 liquidity and ticks set to current
        state.positions[0] = Position({
            tickLower: tickLower,
            tickUpper: tickLower,
            liquidity: 0
        });

        (Position memory upper, uint256 assetRemaining) = _computeUpperPositionData(key, state, 0, tick, state.tokensToSell);

        state.positions[1] = upper;
    }

    /// @notice Computes the upper position ticks and liquidity
    ///         Places a position with the range according to the per epoch gamma, starting at the current tick
    ///         Provides the amount of tokens required to reach the expected amount sold by next epoch
    ///         If we have already sold more tokens than expected by next epoch, we don't place a position
    /// @param key The pool key
    /// @param totalTokensSold_ The total amount of tokens sold
    /// @param currentTick The current tick of the pool
    /// @param assetAvailable The amount of asset tokens available to provide liquidity
    /// @return position The computed upper position data
    /// @return assetRemaining The amount of asset tokens remaining after providing liquidity
    function _computeUpperPositionData(
        PoolKey memory key,
        PoolState storage state,
        uint256 totalTokensSold_,
        int24 currentTick,
        uint256 assetAvailable
    ) internal view returns (Position memory position, uint256 assetRemaining) {
        // Compute the delta between the amount of tokens sold relative to the expected amount sold by next epoch
        uint256 expectedAmountSold = _getExpectedAmountSoldWithEpochOffset(
            state,
            1
        );

        uint256 tokensToLp;
        // If we have sold less tokens than expected, we place a slug with the amount of tokens to sell to reach
        // the expected amount sold by next epoch
        if (expectedAmountSold > totalTokensSold_) {
            tokensToLp = uint256(
                int256(expectedAmountSold) - int256(totalTokensSold_)
            );
            if (tokensToLp > assetAvailable) {
                tokensToLp = assetAvailable;
            }

            int24 upperPositionRange = state.upperPositionRange > key.tickSpacing
                ? state.upperPositionRange
                : key.tickSpacing;
            position.tickLower = currentTick;
            position.tickUpper = _alignComputedTickWithTickSpacing(
                position.tickLower + upperPositionRange
            );
        } else {
            position.tickLower = currentTick;
            position.tickUpper = currentTick;
        }

        // We compute the amount of liquidity to place only if the tick range is non-zero
        if (position.tickLower != position.tickUpper) {
            position.liquidity = _computeLiquidity(
                TickMath.getSqrtPriceAtTick(position.tickLower),
                TickMath.getSqrtPriceAtTick(position.tickUpper),
                tokensToLp
            );
        } else {
            position.liquidity = 0;
        }

        assetRemaining = assetAvailable - tokensToLp;
    }

    /// @notice Computes the single sided liquidity amount for a given price range and amount of tokens
    /// @param lowerPrice The lower sqrt price of the range
    /// @param upperPrice The upper sqrt price of the range
    /// @param amount The amount of tokens to place as liquidity
    function _computeLiquidity(
        uint160 lowerPrice,
        uint160 upperPrice,
        uint256 amount
    ) internal pure returns (uint128) {
        // We decrement the amount by 1 to avoid rounding errors
        amount = amount != 0 ? amount - 1 : amount;

        return
            LiquidityAmounts.getLiquidityForAmount0(
                lowerPrice,
                upperPrice,
                amount
            );
    }

    /// @notice Retrieves the elapsed time since the start of the sale, normalized to 1e18
    /// @param timestamp The timestamp to retrieve for
    function _getNormalizedTimeElapsed(
        PoolState storage state,
        uint256 timestamp
    ) internal view returns (uint256) {
        return
            FullMath.mulDiv(
                timestamp - state.startingTime,
                PRECISION_UINT,
                state.endingTime - state.startingTime
            );
    }

    /// @notice Retrieves the current epoch
    function _getCurrentEpoch(
        PoolState storage state
    ) internal view returns (uint256) {
        if (block.timestamp < state.startingTime) return 1;
        return (block.timestamp - state.startingTime) / state.epochLength + 1;
    }

    /// @notice If offset == 0, retrieves the expected amount sold by the end of the last epoch
    ///         If offset == 1, retrieves the expected amount sold by the end of the current epoch
    ///         If offset == n, retrieves the expected amount sold by the end of the nth epoch from the current
    /// @param offset The epoch offset to retrieve for
    function _getExpectedAmountSoldWithEpochOffset(
        PoolState storage state,
        int256 offset
    ) internal view returns (uint256) {
        return
            FullMath.mulDiv(
                _getNormalizedTimeElapsed(
                    state,
                    uint256(
                        (int256(_getCurrentEpoch(state)) + offset - 1) *
                            int256(state.epochLength) +
                            int256(state.startingTime)
                    )
                ),
                state.tokensToSell,
                PRECISION_UINT
            );
    }

    /// @notice Computes the global lower and upper ticks based on the accumulator and tickSpacing
    ///         These ticks represent the global range of the bonding curve, across all liquidity slugs
    /// @param accumulator The tickAccumulator value
    /// @param startingTick The starting tick of the pool
    /// @param curveTickRange The curve tick range of the pool
    /// @return lower The computed global lower tick
    /// @return upper The computed global upper tick
    function _getTicksBasedOnState(
        int256 accumulator,
        int24 startingTick,
        int24 curveTickRange
    ) internal pure returns (int24 lower, int24 upper) {
        // compute actual tick change by accounting for the precision
        int24 accumulatorDelta = (accumulator / PRECISION).toInt24();
        // compute lower tick of the curve by adjusting starting tick by the accumulator delta and aligning with the tick spacing
        int24 adjustedTick = startingTick + accumulatorDelta;
        lower = _alignComputedTickWithTickSpacing(adjustedTick);
        // compute upper tick of the curve by adding the curve tick range to the lower tick, no need to align with the tick spacing because curve tick range is a multiple of the tick spacing
        upper = lower + curveTickRange;
    }

    /// @notice Aligns a given tick with the TICK_SPACING of the pool
    ///         Rounds down according to the asset token denominated price
    /// @param tick The tick to align
    function _alignComputedTickWithTickSpacing(
        int24 tick
    ) internal pure returns (int24) {
        if (tick < 0) {
            // If the tick is negative, we round up (negatively) the negative result to round down
            return ((tick - TICK_SPACING + 1) / TICK_SPACING) * TICK_SPACING;
        } else {
            // Else if positive, we simply round down
            return (tick / TICK_SPACING) * TICK_SPACING;
        }
    }
}
