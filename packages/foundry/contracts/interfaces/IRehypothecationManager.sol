// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Currency} from "@v4-core/types/Currency.sol";
import {PoolId} from "@v4-core/types/PoolId.sol";

interface IRehypothecationManager {
    
    struct CampaignVault {
        address campaignOwner;
        bool isActive;
        uint256 campaignEndTime;
        uint256 totalDeposited; 
        uint256 aTokenBalance;
    }

    event Deposited(PoolId indexed poolId, Currency currency, uint256 amount);
    event Withdrawn(PoolId indexed poolId, Currency currency, uint256 amount, uint256 yield, address recipient);
    event CampaignInitialized(PoolId indexed poolId, Currency currency, address campaignOwner);
    event CampaignEnded(PoolId indexed poolId);

    error InvalidAmount();
    error CampaignNotActive();
    error CampaignNotEnded();
    error UnauthorizedWithdrawal();
    error UnsupportedCurrency();
    error AlreadyInitialized();

    function deposit(PoolId poolId, Currency currency, uint256 amount) external payable;
    function withdrawCampaignFunds(PoolId poolId, Currency currency) external returns (uint256 principal, uint256 yield);
    function initializeCampaign(PoolId poolId, Currency currency, address campaignOwner, uint256 campaignDuration) external;
    function getCampaignVault(PoolId poolId, Currency currency) external view returns (CampaignVault memory);
    function getAccruedYield(PoolId poolId, Currency currency) external view returns (uint256);
}