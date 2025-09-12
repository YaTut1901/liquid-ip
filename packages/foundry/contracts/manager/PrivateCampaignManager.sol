// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPoolManager} from "@v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "@v4-core/types/PoolKey.sol";
import {PoolId} from "@v4-core/types/PoolId.sol";
import {Currency} from "@v4-core/types/Currency.sol";
import {IHooks} from "@v4-core/interfaces/IHooks.sol";
import {TickMath} from "@v4-core/libraries/TickMath.sol";
import {console} from "forge-std/console.sol";
import {PrivateLicenseHook} from "../hook/PrivateLicenseHook.sol";
import {LicenseERC20} from "../token/LicenseERC20.sol";
import {IHooks} from "@v4-core/interfaces/IHooks.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {InEuint32, InEuint256, InEuint128} from "@fhenixprotocol/cofhe-contracts/FHE.sol";
import {AbstractCampaignManager} from "./AbstractCampaignManager.sol";
import {PrivateCampaignConfig} from "../lib/PrivateCampaignConfig.sol";

contract PublicCampaignManager is AbstractCampaignManager {
    using PrivateCampaignConfig for bytes;

    PrivateLicenseHook public immutable licenseHook;

    constructor(
        address _owner,
        IPoolManager _manager,
        IERC721 _patentErc721,
        IERC20[] memory _allowedNumeraires,
        PrivateLicenseHook _licenseHook
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

    function initialize(
        uint256 patentId,
        string memory assetMetadataUri,
        bytes32 licenseSalt,
        IERC20 numeraire,
        bytes calldata campaignConfig
    ) external override {
        _validateGeneral(assetMetadataUri, patentId, licenseSalt, numeraire);

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

        // licenseHook.initializeState(poolKey, campaignConfig);

        poolManager.initialize(
            poolKey,
            TickMath.getSqrtPriceAtTick(TickMath.MAX_TICK)
        );

        emit CampaignInitialized(patentId, address(license), poolKey.toId());
    }
}
