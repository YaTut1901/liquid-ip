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

struct PoolState {
    int24 curveTickRange;
    int256 tickAccumulator;
    int24 startingTick;
    uint40 currentEpoch;
}

struct CallbackData {
    PoolKey key;
    address sender;
    int24 tick;
}

contract LicenseHook is BaseHook {
    using SafeCastLib for int256;

    error LicenseHook_NotOwnerOfPatent();
    error LicenseHook_AssetNotLicense();
    error LicenseHook_NumeraireNotAllowed();
    error LicenseHook_InvalidCurveTickRange();
    error LicenseHook_UnathorizedPoolInitialization();

    int24 public constant TICK_SPACING = 30;
    int256 public constant PRECISION = 1e18;
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
                beforeInitialize: false,
                afterInitialize: false,
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
        int24 curveTickRange
    ) external {
        /// @dev Check that the asset is a license token
        uint256 patentId;
        try LicenseERC20(asset).patentId() returns (uint256 _patentId) {
            patentId = _patentId;
        } catch {
            revert LicenseHook_AssetNotLicense();
        }

        /// @dev Check that the sender is the owner of the patent
        require(
            IERC721(patentErc721).ownerOf(patentId) == msg.sender,
            LicenseHook_NotOwnerOfPatent()
        );

        /// @dev Check that the curve tick range is a multiple of the tick spacing
        require(
            curveTickRange % TICK_SPACING == 0,
            LicenseHook_InvalidCurveTickRange()
        );

        /// @dev Check that the numeraire is allowed
        require(
            isAllowedNumeraires[numeraire],
            LicenseHook_NumeraireNotAllowed()
        );

        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(asset),
            currency1: Currency.wrap(numeraire),
            hooks: IHooks(this),
            fee: 0,
            tickSpacing: TICK_SPACING /// @dev constant TICK_SPACING is used for all pools
        });

        poolStates[poolKey.toId()] = PoolState({
            curveTickRange: curveTickRange,
            tickAccumulator: 0, /// @dev tickAccumulator is used to track the total amount of ticks that have been accumulated during rebalance, initially 0
            startingTick: startingTick,
            currentEpoch: 0 /// @dev currentEpoch is used to track the current epoch of the pool, initialized as 0 but will be set to 1 in unlockCallback
        });

        poolManager.initialize(
            poolKey,
            TickMath.getSqrtPriceAtTick(startingTick)
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
        state.currentEpoch++; /// @dev increment the current epoch because with new curve defined the epoch starts

        /// @dev computes lower and upper ticks of the curve, tickLower is the same as starting tick at this moment
        (int24 tickLower, int24 tickUpper) = _getTicksBasedOnState(
            state.tickAccumulator,
            state.startingTick,
            state.curveTickRange
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
        /// @dev compute actual tick change by accounting for the precision
        int24 accumulatorDelta = (accumulator / PRECISION).toInt24();
        /// @dev compute lower tick of the curve by adjusting starting tick by the accumulator delta and aligning with the tick spacing
        int24 adjustedTick = startingTick + accumulatorDelta;
        lower = _alignComputedTickWithTickSpacing(adjustedTick);
        /// @dev compute upper tick of the curve by adding the curve tick range to the lower tick, no need to align with the tick spacing because curve tick range is a multiple of the tick spacing
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
