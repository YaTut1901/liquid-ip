// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPoolManager} from "@v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "@v4-core/types/PoolKey.sol";
import {Currency} from "@v4-core/types/Currency.sol";
import {IHooks} from "@v4-core/interfaces/IHooks.sol";
import {PublicLicenseHook} from "../hook/PublicLicenseHook.sol";
import {LicenseERC20} from "../token/LicenseERC20.sol";
import {IHooks} from "@v4-core/interfaces/IHooks.sol";
import {TickMath} from "@v4-core/libraries/TickMath.sol";
import {AbstractCampaignManager} from "./AbstractCampaignManager.sol";
import {PublicCampaignConfig} from "../lib/PublicCampaignConfig.sol";

/// @title PublicCampaignManager
/// @notice Deploys campaigns with plaintext public configuration; seeds pool and initializes hook state.
contract PublicCampaignManager is AbstractCampaignManager {
    using PublicCampaignConfig for bytes;

    PublicLicenseHook public immutable licenseHook;

    constructor(
        address _owner,
        IPoolManager _manager,
        IERC721 _patentErc721,
        IERC20[] memory _allowedNumeraires,
        PublicLicenseHook _licenseHook
    )
        AbstractCampaignManager(
            _owner,
            _manager,
            _patentErc721,
            _allowedNumeraires
        )
    {
        licenseHook = _licenseHook;
    }

    /// @notice Initializes a campaign using public config, deploys license token, mints to hook and initializes pool.
    function initialize(
        uint256 patentId,
        string memory assetMetadataUri,
        bytes32 licenseSalt,
        IERC20 numeraire,
        bytes calldata campaignConfig
    ) external override {
        _validateGeneral(assetMetadataUri, patentId, licenseSalt, numeraire);
        _validateCampaignConfig(campaignConfig);

        LicenseERC20 license = new LicenseERC20{salt: licenseSalt}(
            patentErc721,
            patentId,
            assetMetadataUri
        );

        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(address(numeraire)),
            currency1: Currency.wrap(address(license)),
            hooks: IHooks(licenseHook),
            fee: 0,
            tickSpacing: TICK_SPACING
        });

        campaignEndTimestamp[patentId] = campaignConfig.endingTime();
        license.mint(address(licenseHook), campaignConfig.totalTokensToSell());

        licenseHook.initializeState(poolKey, campaignConfig);

        poolManager.initialize(
            poolKey,
            TickMath.getSqrtPriceAtTick(campaignConfig.epochStartingTick(0))
        );

        emit CampaignInitialized(patentId, address(license), poolKey.toId());
    }

    /// @dev Validates ticks and ranges in the provided public campaign config.
    function _validateCampaignConfig(
        bytes calldata campaignConfig
    ) internal view {
        campaignConfig.validate();
        uint16 epochs = campaignConfig.numEpochs();
        for (uint16 e = 0; e < epochs; ) {
            uint8 count = campaignConfig.numPositions(e);
            for (uint8 i = 0; i < count; ) {
                int24 lower = campaignConfig.tickLower(e, i);
                int24 upper = campaignConfig.tickUpper(e, i);
                require(
                    lower % TICK_SPACING == 0,
                    InvalidTick(e, i, lower, _calculateClosestProperTick(lower))
                );
                require(
                    upper % TICK_SPACING == 0,
                    InvalidTick(e, i, upper, _calculateClosestProperTick(upper))
                );
                require(lower < upper, InvalidTickRange());
                i++;
            }
            e++;
        }
    }
}
