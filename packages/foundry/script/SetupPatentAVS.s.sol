// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script, console} from "forge-std/Script.sol";

import {OperatorSet} from "@hourglass/lib/eigenlayer-middleware/lib/eigenlayer-contracts/src/contracts/libraries/OperatorSetLib.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IKeyRegistrarTypes} from "@hourglass/lib/eigenlayer-middleware/lib/eigenlayer-contracts/src/contracts/interfaces/IKeyRegistrar.sol";

import {ITaskMailbox, ITaskMailboxTypes} from "@hourglass/lib/eigenlayer-middleware/lib/eigenlayer-contracts/src/contracts/interfaces/ITaskMailbox.sol";
import {IAVSTaskHook} from "@hourglass/lib/eigenlayer-middleware/lib/eigenlayer-contracts/src/contracts/interfaces/IAVSTaskHook.sol";

contract SetupPatentAVS is Script {
    function run(address taskMailbox, address taskHook) public {
        uint256 avsPrivateKey = vm.envUint("PRIVATE_KEY_AVS");
        uint96 taskSLA = uint96(vm.envOr("TASK_SLA", uint256(60)));
        uint16 thresholdBps = uint16(vm.envOr("THRESHOLD_BPS", uint256(100))); // 1% by default

        address avs = vm.addr(avsPrivateKey);
        vm.startBroadcast(avsPrivateKey);
        console.log("AVS (operator set owner):", avs);

        ITaskMailboxTypes.ExecutorOperatorSetTaskConfig memory cfg = ITaskMailboxTypes
            .ExecutorOperatorSetTaskConfig({
                taskHook: IAVSTaskHook(taskHook),
                taskSLA: taskSLA,
                feeToken: IERC20(address(0)),
                curveType: IKeyRegistrarTypes.CurveType.BN254,
                feeCollector: address(0),
                consensus: ITaskMailboxTypes.Consensus({
                    consensusType: ITaskMailboxTypes.ConsensusType.STAKE_PROPORTION_THRESHOLD,
                    value: abi.encode(thresholdBps)
                }),
                taskMetadata: bytes("")
            });

        // Use operator set id = 1 by convention
        OperatorSet memory setKey = OperatorSet(avs, 1);

        ITaskMailbox(taskMailbox).setExecutorOperatorSetTaskConfig(setKey, cfg);
        ITaskMailbox(taskMailbox).registerExecutorOperatorSet(setKey, true);

        ITaskMailboxTypes.ExecutorOperatorSetTaskConfig memory stored = ITaskMailbox(taskMailbox)
            .getExecutorOperatorSetTaskConfig(setKey);
        console.log("Config set. Curve:", uint8(stored.curveType), "Hook:", address(stored.taskHook));

        vm.stopBroadcast();
    }
} 