// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/*
Test Plan: PublicLicenseHook Integration (swaps and price actions only)

Scope
- Validate swap-time behavior of `PublicLicenseHook` with the real v4 `PoolManager`: allocation on first swap, price landing at top-of-liquidity, amount in/out correctness, and state/balance evolution across multiple swaps and epochs.
- Do not test deployment/initialization logic; assume pool and config are set up in test setup.

Conventions
- Use real v4 `PoolManager` and routers via Deployers.
- Deploy hook with `HookMiner` to match `getHookPermissions`.
- Configure verifier to behave as VALID (no mailbox flow) so swaps aren’t blocked.
- Use `LicenseERC20` as `currency0` providing a fixed `patentId`.
- Initialize the pool once in setup; tests focus solely on swaps and post-swap assertions.
- Use `vm.warp` to enter specific epoch windows before executing swap sequences.

Swap-Focused Integration Tests
1) First-swap allocation and price anchoring
   - Given epoch E has positions, perform the first swap in E.
   - Assert `ModifyLiquidity` adds all E positions; `LiquidityAllocated(poolId,E)` emitted once.
   - Assert `slot0.sqrtPriceX96 == TickMath.getSqrtPriceAtTick(maxTickUpper_E)` (top-of-liquidity).

2) Multi-swap bombardment within an epoch (fuzzed 10–20 swaps)
   - Generate a sequence of swaps (fuzz zeroForOne, exactIn/out sign/magnitude, and reasonable price limits).
   - For each swap:
     - Assert returned `swapDelta` signs and directions are consistent with zeroForOne and exactIn/out.
     - Assert pool price respects the provided limit and moves monotonically toward the limit without overshooting.
     - Assert conservation-ish checks: nonzero output only when liquidity is present; zero output if beyond liquidity.
     - Optionally assert pool manager deltas settle to zero by end of swap (or via settle path), using TransientState queries.

3) Epoch boundary: automatic cleanup/apply on first swap of next epoch
   - Warp into next epoch window and perform one swap.
   - Assert removal of all prior epoch positions (negative liquidity deltas) and addition of current epoch positions (positive deltas).
   - Assert price anchors at `TickMath.getSqrtPriceAtTick(maxTickUpper_nextEpoch)` immediately after allocation.

4) Empty-positions epoch behavior
   - For an epoch with `numPositions=0`, first swap emits `LiquidityAllocated` and performs no `ModifyLiquidity`.
   - Bombard with 10–20 swaps; assert near-zero price movement and zero output amounts (no liquidity).

5) Direction and limits correctness under bombardment
   - Mix zeroForOne and oneForZero swaps with realistic price limits above/below top-of-liquidity.
   - Assert each swap’s `Swap` event (amount0, amount1, sqrtPriceX96, tick) matches direction and limit semantics.
   - Verify pool tick never jumps beyond the provided limit in any swap.

6) Amounts in/out plausibility checks
   - For exactIn (amountSpecified < 0), assert magnitude of input equals |amountSpecified| minus fees (if any), and output nonnegative.
   - For exactOut (amountSpecified > 0), assert magnitude of output equals amountSpecified and input nonnegative.
   - Aggregate over 10–20 swaps: ensure cumulative deltas are consistent and no arithmetic anomalies occur.

7) Verifier side-effect call presence (non-blocking)
   - On first swap per epoch, confirm `validate(tokenId)` is invoked once; bombardment swaps in the same epoch should not re-invoke.

