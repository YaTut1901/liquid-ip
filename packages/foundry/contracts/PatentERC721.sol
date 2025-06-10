// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";

contract PatentERC721 is ERC721URIStorage {
    uint256 private _nextTokenId;

    constructor() ERC721("Patent NFT", "PNFT") {}

    function mint(address to, string memory uri) external {
        uint256 tokenId = _nextTokenId++;
        _mint(to, tokenId);
        _setTokenURI(tokenId, uri);
    }
}
