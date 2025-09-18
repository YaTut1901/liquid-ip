// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IRehypothecationManager} from "./interfaces/IRehypothecationManager.sol";
import {Currency} from "@v4-core/types/Currency.sol";
import {PoolId} from "@v4-core/types/PoolId.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IPoolDataProvider} from "@aave/core-v3/contracts/interfaces/IPoolDataProvider.sol";
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";

/// @title RehypothecationManager
/// @notice Manages depositing idle campaign proceeds into Aave to earn yield and
///         returning principal plus accrued yield to the campaign owner once the campaign ends.
/// @dev Deposits are tracked per Uniswap v4 `PoolId` and `Currency` (numeraire). The contract
///      holds aTokens and proportionally attributes balances to active campaigns. ETH deposits
///      are routed via Aave's Wrapped Token Gateway; ERC20 deposits are supplied directly.
contract RehypothecationManager is IRehypothecationManager, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IPool public immutable aavePool;
    IPoolDataProvider public immutable aaveDataProvider;
    address public immutable wrappedTokenGateway;

    mapping(address => bool) public authorizedHooks;
    mapping(PoolId => mapping(Currency => CampaignVault)) public campaignVaults;

    // Track global aToken balance to properly allocate per campaign
    mapping(Currency => uint256) public totalATokenBalance;

    /// @notice Restricts function access to pre-authorized hook contracts.
    /// @dev Owner can add/remove authorized hooks via {authorizeHook} and {revokeHook}.
    modifier onlyAuthorizedHook() {
        require(authorizedHooks[msg.sender], "Unauthorized hook");
        _;
    }

    /// @notice Initializes the rehypothecation manager with Aave endpoints and ownership.
    /// @param _owner Address that will own admin functions (authorizing hooks).
    /// @param _aavePool Address of Aave v3 Pool contract used for supply/withdraw.
    /// @param _aaveDataProvider Address of Aave v3 PoolDataProvider used to resolve aTokens.
    /// @param _wrappedTokenGateway Address of Aave's Wrapped Token Gateway for ETH.
    constructor(address _owner, address _aavePool, address _aaveDataProvider, address _wrappedTokenGateway) Ownable(_owner) {
        aavePool = IPool(_aavePool);
        aaveDataProvider = IPoolDataProvider(_aaveDataProvider);
        wrappedTokenGateway = _wrappedTokenGateway;
    }

    /// @dev Resolves Aave aToken for a given underlying asset; reverts if unsupported.
    /// @param underlying ERC20 underlying asset address.
    /// @return aToken The corresponding Aave aToken address.
    function _getATokenAddress(address underlying) private view returns (address aToken) {
        (aToken, , ) = aaveDataProvider.getReserveTokensAddresses(underlying);
        require(aToken != address(0), "Asset not supported by Aave");
        return aToken;
    }

    /// @dev Maps Currency to an underlying ERC20 address for Aave. For native ETH (address(0)),
    ///      returns canonical WETH address used by Aave.
    /// @param currency The Uniswap v4 currency type.
    /// @return The ERC20 underlying address or WETH for ETH.
    function _getUnderlying(Currency currency) private pure returns (address) {
        address underlying = Currency.unwrap(currency);
        // If native ETH, use WETH address for Aave 
        if (underlying == address(0)) {
            return 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        }
        return underlying;
    }

    /// @notice Authorizes a hook contract to call campaign/rehypothecation functions.
    /// @param hook The hook contract address to authorize.
    function authorizeHook(address hook) external onlyOwner {
        authorizedHooks[hook] = true;
    }

    /// @notice Revokes a previously authorized hook contract.
    /// @param hook The hook contract address to revoke.
    function revokeHook(address hook) external onlyOwner {
        authorizedHooks[hook] = false;
    }

    /// @notice Initializes a campaign vault for a given pool and currency.
    /// @dev Verifies the currency is supported by Aave by resolving its aToken. A campaign can be
    ///      initialized only once. Duration defines when withdrawals are permitted.
    /// @param poolId Uniswap v4 pool identifier.
    /// @param currency Campaign numeraire currency.
    /// @param campaignOwner Address entitled to withdraw principal and yield after the campaign ends.
    /// @param campaignDuration Duration in seconds from initialization to campaign end.
    function initializeCampaign(
        PoolId poolId,
        Currency currency,
        address campaignOwner,
        uint256 campaignDuration
    ) external override onlyAuthorizedHook {
        CampaignVault storage vault = campaignVaults[poolId][currency];
        if (vault.isActive) revert AlreadyInitialized();

        address underlying = _getUnderlying(currency);
        _getATokenAddress(underlying);

        vault.campaignOwner = campaignOwner;
        vault.isActive = true;
        vault.campaignEndTime = block.timestamp + campaignDuration;
        vault.totalDeposited = 0;
        vault.aTokenBalance = 0;

        emit CampaignInitialized(poolId, currency, campaignOwner);
    }

    /// @notice Deposits campaign proceeds into Aave for the specified pool and currency.
    /// @dev For ETH deposits, `msg.value` must equal `amount` and funds are routed via WrappedTokenGateway.
    ///      For ERC20 deposits, tokens are transferred from the caller and supplied to Aave.
    ///      Accrued aTokens are attributed to the campaign's vault proportionally.
    /// @param poolId Uniswap v4 pool identifier.
    /// @param currency The numeraire currency being deposited (ETH or ERC20).
    /// @param amount The amount to deposit.
    function deposit(
        PoolId poolId,
        Currency currency,
        uint256 amount
    ) external payable override onlyAuthorizedHook nonReentrant {
        if (amount == 0) revert InvalidAmount();

        CampaignVault storage vault = campaignVaults[poolId][currency];
        if (!vault.isActive) revert CampaignNotActive();

        address underlying = _getUnderlying(currency);
        address aToken = _getATokenAddress(underlying);

        uint256 aTokenBalanceBefore = IERC20(aToken).balanceOf(address(this));

        if (Currency.unwrap(currency) == address(0)) {
            // use WrappedTokenGateway for native ETH
            require(msg.value == amount, "ETH amount mismatch");
            // Call depositETH on wrapped token gateway
            (bool success,) = wrappedTokenGateway.call{value: msg.value}(
                abi.encodeWithSignature("depositETH(address,address,uint16)", address(aavePool), address(this), uint16(0))
            );
            require(success, "depositETH failed");
        } else {
            require(msg.value == 0, "ETH sent for ERC20 deposit");
            IERC20(underlying).safeTransferFrom(msg.sender, address(this), amount);
            IERC20(underlying).safeIncreaseAllowance(address(aavePool), amount);
            aavePool.supply(underlying, amount, address(this), uint16(0));
        }

        uint256 aTokenBalanceAfter = IERC20(aToken).balanceOf(address(this));
        uint256 aTokensMinted = aTokenBalanceAfter - aTokenBalanceBefore;

        vault.aTokenBalance += aTokensMinted;
        vault.totalDeposited += amount;

        totalATokenBalance[currency] += aTokensMinted;

        emit Deposited(poolId, currency, amount);
    }

    /// @notice Withdraws the campaign's principal and accrued yield to the campaign owner after end time.
    /// @dev Calculates the campaign share of current aToken balance based on its attributed aTokens.
    ///      For ETH currency, uses WrappedTokenGateway to unwrap and transfer ETH. Marks the campaign inactive.
    /// @param poolId Uniswap v4 pool identifier.
    /// @param currency The campaign's numeraire currency.
    /// @return principal The original deposited amount.
    /// @return yield The accrued yield amount (0 if none).
    function withdrawCampaignFunds(
        PoolId poolId,
        Currency currency
    ) external override nonReentrant returns (uint256 principal, uint256 yield) {
        CampaignVault storage vault = campaignVaults[poolId][currency];

        if (!vault.isActive) revert CampaignNotActive();
        if (msg.sender != vault.campaignOwner) revert UnauthorizedWithdrawal();
        if (block.timestamp < vault.campaignEndTime) revert CampaignNotEnded();

        address underlying = _getUnderlying(currency);
        address aToken = _getATokenAddress(underlying);

        uint256 currentTotalBalance = IERC20(aToken).balanceOf(address(this));
        uint256 campaignATokens = totalATokenBalance[currency] > 0
            ? (currentTotalBalance * vault.aTokenBalance) / totalATokenBalance[currency]
            : vault.aTokenBalance;

        if (campaignATokens > 0) {
            uint256 withdrawn;

            if (Currency.unwrap(currency) == address(0)) {
                // wrappedTokenGateway for ETH
                IERC20(aToken).safeIncreaseAllowance(wrappedTokenGateway, campaignATokens);
                (bool success,) = wrappedTokenGateway.call(
                    abi.encodeWithSignature("withdrawETH(address,uint256,address)", address(aavePool), campaignATokens, msg.sender)
                );
                require(success, "withdrawETH failed");
                withdrawn = campaignATokens; 
            } else {
                withdrawn = aavePool.withdraw(underlying, campaignATokens, msg.sender);
            }

            principal = vault.totalDeposited;
            yield = withdrawn > principal ? withdrawn - principal : 0;

            totalATokenBalance[currency] -= vault.aTokenBalance;

            vault.isActive = false;
            vault.totalDeposited = 0;
            vault.aTokenBalance = 0;

            emit Withdrawn(poolId, currency, principal, yield, msg.sender);
        }

        return (principal, yield);
    }

    /// @notice Returns the current vault state for a campaign.
    /// @param poolId Uniswap v4 pool identifier.
    /// @param currency The campaign's numeraire currency.
    /// @return The `CampaignVault` struct.
    function getCampaignVault(
        PoolId poolId,
        Currency currency
    ) external view override returns (CampaignVault memory) {
        return campaignVaults[poolId][currency];
    }

    /// @notice Returns the currently accrued yield (if any) for a campaign.
    /// @dev Computes the campaign's proportional current value from aToken balance and subtracts totalDeposited.
    /// @param poolId Uniswap v4 pool identifier.
    /// @param currency The campaign's numeraire currency.
    /// @return The accrued yield amount in underlying units.
    function getAccruedYield(
        PoolId poolId,
        Currency currency
    ) external view override returns (uint256) {
        CampaignVault storage vault = campaignVaults[poolId][currency];

        if (!vault.isActive || vault.aTokenBalance == 0) return 0;

        address underlying = _getUnderlying(currency);
        address aToken = _getATokenAddress(underlying);
        uint256 currentTotalBalance = IERC20(aToken).balanceOf(address(this));

        uint256 campaignCurrentValue = totalATokenBalance[currency] > 0
            ? (currentTotalBalance * vault.aTokenBalance) / totalATokenBalance[currency]
            : vault.aTokenBalance;

        return campaignCurrentValue > vault.totalDeposited ? campaignCurrentValue - vault.totalDeposited : 0;
    }

    /// @notice Accepts ETH sent from Aave Wrapped Token Gateway during withdrawals.
    receive() external payable {}
}
