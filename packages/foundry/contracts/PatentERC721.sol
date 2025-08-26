// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";

contract PatentERC721 is ERC721URIStorage {
    uint256 public _nextTokenId;

    constructor() ERC721("Patent NFT", "PNFT") {
        _nextTokenId = 1;
    }

    function mint(address to, string memory uri) external returns (uint256) {
        _safeMint(to, _nextTokenId);
        _setTokenURI(_nextTokenId, uri);
        _nextTokenId++;
        return _nextTokenId - 1;
    }
}
