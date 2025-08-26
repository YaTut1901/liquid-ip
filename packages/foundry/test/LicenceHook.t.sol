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
import {Currency} from "@v4-core/types/Currency.sol";
import {IHooks} from "@v4-core/interfaces/IHooks.sol";
import {PoolId, PoolIdLibrary} from "@v4-core/types/PoolId.sol";
import {StateLibrary} from "@v4-core/libraries/StateLibrary.sol";
import {TickMath} from "@v4-core/libraries/TickMath.sol";
import {PoolState} from "../contracts/LicenseHook.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 1000000 * 10 ** 18);
    }
}

contract LicenseHookTest is Test {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    LicenseHook licenseHook;
    PatentERC721 patentERC721;
    LicenseERC20 asset;
    MockERC20 numeraire;
    IPoolManager poolManager;

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function setUp() public {
        poolManager = new PoolManager(address(this));

        patentERC721 = new PatentERC721();
        uint256 patentId = patentERC721.mint(
            address(this),
            "https://example.com/asset"
        );

        asset = new LicenseERC20(
            address(patentERC721),
            patentId,
            "https://example.com/asset"
        );
        asset.mint(address(this), 1000000 * 10 ** 18);

        numeraire = new MockERC20("Numeraire", "NUM");
        address[] memory allowedNumeraires = new address[](1);
        allowedNumeraires[0] = address(numeraire);

        bytes memory creationCode = type(LicenseHook).creationCode;
        uint160 flags = uint160(
            Hooks.BEFORE_INITIALIZE_FLAG |
                Hooks.AFTER_INITIALIZE_FLAG |
                Hooks.BEFORE_ADD_LIQUIDITY_FLAG |
                Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG |
                Hooks.BEFORE_SWAP_FLAG |
                Hooks.AFTER_SWAP_FLAG
        );
        bytes memory constructorArgs = abi.encode(
            IPoolManager(address(poolManager)),
            address(patentERC721),
            allowedNumeraires
        );
        (, bytes32 salt) = HookMiner.find(
            address(this),
            flags,
            creationCode,
            constructorArgs
        );

        licenseHook = new LicenseHook{salt: salt}(
            poolManager,
            address(patentERC721),
            allowedNumeraires
        );
    }

    function test_initialize_success_setup_before_epochs() public {
        int24 startingTick = int24(2000);
        int24 curveTickRange = int24(900);
        uint256 startingTime = block.timestamp + 1 hours;
        uint256 endingTime = startingTime + 2 hours;
        uint24 totalEpochs = 10;
        uint256 tokensToSell = 1000;
        uint24 epochDuration = uint24(
            (endingTime - startingTime) / totalEpochs
        );
        int24 epochTickRange = int24(curveTickRange / int24(totalEpochs));
        uint24 currentEpoch = uint24(0);

        licenseHook.initialize(
            address(asset),
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
            tickSpacing: licenseHook.TICK_SPACING()
        });

        PoolId poolId = poolKey.toId();

        (uint160 sqrtPriceX96, , , ) = poolManager.getSlot0(poolId);
        // pool exists and price is at the starting tick
        assertTrue(sqrtPriceX96 == TickMath.getSqrtPriceAtTick(startingTick));

        (
            int24 startingTick_,
            int24 curveTickRange_,
            int24 epochTickRange_,
            uint256 startingTime_,
            uint256 endingTime_,
            uint24 epochDuration_,
            uint24 currentEpoch_,
            uint24 totalEpochs_,
            uint256 tokensToSell_,
            uint24 positionCounter_
        ) = licenseHook.poolStates(poolId);

        assertEq(startingTick_, startingTick);
        assertEq(curveTickRange_, curveTickRange);
        assertEq(epochTickRange_, epochTickRange);
        assertEq(startingTime_, startingTime);
        assertEq(endingTime_, endingTime);
        assertEq(epochDuration_, epochDuration);
        assertEq(currentEpoch_, currentEpoch);
        assertEq(totalEpochs_, totalEpochs);
        assertEq(tokensToSell_, tokensToSell);
        assertEq(positionCounter_, 0);

        // no positions added yet because we are before epochs
        assertEq(poolManager.getLiquidity(poolId), 0);
    }

    function test_initialize_success_setup_at_epoch() public {
        int24 startingTick = int24(2000);
        int24 curveTickRange = int24(900);
        uint256 startingTime = block.timestamp;
        uint256 endingTime = startingTime + 2 hours;
        uint24 totalEpochs = 10;
        uint256 tokensToSell = 1000;
        uint24 epochDuration = uint24(
            (endingTime - startingTime) / totalEpochs
        );
        int24 epochTickRange = int24(curveTickRange / int24(totalEpochs));
        uint24 currentEpoch = uint24(0);

        licenseHook.initialize(
            address(asset),
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
            tickSpacing: licenseHook.TICK_SPACING()
        });

        PoolId poolId = poolKey.toId();

        (uint160 sqrtPriceX96, , , ) = poolManager.getSlot0(poolId);
        // pool exists and price is at the starting tick
        assertTrue(sqrtPriceX96 == TickMath.getSqrtPriceAtTick(startingTick));

        
    }
}

// write a test for initialize function. test should include successful execution of pool setup. conduct checks to determine if pool is created successfully and initial liquidity is placed:
// 1) call pool manager and check if pool id exists
// 2) check if in hook state is saved with provided values
// 3) check if pool has initial position placed in range of provided values (e.g. from startingTick - epochRange to startingTick)
// 4) check if position consists only of asset tokens
