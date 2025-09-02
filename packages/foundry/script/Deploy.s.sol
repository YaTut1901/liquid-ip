//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./DeployHelpers.s.sol";
import {PatentERC721} from "../contracts/PatentERC721.sol";
import {CampaignManager} from "../contracts/CampaignManager.sol";
import {LicenseHook} from "../contracts/LicenseHook.sol";
import {PatentMetadataVerifier} from "../contracts/PatentMetadataVerifier.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IPoolManager} from "@v4-core/interfaces/IPoolManager.sol";
import {IEpochLiquidityAllocationManager} from "../contracts/interfaces/IEpochLiquidityAllocationManager.sol";
import {IRehypothecationManager} from "../contracts/interfaces/IRehypothecationManager.sol";
import {Hooks} from "@v4-core/libraries/Hooks.sol";
import {HookMiner} from "@v4-periphery/utils/HookMiner.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 1000000 * 10 ** 18);
    }
}

/**
 * @notice Main deployment script for all contracts
 * @dev Run this when you want to deploy multiple contracts at once
 *
 * Example: yarn deploy # runs this script(without`--file` flag)
 */
contract DeployScript is ScaffoldETHDeploy {
    function run() external ScaffoldEthDeployerRunner {
        // Deploy core ERC721
        PatentERC721 patentERC721 = new PatentERC721();
        console.log("PatentERC721 deployed to:", address(patentERC721));
        deployments.push(
            Deployment({name: "PatentERC721", addr: address(patentERC721)})
        );

        // Read external dependencies from env
        IPoolManager poolManager = IPoolManager(deployer);
        deployments.push(
            Deployment({name: "PoolManager", addr: address(poolManager)})
        );

        // Deploy verifier (owned by AVS owner)
        PatentMetadataVerifier verifier = new PatentMetadataVerifier(
            deployer,
            uint256(86400)
        );
        console.log("PatentMetadataVerifier deployed to:", address(verifier));
        deployments.push(
            Deployment({
                name: "PatentMetadataVerifier",
                addr: address(verifier)
            })
        );

        // Deploy LicenseHook (owner: deployer for now)
        bytes memory creationCode = type(LicenseHook).creationCode;
        uint160 flags = uint160(
            Hooks.BEFORE_INITIALIZE_FLAG |
                Hooks.BEFORE_SWAP_FLAG
        );
        bytes memory constructorArgs = abi.encode(
            IPoolManager(address(poolManager)),
            verifier
        );
        (address licenseHookAddress, bytes32 salt) = HookMiner.find(
            address(this),
            flags,
            creationCode,
            constructorArgs
        );
        LicenseHook licenseHook = new LicenseHook{salt: salt}(poolManager, verifier);
        console.log("LicenseHook deployed to:", address(licenseHook));
        deployments.push(
            Deployment({name: "LicenseHook", addr: address(licenseHook)})
        );

        IERC20[] memory allowedNumeraires = new IERC20[](1);
        IERC20 numeraire = new MockERC20("Numeraire", "NUM");
        allowedNumeraires[0] = numeraire;
        deployments.push(
            Deployment({name: "Numeraire", addr: address(numeraire)})
        );

        IEpochLiquidityAllocationManager[] memory allowedEpochManagers = new IEpochLiquidityAllocationManager[](1);
        allowedEpochManagers[0] = IEpochLiquidityAllocationManager(address(0));

        IRehypothecationManager[] memory allowedRehypManagers = new IRehypothecationManager[](1);
        allowedRehypManagers[0] = IRehypothecationManager(address(0));

        // Deploy CampaignManager
        CampaignManager campaignManager = new CampaignManager(
            poolManager,
            patentERC721,
            allowedNumeraires,
            allowedEpochManagers,
            allowedRehypManagers,
            licenseHook
        );
        console.log("CampaignManager deployed to:", address(campaignManager));
        deployments.push(
            Deployment({
                name: "CampaignManager",
                addr: address(campaignManager)
            })
        );

        // Transfer LicenseHook ownership to CampaignManager so it can initialize pools
        licenseHook.transferOwnership(address(campaignManager));
        console.log(
            "LicenseHook ownership transferred to:",
            address(campaignManager)
        );
    }
}
