// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {IPoolManager} from "@v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "@v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@v4-core/types/PoolId.sol";
import {Currency} from "@v4-core/types/Currency.sol";
import {IHooks} from "@v4-core/interfaces/IHooks.sol";
import {TickMath} from "@v4-core/libraries/TickMath.sol";
import {PublicLicenseHook} from "../contracts/hook/PublicLicenseHook.sol";
import {IRehypothecationManager} from "../contracts/interfaces/IRehypothecationManager.sol";
import {PatentMetadataVerifier} from "../contracts/PatentMetadataVerifier.sol";
import {PatentERC721} from "../contracts/PatentERC721.sol";
import {LicenseERC20} from "../contracts/token/LicenseERC20.sol";
import {ITaskMailbox} from "@hourglass/lib/eigenlayer-middleware/lib/eigenlayer-contracts/src/contracts/interfaces/ITaskMailbox.sol";
import {Hooks} from "@v4-core/libraries/Hooks.sol";
import {HookMiner} from "@v4-periphery/utils/HookMiner.sol";
import {PublicCampaignConfig} from "../contracts/lib/PublicCampaignConfig.sol";
import {ISimpleV4Router} from "../contracts/router/ISimpleV4Router.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// no longer needed

contract OZMockERC20 is ERC20 {
    constructor(string memory n, string memory s) ERC20(n, s) {}
    function mint(address to, uint256 a) external { _mint(to, a); }
}

contract SimpleV4RouterIntegrationTest is Test {
    using PoolIdLibrary for PoolKey;
    using PublicCampaignConfig for bytes;

    IPoolManager internal manager;
    PublicLicenseHook internal hook;
    PatentMetadataVerifier internal verifier;
    PatentERC721 internal patentNft;
    LicenseERC20 internal license;
    OZMockERC20 internal numeraire;
    PoolKey internal key;
    PoolId internal poolId;
    ISimpleV4Router internal router;
    address internal routerAddr;

    function setUp() public {
        // Deploy PoolManager
        address mgr = deployCode("PoolManager.sol:PoolManager", abi.encode(address(this)));
        manager = IPoolManager(mgr);

        // Verifier + NFT
        verifier = new PatentMetadataVerifier(ITaskMailbox(address(0)), address(this), 0, address(this));
        patentNft = new PatentERC721(verifier, address(this));
        verifier.setPatentErc721(patentNft);

        // Mine and deploy hook
        uint160 flags = uint160(
            Hooks.BEFORE_INITIALIZE_FLAG |
            Hooks.BEFORE_ADD_LIQUIDITY_FLAG |
            Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG |
            Hooks.BEFORE_SWAP_FLAG |
            Hooks.BEFORE_DONATE_FLAG
        );
        bytes memory creationCode = type(PublicLicenseHook).creationCode;
        bytes memory constructorArgs = abi.encode(manager, verifier, IRehypothecationManager(address(0)), address(this));
        (, bytes32 salt) = HookMiner.find(address(this), flags, creationCode, constructorArgs);
        hook = new PublicLicenseHook{salt: salt}(manager, verifier, IRehypothecationManager(address(0)), address(this));

        // Tokens
        uint256 patentId = patentNft.mint(address(this), "ipfs://meta");
        license = new LicenseERC20(patentNft, patentId, "ipfs://lic");
        numeraire = new OZMockERC20("TKN","TKN");

        // Ensure address ordering (retry numeraire if needed)
        // if ordering fails, redeploy numeraire until it's lower than license
        if (address(numeraire) >= address(license)) {
            for (uint256 i = 0; i < 10; i++) {
                numeraire = new OZMockERC20("TKN","TKN");
                if (address(numeraire) < address(license)) break;
            }
            require(address(numeraire) < address(license), "order fail");
        }

        // Mint balances
        numeraire.mint(address(this), 1e24);
        numeraire.mint(address(hook), 1e24); // ensure hook can settle negatives
        license.mint(address(hook), 1e24); // hook will allocate on first swap

        // Build pool key
        key = PoolKey({
            currency0: Currency.wrap(address(numeraire)),
            currency1: Currency.wrap(address(license)),
            fee: 0,
            tickSpacing: 30,
            hooks: IHooks(address(hook))
        });
        poolId = key.toId();

        // Initialize hook state with simple one-epoch config
        bytes memory cfg = _simpleConfig();
        // mark metadata VALID
        bytes32 metaSlot = keccak256(abi.encode(uint256(1), uint256(2)));
        vm.store(address(verifier), metaSlot, bytes32(uint256(uint8(1))));
        hook.initializeState(key, cfg);

        // Initialize pool at tick 0 (hook will anchor on first swap)
        manager.initialize(key, TickMath.getSqrtPriceAtTick(0));

        // Deploy router and configure (via artifact)
        routerAddr = deployCode("SimpleV4Router.sol:SimpleV4Router", abi.encode(manager));
        router = ISimpleV4Router(routerAddr);
        router.configureDefaultPoolKey(key);

        // Approvals for router to pull numeraire
        numeraire.approve(routerAddr, type(uint256).max);

        // Warp to within epoch window so hook allows swaps (use current time + 3s)
        vm.warp(block.timestamp + 3);
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function test_ExactInSingle_basic() public {
        uint256 bal0Before = numeraire.balanceOf(address(this));
        uint256 bal1Before = license.balanceOf(address(this));

        // amountIn = 1e18, minOut = 0
        router.swapExactInDefault(1e18, 0);

        uint256 bal0After = numeraire.balanceOf(address(this));
        uint256 bal1After = license.balanceOf(address(this));

        console.log("numeraire delta:", int256(bal0After) - int256(bal0Before));
        console.log("license delta:", int256(bal1After) - int256(bal1Before));

        assertLt(bal0After, bal0Before, "numeraire not spent");
        assertGt(bal1After, bal1Before, "license not received");
    }

    function _simpleConfig() internal view returns (bytes memory config) {
        uint8 ver = 1;
        uint16 epochs = 1;
        uint32 epoch0Offset = 19 + 4 * uint32(epochs);
        config = bytes.concat(
            bytes8(keccak256("PublicCampaignConfig")),
            abi.encodePacked(uint8(ver)),
            abi.encodePacked(uint64(block.timestamp + 2)),
            abi.encodePacked(uint16(epochs)),
            abi.encodePacked(uint32(epoch0Offset)),
            abi.encodePacked(uint32(3600)),
            abi.encodePacked(uint8(uint8(1))),
            abi.encodePacked(int24(-600)),
            abi.encodePacked(int24(600)),
            abi.encodePacked(uint128(10 ether))
        );
    }
}


