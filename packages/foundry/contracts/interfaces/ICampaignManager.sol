// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {PoolId} from "@v4-core/types/PoolId.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title ICampaignManager
/// @notice Interface for deploying campaigns and managing patent delegation lifecycle.
/// @dev Implements IERC721Receiver to accept delegated patent NFTs which authorize campaign initialization
///      on behalf of the patent owner.
interface ICampaignManager is IERC721Receiver {
    error InvalidAssetNumeraireOrder();
    error NumeraireNotAllowed();
    error InvalidTick(uint16 epoch, uint8 position, int24 tick, int24 closestProperTick);
    error InvalidERC721();
    error PatentNotDelegated();
    error CampaignOngoing();
    error InvalidTickRange();

    event PatentDelegated(uint256 patentId, address owner);
    event PatentRetrieved(uint256 patentId, address owner);
    event CampaignInitialized(uint256 patentId, address license, PoolId poolId);

    /// @notice Adds a new allowed numeraire (ERC20 token) to deploy campaigns with.
    /// @dev Governance protected function.
    /// @param numeraire The address of the ERC20 token to allow.
    function addAllowedNumeraire(IERC20 numeraire) external;

    /// @notice Removes a numeraire (ERC20 token) from allowed to deploy campaigns with.
    /// @dev Governance protected function.
    /// @param numeraire The address of the ERC20 token to remove.
    function removeAllowedNumeraire(IERC20 numeraire) external;

    /// @notice Retrieves a patent from a campaign once it is no longer ongoing.
    /// @param patentId The ID of the patent to retrieve.
    function retrieve(uint256 patentId) external;

    /// @notice Initializes a campaign.
    /// @param patentId The ID of the patent to initialize the campaign for.
    /// @param assetMetadataUri The URI of the asset metadata (licence ERC20).
    /// @param licenseSalt The salt used for Create2 deployment of the license token.
    /// @param numeraire The ERC20 numeraire of the campaign.
    /// @param params Encoded campaign configuration defining epoch durations and position allocations.
    function initialize(
        uint256 patentId,
        string memory assetMetadataUri,
        bytes32 licenseSalt,
        IERC20 numeraire,
        bytes calldata params
    ) external;
}
