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

struct PoolState {
    int24 curveTickRange;
}

contract LicenseHook is BaseHook {
    error LicenseHook_NotOwnerOfPatent();
    error LicenseHook_AssetNotLicense();
    error LicenseHook_NumeraireNotAllowed();
    error LicenseHook_InvalidCurveTickRange();
    error LicenseHook_UnathorizedPoolInitialization();

    int24 public constant TICK_SPACING = 30;
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

    /// @notice Creates a new licence distribution campaign, expects that patent is already registered as NFT and licence token is already emitted
    /// @dev Call PoolManager to create a pool, save provided parameters as this pool state
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
        uint256 patentId;
        try LicenseERC20(asset).patentId() returns (uint256 _patentId) {
            patentId = _patentId;
        } catch {
            revert LicenseHook_AssetNotLicense();
        }
        require(
            IERC721(patentErc721).ownerOf(patentId) == msg.sender,
            LicenseHook_NotOwnerOfPatent()
        );
        require(
            curveTickRange % TICK_SPACING == 0,
            LicenseHook_InvalidCurveTickRange()
        );
        require(
            isAllowedNumeraires[numeraire],
            LicenseHook_NumeraireNotAllowed()
        );

        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(asset),
            currency1: Currency.wrap(numeraire),
            hooks: IHooks(this),
            fee: 0,
            tickSpacing: TICK_SPACING
        });

        poolManager.initialize(
            poolKey,
            TickMath.getSqrtPriceAtTick(startingTick)
        );

        poolStates[poolKey.toId()] = PoolState({
            curveTickRange: curveTickRange
        });
    }

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
            abi.encode(
                // TODO: add callback data
            )
        );
        return BaseHook.afterInitialize.selector;
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
}
