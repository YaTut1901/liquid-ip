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
import {LicenseHook} from "./LicenseHook.sol";
import {LicenseERC20} from "./LicenseERC20.sol";
import {IHooks} from "@v4-core/interfaces/IHooks.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IEpochLiquidityAllocationManager} from "./interfaces/IEpochLiquidityAllocationManager.sol";
import {IRehypothecationManager} from "./interfaces/IRehypothecationManager.sol";

contract CampaignManager is Ownable {
    int24 public constant TICK_SPACING = 30;

    error InvalidAssetNumeraireOrder();
    error InvalidTimeRange();
    error CurveTickRangeNotPositive();
    error InvalidEpochTickRange(int24 closestProperTickRange);
    error NumeraireNotAllowed();
    error InvalidStartingTick(int24 closestProperStartingTick);
    error InvalidERC721();
    error PatentNotDelegated();
    error CampaignOngoing();
    error EpochLiquidityAllocationManagerNotAllowed();
    error RehypothecationManagerNotAllowed();

    event PatentDelegated(uint256 patentId, address owner);
    event PatentRetrieved(uint256 patentId, address owner);
    event CampaignInitialized(uint256 patentId, address license, PoolId poolId);

    IERC721 public immutable patentErc721;
    IPoolManager public immutable poolManager;
    LicenseHook public immutable licenseHook;

    mapping(IERC20 numeraire => bool isAllowed) public isAllowedNumeraires;
    mapping(IEpochLiquidityAllocationManager epochLiquidityAllocationManager => bool isAllowed)
        public isAllowedEpochLiquidityAllocationManagers;
    mapping(IRehypothecationManager rehypothecationManager => bool isAllowed)
        public isAllowedRehypothecationManagers;
    mapping(uint256 delegatedPatentId => address owner) public delegatedPatents;
    mapping(uint256 patentId => uint256 campaignEndTimestamp)
        public campaignEndTimestamp;

    constructor(
        IPoolManager _manager,
        IERC721 _patentErc721,
        IERC20[] memory _allowedNumeraires,
        IEpochLiquidityAllocationManager[]
            memory _allowedEpochLiquidityAllocationManagers,
        IRehypothecationManager[] memory _allowedRehypothecationManagers,
        LicenseHook _licenseHook
    ) Ownable() {
        poolManager = _manager;
        patentErc721 = _patentErc721;
        licenseHook = _licenseHook;

        for (uint256 i = 0; i < _allowedNumeraires.length; i++) {
            isAllowedNumeraires[_allowedNumeraires[i]] = true;
        }

        for (
            uint256 i = 0;
            i < _allowedEpochLiquidityAllocationManagers.length;
            i++
        ) {
            isAllowedEpochLiquidityAllocationManagers[
                _allowedEpochLiquidityAllocationManagers[i]
            ] = true;
        }

        for (uint256 i = 0; i < _allowedRehypothecationManagers.length; i++) {
            isAllowedRehypothecationManagers[
                _allowedRehypothecationManagers[i]
            ] = true;
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
        isAllowedNumeraires[numeraire] = true;
    }

    function removeAllowedNumeraire(IERC20 numeraire) external onlyOwner {
        isAllowedNumeraires[numeraire] = false;
    }

    function addAllowedEpochLiquidityAllocationManager(
        IEpochLiquidityAllocationManager epochLiquidityAllocationManager
    ) external onlyOwner {
        isAllowedEpochLiquidityAllocationManagers[
            epochLiquidityAllocationManager
        ] = true;
    }

    function removeAllowedEpochLiquidityAllocationManager(
        IEpochLiquidityAllocationManager epochLiquidityAllocationManager
    ) external onlyOwner {
        isAllowedEpochLiquidityAllocationManagers[
            epochLiquidityAllocationManager
        ] = false;
    }

    function addAllowedRehypothecationManager(
        IRehypothecationManager rehypothecationManager
    ) external onlyOwner {
        isAllowedRehypothecationManagers[rehypothecationManager] = true;
    }

    function removeAllowedRehypothecationManager(
        IRehypothecationManager rehypothecationManager
    ) external onlyOwner {
        isAllowedRehypothecationManagers[rehypothecationManager] = false;
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
        int24 startingTick,
        int24 curveTickRange,
        uint256 startingTime,
        uint256 endingTime,
        uint24 totalEpochs,
        uint256 tokensToSell,
        IEpochLiquidityAllocationManager epochLiquidityAllocationManager,
        IRehypothecationManager rehypothecationManager
    ) external {
        int24 epochTickRange = int24(uint24(curveTickRange) / totalEpochs);

        _validateInput(
            assetMetadataUri,
            patentId,
            licenseSalt,
            numeraire,
            startingTick,
            curveTickRange,
            startingTime,
            endingTime,
            epochTickRange,
            totalEpochs,
            epochLiquidityAllocationManager,
            rehypothecationManager
        );

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
            tickSpacing: TICK_SPACING // constant TICK_SPACING is used for all pools
        });

        campaignEndTimestamp[patentId] = endingTime;

        license.mint(address(licenseHook), tokensToSell);

        licenseHook.initializeState(
            poolKey,
            startingTick,
            curveTickRange,
            startingTime,
            endingTime,
            totalEpochs,
            tokensToSell,
            epochTickRange,
            epochLiquidityAllocationManager,
            rehypothecationManager
        );

        poolManager.initialize(
            poolKey,
            TickMath.getSqrtPriceAtTick(startingTick)
        );

        emit CampaignInitialized(patentId, address(license), poolKey.toId());
    }

    function _validateInput(
        string memory assetMetadataUri,
        uint256 patentId,
        bytes32 licenseSalt,
        IERC20 numeraire,
        int24 startingTick,
        int24 curveTickRange,
        uint256 startingTime,
        uint256 endingTime,
        int24 epochTickRange,
        uint24 totalEpochs,
        IEpochLiquidityAllocationManager epochLiquidityAllocationManager,
        IRehypothecationManager rehypothecationManager
    ) internal view {
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

        require(startingTime < endingTime, InvalidTimeRange());

        // Check that the curve tick range is positive
        require(curveTickRange > 0, CurveTickRangeNotPositive());

        // Check that the starting tick is a multiple of the tick spacing
        require(
            startingTick % TICK_SPACING == 0,
            InvalidStartingTick(_calculateClosestProperTick(startingTick))
        );

        // Check that the epoch tick range is a multiple of the tick spacing
        require(
            epochTickRange % TICK_SPACING == 0,
            InvalidEpochTickRange(
                _calculateClosestProperTickRange(epochTickRange, totalEpochs)
            )
        );

        // Check that the numeraire is allowed
        require(isAllowedNumeraires[numeraire], NumeraireNotAllowed());

        // Check that the epoch liquidity allocation manager is allowed
        require(
            isAllowedEpochLiquidityAllocationManagers[
                epochLiquidityAllocationManager
            ],
            EpochLiquidityAllocationManagerNotAllowed()
        );

        // Check that the rehypothecation manager is allowed
        require(
            isAllowedRehypothecationManagers[rehypothecationManager],
            RehypothecationManagerNotAllowed()
        );
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
