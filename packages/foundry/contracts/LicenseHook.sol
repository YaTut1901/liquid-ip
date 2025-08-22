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
import {ModifyLiquidityParams, SwapParams} from "@v4-core/types/PoolOperation.sol";
import {TransientStateLibrary} from "@v4-core/libraries/TransientStateLibrary.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@v4-core/types/BeforeSwapDelta.sol";
import {StateLibrary} from "@v4-core/libraries/StateLibrary.sol";

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
    Position[] positions; // positions of the curve, from index 0 positions are going from higher to lower price range
    uint24 positionCounter; // counter of positions applied to the pool
}

struct Position {
    int24 tickLower;
    int24 tickUpper;
    int256 liquidity;
}

contract LicenseHook is BaseHook {
    using SafeCastLib for int256;
    using SafeCastLib for uint256;
    using SafeCastLib for uint128;
    using StateLibrary for IPoolManager;
    using TransientStateLibrary for IPoolManager;

    error LicenseHook_NotOwnerOfPatent();
    error LicenseHook_AssetNotLicense();
    error LicenseHook_NumeraireNotAllowed();
    error LicenseHook_CurveTickRangeNotPositive();
    error LicenseHook_InvalidEpochTickRange(int24 closestProperTickRange);
    error LicenseHook_InvalidStartTime();
    error LicenseHook_InvalidTimeRange();
    error LicenseHook_UnathorizedPoolInitialization();
    error LicenseHook_ModifyingLiquidityNotAllowed();
    error LicenseHook_InvalidAssetNumeraireOrder();
    error LicenseHook_RedeemNotAllowed();

    int24 public constant TICK_SPACING = 30;
    int256 public constant PRECISION = 1e18;
    uint256 public constant PRECISION_UINT = 1e18;
    IERC721 public immutable patentErc721;

    mapping(PoolId poolId => PoolState poolState) public poolStates;
    mapping(address numeraire => bool isAllowed) public isAllowedNumeraires;

    constructor(
        IPoolManager _manager,
        address _patentErc721,
        address[] memory _allowedNumeraires
    ) BaseHook(_manager) {
        patentErc721 = IERC721(_patentErc721);

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
                beforeAddLiquidity: true,
                beforeRemoveLiquidity: true,
                afterAddLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: true,
                afterSwap: true,
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
        int24 curveTickRange,
        uint256 startingTime,
        uint256 endingTime,
        uint24 totalEpochs,
        uint256 tokensToSell
    ) external {
        int24 epochTickRange = int24(uint24(curveTickRange) / totalEpochs); // length of each epoch in ticks
        _validateInput(
            asset,
            numeraire,
            curveTickRange,
            startingTime,
            endingTime,
            epochTickRange,
            totalEpochs
        );

        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(numeraire),
            currency1: Currency.wrap(asset),
            hooks: IHooks(this),
            fee: 0,
            tickSpacing: TICK_SPACING // constant TICK_SPACING is used for all pools
        });

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
            positions: new Position[](0), // positions is used to track positions with which curve is defined, initially empty
            positionCounter: 0 // counter of the positions
        });

        poolManager.initialize(
            poolKey,
            TickMath.getSqrtPriceAtTick(startingTick)
        );
    }

    function unlockCallback(
        bytes calldata data
    ) external onlyPoolManager returns (bytes memory) {
        PoolKey memory key = abi.decode(data, (PoolKey));

        PoolState storage state = poolStates[key.toId()];

        // calculate current epoch
        uint24 currentEpoch = uint24(block.timestamp - state.startingTime) /
            state.epochDuration +
            1;

        if (currentEpoch != state.currentEpoch) {
            state.currentEpoch = currentEpoch;
            _calculatePositions(state);
            _applyPositions(key);
        }
    }

    function _calculatePositions(PoolState storage state) internal {
        uint256 amountToSell = state.tokensToSell / state.totalEpochs;
        int24 tickLower = state.startingTick -
            state.epochTickRange *
            int24(state.currentEpoch);
        int24 tickUpper = state.startingTick -
            state.epochTickRange *
            int24(state.currentEpoch - 1);

        state.positions.push(
            Position({
                tickLower: tickLower,
                tickUpper: tickUpper,
                liquidity: _computeLiquidity(
                    tickLower,
                    tickUpper,
                    amountToSell,
                    false
                )
            })
        );
    }

    function _applyPositions(PoolKey memory key) internal {
        PoolId poolId = key.toId();
        PoolState storage state = poolStates[poolId];

        if (state.positions.length == 0) {
            return;
        }

        int24 epochUpperTick = state.positions[0].tickUpper;

        // clean up previous epoch positions
        for (uint256 i = 0; i < state.positionCounter; i++) {
            poolManager.modifyLiquidity(
                key,
                ModifyLiquidityParams({
                    tickLower: state.positions[i].tickLower,
                    tickUpper: state.positions[i].tickUpper,
                    liquidityDelta: -state.positions[i].liquidity,
                    salt: bytes32(uint256(i))
                }),
                ""
            );
        }

        state.positionCounter = 0;

        // apply new positions
        for (uint256 i = 0; i < state.positions.length; i++) {
            poolManager.modifyLiquidity(
                key,
                ModifyLiquidityParams({
                    tickLower: state.positions[i].tickLower,
                    tickUpper: state.positions[i].tickUpper,
                    liquidityDelta: state.positions[i].liquidity,
                    salt: bytes32(uint256(i))
                }),
                ""
            );

            state.positionCounter++;
        }

        delete state.positions;

        // transfer deltas
        int256 currency1Delta = poolManager.currencyDelta(
            address(this),
            key.currency1
        );
        poolManager.sync(key.currency1);
        key.currency1.transfer(address(poolManager), uint256(-currency1Delta));
        poolManager.settle();

        (, int24 currentTick, , ) = poolManager.getSlot0(poolId);

        // check if the price is at the upper tick of the curve, if not then move it to the upper tick
        if (currentTick != epochUpperTick) {
            poolManager.swap(
                key,
                SwapParams({
                    zeroForOne: true,
                    amountSpecified: 1,
                    sqrtPriceLimitX96: TickMath.getSqrtPriceAtTick(
                        epochUpperTick
                    )
                }),
                ""
            );
        }
    }

    function _computeLiquidity(
        int24 startingTick,
        int24 endingTick,
        uint256 amount,
        bool forAmount0
    ) internal pure returns (int256) {
        amount = amount != 0 ? amount - 1 : amount;

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

    function _validateInput(
        address asset,
        address numeraire,
        int24 curveTickRange,
        uint256 startingTime,
        uint256 endingTime,
        int24 epochTickRange,
        uint24 totalEpochs
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
            patentErc721.ownerOf(patentId) == msg.sender,
            LicenseHook_NotOwnerOfPatent()
        );

        // Check that the asset address is bigger than the numeraire address (uni v4 requirement)
        require(asset > numeraire, LicenseHook_InvalidAssetNumeraireOrder());

        // Check that the starting time is in the future
        require(block.timestamp < startingTime, LicenseHook_InvalidStartTime());
        require(startingTime < endingTime, LicenseHook_InvalidTimeRange());

        // Check that the curve tick range is positive
        require(curveTickRange > 0, LicenseHook_CurveTickRangeNotPositive());

        // Check that the epoch tick range is a multiple of the tick spacing
        require(
            epochTickRange % TICK_SPACING == 0,
            LicenseHook_InvalidEpochTickRange(
                _calculateClosestProperTickRange(epochTickRange, totalEpochs)
            )
        );

        // Check that the numeraire is allowed
        require(
            isAllowedNumeraires[numeraire],
            LicenseHook_NumeraireNotAllowed()
        );
    }

    function _calculateClosestProperTickRange(
        int24 epochTickRange,
        uint24 totalEpochs
    ) internal pure returns (int24) {
        int24 remainder = epochTickRange % TICK_SPACING;

        if (remainder < TICK_SPACING / 2) {
            return int24(totalEpochs) * epochTickRange - remainder;
        }

        return
            int24(totalEpochs) * (epochTickRange + (TICK_SPACING - remainder));
    }

    function _beforeSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata swapParams,
        bytes calldata
    ) internal override returns (bytes4, BeforeSwapDelta, uint24) {
        if (!swapParams.zeroForOne) {
            revert LicenseHook_RedeemNotAllowed();
        }

        poolManager.unlock(
            abi.encode(key)
        );

        return (
            BaseHook.beforeSwap.selector,
            BeforeSwapDeltaLibrary.ZERO_DELTA,
            0
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

    /// @notice calls poolManager to place initial liquidity on the curve
    function _afterInitialize(
        address sender,
        PoolKey calldata key,
        uint160,
        int24 tick
    ) internal override returns (bytes4) {
        poolManager.unlock(
            abi.encode(key)
        );
        return BaseHook.afterInitialize.selector;
    }

    function _beforeAddLiquidity(
        address sender,
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        bytes calldata
    ) internal view override returns (bytes4) {
        if (sender != address(this)) {
            revert LicenseHook_ModifyingLiquidityNotAllowed();
        }

        return BaseHook.beforeAddLiquidity.selector;
    }

    function _beforeRemoveLiquidity(
        address sender,
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        bytes calldata
    ) internal view override returns (bytes4) {
        if (sender != address(this)) {
            revert LicenseHook_ModifyingLiquidityNotAllowed();
        }

        return BaseHook.beforeRemoveLiquidity.selector;
    }
}
