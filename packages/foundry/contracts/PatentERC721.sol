// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import {PatentMetadataVerifier, Request} from "./PatentMetadataVerifier.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

// owner is avs task hook
contract PatentERC721 is ERC721URIStorage, Ownable {
    PatentMetadataVerifier public immutable verifier;

    uint256 public _nextTokenId;

    constructor(
        PatentMetadataVerifier _verifier,
        address _owner
    ) ERC721("Patent NFT", "PNFT") Ownable(_owner) {
        verifier = _verifier;
        _nextTokenId = 1;
    }

    function mint(address to, string memory uri) external returns (uint256) {
        // avs mints the token and updates the URI
        if (owner() == msg.sender) {
            _safeMint(to, _nextTokenId);
            _setTokenURI(_nextTokenId, uri);
            _nextTokenId++;
            return _nextTokenId - 1;
        } else {
            // called by other than avs then it submits request to avs
            verifier.verify(_nextTokenId, Request({requester: to, uri: uri}));
        }
    }

    function updateURI(uint256 tokenId, string memory uri) public {
        // avs updates the URI
        if (owner() == msg.sender) {
            _setTokenURI(tokenId, uri);
        } else {
            // if function is called by token owner then it submits request to avs
            require(ownerOf(tokenId) == msg.sender, "Not the owner");
            verifier.verify(
                tokenId,
                Request({requester: address(0), uri: uri})
            );
        }
    }
}