Notes
- Prefer realistic, bounded fuzz domains to avoid pathological, price-limit-hitting swaps that short-circuit assertions.
- Use `manager.getSlot0(id)` and `getPositionInfo` for ground-truth state; use emitted `Swap` and `ModifyLiquidity` events to corroborate.
- Keep hook-specific assertions limited to swap-time behavior; pool/hook deployment is assumed correct.
*/

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {IPoolManager} from "@v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "@v4-core/libraries/Hooks.sol";
import {HookMiner} from "@v4-periphery/utils/HookMiner.sol";
import {PublicLicenseHook} from "../contracts/hook/PublicLicenseHook.sol";
import {PatentMetadataVerifier} from "../contracts/PatentMetadataVerifier.sol";
import {PatentERC721} from "../contracts/PatentERC721.sol";
import {ITaskMailbox} from "@hourglass/lib/eigenlayer-middleware/lib/eigenlayer-contracts/src/contracts/interfaces/ITaskMailbox.sol";
import {PoolKey} from "@v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@v4-core/types/PoolId.sol";
import {Currency} from "@v4-core/types/Currency.sol";
import {IHooks} from "@v4-core/interfaces/IHooks.sol";
import {TickMath} from "@v4-core/libraries/TickMath.sol";
import {SwapParams} from "@v4-core/types/PoolOperation.sol";
import {StateLibrary} from "@v4-core/libraries/StateLibrary.sol";
import {CurrencySettler} from "@v4-core-test/utils/CurrencySettler.sol";
import {TransientStateLibrary} from "@v4-core/libraries/TransientStateLibrary.sol";
import {LicenseERC20} from "../contracts/token/LicenseERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {PublicCampaignConfig} from "../contracts/lib/PublicCampaignConfig.sol";

contract TestERC20 is ERC20 {
    uint8 private immutable _decimals;
    constructor(string memory name_, string memory symbol_, uint8 decimals_) ERC20(name_, symbol_) {
        _decimals = decimals_;
    }
    function decimals() public view override returns (uint8) { return _decimals; }
    function mint(address to, uint256 amount) external { _mint(to, amount); }
}

