// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

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

/// @title PatentMetadataVerifier
/// @notice Coordinates off-chain verification of patent metadata via EigenLayer AVS task mailbox.
/// @dev The contract owner is expected to be the AVS task hook. Users or the Patent ERC721 contract
///      can request verification using {verify}. Upon task result submission, this contract updates
///      on-chain state and triggers mint/URI update on the Patent ERC721.
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
    PatentERC721 public patentErc721;

    mapping(uint256 tokenId => Metadata metadata) public metadata;
    mapping(uint256 tokenId => Request request) public requests;

    constructor(
        ITaskMailbox _mailbox,
        address _operatorSetOwner,
        uint32 _operatorSetId,
        address _owner
    ) Ownable(_owner) {
        mailbox = _mailbox;
        operatorSetOwner = _operatorSetOwner;
        operatorSetId = _operatorSetId;
    }

    modifier onlyConfigured {
        require(
            address(patentErc721) != address(0),
            "PatentErc721 not configured"
        );
        _;
    }

    /// @notice Sets the Patent ERC721 contract to operate on.
    /// @param _patentErc721 The Patent ERC721 contract instance.
    function setPatentErc721(PatentERC721 _patentErc721) external onlyOwner {
        patentErc721 = _patentErc721;
    }

    /// @notice Creates a verification task for the provided token metadata.
    /// @dev Stores the request and submits a task to the mailbox with encoded `(tokenId, uri)` payload.
    /// @param tokenId The target Patent NFT token ID (minting if not yet minted).
    /// @param request The request describing requester (mint vs update) and new URI.
    /// @return taskHash The created task hash returned by the mailbox.
    function verify(
        uint256 tokenId,
        Request memory request
    ) public onlyConfigured returns (bytes32 taskHash) {
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

    /// @notice Validates the current metadata status for a token; re-requests verification if status is UNKNOWN.
    /// @dev Reverts with {PatentIsInvalid} if the last metadata status is INVALID.
    /// @param tokenId The Patent NFT token ID to validate.
    function validate(uint256 tokenId) external onlyConfigured {
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

    /// @notice Callback invoked by the mailbox after a task result is submitted.
    /// @dev Decodes `(tokenId, valid, meta)` from the task result. Emits WrongMetadataFormat if `valid` is false.
    ///      If a mint request was pending (requester != 0), mints the token; otherwise updates the URI. Clears request.
    /// @param taskHash The mailbox task hash whose result is being handled.
    function handlePostTaskResultSubmission(
        address,
        bytes32 taskHash
    ) external onlyConfigured {
        require(msg.sender == address(mailbox), "Only mailbox can call");

        bytes memory result = mailbox.getTaskResult(taskHash);
        (uint256 tokenId, bool valid, Metadata memory meta) = abi.decode(
            result,
            (uint256, bool, Metadata)
        );

        require(bytes(requests[tokenId].uri).length > 0, "No pending requests");

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

    /// @inheritdoc IAVSTaskHook
    function validatePreTaskCreation(
        address,
        ITaskMailboxTypes.TaskParams memory
    ) external view {}

    /// @inheritdoc IAVSTaskHook
    function handlePostTaskCreation(bytes32) external {}

    /// @inheritdoc IAVSTaskHook
    function validatePreTaskResultSubmission(
        address,
        bytes32,
        bytes memory,
        bytes memory
    ) external view {}

    /// @inheritdoc IAVSTaskHook
    function calculateTaskFee(
        ITaskMailboxTypes.TaskParams memory
    ) external pure returns (uint96) {
        return 0;
    }
}
