// //SPDX-License-Identifier: MIT
// pragma solidity ^0.8.27;

// import "./DeployHelpers.s.sol";
// import {console} from "forge-std/console.sol";
// import {PatentERC721} from "../contracts/PatentERC721.sol";
// import {PatentMetadataVerifier} from "../contracts/PatentMetadataVerifier.sol";
// import {ITaskMailbox, ITaskMailboxTypes} from "@hourglass/lib/eigenlayer-middleware/lib/eigenlayer-contracts/src/contracts/interfaces/ITaskMailbox.sol";
// import {IAVSTaskHook} from "@hourglass/lib/eigenlayer-middleware/lib/eigenlayer-contracts/src/contracts/interfaces/IAVSTaskHook.sol";
// import {IKeyRegistrarTypes} from "@hourglass/lib/eigenlayer-middleware/lib/eigenlayer-contracts/src/contracts/interfaces/IKeyRegistrar.sol";
// import {IKeyRegistrar} from "@hourglass/lib/eigenlayer-middleware/lib/eigenlayer-contracts/src/contracts/interfaces/IKeyRegistrar.sol";
// import {IOperatorTableUpdater} from "@hourglass/lib/eigenlayer-middleware/lib/eigenlayer-contracts/src/contracts/interfaces/IOperatorTableUpdater.sol";
// import {OperatorSet} from "@hourglass/lib/eigenlayer-middleware/lib/eigenlayer-contracts/src/contracts/libraries/OperatorSetLib.sol";
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import {BN254CertificateVerifier} from "@hourglass/lib/eigenlayer-middleware/lib/eigenlayer-contracts/src/contracts/multichain/BN254CertificateVerifier.sol";
// import {TaskMailbox} from "@hourglass/lib/eigenlayer-middleware/lib/eigenlayer-contracts/src/contracts/avs/task/TaskMailbox.sol";
// import {KeyRegistrar} from "@hourglass/lib/eigenlayer-middleware/lib/eigenlayer-contracts/src/contracts/permissions/KeyRegistrar.sol";
// import {IPermissionController} from "@hourglass/lib/eigenlayer-middleware/lib/eigenlayer-contracts/src/contracts/interfaces/IPermissionController.sol";
// import {IAllocationManager} from "@hourglass/lib/eigenlayer-middleware/lib/eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
// import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
// import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
// import {IOperatorTableCalculatorTypes} from "@hourglass/lib/eigenlayer-middleware/lib/eigenlayer-contracts/src/contracts/interfaces/IOperatorTableCalculator.sol";
// import {ICrossChainRegistryTypes} from "@hourglass/lib/eigenlayer-middleware/lib/eigenlayer-contracts/src/contracts/interfaces/ICrossChainRegistry.sol";
// import {BN254} from "@hourglass/lib/eigenlayer-middleware/lib/eigenlayer-contracts/src/contracts/libraries/BN254.sol";
// import {CampaignManager} from "../contracts/CampaignManager.sol";
// import {LicenseHook} from "../contracts/LicenseHook.sol";
// import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
// import {IPoolManager} from "@v4-core/interfaces/IPoolManager.sol";
// import {IEpochLiquidityAllocationManager} from "../contracts/interfaces/IEpochLiquidityAllocationManager.sol";
// import {IRehypothecationManager} from "../contracts/interfaces/IRehypothecationManager.sol";
// import {Hooks} from "@v4-core/libraries/Hooks.sol";
// import {HookMiner} from "@v4-periphery/utils/HookMiner.sol";
// import {MockERC20} from "./MockERC.sol";

// contract DeployScript is ScaffoldETHDeploy {
//     function run(address poolManager) external ScaffoldEthDeployerRunner {
//         (
//             ITaskMailbox mailbox,
//             address operatorSetOwner,
//             uint32 operatorSetId
//         ) = _deployHourglass();

//         _deployCustom(
//             IPoolManager(poolManager),
//             mailbox,
//             operatorSetOwner,
//             operatorSetId
//         );
//     }

