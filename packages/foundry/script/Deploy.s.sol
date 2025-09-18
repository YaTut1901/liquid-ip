//SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "./DeployHelpers.s.sol";
import {console} from "forge-std/console.sol";
import {PatentERC721} from "../contracts/PatentERC721.sol";
import {PatentMetadataVerifier} from "../contracts/PatentMetadataVerifier.sol";
import {ITaskMailbox} from "@hourglass/lib/eigenlayer-middleware/lib/eigenlayer-contracts/src/contracts/interfaces/ITaskMailbox.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPoolManager} from "@v4-core/interfaces/IPoolManager.sol";
import {IRehypothecationManager} from "../contracts/interfaces/IRehypothecationManager.sol";
import {RehypothecationManager} from "../contracts/RehypothecationManager.sol";
import {Hooks} from "@v4-core/libraries/Hooks.sol";
import {HookMiner} from "@v4-periphery/utils/HookMiner.sol";
import {PublicLicenseHook} from "../contracts/hook/PublicLicenseHook.sol";
import {Status} from "../contracts/PatentMetadataVerifier.sol";
import {PublicCampaignManager} from "../contracts/manager/PublicCampaignManager.sol";
import {LicenseERC20} from "../contracts/token/LicenseERC20.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {ISimpleV4Router} from "../contracts/router/ISimpleV4Router.sol";
import {PoolKey} from "@v4-core/types/PoolKey.sol";
import {Currency} from "@v4-core/types/Currency.sol";
import {IHooks} from "@v4-core/interfaces/IHooks.sol";

interface IUSDC {
    function masterMinter() external view returns (address);
    function configureMinter(address minter, uint256 minterAllowedAmount) external returns (bool);
    function mint(address to, uint256 amount) external returns (bool);
}

