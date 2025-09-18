// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;


import {Test, console} from "forge-std/Test.sol";
import {IPoolManager} from "@v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "@v4-core/libraries/Hooks.sol";
import {HookMiner} from "@v4-periphery/utils/HookMiner.sol";
import {PublicLicenseHook} from "../contracts/hook/PublicLicenseHook.sol";
import {RehypothecationManager} from "../contracts/RehypothecationManager.sol";
import {IRehypothecationManager} from "../contracts/interfaces/IRehypothecationManager.sol";
import {PatentMetadataVerifier} from "../contracts/PatentMetadataVerifier.sol";
import {PatentERC721} from "../contracts/PatentERC721.sol";
import {ITaskMailbox} from "@hourglass/lib/eigenlayer-middleware/lib/eigenlayer-contracts/src/contracts/interfaces/ITaskMailbox.sol";
import {PoolKey} from "@v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@v4-core/types/PoolId.sol";
import {Currency} from "@v4-core/types/Currency.sol";
import {IHooks} from "@v4-core/interfaces/IHooks.sol";
import {TickMath} from "@v4-core/libraries/TickMath.sol";
import {SwapParams} from "@v4-core/types/PoolOperation.sol";
import {CurrencySettler} from "@v4-core-test/utils/CurrencySettler.sol";
import {StateLibrary} from "@v4-core/libraries/StateLibrary.sol";
import {TransientStateLibrary} from "@v4-core/libraries/TransientStateLibrary.sol";
import {LicenseERC20} from "../contracts/token/LicenseERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PublicCampaignConfig} from "../contracts/lib/PublicCampaignConfig.sol";
import {IPoolDataProvider} from "@aave/core-v3/contracts/interfaces/IPoolDataProvider.sol";
import {IPoolAddressesProvider} from "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";


/* Integration test of Rehypothecation with PublicLicenseHook
 - Test to add: ETH handling
 - Private campaign tests
*/