//     function _deployHourglass()
//         internal
//         returns (
//             ITaskMailbox mailbox,
//             address operatorSetOwner,
//             uint32 operatorSetId
//         )
//     {
//         // --- Deploy Hourglass singletons locally ---
//         BN254CertificateVerifier bn254 = new BN254CertificateVerifier(
//             IOperatorTableUpdater(deployer),
//             "local"
//         );
//         console.log("BN254CertificateVerifier:", address(bn254));
//         deployments.push(
//             Deployment({name: "BN254CertificateVerifier", addr: address(bn254)})
//         );

//         // Deploy a separate proxy admin to avoid admin-call fallback reverts
//         ProxyAdmin proxyAdmin = new ProxyAdmin(deployer);
//         console.log("ProxyAdmin:", address(proxyAdmin));
//         deployments.push(
//             Deployment({name: "ProxyAdmin", addr: address(proxyAdmin)})
//         );

//         uint96 maxTaskSLA = 7 days / 2;
//         TaskMailbox mailboxImpl = new TaskMailbox(
//             address(bn254),
//             address(0),
//             maxTaskSLA,
//             "local"
//         );
//         bytes memory initData = abi.encodeWithSelector(
//             TaskMailbox.initialize.selector,
//             deployer,
//             uint16(0),
//             deployer
//         );
//         TransparentUpgradeableProxy mailboxProxy = new TransparentUpgradeableProxy(
//                 address(mailboxImpl),
//                 address(proxyAdmin),
//                 initData
//             );
//         mailbox = ITaskMailbox(address(mailboxProxy));
//         console.log("TaskMailbox:", address(mailbox));
//         deployments.push(
//             Deployment({name: "TaskMailbox", addr: address(mailbox)})
//         );

//         KeyRegistrar keyReg = new KeyRegistrar(
//             IPermissionController(address(0)),
//             IAllocationManager(address(0)),
//             "local"
//         );
//         console.log("KeyRegistrar:", address(keyReg));
//         deployments.push(
//             Deployment({name: "KeyRegistrar", addr: address(keyReg)})
//         );

//         // --- Seed operator set owner in BN254CertificateVerifier so Mailbox owner checks pass ---
//         operatorSetOwner = deployer;
//         operatorSetId = 1;
//         OperatorSet memory setKey = OperatorSet(
//             operatorSetOwner,
//             operatorSetId
//         );
//         IOperatorTableCalculatorTypes.BN254OperatorSetInfo
//             memory emptyInfo = IOperatorTableCalculatorTypes
//                 .BN254OperatorSetInfo({
//                     operatorInfoTreeRoot: bytes32(0),
//                     numOperators: 0,
//                     aggregatePubkey: BN254.G1Point({X: 0, Y: 0}),
//                     totalWeights: new uint256[](0)
//                 });
//         ICrossChainRegistryTypes.OperatorSetConfig
//             memory cfgSeed = ICrossChainRegistryTypes.OperatorSetConfig({
//                 owner: operatorSetOwner,
//                 maxStalenessPeriod: 0
//             });
//         bn254.updateOperatorTable(
//             setKey,
//             uint32(block.timestamp),
//             emptyInfo,
//             cfgSeed
//         );
//         console.log("Seeded operator set owner in BN254CertificateVerifier");
//     }

//     function _deployCustom(
//         IPoolManager poolManager,
//         ITaskMailbox mailbox,
//         address operatorSetOwner,
//         uint32 operatorSetId
//     ) internal {
//         // --- Deploy your AVS contracts ---
//         PatentMetadataVerifier verifier = new PatentMetadataVerifier(
//             ITaskMailbox(address(mailbox)),
//             operatorSetOwner,
//             operatorSetId,
//             deployer
//         );
//         console.log("PatentMetadataVerifier:", address(verifier));
//         deployments.push(
//             Deployment({
//                 name: "PatentMetadataVerifier",
//                 addr: address(verifier)
//             })
//         );

