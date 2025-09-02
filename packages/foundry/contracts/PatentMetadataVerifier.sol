// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

// owner is avs
contract PatentMetadataVerifier is Ownable {
    event ScanRequestedFor(uint256 tokenId);

    error PatentIsInvalid();

    uint256 public immutable scanInterval;

    enum Status {
        UNKNOWN, // 0
        VALID, // 1
        INVALID, // 2
        UNDER_ATTACK // 3
    }

    constructor(address _owner, uint256 _scanInterval) Ownable(_owner) {
        scanInterval = _scanInterval;
    }

    mapping(uint256 tokenId => uint8 status) public statuses;
    mapping(uint256 tokenId => uint256 lastScan) public lastScans;

    function setStatus(uint256 tokenId, uint8 status) external onlyOwner {
        statuses[tokenId] = status;
        lastScans[tokenId] = block.timestamp;
    }

    function verify(uint256 tokenId) external {
        // condition to submit a task to avs
        if (statuses[tokenId] == 0 || block.timestamp - lastScans[tokenId] > scanInterval) {
            emit ScanRequestedFor(tokenId);
        }
        if (statuses[tokenId] == 2) {
            revert PatentIsInvalid();
        }
        return;
    }
}