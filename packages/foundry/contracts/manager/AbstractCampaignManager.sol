// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ICampaignManager} from "../interfaces/ICampaignManager.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPoolManager} from "@v4-core/interfaces/IPoolManager.sol";
import {LicenseHook} from "../LicenseHook.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {LicenseERC20} from "../token/LicenseERC20.sol";

abstract contract AbstractCampaignManager is ICampaignManager, Ownable {
    int24 public constant TICK_SPACING = 30;

    IERC721 public immutable patentErc721;
    IPoolManager public immutable poolManager;
    LicenseHook public immutable licenseHook;

    mapping(IERC20 numeraire => bool) public allowedNumeraires;
    mapping(uint256 delegatedPatentId => address owner) public delegatedPatents;
    mapping(uint256 patentId => uint256 campaignEndTimestamp)
        public campaignEndTimestamp;

    constructor(
        address _owner,
        IPoolManager _manager,
        IERC721 _patentErc721,
        IERC20[] memory _allowedNumeraires,
        LicenseHook _licenseHook
    ) Ownable(_owner) {
        poolManager = _manager;
        patentErc721 = _patentErc721;
        licenseHook = _licenseHook;

        for (uint256 i = 0; i < _allowedNumeraires.length; i++) {
            allowedNumeraires[_allowedNumeraires[i]] = true;
        }
    }

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4) {
        if (msg.sender != address(patentErc721)) {
            revert InvalidERC721();
        }
        delegatedPatents[tokenId] = from;

        emit PatentDelegated(tokenId, from);
        return this.onERC721Received.selector;
    }

    function addAllowedNumeraire(IERC20 numeraire) external onlyOwner {
        allowedNumeraires[numeraire] = true;
    }

    function removeAllowedNumeraire(IERC20 numeraire) external onlyOwner {
        allowedNumeraires[numeraire] = false;
    }

    function retrieve(uint256 patentId) external {
        require(
            block.timestamp > campaignEndTimestamp[patentId],
            CampaignOngoing()
        );
        address patentOwner = delegatedPatents[patentId];
        delegatedPatents[patentId] = address(0);
        patentErc721.transferFrom(address(this), patentOwner, patentId);
        emit PatentRetrieved(patentId, patentOwner);
    }

    function initialize(
        uint256 patentId,
        string memory assetMetadataUri,
        bytes32 licenseSalt,
        IERC20 numeraire,
        bytes calldata params
    ) external virtual;

    function _validateGeneral(
        string memory assetMetadataUri,
        uint256 patentId,
        bytes32 licenseSalt,
        IERC20 numeraire
    ) internal {
        // Check that the patent is already delegated
        require(delegatedPatents[patentId] != address(0), PatentNotDelegated());
        // Compute the address of the contract to be deployed and verify it's compatible with uni v4
        bytes32 bytecodeHash = keccak256(
            abi.encodePacked(
                type(LicenseERC20).creationCode,
                abi.encode(patentErc721, patentId, assetMetadataUri)
            )
        );
        address asset = Create2.computeAddress(
            licenseSalt,
            bytecodeHash,
            address(this)
        );
        // Check that the asset address is bigger than the numeraire address (uni v4 requirement)
        require(asset > address(numeraire), InvalidAssetNumeraireOrder());
        // Check that the numeraire is allowed
        require(allowedNumeraires[numeraire], NumeraireNotAllowed());
    }

    function _calculateClosestProperTick(
        int24 tick
    ) internal pure returns (int24) {
        int24 remainder = tick % TICK_SPACING;

        if (remainder < TICK_SPACING / 2) {
            return tick - remainder;
        }

        return tick + remainder;
    }

    function _calculateClosestProperTickRange(
        int24 epochTickRange,
        uint24 totalEpochs
    ) internal pure returns (int24) {
        int24 remainder = epochTickRange % TICK_SPACING;

        if (remainder < TICK_SPACING / 2) {
            return int24(totalEpochs) * epochTickRange - remainder;
        }

        return
            int24(totalEpochs) * (epochTickRange + (TICK_SPACING - remainder));
    }
}
