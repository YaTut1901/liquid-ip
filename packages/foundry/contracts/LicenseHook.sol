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
    int24 startingTick;
    int24 curveTickRange;
    uint256 startingTime;
    uint256 endingTime;
    uint24 epochDuration;
    uint24 currentEpoch;
    uint24 totalEpochs;
    uint256 tokensToSell;
    Position[] positions;
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
    error LicenseHook_InvalidAssetNumeraireOrder();

    int24 public constant TICK_SPACING = 30;
    uint256 public constant MAX_PRICE_DISCOVERY_SLUGS = 15;
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
        int24 curveTickRange,
        uint256 startingTime,
        uint256 endingTime,
        uint24 totalEpochs,
        uint256 tokensToSell
    ) external {
        uint24 epochDuration = uint24((endingTime - startingTime) / totalEpochs); // duration of each epoch in seconds
        _validateInput(
            asset,
            numeraire,
            curveTickRange,
            startingTime,
            endingTime,
            epochDuration
        );

        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(asset),
            currency1: Currency.wrap(numeraire),
            hooks: IHooks(this),
            fee: 0,
            tickSpacing: TICK_SPACING // constant TICK_SPACING is used for all pools
        });

        poolStates[poolKey.toId()] = PoolState({
            startingTick: startingTick,
            curveTickRange: curveTickRange, // length of curve in ticks
            startingTime: startingTime,
            endingTime: endingTime,
            epochDuration: epochDuration, // duration of each epoch in seconds
            currentEpoch: 0, // currentEpoch is used to track the current epoch of the pool, which is a time period within overall duration of token sale and in scope of which certain price curve is used, initialized as 0 but will be set to 1 in unlockCallback
            tokensToSell: tokensToSell, // tokensToSell is used to track the total amount of tokens to be sold during campaign
            totalEpochs: totalEpochs,
            positions: new Position[](0) // positions is used to track positions with which curve is defined, initially empty
        });

        poolManager.initialize(
            poolKey,
            TickMath.getSqrtPriceAtTick(startingTick)
        );
    }

    function _validateInput(
        address asset,
        address numeraire,
        int24 curveTickRange,
        uint256 startingTime,
        uint256 endingTime,
        uint24 epochDuration
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

        // Check that the asset is less than the numeraire (uni v4 requirement)
        require(asset < numeraire, LicenseHook_InvalidAssetNumeraireOrder());

        // Check that the starting time is in the future
        require(block.timestamp < startingTime, LicenseHook_InvalidStartTime());
        require(startingTime < endingTime, LicenseHook_InvalidTimeRange());

        // Check that the curve tick range is a multiple of the tick spacing
        require(
            curveTickRange % TICK_SPACING == 0,
            LicenseHook_InvalidCurveTickRange()
        );

        // Check that the curve tick range is positive
        require(curveTickRange > 0, LicenseHook_InvalidCurveTickRange());

        // Check that the epoch tick range is a multiple of the tick spacing
        uint256 totalDuration = endingTime - startingTime;
        require(
            FullMath.mulDiv(
                FullMath.mulDiv(epochDuration, PRECISION_UINT, totalDuration),
                uint256(int256(curveTickRange)),
                PRECISION_UINT
            ) %
                uint256(int256(TICK_SPACING)) ==
                0,
            LicenseHook_InvalidCurveTickRange()
        );

        // Check that the numeraire is allowed
        require(
            isAllowedNumeraires[numeraire],
            LicenseHook_NumeraireNotAllowed()
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
    }
}