contract PublicLicenseHookIntegration is Test {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    using CurrencySettler for Currency;
    using TransientStateLibrary for IPoolManager;
    using PublicCampaignConfig for bytes;

    IPoolManager internal manager;
    PublicLicenseHook internal hook;
    PatentMetadataVerifier internal verifier;
    PatentERC721 internal patentNft;
    LicenseERC20 internal license0;
    TestERC20 internal token1;
    PoolKey internal key;
    PoolId internal poolId;
    mapping(uint16 => SwapParams[]) internal epochSwaps; // epochIndex => swaps
    struct EpochMeta { uint64 start; uint32 duration; }
    mapping(uint16 => EpochMeta) internal epochMeta;
    uint256 internal testSeed; // configurable via env var SEED

    /// @dev Pseudo-random, valid config generator with ticks aligned to tickSpacing=30 and lower < upper per position.
    /// - Random number of epochs in [1..3]
    /// - For each epoch: random duration in [1800..7200] seconds, random positions in [1..4]
    /// - For each position: random lower/upper ticks (multiples of 30) within a bounded range, random uint128 amount
    function _buildRandomConfigTickSpacing30(uint256 seed) internal view returns (bytes memory) {
        uint64 startTs = uint64(block.timestamp + 1);
        uint16 epochs;
        {
            // epochs in [1..5]
            seed = uint256(keccak256(abi.encode(seed, "epochs")));
            epochs = uint16(1 + (seed % 5));
        }

        // Precompute epoch payloads and their sizes to derive offsets
        bytes[] memory epochPayloads = new bytes[](epochs);
        uint32[] memory epochSizes = new uint32[](epochs);

        // Tick step bounds (steps * 30 = actual ticks). Keep within a safe, compact range
        int24 minStep = -600; // -18000
        int24 maxStep = 600;  //  18000

        for (uint16 e = 0; e < epochs; e++) {
            // duration in [1800..7200]
            seed = uint256(keccak256(abi.encode(seed, "dur", e)));
            uint32 duration = uint32(1800 + (seed % 5401));

            // positions in [1..4]
            seed = uint256(keccak256(abi.encode(seed, "npos", e)));
            uint8 npos = uint8(1 + (seed % 4));

            bytes memory posBytes;
            for (uint8 i = 0; i < npos; i++) {
                // Draw lower step in [minStep .. maxStep-1]
                seed = uint256(keccak256(abi.encode(seed, "lo", e, i)));
                uint256 stepsRange = uint256(int256((maxStep - 1) - minStep));
                int24 lowerStep = int24(int256(minStep) + int256(seed % stepsRange));

                // span in [1..60] steps (i.e., up to 1800 ticks)
                seed = uint256(keccak256(abi.encode(seed, "span", e, i)));
                int24 spanSteps = int24(1 + int256(seed % 60));

                int24 upperStep = lowerStep + spanSteps;
                if (upperStep > maxStep) {
                    upperStep = maxStep;
                }
                if (upperStep <= lowerStep) {
                    upperStep = lowerStep + 1; // ensure strictly increasing
                }

                int24 tickLower = lowerStep * 30;
                int24 tickUpper = upperStep * 30;

                // amount in [1e18 .. 10e18]
                seed = uint256(keccak256(abi.encode(seed, "amt", e, i)));
                uint128 amt = uint128(1 ether + (seed % (10 ether)));

                posBytes = bytes.concat(
                    posBytes,
                    abi.encodePacked(tickLower),
                    abi.encodePacked(tickUpper),
                    abi.encodePacked(amt)
                );
            }

            bytes memory payload = bytes.concat(
                abi.encodePacked(duration),
                abi.encodePacked(npos),
                posBytes
            );
            epochPayloads[e] = payload;
            epochSizes[e] = uint32(payload.length);
        }

        // Compute offsets: header (19) + offsets table (epochs * 4)
        uint32 base = uint32(19 + 4 * uint32(epochs));
        uint32[] memory offsets = new uint32[](epochs);
        uint32 cursor = base;
        for (uint16 e = 0; e < epochs; e++) {
            // Each epoch payload must be 5 + 22*npos bytes
            require(epochSizes[e] >= 5 && ((epochSizes[e] - 5) % 22) == 0, "bad epoch size");
            offsets[e] = cursor;
            cursor += epochSizes[e];
        }

        // Assemble full params: header + offsets + epoch payloads
        bytes memory params = bytes.concat(
            bytes8(keccak256("PublicCampaignConfig")),
            abi.encodePacked(uint8(1)),
            abi.encodePacked(startTs),
            abi.encodePacked(epochs)
        );
        for (uint16 e = 0; e < epochs; e++) {
            params = bytes.concat(params, abi.encodePacked(offsets[e]));
        }
        for (uint16 e = 0; e < epochs; e++) {
            params = bytes.concat(params, epochPayloads[e]);
        }
        return params;
    }

    function setUp() public {
        // Deploy v4 PoolManager (0.8.26) via deployCode without importing PoolManager.sol
        address mgr = deployCode(
            "PoolManager.sol:PoolManager",
            abi.encode(address(this))
        );
        manager = IPoolManager(mgr);
        console.log("Deployed PoolManager:", mgr);

        // Deploy verifier and link a PatentERC721 so validate() is non-blocking
        verifier = new PatentMetadataVerifier(
            ITaskMailbox(address(0)),
            address(0),
            0,
            address(this)
        );
        
        patentNft = new PatentERC721(verifier, address(this));
        verifier.setPatentErc721(patentNft);
        console.log("Deployed Verifier:", address(verifier));
        console.log("Deployed PatentERC721:", address(patentNft));

        // Deploy hook at a permissioned address using HookMiner
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
            address(this)
        );
        (address desired, bytes32 salt) = HookMiner.find(
            address(this),
            flags,
            creationCode,
            constructorArgs
        );
        // CREATE2 deploy to the found address
        hook = new PublicLicenseHook{salt: salt}(
            manager,
            verifier,
            address(this)
        );
        require(address(hook) == desired, "Hook address/flags mismatch");
        console.log("Mined & Deployed Hook at:", address(hook));
        console.logBytes32(salt);

        // Deploy tokens and mint balances
        uint256 patentId = patentNft.mint(address(this), "ipfs://meta");
        license0 = new LicenseERC20(patentNft, patentId, "ipfs://lic");
        token1 = new TestERC20("TKN", "TKN", 18);
        TestERC20(token1).mint(address(this), 1e24);
        console.log("Deployed LicenseERC20 (currency1):", address(license0));
        console.log("Deployed TestERC20 (currency0):", address(token1));

        // Ensure address order required by v4 (currency0 < currency1) while keeping license as currency1
        // If order is wrong, deploy a new token1 until it's less than license0
        uint256 guard = 0;
        while (address(token1) >= address(license0)) {
            token1 = new TestERC20("TKN", "TKN", 18);
            TestERC20(token1).mint(address(this), 1);
            guard++;
            require(guard < 8, "token1 order guard");
        }
        license0.mint(address(this), 1e24);

        // Build PoolKey; ensure license is currency1 (address sort must hold)
        require(address(token1) < address(license0), "addr order");
        key = PoolKey({
            currency0: Currency.wrap(address(token1)),
            currency1: Currency.wrap(address(license0)),
            fee: 3000,
            tickSpacing: 30,
            hooks: IHooks(address(hook))
        });
        poolId = key.toId();
        console.logBytes32(PoolId.unwrap(poolId));

        // Pre-fund hook with both tokens to cover add-liquidity transfers
        // Prefund hook with both tokens to cover add-liquidity transfers
        license0.mint(address(hook), 1e24);
        token1.mint(address(hook), 1e24);
        console.log("Prefunded hook with license0 and token1");

        // Derive seed from env var if provided, else fallback
        testSeed = vm.envOr("SEED", uint256(0));
        if (testSeed == 0) {
            testSeed = uint256(keccak256(abi.encode(address(this))));
        }

        // Campaign config: randomly generated with tickSpacing=30 using testSeed
        bytes memory params = _buildRandomConfigTickSpacing30(testSeed);
        // mark metadata VALID to avoid mailbox flow
        bytes32 metaSlot = keccak256(abi.encode(uint256(1), uint256(2)));
        vm.store(address(verifier), metaSlot, bytes32(uint256(uint8(1))));
        hook.initializeState(key, params);
        console.log("initializeState complete");

        // Populate randomized swap params per epoch based on config (needs calldata)
        this._populateEpochSwapsFromConfigExternal(params, testSeed);
        this._populateEpochMetaExternal(params);

        // Initialize pool at tick 0 (after config is set so beforeInitialize passes)
        manager.initialize(key, TickMath.getSqrtPriceAtTick(0));
        console.log("Pool initialized at tick 0");
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function _executeSwap(bytes calldata data) internal {
        (PoolKey memory k, SwapParams memory sp) = abi.decode(data, (PoolKey, SwapParams));
        manager.swap(k, sp, "");
        console.log("UnlockCallback: manager.swap executed");
        int256 d0 = manager.currencyDelta(address(this), k.currency0);
        int256 d1 = manager.currencyDelta(address(this), k.currency1);
        console.log("UnlockCallback: currencyDelta d0", d0);
        console.log("UnlockCallback: currencyDelta d1", d1);
        if (d0 < 0) {
            console.log("UnlockCallback: settling currency0", uint256(-d0));
            k.currency0.settle(manager, address(this), uint256(-d0), false);
        }
        if (d1 < 0) {
            console.log("UnlockCallback: settling currency1", uint256(-d1));
            k.currency1.settle(manager, address(this), uint256(-d1), false);
        }
        if (d0 > 0) {
            console.log("UnlockCallback: taking currency0", uint256(d0));
            k.currency0.take(manager, address(this), uint256(d0), false);
        }
        if (d1 > 0) {
            console.log("UnlockCallback: taking currency1", uint256(d1));
            k.currency1.take(manager, address(this), uint256(d1), false);
        }
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(manager), "only manager");
        _executeSwap(data);
        return "";
    }

    /// @dev External wrapper to accept calldata for config parsing using the library.
    function _populateEpochSwapsFromConfigExternal(bytes calldata params, uint256 seed) external {
        require(msg.sender == address(this), "self only");
        _populateEpochSwapsFromConfig(params, seed);
    }

    /// @dev Parses the config and fills epochSwaps with randomized swaps.
    /// Some epochs may have zero swaps intentionally.
    function _populateEpochSwapsFromConfig(bytes calldata params, uint256 seed) internal {
        params.validate();
        uint16 epochs = params.numEpochs();

        for (uint16 e = 0; e < epochs; e++) {
            delete epochSwaps[e];

            // choose 0..4 swaps for this epoch
            seed = uint256(keccak256(abi.encode(seed, "nswaps", e)));
            uint8 nswaps = uint8(seed % 5);

            if (nswaps == 0) {
                continue; // epoch with no swaps
            }

            // derive a valid zeroForOne price limit: if epoch top tick is negative, anchor near it; otherwise anchor just below 0
            int24 topTick = params.epochStartingTick(e);
            int24 limitTick = topTick < 0 ? topTick - int24(1) : int24(-1);
            if (limitTick < TickMath.MIN_TICK) {
                limitTick = TickMath.MIN_TICK + 1;
            }
            uint160 limit = TickMath.getSqrtPriceAtTick(limitTick);

            for (uint8 i = 0; i < nswaps; i++) {
                // randomize exactIn size in [1e18 .. 5e18]
                seed = uint256(keccak256(abi.encode(seed, "amt", e, i)));
                int256 amtIn = int256(1e18 + (seed % 5) * 1e18);

                SwapParams memory sp = SwapParams({
                    zeroForOne: true,
                    amountSpecified: -amtIn, // exact in
                    sqrtPriceLimitX96: limit
                });
                epochSwaps[e].push(sp);
            }
        }
    }

    /// @dev External wrapper to store epoch start/duration in memory for test warps.
    function _populateEpochMetaExternal(bytes calldata params) external {
        require(msg.sender == address(this), "self only");
        _populateEpochMeta(params);
    }

    function _populateEpochMeta(bytes calldata params) internal {
        params.validate();
        uint16 epochs = params.numEpochs();
        for (uint16 e = 0; e < epochs; e++) {
            epochMeta[e] = EpochMeta({
                start: params.epochStartingTime(e),
                duration: params.durationSeconds(e)
            });
        }
    }

    function test_Bombardment_ByEpoch_ExecutesSwapsAndWarps() public {
        // approvals
        token1.approve(address(manager), type(uint256).max);
        license0.approve(address(manager), type(uint256).max);

        // iterate epochs
        uint16 e = 0;
        while (true) {
            EpochMeta memory m = epochMeta[e];
            if (m.start == 0) break; // no more epochs

            // warp to the beginning of the epoch window
            vm.warp(m.start + 1);
            console.log("Epoch start");
            console.logUint(e);
            console.log("Start ts");
            console.logUint(m.start);
            console.log("Duration");
            console.logUint(m.duration);

            // execute swaps for this epoch if any;
            // ensure the first swap for an epoch anchors at top-of-liquidity by using a limit at topTick-1
            SwapParams[] memory arr = epochSwaps[e];
            for (uint256 i = 0; i < arr.length; i++) {
                (uint160 sqrtP, int24 curTick,,) = manager.getSlot0(poolId);
                int24 limitTickExec = curTick - int24(1);
                if (limitTickExec < TickMath.MIN_TICK) {
                    limitTickExec = TickMath.MIN_TICK + 1;
                }
                uint160 execLimit = TickMath.getSqrtPriceAtTick(limitTickExec);
                SwapParams memory spExec = arr[i];
                spExec.sqrtPriceLimitX96 = execLimit;
                manager.unlock(abi.encode(key, spExec));
            }

            // move to next epoch index
            unchecked { e++; }
        }
    }
}


