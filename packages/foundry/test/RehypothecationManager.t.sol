// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import {RehypothecationManager} from "../contracts/RehypothecationManager.sol";
import {IRehypothecationManager} from "../contracts/interfaces/IRehypothecationManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Currency} from "@v4-core/types/Currency.sol";
import {PoolId} from "@v4-core/types/PoolId.sol";

contract MockHook {
    RehypothecationManager public manager;

    constructor(RehypothecationManager _manager) {
        manager = _manager;
    }
    // mock function for simplicity
    function deposit(PoolId poolId, Currency currency, uint256 amount) external payable {
        if (Currency.unwrap(currency) == address(0)) {
            manager.deposit{value: msg.value}(poolId, currency, amount);
        } else {
            IERC20 token = IERC20(Currency.unwrap(currency));
            token.transferFrom(msg.sender, address(this), amount);
            token.approve(address(manager), amount);
            manager.deposit(poolId, currency, amount);
        }
    }

    function initializeCampaign(
        PoolId poolId,
        Currency currency,
        address campaignOwner,
        uint256 duration
    ) external {
        manager.initializeCampaign(poolId, currency, campaignOwner, duration);
    }
}

contract RehypothecationManagerTest is Test {
    RehypothecationManager public manager;
    MockHook public hook;

    address public owner = address(this);
    address public campaignOwner = makeAddr("owner1");
    address public campaignOwner2 = makeAddr("owner2");
    address public user = makeAddr("user");

    Currency public usdcCurrency;
    Currency public usdtCurrency;
    Currency public ethCurrency;

    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    address constant AAVE_POOL = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;
    address constant AAVE_DATA_PROVIDER = 0x7B4EB56E7CD4b454BA8ff71E4518426369a138a3;
    address constant WRAPPED_TOKEN_GATEWAY = 0xD322A49006FC828F9B5B37Ab215F99B4E5caB19C;

    address constant AAVE_aUSDC = 0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c;
    address constant AAVE_aUSDT = 0x23878914EFE38d27C4D67Ab83ed1b93A74D4086a;
    address constant AAVE_aWETH = 0x4d5F47FA6A74757f35C14fD3a6Ef8E3C9BC514E8;

    PoolId public poolId1;
    PoolId public poolId2;

    function setUp() public {
        vm.createSelectFork("https://eth-mainnet.g.alchemy.com/v2/QL0rexMTCoEvHKylxFPS5", 18800000);

        manager = new RehypothecationManager(owner, AAVE_POOL, AAVE_DATA_PROVIDER, WRAPPED_TOKEN_GATEWAY);
        hook = new MockHook(manager);

        manager.authorizeHook(address(hook));

        usdcCurrency = Currency.wrap(USDC);
        usdtCurrency = Currency.wrap(USDT);
        ethCurrency = Currency.wrap(address(0));

        poolId1 = PoolId.wrap(bytes32(uint256(1)));
        poolId2 = PoolId.wrap(bytes32(uint256(2)));

        deal(USDC, user, 10000e6);
        deal(USDT, user, 10000e6);
        deal(user, 10 ether);
    }

    function testInitializeCampaign() public {
        uint256 duration = 30 days;

        hook.initializeCampaign(poolId1, usdcCurrency, campaignOwner, duration);

        IRehypothecationManager.CampaignVault memory vault = manager.getCampaignVault(poolId1, usdcCurrency);

        assertEq(vault.campaignOwner, campaignOwner);
        assertTrue(vault.isActive);
        assertEq(vault.campaignEndTime, block.timestamp + duration);
        assertEq(vault.totalDeposited, 0);
        assertEq(vault.aTokenBalance, 0);
    }

    function testCannotInitializeTwice() public {
        uint256 duration = 30 days;

        hook.initializeCampaign(poolId1, usdcCurrency, campaignOwner, duration);

        vm.expectRevert(IRehypothecationManager.AlreadyInitialized.selector);
        hook.initializeCampaign(poolId1, usdcCurrency, campaignOwner, duration);
    }

    function testDepositUSDC() public {
        uint256 depositAmount = 1000e6;

        hook.initializeCampaign(poolId1, usdcCurrency, campaignOwner, 30 days);

        vm.startPrank(user);
        IERC20(USDC).approve(address(hook), depositAmount);
        hook.deposit(poolId1, usdcCurrency, depositAmount);
        vm.stopPrank();

        IRehypothecationManager.CampaignVault memory vault = manager.getCampaignVault(poolId1, usdcCurrency);
        assertEq(vault.totalDeposited, depositAmount);
        assertGt(vault.aTokenBalance, 0);

        uint256 aUSDCBalance = IERC20(AAVE_aUSDC).balanceOf(address(manager));
        assertGt(aUSDCBalance, 0);
    }

    function testDepositETH() public {
        uint256 depositAmount = 1 ether;

        hook.initializeCampaign(poolId1, ethCurrency, campaignOwner, 30 days);

        vm.prank(user);
        hook.deposit{value: depositAmount}(poolId1, ethCurrency, depositAmount);

        IRehypothecationManager.CampaignVault memory vault = manager.getCampaignVault(poolId1, ethCurrency);
        assertEq(vault.totalDeposited, depositAmount);
        assertGt(vault.aTokenBalance, 0);

        uint256 aWETHBalance = IERC20(AAVE_aWETH).balanceOf(address(manager));
        assertGt(aWETHBalance, 0);
    }

    function testMultipleCampaignsSameCurrency() public {
        uint256 deposit1 = 1000e6;
        uint256 deposit2 = 2000e6;

        hook.initializeCampaign(poolId1, usdcCurrency, campaignOwner, 30 days);
        hook.initializeCampaign(poolId2, usdcCurrency, campaignOwner2, 60 days);

        vm.startPrank(user);
        IERC20(USDC).approve(address(hook), deposit1 + deposit2);
        hook.deposit(poolId1, usdcCurrency, deposit1);
        hook.deposit(poolId2, usdcCurrency, deposit2);
        vm.stopPrank();

        IRehypothecationManager.CampaignVault memory vault1 = manager.getCampaignVault(poolId1, usdcCurrency);
        IRehypothecationManager.CampaignVault memory vault2 = manager.getCampaignVault(poolId2, usdcCurrency);

        assertEq(vault1.totalDeposited, deposit1);
        assertEq(vault2.totalDeposited, deposit2);

        assertGt(vault1.aTokenBalance, 0);
        assertGt(vault2.aTokenBalance, 0);
        assertNotEq(vault1.aTokenBalance, vault2.aTokenBalance);
    }

    function testWithdrawWithYield() public {
        uint256 depositAmount = 1000e6;

        hook.initializeCampaign(poolId1, usdcCurrency, campaignOwner, 30 days);

        vm.startPrank(user);
        IERC20(USDC).approve(address(hook), depositAmount);
        hook.deposit(poolId1, usdcCurrency, depositAmount);
        vm.stopPrank();

        vm.warp(block.timestamp + 30 days);

        uint256 balanceBefore = IERC20(USDC).balanceOf(campaignOwner);

        vm.prank(campaignOwner);
        (uint256 principal, uint256 yield) = manager.withdrawCampaignFunds(poolId1, usdcCurrency);

        uint256 balanceAfter = IERC20(USDC).balanceOf(campaignOwner);

        assertEq(principal, depositAmount);
        assertGe(yield, 0);
        assertEq(balanceAfter - balanceBefore, principal + yield);

        IRehypothecationManager.CampaignVault memory vault = manager.getCampaignVault(poolId1, usdcCurrency);
        assertFalse(vault.isActive);
        assertEq(vault.totalDeposited, 0);
        assertEq(vault.aTokenBalance, 0);
    }

    function testCannotWithdrawBeforeCampaignEnd() public {
        uint256 depositAmount = 1000e6;

        hook.initializeCampaign(poolId1, usdcCurrency, campaignOwner, 30 days);

        vm.startPrank(user);
        IERC20(USDC).approve(address(hook), depositAmount);
        hook.deposit(poolId1, usdcCurrency, depositAmount);
        vm.stopPrank();

        vm.expectRevert(IRehypothecationManager.CampaignNotEnded.selector);
        vm.prank(campaignOwner);
        manager.withdrawCampaignFunds(poolId1, usdcCurrency);
    }

    function testOnlyCampaignOwnerCanWithdraw() public {
        uint256 depositAmount = 1000e6;

        hook.initializeCampaign(poolId1, usdcCurrency, campaignOwner, 30 days);

        vm.startPrank(user);
        IERC20(USDC).approve(address(hook), depositAmount);
        hook.deposit(poolId1, usdcCurrency, depositAmount);
        vm.stopPrank();

        vm.warp(block.timestamp + 30 days);

        vm.expectRevert(IRehypothecationManager.UnauthorizedWithdrawal.selector);
        vm.prank(user);
        manager.withdrawCampaignFunds(poolId1, usdcCurrency);
    }

    function testGetAccruedYield() public {
        uint256 depositAmount = 1000e6;

        hook.initializeCampaign(poolId1, usdcCurrency, campaignOwner, 30 days);

        vm.startPrank(user);
        IERC20(USDC).approve(address(hook), depositAmount);
        hook.deposit(poolId1, usdcCurrency, depositAmount);
        vm.stopPrank();

        uint256 initialYield = manager.getAccruedYield(poolId1, usdcCurrency);
        assertEq(initialYield, 0);

        vm.warp(block.timestamp + 7 days);

        uint256 weekYield = manager.getAccruedYield(poolId1, usdcCurrency);
        assertGe(weekYield, 0);
    }

    function testOnlyAuthorizedHookCanDeposit() public {
        hook.initializeCampaign(poolId1, usdcCurrency, campaignOwner, 30 days);

        vm.expectRevert("Unauthorized hook");
        vm.prank(user);
        manager.deposit(poolId1, usdcCurrency, 1000e6);
    }

    function testRevokeHookAuthorization() public {
        manager.revokeHook(address(hook));

        vm.expectRevert("Unauthorized hook");
        hook.initializeCampaign(poolId1, usdcCurrency, campaignOwner, 30 days);
    }

    function testProportionalYieldDistribution() public {
        uint256 deposit1 = 1000e6;
        uint256 deposit2 = 3000e6;

        hook.initializeCampaign(poolId1, usdcCurrency, campaignOwner, 30 days);
        hook.initializeCampaign(poolId2, usdcCurrency, address(0x9999), 30 days);

        vm.startPrank(user);
        IERC20(USDC).approve(address(hook), deposit1 + deposit2);
        hook.deposit(poolId1, usdcCurrency, deposit1);
        hook.deposit(poolId2, usdcCurrency, deposit2);
        vm.stopPrank();

        vm.warp(block.timestamp + 30 days);

        vm.prank(campaignOwner);
        (uint256 principal1, uint256 yield1) = manager.withdrawCampaignFunds(poolId1, usdcCurrency);

        vm.prank(address(0x9999));
        (uint256 principal2, uint256 yield2) = manager.withdrawCampaignFunds(poolId2, usdcCurrency);

        assertEq(principal1, deposit1);
        assertEq(principal2, deposit2);

        if (yield1 > 0 && yield2 > 0) {
            uint256 ratio = (yield2 * 100) / yield1;
            assertApproxEqAbs(ratio, 300, 10);
        }
    }
}