//         PatentERC721 patentERC721 = new PatentERC721(
//             verifier,
//             address(verifier)
//         );
//         console.log("PatentERC721:", address(patentERC721));
//         deployments.push(
//             Deployment({name: "PatentERC721", addr: address(patentERC721)})
//         );

//         verifier.setPatentErc721(patentERC721);

//         ITaskMailboxTypes.ExecutorOperatorSetTaskConfig
//             memory cfg = ITaskMailboxTypes.ExecutorOperatorSetTaskConfig({
//                 taskHook: IAVSTaskHook(address(verifier)),
//                 taskSLA: 120,
//                 feeToken: IERC20(address(0)),
//                 curveType: IKeyRegistrarTypes.CurveType.BN254,
//                 feeCollector: address(0),
//                 consensus: ITaskMailboxTypes.Consensus({
//                     consensusType: ITaskMailboxTypes.ConsensusType.NONE,
//                     value: bytes("")
//                 }),
//                 taskMetadata: bytes("")
//             });
//         OperatorSet memory setKey = OperatorSet(
//             operatorSetOwner,
//             operatorSetId
//         );
//         mailbox.setExecutorOperatorSetTaskConfig(setKey, cfg);
//         mailbox.registerExecutorOperatorSet(setKey, true);
//         console.log("TaskMailbox configured. Hook:", address(cfg.taskHook));

//         // Deploy LicenseHook (owner: deployer for now) using HookMiner
//         bytes memory creationCode = type(LicenseHook).creationCode;
//         uint160 flags = uint160(
//             Hooks.BEFORE_INITIALIZE_FLAG |
//                 Hooks.BEFORE_ADD_LIQUIDITY_FLAG |
//                 Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG |
//                 Hooks.BEFORE_SWAP_FLAG |
//                 Hooks.BEFORE_DONATE_FLAG
//         );
//         bytes memory constructorArgs = abi.encode(
//             IPoolManager(address(poolManager)),
//             verifier,
//             deployer
//         );
//         (address licenseHookAddress, bytes32 salt) = HookMiner.find(
//             0x4e59b44847b379578588920cA78FbF26c0B4956C,
//             flags,
//             creationCode,
//             constructorArgs
//         );
//         LicenseHook licenseHook = new LicenseHook{salt: salt}(
//             poolManager,
//             verifier,
//             deployer
//         );
//         console.log("LicenseHook:", address(licenseHook));
//         deployments.push(
//             Deployment({name: "LicenseHook", addr: address(licenseHook)})
//         );

//         IERC20[] memory allowedNumeraires = new IERC20[](1);
//         IERC20 numeraire = new MockERC20("Numeraire", "NUM");
//         allowedNumeraires[0] = numeraire;
//         deployments.push(
//             Deployment({name: "Numeraire", addr: address(numeraire)})
//         );

//         IEpochLiquidityAllocationManager[]
//             memory allowedEpochManagers = new IEpochLiquidityAllocationManager[](
//                 1
//             );
//         allowedEpochManagers[0] = IEpochLiquidityAllocationManager(address(0));

//         IRehypothecationManager[]
//             memory allowedRehypManagers = new IRehypothecationManager[](1);
//         allowedRehypManagers[0] = IRehypothecationManager(address(0));

//         CampaignManager campaignManager = new CampaignManager(
//             deployer,
//             poolManager,
//             patentERC721,
//             allowedNumeraires,
//             licenseHook
//         );
//         console.log("CampaignManager:", address(campaignManager));
//         deployments.push(
//             Deployment({
//                 name: "CampaignManager",
//                 addr: address(campaignManager)
//             })
//         );

//         // Transfer LicenseHook ownership to CampaignManager so it can initialize pools
//         licenseHook.transferOwnership(address(campaignManager));
//         console.log(
//             "LicenseHook ownership transferred to:",
//             address(campaignManager)
//         );
//     }
// }
