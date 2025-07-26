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

    function initialize(
        address asset,
        address numeraire,
        int24 startingTick,
        int24 curveTickRange
    ) external {
        require(LicenseERC20(asset).patentId() != 0, LicenseHook_AssetNotLicense());
        require(
            IERC721(patentErc721).ownerOf(LicenseERC20(asset).patentId()) ==
                msg.sender,
            LicenseHook_NotOwnerOfPatent()
        );
        require(curveTickRange % TICK_SPACING == 0, LicenseHook_InvalidCurveTickRange());
        require(isAllowedNumeraires[numeraire], LicenseHook_NumeraireNotAllowed());

        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(asset),
            currency1: Currency.wrap(numeraire),
            hooks: IHooks(this),
            fee: 0,
            tickSpacing: TICK_SPACING
        });

        IPoolManager(poolManager).initialize(
            poolKey,
            TickMath.getSqrtPriceAtTick(startingTick)
        );

        poolStates[poolKey.toId()] = PoolState({curveTickRange: curveTickRange});
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
