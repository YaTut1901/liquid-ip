// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract LicenseERC20 is ERC20 {
    using Strings for uint256;

    error LicenseERC20_OnlyPatentOwner();

    address public immutable patentErc721;
    uint256 public immutable patentId;
    
    string public licenceMetadataUri;

    modifier onlyPatentOwner() {
        require(msg.sender == IERC721(patentErc721).ownerOf(patentId), LicenseERC20_OnlyPatentOwner());
        _;
    }

    constructor(
        address _patentErc721,
        uint256 _patentId,
        string memory _licenceMetadataUri
    ) ERC20("LiquidIpProtocolLicense", string(abi.encodePacked("LIPL-", Strings.toString(_patentId)))) {
        require(msg.sender == IERC721(_patentErc721).ownerOf(_patentId), LicenseERC20_OnlyPatentOwner());

        patentErc721 = _patentErc721;
        patentId = _patentId;
        licenceMetadataUri = _licenceMetadataUri;
    }

    function mint(address to, uint256 amount) external onlyPatentOwner {
        _mint(to, amount);
    }
}
