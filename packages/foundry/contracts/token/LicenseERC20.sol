// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/// @title LicenseERC20
/// @notice ERC20 representing a license token for a given patent. Minting is restricted to the patent owner.
contract LicenseERC20 is ERC20 {
    using Strings for uint256;

    error OnlyPatentOwner();

    IERC721 public immutable patentErc721;
    uint256 public immutable patentId;
    
    string public licenceMetadataUri;

    modifier onlyPatentOwner() {
        require(msg.sender == patentErc721.ownerOf(patentId), OnlyPatentOwner());
        _;
    }

    /// @notice Deploys the License ERC20 for a specific patent.
    /// @param _patentErc721 Patent ERC721 contract.
    /// @param _patentId Patent token ID this license is bound to.
    /// @param _licenceMetadataUri Metadata URI for the license token.
    constructor(
        IERC721 _patentErc721,
        uint256 _patentId,
        string memory _licenceMetadataUri
    ) ERC20("LiquidIpProtocolLicense", string(abi.encodePacked("LIPL-", Strings.toString(_patentId)))) {
        require(msg.sender == _patentErc721.ownerOf(_patentId), OnlyPatentOwner());

        patentErc721 = _patentErc721;
        patentId = _patentId;
        licenceMetadataUri = _licenceMetadataUri;
    }

    /// @notice Mints license tokens. Only callable by the current patent owner.
    /// @param to Recipient address.
    /// @param amount Amount of tokens to mint.
    function mint(address to, uint256 amount) external onlyPatentOwner {
        _mint(to, amount);
    }
}