contract DeployScript is ScaffoldETHDeploy {
    function run() external ScaffoldEthDeployerRunner {
        // mainnet PoolManager
        IPoolManager poolManager = IPoolManager(
            0x000000000004444c5dc75cB358380D2e3dE08A90
        );

        _logAndSave(address(poolManager), "PoolManager");

        PatentMetadataVerifier patentMetadataVerifier = new PatentMetadataVerifier(
                ITaskMailbox(address(0)),
                address(deployer),
                0,
                address(deployer)
            );

        _logAndSave(address(patentMetadataVerifier), "PatentMetadataVerifier");

        // Pre-mark verifier metadata status as VALID to avoid mailbox path
        // metadata mapping is at storage slot 2
        bytes32 slot = keccak256(abi.encode(uint256(1), uint256(2)));
        vm.store(
            address(patentMetadataVerifier),
            slot,
            bytes32(uint256(uint8(Status.VALID)))
        );

        PatentERC721 patentERC721 = new PatentERC721(
            patentMetadataVerifier,
            deployer
        );
        patentMetadataVerifier.setPatentErc721(patentERC721);

        _logAndSave(address(patentERC721), "PatentERC721");

        // ipfs hash of the json file already deployed on ipfs
        // mint to address with index 0 from anvil generated addresses
        patentERC721.mint(
            deployer,
            "ipfs://bafkreigpjxayyoyap4ja5vcf7wsoly75iszt3siqxjjpltjysyqnpxsz7e"
        );

        // mint patent nft with deployer as owner and transfer ownership to patentMetadataVerifier as it should be in real setup
        patentERC721.transferOwnership(address(patentMetadataVerifier));

        // Mainnet Aave V3 addresses
        address AAVE_POOL = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;
        address AAVE_DATA_PROVIDER = 0x7B4EB56E7CD4b454BA8ff71E4518426369a138a3;
        address WRAPPED_TOKEN_GATEWAY = 0xD322A49006FC828F9B5B37Ab215F99B4E5caB19C;

        RehypothecationManager rehypothecationManager = new RehypothecationManager(
                deployer,
                AAVE_POOL,
                AAVE_DATA_PROVIDER,
                WRAPPED_TOKEN_GATEWAY
            );
        _logAndSave(address(rehypothecationManager), "RehypothecationManager");

        // Deploy LicenseHook (owner: deployer for now) using HookMiner
        bytes memory creationCode = type(PublicLicenseHook).creationCode;
        uint160 flags = uint160(
            Hooks.BEFORE_INITIALIZE_FLAG |
                Hooks.BEFORE_ADD_LIQUIDITY_FLAG |
                Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG |
                Hooks.BEFORE_SWAP_FLAG |
                Hooks.BEFORE_DONATE_FLAG
        );
        bytes memory constructorArgs = abi.encode(
            poolManager,
            patentMetadataVerifier,
            rehypothecationManager,
            deployer
        );
        (, bytes32 salt) = HookMiner.find(
            0x4e59b44847b379578588920cA78FbF26c0B4956C,
            flags,
            creationCode,
            constructorArgs
        );
        PublicLicenseHook licenseHook = new PublicLicenseHook{salt: salt}(
            poolManager,
            patentMetadataVerifier,
            rehypothecationManager,
            deployer
        );
        _logAndSave(address(licenseHook), "PublicLicenseHook");

        rehypothecationManager.authorizeHook(address(licenseHook));

        IERC20[] memory allowedNumeraires = new IERC20[](1);
        // USDC token address on mainnet
        IERC20 numeraire = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
        allowedNumeraires[0] = numeraire;

        _mintUSDCViaFFI(address(numeraire), deployer, 1_000_000 * 1e6);
        
        _logAndSave(address(numeraire), "USDC");

        PublicCampaignManager campaignManager = new PublicCampaignManager(
            deployer,
            poolManager,
            patentERC721,
            allowedNumeraires,
            licenseHook
        );
        _logAndSave(address(campaignManager), "CampaignManager");

        licenseHook.transferOwnership(address(campaignManager));

        patentERC721.safeTransferFrom(deployer, address(campaignManager), 1);

        ISimpleV4Router simpleRouter = ISimpleV4Router(
            deployCode(
                "SimpleV4Router.sol:SimpleV4Router",
                abi.encode(poolManager)
            )
        );
        _logAndSave(address(simpleRouter), "SimpleV4Router");

        string
            memory metadataUri = "ipfs://bafkreig5fcmv6xo4if6gr36l26pfo5mcv6tmes5czu4gv7ed4t7y5o4waq";
        (bytes32 licenseSalt, address asset) = _mineSalt(
            patentERC721,
            1,
            metadataUri,
            numeraire,
            address(campaignManager)
        );
        _logAndSave(address(asset), "LicenseERC20");

        // init campaign with metadata already stored on ipfs
        campaignManager.initialize(
            1,
            metadataUri,
            licenseSalt,
            numeraire,
            _getSimpleConfig()
        );

        // configure SimpleV4Router default pool key for easy swaps
        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(address(numeraire)),
            currency1: Currency.wrap(asset),
            hooks: IHooks(address(licenseHook)),
            fee: 0,
            tickSpacing: campaignManager.TICK_SPACING()
        });
        simpleRouter.configureDefaultPoolKey(poolKey);
    }


    /// @notice Mint USDC to a recipient using FFI to impersonate masterMinter on mainnet fork
    /// @param usdcAddress The USDC contract address
    /// @param recipient The address to mint USDC to
    /// @param amount The amount of USDC to mint (in wei, e.g., 1e6 for 1 USDC)
    function _mintUSDCViaFFI(address usdcAddress, address recipient, uint256 amount) internal {
        IUSDC usdc = IUSDC(usdcAddress);
        address mm = usdc.masterMinter();
        address tempMinter = 0x1111111111111111111111111111111111111111;
        string memory rpc = "http://localhost:8545";

        // pause broadcast, run cast commands via FFI
        vm.stopBroadcast();

        // impersonate and fund masterMinter
        {
            string[] memory cmd = new string[](3);
            cmd[0] = "bash"; cmd[1] = "-lc";
            cmd[2] = string.concat(
                "cast rpc anvil_impersonateAccount ", vm.toString(mm), " --rpc-url ", rpc
            );
            vm.ffi(cmd);
        }
        {
            string[] memory cmd = new string[](3);
            cmd[0] = "bash"; cmd[1] = "-lc";
            cmd[2] = string.concat(
                "cast rpc anvil_setBalance ", vm.toString(mm), " 0xDE0B6B3A7640000 --rpc-url ", rpc
            );
            vm.ffi(cmd);
        }
        // configure tempMinter as minter from masterMinter
        {
            string[] memory cmd = new string[](3);
            cmd[0] = "bash"; cmd[1] = "-lc";
            cmd[2] = string.concat(
                "cast send ",
                vm.toString(usdcAddress),
                " \"configureMinter(address,uint256)\" ",
                vm.toString(tempMinter),
                " 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff ",
                "--from ", vm.toString(mm), " --unlocked --rpc-url ", rpc
            );
            vm.ffi(cmd);
        }
        // impersonate and fund tempMinter, then mint to recipient
        {
            string[] memory cmd = new string[](3);
            cmd[0] = "bash"; cmd[1] = "-lc";
            cmd[2] = string.concat(
                "cast rpc anvil_impersonateAccount ", vm.toString(tempMinter), " --rpc-url ", rpc
            );
            vm.ffi(cmd);
        }
        {
            string[] memory cmd = new string[](3);
            cmd[0] = "bash"; cmd[1] = "-lc";
            cmd[2] = string.concat(
                "cast rpc anvil_setBalance ", vm.toString(tempMinter), " 0xDE0B6B3A7640000 --rpc-url ", rpc
            );
            vm.ffi(cmd);
        }
        {
            string[] memory cmd = new string[](3);
            cmd[0] = "bash"; cmd[1] = "-lc";
            cmd[2] = string.concat(
                "cast send ",
                vm.toString(usdcAddress),
                " \"mint(address,uint256)\" ",
                vm.toString(recipient),
                " ", vm.toString(amount),
                " --from ", vm.toString(tempMinter), " --unlocked --rpc-url ", rpc
            );
            vm.ffi(cmd);
        }

        // resume broadcast
        vm.startBroadcast();
        console.log("USDC balance (recipient):", IERC20(usdcAddress).balanceOf(recipient));
    }

    function _getSimpleConfig() internal view returns (bytes memory config) {
        uint8 ver = 1;
        uint16 epochs = 1;
        uint32 epoch0Offset = 19 + 4 * uint32(epochs);
        config = bytes.concat(
            bytes8(keccak256("PublicCampaignConfig")),
            abi.encodePacked(uint8(ver)),
            abi.encodePacked(uint64(block.timestamp + 2 * 60)),
            abi.encodePacked(uint16(epochs)),
            abi.encodePacked(uint32(epoch0Offset)),
            abi.encodePacked(uint32(3600)),
            abi.encodePacked(uint8(uint8(1))),
            abi.encodePacked(int24(-600)),
            abi.encodePacked(int24(600)),
            abi.encodePacked(uint128(10 * 1e6))
        );
    }

    function _mineSalt(
        PatentERC721 patentErc721,
        uint256 patentId,
        string memory assetMetadataUri,
        IERC20 numeraire,
        address deployerAddress
    ) internal view returns (bytes32, address) {
        bytes32 licenseSalt;
        uint256 count = 0;
        while (true) {
            licenseSalt = keccak256(abi.encodePacked(count));
            bytes32 bytecodeHash = keccak256(
                abi.encodePacked(
                    type(LicenseERC20).creationCode,
                    abi.encode(patentErc721, patentId, assetMetadataUri)
                )
            );
            address asset = Create2.computeAddress(
                licenseSalt,
                bytecodeHash,
                deployerAddress
            );
            if (asset > address(numeraire)) {
                return (licenseSalt, asset);
            }
            unchecked {
                ++count;
            }
        }
    }

    function _logAndSave(address addr, string memory name) internal {
        console.log(name, ":", addr);
        deployments.push(Deployment({name: name, addr: addr}));
    }
}
