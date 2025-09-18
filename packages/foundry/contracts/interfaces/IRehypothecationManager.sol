// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Currency} from "@v4-core/types/Currency.sol";
import {PoolId} from "@v4-core/types/PoolId.sol";

/// @title IRehypothecationManager
/// @notice Interface for managing campaign deposits into Aave and withdrawing principal + yield.
interface IRehypothecationManager {
    
    struct CampaignVault {
        address campaignOwner;
        bool isActive;
        uint256 campaignEndTime;
        uint256 totalDeposited; 
        uint256 aTokenBalance;
    }

    /// @notice Emitted when funds are deposited on behalf of a campaign.
    event Deposited(PoolId indexed poolId, Currency currency, uint256 amount);
    /// @notice Emitted when principal and yield are withdrawn to the recipient.
    event Withdrawn(PoolId indexed poolId, Currency currency, uint256 amount, uint256 yield, address recipient);
    /// @notice Emitted when a campaign vault is initialized.
    event CampaignInitialized(PoolId indexed poolId, Currency currency, address campaignOwner);
    /// @notice Emitted when a campaign is marked as ended.
    event CampaignEnded(PoolId indexed poolId);

    error InvalidAmount();
    error CampaignNotActive();
    error CampaignNotEnded();
    error UnauthorizedWithdrawal();
    error UnsupportedCurrency();
    error AlreadyInitialized();

    /// @notice Deposits funds on behalf of a campaign into Aave.
    /// @param poolId The Uniswap v4 pool identifier.
    /// @param currency The numeraire currency of the campaign (ETH uses address(0)).
    /// @param amount Amount to deposit. For ETH, must match msg.value.
    function deposit(PoolId poolId, Currency currency, uint256 amount) external payable;

    /// @notice Withdraws principal and accrued yield after the campaign ends.
    /// @param poolId The Uniswap v4 pool identifier.
    /// @param currency The numeraire currency for the campaign.
    /// @return principal Original total deposited amount.
    /// @return yield Accrued yield in underlying units.
    function withdrawCampaignFunds(PoolId poolId, Currency currency) external returns (uint256 principal, uint256 yield);

    /// @notice Initializes a campaign vault with owner and duration.
    /// @param poolId The Uniswap v4 pool identifier.
    /// @param currency The numeraire currency of the campaign.
    /// @param campaignOwner Address authorized to withdraw after end.
    /// @param campaignDuration Number of seconds until campaign end.
    function initializeCampaign(PoolId poolId, Currency currency, address campaignOwner, uint256 campaignDuration) external;

    /// @notice Returns stored vault info for a campaign.
    /// @param poolId The Uniswap v4 pool identifier.
    /// @param currency The numeraire currency of the campaign.
    function getCampaignVault(PoolId poolId, Currency currency) external view returns (CampaignVault memory);

    /// @notice Computes currently accrued yield for a campaign.
    /// @param poolId The Uniswap v4 pool identifier.
    /// @param currency The numeraire currency of the campaign.
    function getAccruedYield(PoolId poolId, Currency currency) external view returns (uint256);
}