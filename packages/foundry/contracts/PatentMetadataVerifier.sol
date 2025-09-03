// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ITaskMailbox, ITaskMailboxTypes} from "@hourglass/lib/eigenlayer-middleware/lib/eigenlayer-contracts/src/contracts/interfaces/ITaskMailbox.sol";
import {OperatorSet} from "@hourglass/lib/eigenlayer-middleware/lib/eigenlayer-contracts/src/contracts/libraries/OperatorSetLib.sol";
import {IAVSTaskHook} from "@hourglass/lib/eigenlayer-middleware/lib/eigenlayer-contracts/src/contracts/interfaces/IAVSTaskHook.sol";
import {PatentERC721} from "./PatentERC721.sol";

enum Status {
    UNKNOWN, // 0
    VALID, // 1
    INVALID, // 2
    UNDER_ATTACK // 3
}

struct Metadata {
    Status status;
}

struct Request {
    address requester; // if requester is address(0), then it is an update request otherwise it is a mint request
    string uri;
}

// owner is avs task hook
contract PatentMetadataVerifier is Ownable, IAVSTaskHook {
    event ScanTaskCreated(
        bytes32 indexed taskHash,
        uint256 indexed tokenId,
        string newUri
    );
    event WrongMetadataFormat(uint256 indexed tokenId, string newUri);

    error PatentIsInvalid();

    ITaskMailbox public immutable mailbox;
    address public immutable operatorSetOwner;
    uint32 public immutable operatorSetId;
    PatentERC721 public immutable patentErc721;

    mapping(uint256 tokenId => Metadata metadata) public metadata;
    mapping(uint256 tokenId => Request request) public requests;

    constructor(
        ITaskMailbox _mailbox,
        address _operatorSetOwner,
        uint32 _operatorSetId,
        PatentERC721 _patentErc721,
        address _owner
    ) Ownable(_owner) {
        mailbox = _mailbox;
        operatorSetOwner = _operatorSetOwner;
        operatorSetId = _operatorSetId;
        patentErc721 = _patentErc721;
    }

    // function to create a task to verify the metadata
    function verify(
        uint256 tokenId,
        Request memory request
    ) public returns (bytes32 taskHash) {
        requests[tokenId] = request;
        ITaskMailboxTypes.TaskParams memory params = ITaskMailboxTypes
            .TaskParams({
                refundCollector: msg.sender,
                executorOperatorSet: OperatorSet(
                    operatorSetOwner,
                    operatorSetId
                ),
                payload: abi.encode(tokenId, request.uri)
            });
        taskHash = mailbox.createTask(params);
        emit ScanTaskCreated(taskHash, tokenId, request.uri);
    }

    // function to aggregate required actions on metadata fields
    function validate(uint256 tokenId) external {
        // this case should be impossible to reach
        if (metadata[tokenId].status == Status.UNKNOWN) {
            verify(
                tokenId,
                Request({
                    requester: address(0),
                    uri: patentErc721.tokenURI(tokenId)
                })
            );
        }
        if (metadata[tokenId].status == Status.INVALID) {
            revert PatentIsInvalid();
        }
    }

    function handlePostTaskResultSubmission(
        address caller,
        bytes32 taskHash
    ) external {
        bytes memory result = mailbox.getTaskResult(taskHash);
        (uint256 tokenId, bool valid, Metadata memory meta) = abi.decode(
            result,
            (uint256, bool, Metadata)
        );

        if (!valid) {
            emit WrongMetadataFormat(tokenId, requests[tokenId].uri);
        }

        metadata[tokenId] = meta;
        if (requests[tokenId].requester != address(0)) {
            patentErc721.mint(
                requests[tokenId].requester,
                requests[tokenId].uri
            );
        } else {
            patentErc721.updateURI(tokenId, requests[tokenId].uri);
        }
        delete requests[tokenId];
    }

    function validatePreTaskCreation(
        address,
        ITaskMailboxTypes.TaskParams memory
    ) external view {}

    function handlePostTaskCreation(bytes32) external {}

    function validatePreTaskResultSubmission(
        address,
        bytes32,
        bytes memory,
        bytes memory
    ) external view {}

    function calculateTaskFee(
        ITaskMailboxTypes.TaskParams memory
    ) external pure returns (uint96) {
        return 0;
    }
}
