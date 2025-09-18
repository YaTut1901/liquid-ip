// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import {PatentMetadataVerifier, Request} from "./PatentMetadataVerifier.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title PatentERC721
/// @notice ERC721 representing a patent NFT whose metadata can be minted/updated directly by the AVS task hook (contract owner)
///         or requested by users, in which case a verification task is created in {PatentMetadataVerifier}.
/// @dev The contract owner is expected to be the AVS task hook that is authorized to perform direct mints/updates.
contract PatentERC721 is ERC721URIStorage, Ownable {
    PatentMetadataVerifier public immutable verifier;

    uint256 public _nextTokenId;

    /// @notice Deploys the Patent ERC721.
    /// @param _verifier Address of the {PatentMetadataVerifier} used to create verification tasks.
    /// @param _owner Address that will own this contract (typically the AVS task hook).
    constructor(
        PatentMetadataVerifier _verifier,
        address _owner
    ) ERC721("Patent NFT", "PNFT") Ownable(_owner) {
        verifier = _verifier;
        _nextTokenId = 1;
    }

    /// @notice Mints a new patent NFT or submits a verification request depending on caller.
    /// @dev If called by the contract owner (AVS), the token is minted immediately and URI set.
    ///      Otherwise, a verification task is created in {PatentMetadataVerifier}.
    /// @param to Recipient of the NFT in case of direct mint, or requester recorded for verification.
    /// @param uri Initial metadata URI to set (or to be verified).
    /// @return tokenId The newly minted token ID if minted directly; otherwise zero and a task is created.
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
            return 0;
        }
    }

    /// @notice Updates a patent NFT metadata URI or submits a verification request depending on caller.
    /// @dev If called by the contract owner (AVS), the token URI is updated immediately.
    ///      If called by the current token owner, a verification task is created and AVS will update on success.
    /// @param tokenId The NFT token ID to update.
    /// @param uri New metadata URI to set (or to be verified).
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
