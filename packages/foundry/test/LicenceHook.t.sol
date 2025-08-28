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
import {LiquidityAmounts} from "@v4-core-test/utils/LiquidityAmounts.sol";
import {SafeCastLib} from "@solady/utils/SafeCastLib.sol";
import {CampaignManager} from "../contracts/CampaignManager.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 1000000 * 10 ** 18);
    }
}

contract LicenseHookTest is Test {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    using SafeCastLib for uint128;

    string constant ASSET_METADATA_URI = "https://example.com/asset";
    int24 TICK_SPACING = 30;

    LicenseHook licenseHook;
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
        bytes memory creationCode = type(LicenseHook).creationCode;
        uint160 flags = uint160(
            Hooks.BEFORE_INITIALIZE_FLAG |
                Hooks.AFTER_INITIALIZE_FLAG |
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
        licenseHook = new LicenseHook{salt: salt}(poolManager);

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
    }

    function test_initialize_success_setup_before_epochs() public {
        int24 startingTick = int24(2010);
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
            currency1: Currency.wrap(asset),
            hooks: IHooks(address(licenseHook)),
            fee: 0,
            tickSpacing: TICK_SPACING
        });

        PoolId poolId = poolKey.toId();

        (uint160 sqrtPriceX96, , , ) = poolManager.getSlot0(poolId);
        // pool exists and price is at the starting tick
        assertEq(sqrtPriceX96, TickMath.getSqrtPriceAtTick(startingTick));

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

        (uint160 sqrtPriceX96, , , ) = poolManager.getSlot0(poolId);
        // pool exists and price is at the starting tick
        assertEq(sqrtPriceX96, TickMath.getSqrtPriceAtTick(startingTick));

        uint128 epochPositionLiquidityExpected = LiquidityAmounts
            .getLiquidityForAmount1(
                TickMath.getSqrtPriceAtTick(startingTick - epochTickRange),
                TickMath.getSqrtPriceAtTick(startingTick),
                tokensToSell / totalEpochs
            );

        (uint128 epochPositionLiquidityActual, , ) = poolManager.getPositionInfo(
            poolId,
            address(licenseHook),
            startingTick - epochTickRange,
            startingTick,
            bytes32(0)
        );

        assertEq(epochPositionLiquidityActual, epochPositionLiquidityExpected);
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
}

// write a test for initialize function. test should include successful execution of pool setup. conduct checks to determine if pool is created successfully and initial liquidity is placed:
// 1) call pool manager and check if pool id exists
// 2) check if in hook state is saved with provided values
// 3) check if pool has initial position placed in range of provided values (e.g. from startingTick - epochRange to startingTick)
// 4) check if position consists only of asset tokens