contract RehypothecationManagerIntegration is Test {
    using PoolIdLibrary for PoolKey;
    using CurrencySettler for Currency;
    using PublicCampaignConfig for bytes;
    using StateLibrary for IPoolManager;
    using TransientStateLibrary for IPoolManager;

    address constant AAVE_POOL = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;
    address constant POOL_ADDRESSES_PROVIDER = 0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e;
    address constant WRAPPED_TOKEN_GATEWAY = 0xd9D93142de7aaB5a98007ef26e6F7F5Eab4c6405;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    IPoolManager internal manager;
    PublicLicenseHook internal hook;
    RehypothecationManager internal rehypManager;
    PatentMetadataVerifier internal verifier;
    PatentERC721 internal patentNft;
    LicenseERC20 internal license1;
    IERC20 internal usdc;
    PoolKey internal key;
    PoolId internal poolId;

    struct EpochMeta {
        uint64 start;
        uint32 duration;
    }
    mapping(uint16 => EpochMeta) internal epochMeta;

    function setUp() public {
        uint256 forkId = vm.createFork(vm.rpcUrl("mainnet"), 21778000);
        vm.selectFork(forkId);

        address aaveDataProvider = IPoolAddressesProvider(POOL_ADDRESSES_PROVIDER).getPoolDataProvider();

        vm.makePersistent(AAVE_POOL);
        vm.makePersistent(aaveDataProvider);
        vm.makePersistent(WRAPPED_TOKEN_GATEWAY);

        address mgr = deployCode(
            "PoolManager.sol:PoolManager",
            abi.encode(address(this))
        );
        manager = IPoolManager(mgr);

        rehypManager = new RehypothecationManager(
            address(this),
            AAVE_POOL,
            aaveDataProvider,
            WRAPPED_TOKEN_GATEWAY
        );

        verifier = new PatentMetadataVerifier(
            ITaskMailbox(address(0)),
            address(0),
            0,
            address(this)
        );

        patentNft = new PatentERC721(verifier, address(this));
        verifier.setPatentErc721(patentNft);

        uint160 flags = uint160(
            Hooks.BEFORE_INITIALIZE_FLAG |
                Hooks.BEFORE_ADD_LIQUIDITY_FLAG |
                Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG |
                Hooks.BEFORE_SWAP_FLAG |
                Hooks.BEFORE_DONATE_FLAG
        );
        bytes memory creationCode = type(PublicLicenseHook).creationCode;
        bytes memory constructorArgs = abi.encode(
            manager,
            verifier,
            rehypManager,
            address(this)
        );
        (address hookAddress, bytes32 salt) = HookMiner.find(
            address(this),
            flags,
            creationCode,
            constructorArgs
        );

        hook = new PublicLicenseHook{salt: salt}(
            manager,
            verifier,
            rehypManager,
            address(this)
        );
        require(address(hook) == hookAddress, "Hook address/flags mismatch");

        rehypManager.authorizeHook(address(hook));

        uint256 patentId = patentNft.mint(address(this), "ipfs://meta");
        license1 = new LicenseERC20(patentNft, patentId, "ipfs://lic");
        usdc = IERC20(USDC); // Use real USDC

        vm.deal(address(this), 100 ether); // Give ETH for gas
        deal(address(usdc), address(this), 1000000 * 1e6);

        license1.mint(address(this), 1000000 * 1e18); // 1M license tokens

        require(address(usdc) < address(license1), "addr order");

        require(address(usdc) < address(license1), "addr order");
        key = PoolKey({
            currency0: Currency.wrap(address(usdc)),
            currency1: Currency.wrap(address(license1)),
            fee: 3000,
            tickSpacing: 30,
            hooks: IHooks(address(hook))
        });
        poolId = key.toId();

        license1.mint(address(hook), 1000000 * 1e18);
        deal(address(usdc), address(hook), 1000000 * 1e6);

        bytes memory config = _buildSimpleConfig();

        bytes32 metaSlot = keccak256(abi.encode(uint256(1), uint256(2)));
        vm.store(address(verifier), metaSlot, bytes32(uint256(uint8(1))));

        hook.initializeState(key, config);

        manager.initialize(key, TickMath.getSqrtPriceAtTick(0));
    }

    function _buildSimpleConfig() internal returns (bytes memory) {
        uint64 startTs = uint64(block.timestamp + 1);
        uint16 epochs = 2;

        bytes memory epoch0 = bytes.concat(
            abi.encodePacked(uint32(3600)), // duration
            abi.encodePacked(uint8(1)),     // numPositions
            abi.encodePacked(int24(-600)),  // tickLower
            abi.encodePacked(int24(600)),   // tickUpper
            abi.encodePacked(uint128(100 * 1e6)) // 100 USDC
        );

        bytes memory epoch1 = bytes.concat(
            abi.encodePacked(uint32(3600)), // duration
            abi.encodePacked(uint8(1)),     // numPositions
            abi.encodePacked(int24(-300)),  // tickLower
            abi.encodePacked(int24(300)),   // tickUpper
            abi.encodePacked(uint128(200 * 1e6)) // 200 USDC
        );

        uint32 headerSize = 19 + 4 * epochs; // 27
        uint32 offset0 = headerSize;
        uint32 offset1 = offset0 + uint32(epoch0.length);

        epochMeta[0] = EpochMeta({start: startTs, duration: 3600});
        epochMeta[1] = EpochMeta({start: startTs + 3600, duration: 3600});

        return bytes.concat(
            bytes8(keccak256("PublicCampaignConfig")),
            abi.encodePacked(uint8(1)),
            abi.encodePacked(startTs),
            abi.encodePacked(epochs),
            abi.encodePacked(offset0),
            abi.encodePacked(offset1),
            epoch0,
            epoch1
        );
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(manager), "only manager");
        (PoolKey memory k, SwapParams memory sp) = abi.decode(data, (PoolKey, SwapParams));

        manager.swap(k, sp, "");

        int256 d0 = manager.currencyDelta(address(this), k.currency0);
        int256 d1 = manager.currencyDelta(address(this), k.currency1);

        if (d0 < 0) {
            k.currency0.settle(manager, address(this), uint256(-d0), false);
        }
        if (d1 < 0) {
            k.currency1.settle(manager, address(this), uint256(-d1), false);
        }
        if (d0 > 0) {
            k.currency0.take(manager, address(this), uint256(d0), false);
        }
        if (d1 > 0) {
            k.currency1.take(manager, address(this), uint256(d1), false);
        }

        return "";
    }

    function _executeSwapWithDynamicLimit(int256 amountSpecified, bool zeroForOne) internal {
        // Use extreme price limits to avoid reverts when hooks move price in beforeSwap
        uint160 limit = zeroForOne ? (TickMath.MIN_SQRT_PRICE + 1) : (TickMath.MAX_SQRT_PRICE - 1);

        SwapParams memory sp = SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: amountSpecified,
            sqrtPriceLimitX96: limit
        });

        manager.unlock(abi.encode(key, sp));
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function test_EpochTransitionTriggersRehypothecation() public {
        usdc.approve(address(manager), type(uint256).max);
        license1.approve(address(manager), type(uint256).max);

        address aaveDataProvider = IPoolAddressesProvider(POOL_ADDRESSES_PROVIDER).getPoolDataProvider();
        (address aTokenAddress,,) = IPoolDataProvider(aaveDataProvider).getReserveTokensAddresses(USDC);
        IERC20 aUSDC = IERC20(aTokenAddress);
        uint256 initialATokenBalance = aUSDC.balanceOf(address(rehypManager));

        EpochMeta memory epoch0 = epochMeta[0];
        vm.warp(epoch0.start + 1);

        _executeSwapWithDynamicLimit(-int256(10 * 1e6), true);

        EpochMeta memory epoch1 = epochMeta[1];
        vm.warp(epoch1.start + 1);

        _executeSwapWithDynamicLimit(-int256(10 * 1e6), true);

        uint256 balanceAfterEpoch0Rehyp = aUSDC.balanceOf(address(rehypManager));

        vm.warp(epoch1.start + epoch1.duration + 1);

        uint256 finalATokenBalance = aUSDC.balanceOf(address(rehypManager));

        IRehypothecationManager.CampaignVault memory vault = rehypManager.getCampaignVault(poolId, key.currency0);
        assertEq(vault.campaignOwner, address(this), "Campaign owner should be set");
        assertTrue(vault.isActive, "Campaign should be active");


        assertGt(balanceAfterEpoch0Rehyp, initialATokenBalance, "aToken balance should increase after epoch 0 rehypothecation");

        assertGe(finalATokenBalance, balanceAfterEpoch0Rehyp, "Final balance should include all epoch rehypothecations");

        if (vault.aTokenBalance > 0) {
            assertGt(finalATokenBalance, initialATokenBalance, "Total aToken balance should increase from all rehypothecations");
            assertEq(vault.totalDeposited, vault.aTokenBalance, "Total deposited should equal aToken balance");

            uint256 accruedYield = rehypManager.getAccruedYield(poolId, key.currency0);
            assertGe(accruedYield, 0, "Yield should be non-negative");
        }
    }

    function test_MultipleCampaignsWithSameCurrency() public {
        LicenseERC20 license2;
        uint256 patentId2;
        uint256 guard = 0;
        while (true) {
            patentId2 = patentNft.mint(address(this), string(abi.encodePacked("ipfs://meta2", guard)));
            license2 = new LicenseERC20(patentNft, patentId2, string(abi.encodePacked("ipfs://lic2", guard)));
            if (address(usdc) < address(license2)) {
                break;
            }
            guard++;
            require(guard < 10, "Could not find suitable license2 address");
        }
        license2.mint(address(this), 1000000 * 1e18);
        license2.mint(address(hook), 1000000 * 1e18); // Fund hook for liquidity

        PoolKey memory key2 = PoolKey({
            currency0: Currency.wrap(address(usdc)),
            currency1: Currency.wrap(address(license2)),
            fee: 3000,
            tickSpacing: 30,
            hooks: IHooks(address(hook))
        });
        PoolId poolId2 = key2.toId();

        bytes32 metaSlot2 = keccak256(abi.encode(uint256(patentId2), uint256(2)));
        vm.store(address(verifier), metaSlot2, bytes32(uint256(uint8(1))));

        bytes memory config2 = _buildSimpleConfig();
        hook.initializeState(key2, config2);
        manager.initialize(key2, TickMath.getSqrtPriceAtTick(0));

        usdc.approve(address(manager), type(uint256).max);
        license1.approve(address(manager), type(uint256).max);
        license2.approve(address(manager), type(uint256).max);

        // Warp to epoch 0 start for both campaigns
        EpochMeta memory epoch0 = epochMeta[0];
        vm.warp(epoch0.start + 1);

        _executeSwapWithDynamicLimit(-int256(2 * 1e6), true);
        _executeSwapWithDynamicLimit(-int256(2 * 1e6), true);   

        _executeSwapForKey(key2, poolId2, -int256(2 * 1e6), true);
        _executeSwapForKey(key2, poolId2, -int256(2 * 1e6), true);

        EpochMeta memory epoch1 = epochMeta[1];
        vm.warp(epoch1.start + 1);

        _executeSwapWithDynamicLimit(-int256(2 * 1e6), true);
        _executeSwapForKey(key2, poolId2, -int256(2 * 1e6), true);

        IRehypothecationManager.CampaignVault memory vault1 = rehypManager.getCampaignVault(poolId, key.currency0);
        IRehypothecationManager.CampaignVault memory vault2 = rehypManager.getCampaignVault(poolId2, key2.currency0);

        assertEq(vault1.campaignOwner, address(this), "Campaign 1 owner should be set");
        assertEq(vault2.campaignOwner, address(this), "Campaign 2 owner should be set");
        assertTrue(vault1.isActive, "Campaign 1 should be active");
        assertTrue(vault2.isActive, "Campaign 2 should be active");

        assertTrue(vault1.isActive && vault2.isActive, "Both campaigns should be active");

        if (vault1.aTokenBalance > 0) {
            uint256 diff1 = vault1.totalDeposited > vault1.aTokenBalance
                ? vault1.totalDeposited - vault1.aTokenBalance
                : vault1.aTokenBalance - vault1.totalDeposited;
            assertLe(diff1, 1, "Campaign 1: deposited and aToken balance should be within 1 wei");
        }
        if (vault2.aTokenBalance > 0) {
            uint256 diff2 = vault2.totalDeposited > vault2.aTokenBalance
                ? vault2.totalDeposited - vault2.aTokenBalance
                : vault2.aTokenBalance - vault2.totalDeposited;
            assertLe(diff2, 1, "Campaign 2: deposited and aToken balance should be within 1 wei");
        }
    }

    function _executeSwapForKey(PoolKey memory k, PoolId /*pid*/, int256 amountSpecified, bool zeroForOne) internal {
        // Use extreme price limits to avoid reverts when hooks move price in beforeSwap
        uint160 limit = zeroForOne ? (TickMath.MIN_SQRT_PRICE + 1) : (TickMath.MAX_SQRT_PRICE - 1);

        SwapParams memory sp = SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: amountSpecified,
            sqrtPriceLimitX96: limit
        });

        manager.unlock(abi.encode(k, sp));
    }

    function test_CampaignOwnerWithdrawal() public {
        usdc.approve(address(manager), type(uint256).max);
        license1.approve(address(manager), type(uint256).max);

        EpochMeta memory epoch0 = epochMeta[0];
        vm.warp(epoch0.start + 1);

        for (uint i = 0; i < 3; i++) {
            _executeSwapWithDynamicLimit(-int256(2 * 1e6), true);
        }

        EpochMeta memory epoch1 = epochMeta[1];
        vm.warp(epoch1.start + 1);

        _executeSwapWithDynamicLimit(-int256(1 * 1e6), true);

        vm.warp(block.timestamp + 1 days);

        vm.warp(epoch1.start + epoch1.duration + 1);

        IRehypothecationManager.CampaignVault memory vaultBefore = rehypManager.getCampaignVault(poolId, key.currency0);
        assertTrue(vaultBefore.isActive, "Campaign should be active");
        assertGt(vaultBefore.aTokenBalance, 0, "Should have aToken balance");

        uint256 userUsdcBefore = usdc.balanceOf(address(this));

        (uint256 principal, uint256 yield) = rehypManager.withdrawCampaignFunds(poolId, key.currency0);

        // Verify withdrawal
        IRehypothecationManager.CampaignVault memory vaultAfter = rehypManager.getCampaignVault(poolId, key.currency0);
        assertFalse(vaultAfter.isActive, "Campaign should be inactive");
        assertEq(vaultAfter.aTokenBalance, 0, "aToken balance should be 0");

        uint256 userUsdcAfter = usdc.balanceOf(address(this));
        assertGt(userUsdcAfter, userUsdcBefore, "User should receive USDC");

        // Verify withdrawal amounts
        assertGt(principal, 0, "Should have principal from rehypothecated funds");
        assertEq(userUsdcAfter - userUsdcBefore, principal + yield, "Total received should equal principal plus yield");
    }

    function test_YieldAccrualAndWithdrawal() public {
        usdc.approve(address(manager), type(uint256).max);
        license1.approve(address(manager), type(uint256).max);

        address aaveDataProvider = IPoolAddressesProvider(POOL_ADDRESSES_PROVIDER).getPoolDataProvider();
        (address aTokenAddress,,) = IPoolDataProvider(aaveDataProvider).getReserveTokensAddresses(USDC);
        IERC20 aUSDC = IERC20(aTokenAddress);

        uint256 depositAmount = 100 * 1e6; // 100 USDC
        deal(address(usdc), address(hook), depositAmount);

        vm.prank(address(hook));
        usdc.approve(address(rehypManager), depositAmount);
        vm.prank(address(hook));
        rehypManager.deposit(poolId, key.currency0, depositAmount);

        uint256 initialATokenBalance = aUSDC.balanceOf(address(rehypManager));
        assertGt(initialATokenBalance, 0, "Should have aTokens from deposit");

        IRehypothecationManager.CampaignVault memory vault = rehypManager.getCampaignVault(poolId, key.currency0);
        assertEq(vault.totalDeposited, depositAmount, "Total deposited should match");
        assertTrue(vault.isActive, "Campaign should be active");

        uint256 accruedYield = rehypManager.getAccruedYield(poolId, key.currency0);
        assertEq(accruedYield, 0, "No yield should have accrued immediately after deposit");

        vm.warp(block.timestamp + 365 days);
        uint256 accruedYieldAfterTime = rehypManager.getAccruedYield(poolId, key.currency0);
        assertGt(accruedYieldAfterTime, accruedYield, "Yield should increase over time");

        EpochMeta memory epoch1 = epochMeta[1];
        vm.warp(epoch1.start + epoch1.duration + 1);

        uint256 userUsdcBefore = usdc.balanceOf(address(this));
        (uint256 principal, uint256 yield) = rehypManager.withdrawCampaignFunds(poolId, key.currency0);
        uint256 userUsdcAfter = usdc.balanceOf(address(this));

        assertEq(principal, depositAmount, "Principal should match deposit");
        assertEq(userUsdcAfter - userUsdcBefore, principal + yield, "Should receive principal + yield");
        assertGt(yield, 0, "Should have earned yield over 1 year");
        assertGe(principal + yield, depositAmount, "Total withdrawal should be at least the deposit amount");
    }
}