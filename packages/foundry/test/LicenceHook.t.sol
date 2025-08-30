// 1) swap amount of tokens bigger then epoch
// 2) try to swap tokens on epoch which is out of specified campaign duration
// 3) to check if the pool has initial position after intialization at the starting tick, filled with JUST asset
// 4) conduct a swap and check if the position is filled with both numeraire and asset
// 5) to check if the pool has a position after epoch cahnged at the proper tick range, filled with JUST asset
// 6) to check if the pool DOES NOT have a position in previous epoch after epoch changed
// 7) initiate an epoch change by swap after some amount of epoch changed

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {LicenseHook} from "../contracts/LicenseHook.sol";
import {IPoolManager} from "@v4-core/interfaces/IPoolManager.sol";
import {PoolManager} from "@v4-core/PoolManager.sol";
import {PatentERC721} from "../contracts/PatentERC721.sol";
import {LicenseERC20} from "../contracts/LicenseERC20.sol";
import {Test} from "forge-std/Test.sol";
import {Hooks} from "@v4-core/libraries/Hooks.sol";
import {HookMiner} from "@v4-periphery/utils/HookMiner.sol";
import {PoolKey} from "@v4-core/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "@v4-core/types/Currency.sol";
import {IHooks} from "@v4-core/interfaces/IHooks.sol";
import {PoolId, PoolIdLibrary} from "@v4-core/types/PoolId.sol";
import {StateLibrary} from "@v4-core/libraries/StateLibrary.sol";
import {TickMath} from "@v4-core/libraries/TickMath.sol";
import {PoolState} from "../contracts/LicenseHook.sol";
import {LiquidityAmounts} from "@v4-core-test/utils/LiquidityAmounts.sol";
import {SafeCastLib} from "@solady/utils/SafeCastLib.sol";
import {CampaignManager} from "../contracts/CampaignManager.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {SwapParams} from "@v4-core/types/PoolOperation.sol";
import {TransientStateLibrary} from "@v4-core/libraries/TransientStateLibrary.sol";
import {CurrencySettler} from "@v4-core-test/utils/CurrencySettler.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 1000000 * 10 ** 18);
    }
}

contract LicenseHookHarness is LicenseHook {
    constructor(IPoolManager manager) LicenseHook(manager) {}

    function poolStatesSlot() external pure returns (bytes32 s) {
        assembly {
            s := poolStates.slot
        }
    }

    function positionsSlot() external pure returns (bytes32 s) {
        assembly {
            s := positions.slot
        }
    }
}

