// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ITaskMailboxTypes} from "@hourglass/lib/eigenlayer-middleware/lib/eigenlayer-contracts/src/contracts/interfaces/ITaskMailbox.sol";

/// Minimal interface for the verifier callback we need
interface IVerifierCallback {
    function handlePostTaskResultSubmission(address, bytes32 taskHash) external;
}

/// Must match `PatentMetadataVerifier` types layout
enum Status {
    UNKNOWN, // 0
    VALID,   // 1
    INVALID, // 2
    UNDER_ATTACK // 3
}

struct Metadata {
    Status status;
}

/// @title MockTaskMailbox
/// @notice Minimal mailbox that immediately finalizes tasks as VALID and calls back the verifier.
/// @dev Designed for local testing: when the verifier calls `createTask`, this contract
///      stores a pre-encoded result and directly invokes `handlePostTaskResultSubmission`
///      on the verifier in the same transaction. Only the two methods used by the verifier
///      are provided: `createTask` and `getTaskResult`.
contract MockTaskMailbox {
    mapping(bytes32 => bytes) private _results;

    /// @notice Called by the verifier to create a task.
    /// @dev Decodes `(tokenId, uri)` from payload, fabricates a VALID result, stores it,
    ///      and immediately calls back `handlePostTaskResultSubmission` on the verifier (msg.sender).
    function createTask(
        ITaskMailboxTypes.TaskParams memory taskParams
    ) external returns (bytes32 taskHash) {
        (uint256 tokenId, string memory _uri) = abi.decode(
            taskParams.payload,
            (uint256, string)
        );

        // Derive a pseudo task hash deterministically from caller and payload
        taskHash = keccak256(abi.encode(msg.sender, taskParams.payload, block.number));

        // Encode a VALID result for the verifier to consume: (tokenId, valid, Metadata)
        _results[taskHash] = abi.encode(
            tokenId,
            true,
            Metadata({status: Status.VALID})
        );

        // Immediately notify the verifier (the caller) that the result is available
        IVerifierCallback(msg.sender).handlePostTaskResultSubmission(address(0), taskHash);
    }

    /// @notice Returns the pre-stored result for a given task hash.
    function getTaskResult(bytes32 taskHash) external view returns (bytes memory) {
        return _results[taskHash];
    }
}


