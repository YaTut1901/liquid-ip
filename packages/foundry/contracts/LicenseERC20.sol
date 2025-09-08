// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {FHE, euint128, InEuint128, Common} from "@fhenixprotocol/cofhe-contracts/FHE.sol";

contract LicenseERC20 is ERC20 {
    using Strings for uint256;

    error LicenseERC20_OnlyPatentOwner();

    IERC721 public immutable patentErc721;
    uint256 public immutable patentId;
    
    string public licenceMetadataUri;

    mapping(address => euint128) private _encryptedBalances;
    mapping(address => bool) public hasEncryptedBalance;
    euint128 private _encryptedTotalSupply;
    bool public hasEncryptedSupply;

    modifier onlyPatentOwner() {
        require(msg.sender == patentErc721.ownerOf(patentId), LicenseERC20_OnlyPatentOwner());
        _;
    }

    constructor(
        IERC721 _patentErc721,
        uint256 _patentId,
        string memory _licenceMetadataUri
    ) ERC20("LiquidIpProtocolLicense", string(abi.encodePacked("LIPL-", Strings.toString(_patentId)))) {
        require(msg.sender == _patentErc721.ownerOf(_patentId), LicenseERC20_OnlyPatentOwner());

        patentErc721 = _patentErc721;
        patentId = _patentId;
        licenceMetadataUri = _licenceMetadataUri;
    }

    function mint(address to, uint256 amount) external onlyPatentOwner {
        _mint(to, amount);
    }

    function mintEncrypted(address to, InEuint128 calldata encAmount) external onlyPatentOwner {
        euint128 amount = FHE.asEuint128(encAmount);
        FHE.allowThis(amount);

        if (!hasEncryptedBalance[to]) {
            _encryptedBalances[to] = FHE.asEuint128(0);
            hasEncryptedBalance[to] = true;
        }
        
        _encryptedBalances[to] = FHE.add(_encryptedBalances[to], amount);

        if (!hasEncryptedSupply) {
            _encryptedTotalSupply = FHE.asEuint128(0);
            hasEncryptedSupply = true;
        }
        _encryptedTotalSupply = FHE.add(_encryptedTotalSupply, amount);

        FHE.allowThis(_encryptedBalances[to]);
        FHE.allowThis(_encryptedTotalSupply);
    }

    function encryptedBalanceOf(address account) external view returns (euint128) {
        require(hasEncryptedBalance[account], "No encrypted balance");
        return _encryptedBalances[account];
    }

    function encryptedTotalSupply() external view returns (euint128) {
        require(hasEncryptedSupply, "No encrypted supply");
        return _encryptedTotalSupply;
    }

    function requestBalanceDecryption(address account) external {
        require(hasEncryptedBalance[account], "No encrypted balance");
        FHE.decrypt(_encryptedBalances[account]);
    }

    function requestTotalSupplyDecryption() external {
        require(hasEncryptedSupply, "No encrypted supply");
        FHE.decrypt(_encryptedTotalSupply);
    }

    function getDecryptedBalance(address account) external view returns (uint128, bool) {
        require(hasEncryptedBalance[account], "No encrypted balance");
        return FHE.getDecryptResultSafe(_encryptedBalances[account]);
    }

    function getDecryptedTotalSupply() external view returns (uint128, bool) {
        require(hasEncryptedSupply, "No encrypted supply");
        return FHE.getDecryptResultSafe(_encryptedTotalSupply);
    }
}