contract LicenseHookTest is Test {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    using TransientStateLibrary for IPoolManager;
    using CurrencySettler for Currency;
    using SafeCastLib for uint128;

    string constant ASSET_METADATA_URI = "https://example.com/asset";
    int24 TICK_SPACING = 30;

    LicenseHookHarness licenseHook;
    PatentERC721 patentErc721;
    MockERC20 numeraire;
    address asset;
    IPoolManager poolManager;
    CampaignManager campaignManager;
    bytes32 licenseSalt;
    uint256 patentId;

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function unlockCallback(
        bytes calldata data
    ) external returns (bytes memory) {
        require(msg.sender == address(poolManager), "only manager");
        (PoolKey memory key, SwapParams memory params) = abi.decode(
            data,
            (PoolKey, SwapParams)
        );

        // perform swap
        poolManager.swap(key, params, "");

        // fetch deltas for this contract
        int256 delta0 = poolManager.currencyDelta(address(this), key.currency0);
        int256 delta1 = poolManager.currencyDelta(address(this), key.currency1);

        // settle negatives (owe tokens to pool)
        if (delta0 < 0) {
            key.currency0.settle(
                poolManager,
                address(this),
                uint256(-delta0),
                false
            );
        }
        if (delta1 < 0) {
            key.currency1.settle(
                poolManager,
                address(this),
                uint256(-delta1),
                false
            );
        }

        // take positives (claim tokens from pool)
        if (delta0 > 0) {
            key.currency0.take(
                poolManager,
                address(this),
                uint256(delta0),
                false
            );
        }
        if (delta1 > 0) {
            key.currency1.take(
                poolManager,
                address(this),
                uint256(delta1),
                false
            );
        }

        return new bytes(0);
    }

    function setUp() public {
        // initialize pool manager
        poolManager = new PoolManager(address(this));

        // initialize patent ERC721
        patentErc721 = new PatentERC721();
        patentId = patentErc721.mint(address(this), ASSET_METADATA_URI);

        // initialize numeraire
        numeraire = new MockERC20("Numeraire", "NUM");
        address[] memory allowedNumeraires = new address[](1);
        allowedNumeraires[0] = address(numeraire);

        // initialize license hook
        bytes memory creationCode = type(LicenseHookHarness).creationCode;
        uint160 flags = uint160(
            Hooks.BEFORE_INITIALIZE_FLAG |
                Hooks.BEFORE_SWAP_FLAG
        );
        bytes memory constructorArgs = abi.encode(
            IPoolManager(address(poolManager))
        );
        (address licenseHookAddress, bytes32 salt) = HookMiner.find(
            address(this),
            flags,
            creationCode,
            constructorArgs
        );
        licenseHook = new LicenseHookHarness{salt: salt}(poolManager);

        // initialize campaign manager
        campaignManager = new CampaignManager(
            poolManager,
            patentErc721,
            allowedNumeraires,
            licenseHook
        );
        licenseHook.transferOwnership(address(campaignManager));

        // find salt for license
        licenseSalt = _findLicenseSalt();

        // compute asset address
        bytes32 bytecodeHash = keccak256(
            abi.encodePacked(
                type(LicenseERC20).creationCode,
                abi.encode(patentErc721, patentId, ASSET_METADATA_URI)
            )
        );
        asset = Create2.computeAddress(
            licenseSalt,
            bytecodeHash,
            address(campaignManager)
        );

        // delegate patent
        patentErc721.safeTransferFrom(
            address(this),
            address(campaignManager),
            patentId
        );

        // transfer numeraire to license hook
        numeraire.transfer(address(licenseHook), 10 ** 18);
    }

    function test_swap_flow_across_epochs() public {
        int24 startingTick = int24(2010);
        int24 curveTickRange = int24(900);
        uint256 startingTime = block.timestamp;
        uint256 endingTime = startingTime + 2 hours;
        uint24 totalEpochs = 10;
        uint256 tokensToSell = 1000;
        int24 epochTickRange = int24(curveTickRange / int24(totalEpochs));

        campaignManager.initialize(
            patentId,
            ASSET_METADATA_URI,
            licenseSalt,
            address(numeraire),
            startingTick,
            curveTickRange,
            startingTime,
            endingTime,
            totalEpochs,
            tokensToSell
        );

        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(address(numeraire)),
            currency1: Currency.wrap(address(asset)),
            hooks: IHooks(address(licenseHook)),
            fee: 0,
            tickSpacing: TICK_SPACING
        });

        PoolId poolId = poolKey.toId();

        (uint160 sqrtPriceBefore, , , ) = poolManager.getSlot0(poolId);
        assertEq(sqrtPriceBefore, TickMath.getSqrtPriceAtTick(startingTick));

        // Approve pool manager to pull numeraire on settle
        numeraire.approve(address(poolManager), type(uint256).max);

        // Execute a small swap within epoch 1 moving price down slightly (via unlock)
        poolManager.unlock(
            abi.encode(
                poolKey,
                SwapParams({
                    zeroForOne: true,
                    amountSpecified: 100,
                    sqrtPriceLimitX96: TickMath.getSqrtPriceAtTick(
                        startingTick - 1
                    )
                })
            )
        );

        (uint160 sqrtPriceAfterFirstSwap, , , ) = poolManager.getSlot0(poolId);
        // Price should have changed from the starting tick
        assertTrue(sqrtPriceAfterFirstSwap != sqrtPriceBefore);

        // After first swap (epoch 1), the epoch-1 position should exist with expected liquidity
        uint128 expectedLiqEpoch1 = LiquidityAmounts.getLiquidityForAmount1(
            TickMath.getSqrtPriceAtTick(startingTick - epochTickRange),
            TickMath.getSqrtPriceAtTick(startingTick),
            tokensToSell / totalEpochs
        );
        (uint128 actualLiqEpoch1, , ) = poolManager.getPositionInfo(
            poolId,
            address(licenseHook),
            startingTick - epochTickRange,
            startingTick,
            bytes32(0)
        );
        assertEq(actualLiqEpoch1, expectedLiqEpoch1);

        // Check pool's numeraire balance increased
        uint256 numeraireBalanceAfterFirstSettle = numeraire.balanceOf(
            address(poolManager)
        );
        assertGt(numeraireBalanceAfterFirstSettle, 0);

        // Warp into epoch 3 and trigger epoch rollover via a swap
        (
            ,
            ,
            ,
            uint256 startingTime_,
            ,
            uint24 epochDuration_,
            ,
            ,

        ) = readPoolState(licenseHook, poolId);

        uint256 toEpoch3 = startingTime_ + uint256(epochDuration_) * 2 + 1;
        vm.warp(toEpoch3);

        int24 epoch3TickUpper = startingTick - epochTickRange * int24(2);
        int24 epoch3TickLower = epoch3TickUpper - epochTickRange;

        // Trigger unlock; set limit to epoch upper so final price aligns with epoch start
        poolManager.unlock(
            abi.encode(
                poolKey,
                SwapParams({
                    zeroForOne: true,
                    amountSpecified: 100,
                    sqrtPriceLimitX96: TickMath.getSqrtPriceAtTick(
                        epoch3TickUpper
                    )
                })
            )
        );

        (uint160 sqrtPriceAtEpoch3, , , ) = poolManager.getSlot0(poolId);
        assertEq(
            sqrtPriceAtEpoch3,
            TickMath.getSqrtPriceAtTick(epoch3TickUpper)
        );

        // Old epoch 1 position should be removed
        (uint128 oldLiq, , ) = poolManager.getPositionInfo(
            poolId,
            address(licenseHook),
            startingTick - epochTickRange,
            startingTick,
            bytes32(0)
        );
        assertEq(oldLiq, 0);

        // New epoch 3 position should exist with expected liquidity
        uint128 expectedLiqEpoch3 = LiquidityAmounts.getLiquidityForAmount1(
            TickMath.getSqrtPriceAtTick(epoch3TickLower),
            TickMath.getSqrtPriceAtTick(epoch3TickUpper),
            tokensToSell / totalEpochs
        );
        (uint128 actualLiqEpoch3, , ) = poolManager.getPositionInfo(
            poolId,
            address(licenseHook),
            epoch3TickLower,
            epoch3TickUpper,
            bytes32(0)
        );
        assertEq(actualLiqEpoch3, expectedLiqEpoch3);

        // Execute another swap in epoch 3 and settle; numeraire balance should increase
        poolManager.unlock(
            abi.encode(
                poolKey,
                SwapParams({
                    zeroForOne: true,
                    amountSpecified: 100,
                    sqrtPriceLimitX96: TickMath.getSqrtPriceAtTick(
                        epoch3TickUpper - 1
                    )
                })
            )
        );
        uint256 numeraireBalanceAfterSecondSettle = numeraire.balanceOf(
            address(poolManager)
        );
        assertGt(
            numeraireBalanceAfterSecondSettle,
            numeraireBalanceAfterFirstSettle
        );

        // After second swap in epoch 3, the epoch-3 position should still have the same liquidity
        uint128 actualLiqEpoch3After;
        uint256 _unused0;
        uint256 _unused1;
        (actualLiqEpoch3After, _unused0, _unused1) = poolManager.getPositionInfo(
            poolId,
            address(licenseHook),
            epoch3TickLower,
            epoch3TickUpper,
            bytes32(0)
        );
        assertEq(actualLiqEpoch3After, expectedLiqEpoch3);
    }

    function _findLicenseSalt() internal view returns (bytes32) {
        address deployer = address(campaignManager);

        bytes memory initCode = abi.encodePacked(
            type(LicenseERC20).creationCode,
            abi.encode(patentErc721, patentId, ASSET_METADATA_URI)
        );
        bytes32 initCodeHash = keccak256(initCode);
        address numeraireAddr = address(numeraire);

        for (uint256 i = 0; i < 100000; i++) {
            bytes32 salt = bytes32(i);
            bytes32 hash = keccak256(
                abi.encodePacked(bytes1(0xff), deployer, salt, initCodeHash)
            );
            address candidate = address(uint160(uint256(hash)));
            if (candidate > numeraireAddr) {
                return salt;
            }
        }
        revert("salt not found");
    }

    function _poolStateBaseSlot(
        PoolId poolId
    ) internal view returns (bytes32) {
        bytes32 slot = licenseHook.poolStatesSlot();
        return keccak256(abi.encode(PoolId.unwrap(poolId), slot));
    }

    function readPoolState(
        LicenseHookHarness hook,
        PoolId poolId
    )
        internal
        view
        returns (
            int24 startingTick,
            int24 curveTickRange,
            int24 epochTickRange,
            uint256 startingTime,
            uint256 endingTime,
            uint24 epochDuration,
            uint24 currentEpoch,
            uint24 totalEpochs,
            uint256 tokensToSell
        )
    {
        bytes32 base = _poolStateBaseSlot(poolId);

        uint256 w0 = uint256(vm.load(address(hook), base));
        startingTick = int24(uint24(w0));
        curveTickRange = int24(uint24(w0 >> 24));
        epochTickRange = int24(uint24(w0 >> 48));

        startingTime = uint256(
            vm.load(address(hook), bytes32(uint256(base) + 1))
        );
        endingTime = uint256(
            vm.load(address(hook), bytes32(uint256(base) + 2))
        );

        uint256 w3 = uint256(
            vm.load(address(hook), bytes32(uint256(base) + 3))
        );
        epochDuration = uint24(w3);
        currentEpoch = uint24(w3 >> 24);
        totalEpochs = uint24(w3 >> 48);

        tokensToSell = uint256(
            vm.load(address(hook), bytes32(uint256(base) + 4))
        );
    }
}

// write a test for initialize function. test should include successful execution of pool setup. conduct checks to determine if pool is created successfully and initial liquidity is placed:
// 1) call pool manager and check if pool id exists
// 2) check if in hook state is saved with provided values
// 3) check if pool has initial position placed in range of provided values (e.g. from startingTick - epochRange to startingTick)
// 4) check if position consists only of asset tokens
