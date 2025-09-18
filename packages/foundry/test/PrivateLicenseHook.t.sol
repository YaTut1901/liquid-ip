// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/*
Test Plan: PrivateLicenseHook

Scope
- Validate epoch-driven liquidity allocation for private campaigns using encrypted config and async decryption.
- Verify pending-swap buffering, decryption request/ready flow, and anchoring-based tick adjustment before applying positions.

Conventions
- Setup: owner calls initializeState(poolKey, config) once; config already validated.
- Epoch i positions apply on first zeroForOne swap within [epochStartingTime(i), epochStartingTime(i)+duration).
- Position salts: keccak256(abi.encodePacked(epochIndex, positionIndex)).
- Anchoring temporary liquidity uses salt keccak256("ANCHOR_TICK").
- Liquidity computed with _computeLiquidity(..., forAmount0=false) for position adds/removes.
- Verifier called once per first-swap in epoch: verifier.validate(LicenseERC20(currency1).patentId()).
- When decryption is not ready, first beforeSwap returns this.beforeSwap.selector with a simulated delta equal to -amountSpecified on currency0 (async path), fee=0.
- All external interactions MUST be done via mocks/harnesses (no live Uniswap/FHE/EigenLayer):
  - Use a MockPoolManager capturing modifyLiquidity/swap/take/sync/settle calls and tracking deltas.
  - Stub PatentMetadataVerifier to return VALID without mailbox flow.
  - Simulate FHE decryption readiness/results via a harness or adapter that exposes toggles/return values for getDecryptResult(Safe); do not rely on real FHE.
  - Simulate Currency settle/take via mock behavior; assert via counters/flags rather than real transfers.

Happy Path Tests
1) State initialization (owner)
   - Emits PoolStateInitialized(poolId)
   - Populates epoch timing and encrypted positions
   - isConfigInitialized[poolId] == true
   - poolState[poolId].numEpochs == config.numEpochs(); poolState[poolId].currentEpoch == 0

2) Pool initialize (owner, config present)
   - beforeInitialize returns selector; requests decryption for epoch 0
   - isDecryptionRequested[poolId][0] == true

3) First swap in epoch 0 when decryption NOT ready (zeroForOne, exact input)
   - Saves pending swap; sets isDecryptionRequested if not already
   - Returns this.beforeSwap.selector, BeforeSwapDelta reflecting -amountSpecified on currency0, fee=0
   - No positions applied; no LiquidityAllocated event

4) Subsequent swap after decryption becomes ready (same epoch)
   - Executes pending swap settlement path, then anchors tick if needed, then applies positions for epoch 0
   - Uses salts keccak256(abi.encodePacked(0, i)) for positions
   - _handleDeltas runs; poolState.currentEpoch=0; isEpochInitialized[0]=true
   - Emits LiquidityAllocated(poolId, 0)
   - Calls verifier.validate(tokenId) once

5) Subsequent swaps in initialized epoch
   - No modifyLiquidity; no anchoring; no verifier call; no event
   - Returns selector, ZERO_DELTA, fee=0

6) Transition to epoch 1 (advance time into its window)
   - First swap: executes any pending, cleans epoch 0 (negative liquidity), anchors if needed, applies epoch 1 (positive liquidity)
   - poolState.currentEpoch updated to 1; isEpochInitialized[0]=false; isEpochInitialized[1]=true
   - _handleDeltas runs; event emitted; verifier called once

7) Multiple epoch progression
   - Repeat across 3+ epochs; proper decryption request per epoch, pending path only once per epoch if needed; correct cleanup/apply each time

8) Empty-positions epoch
   - numPositions == 0: marks epoch initialized; anchoring may no-op; no liquidity modifications
   - Event emitted; subsequent swaps no-op

9) Liquidity calculation consistency
   - liquidityDelta equals _computeLiquidity(tickLower, tickUpper, amountAllocated, forAmount0=false)

10) Boundary start instant
   - Swap exactly at epochStartingTime(0) triggers first-swap behavior (pending or allocation depending on decryption readiness)

General Uniswap v4 Integration Tests
11) Hook permissions
    - getHookPermissions advertises: beforeInitialize, beforeAddLiquidity, beforeRemoveLiquidity, beforeSwap, beforeDonate = true
    - beforeSwapReturnDelta = true; others = false

12) Liquidity modification and donate blocked
    - beforeAddLiquidity/beforeRemoveLiquidity/beforeDonate revert with ModifyingLiquidityNotAllowed/DonatingNotAllowed

13) Callback return values
    - beforeSwap returns selector, ZERO_DELTA, fee=0 on initialized path (with/without anchoring)
    - beforeSwap returns simulated delta on pending (decryption-not-ready) path

Authorization and Revert Tests
14) Pool initialize authorization
    - beforeInitialize reverts UnauthorizedPoolInitialization when sender != owner

15) Config presence for initialize
    - beforeInitialize reverts ConfigNotInitialized if initializeState not called for poolId

16) Single-config initialization
    - initializeState called twice for same poolId reverts ConfigAlreadyInitialized

17) Currency ordering validation
    - initializeState reverts WrongCurrencyOrder when LicenseERC20 is not currency1

18) Swap direction gating
    - beforeSwap with zeroForOne == false reverts RedeemNotAllowed

19) Exact output swaps not allowed
    - beforeSwap with amountSpecified > 0 reverts ExactOutputNotAllowed

20) Ongoing maintenance guard
    - Second pending swap while one is already pending reverts OngoingMaintenance

Epoch Indexing and Window Behavior
21) Campaign window across all epochs
    - beforeSwap reverts CampaignNotStarted if block.timestamp < epochStartingTime(0)
    - beforeSwap reverts CampaignEnded if block.timestamp > lastEpochStartingTime + lastEpochDuration

22) Epoch index selection within campaign window
    - Within the overall [start0, lastEnd] window, _calculateCurrentEpochIndex picks the correct epoch based on each epoch’s [start_i, start_i+dur_i) sub-window
    - Validate behavior at exact boundaries for middle and last epochs (start inclusive, end exclusive)

Delta Handling and Accounting
23) Negative delta path
    - Simulate negative currency delta; _handleDeltas performs sync + transfer + settle; no residual deltas

24) Positive delta path
    - Simulate positive currency delta; _handleDeltas performs take to hook address; no residual deltas

Decryption, Pending Swap, and Anchoring Behavior
25) Decryption request on initialize and first pending
    - _requestDecryption called for epoch 0 in beforeInitialize; for later epochs, requested on first pending if not already
    - isDecryptionRequested[poolId][epoch] toggled true once per epoch

26) Pending swap save and execute
    - _savePendingSwap takes currency0 from user and records sender/params
    - _executePendingSwaps settles currency0 twice via settler path and clears pendingSwaps

27) Anchoring when target != current aligned tick
    - Sets isAnchoring true during operation and false after
    - Adds temp liquidity with salt keccak256("ANCHOR_TICK"), performs directional swap to price limit, then removes temp liquidity (same salt)
    - beforeSwap re-entrancy during anchoring returns ZERO_DELTA

28) Anchoring no-op when already aligned
    - If targetAligned == currentAligned, anchoring does not modify liquidity and does not stall subsequent swaps; isAnchoring resets to false

29) Tick alignment correctness
    - _alignToSpacing handles negative ticks correctly; verify representative negative/positive cases

Events and Determinism
30) Event emission
    - LiquidityAllocated(poolId, epochIndex) emitted only on first allocation per epoch

31) Deterministic salts
    - Position modifyLiquidity salts equal keccak256(abi.encodePacked(epochIndex, positionIndex)) for adds and removes
*/

import "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {PrivateLicenseHook} from "../contracts/hook/PrivateLicenseHook.sol";
import {AbstractLicenseHook} from "../contracts/hook/AbstractLicenseHook.sol";
import {IPoolManager} from "@v4-core/interfaces/IPoolManager.sol";
import {IHooks} from "@v4-core/interfaces/IHooks.sol";
import {PoolKey} from "@v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@v4-core/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {TickMath} from "@v4-core/libraries/TickMath.sol";
import {HookMiner} from "@v4-periphery/utils/HookMiner.sol";
import {BaseHook} from "@v4-periphery/utils/BaseHook.sol";
import {Hooks} from "@v4-core/libraries/Hooks.sol";
import {PatentERC721} from "../contracts/PatentERC721.sol";
import {PatentMetadataVerifier, Status} from "../contracts/PatentMetadataVerifier.sol";
import {ITaskMailbox} from "@hourglass/lib/eigenlayer-middleware/lib/eigenlayer-contracts/src/contracts/interfaces/ITaskMailbox.sol";
import {LicenseERC20} from "../contracts/token/LicenseERC20.sol";
import {BalanceDelta} from "@v4-core/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@v4-core/types/BeforeSwapDelta.sol";
import {toBeforeSwapDelta} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {SwapParams, ModifyLiquidityParams} from "@v4-core/types/PoolOperation.sol";
import {CoFheTest} from "../lib/cofhe-mock-contracts/contracts/CoFheTest.sol";
import {InEuint32, InEuint128, euint32, euint128, FHE} from "@fhenixprotocol/cofhe-contracts/FHE.sol";
import {LiquidityAmounts} from "@v4-core-test/utils/LiquidityAmounts.sol";
import {IRehypothecationManager} from "../contracts/interfaces/IRehypothecationManager.sol";

contract PatentZeroToken {
    function patentId() external pure returns (uint256) {
        return 0;
    }
}

contract PrivateLicenseHookHarness is PrivateLicenseHook {
    using PoolIdLibrary for PoolKey;

    constructor(
        IPoolManager _manager,
        PatentMetadataVerifier _verifier,
        address _owner
    ) PrivateLicenseHook(_manager, _verifier, IRehypothecationManager(address(0)), _owner) {}

    function getIsConfigInitialized(
        PoolKey memory key
    ) external view returns (bool) {
        return isConfigInitialized[key.toId()];
    }

    function getPoolState(
        PoolKey memory key
    ) external view returns (uint16 numEpochs, uint16 currentEpoch) {
        PoolId id = key.toId();
        numEpochs = poolState[id].numEpochs;
        currentEpoch = poolState[id].currentEpoch;
    }

    function getEpochTiming(
        PoolKey memory key,
        uint16 epoch
    ) external view returns (uint64 startingTime, uint32 durationSeconds) {
        PoolId id = key.toId();
        startingTime = epochs[id][epoch].startingTime;
        durationSeconds = epochs[id][epoch].durationSeconds;
    }

    function getIsEpochInitialized(
        PoolKey memory key,
        uint16 epoch
    ) external view returns (bool) {
        return isEpochInitialized[key.toId()][epoch];
    }

    function getEpochNumPositions(
        PoolKey memory key,
        uint16 epoch
    ) external view returns (uint8) {
        return epochs[key.toId()][epoch].numPositions;
    }

    function getEncryptedPositionRaw(
        PoolKey memory key,
        uint16 epoch,
        uint8 index
    ) external view returns (uint256 tlHash, uint256 tuHash, uint256 amtHash) {
        Position storage p = positions[key.toId()][epoch][index];
        tlHash = euint32.unwrap(p.tickLower);
        tuHash = euint32.unwrap(p.tickUpper);
        amtHash = euint128.unwrap(p.amountAllocated);
    }

    function getPendingSwapSender(
        PoolKey memory key
    ) external view returns (address) {
        return pendingSwaps[key.toId()].sender;
    }

    function getIsDecryptionRequested(
        PoolKey memory key,
        uint16 epoch
    ) external view returns (bool) {
        return isDecryptionRequested[key.toId()][epoch];
    }
}

contract MockPoolManager {
    using PoolIdLibrary for PoolKey;

    PoolKey public lastKey;
    ModifyLiquidityParams public lastModify;
    bytes public lastHookData;
    bool public modifyCalled;
    uint256 public modifyCallCount;
    struct Call {
        ModifyLiquidityParams p;
    }
    Call[] public calls;

    mapping(uint256 => int256) public deltaByCurrencyId;
    bool public takeCalled;
    bool public syncCalled;
    bool public settleCalled;
    bool public swapCalled;
    bool public burnCalled;
    bool public mintCalled;

    function currencyDelta(
        address,
        Currency currency
    ) external view returns (int256) {
        return deltaByCurrencyId[currency.toId()];
    }

    function exttload(bytes32) external pure returns (bytes32 value) {
        return bytes32(0);
    }

    function extsload(bytes32) external view returns (bytes32 value) {
        return bytes32(0);
    }

    function extsload(
        bytes32,
        uint256 n
    ) external view returns (bytes32[] memory values) {
        values = new bytes32[](n);
    }

    function sync(Currency) external {
        syncCalled = true;
    }

    function settle() external payable returns (uint256) {
        settleCalled = true;
        return 0;
    }

    function take(Currency, address, uint256) external {
        takeCalled = true;
    }

    function swap(
        PoolKey memory,
        SwapParams memory,
        bytes calldata
    ) external returns (BalanceDelta, BalanceDelta) {
        swapCalled = true;
        return (BalanceDelta.wrap(0), BalanceDelta.wrap(0));
    }

    function burn(address, uint256, uint256) external {
        burnCalled = true;
    }

    function mint(address, uint256, uint256) external {
        mintCalled = true;
    }

    function modifyLiquidity(
        PoolKey memory key,
        ModifyLiquidityParams memory params,
        bytes calldata hookData
    ) external returns (BalanceDelta, BalanceDelta) {
        lastKey = key;
        lastModify = params;
        lastHookData = hookData;
        modifyCalled = true;
        modifyCallCount++;
        calls.push(Call({p: params}));
        return (BalanceDelta.wrap(0), BalanceDelta.wrap(0));
    }

    function resetCounters() external {
        modifyCalled = false;
        modifyCallCount = 0;
        delete calls;
        takeCalled = false;
        syncCalled = false;
        settleCalled = false;
        swapCalled = false;
        burnCalled = false;
        mintCalled = false;
    }

    function getCall(
        uint256 i
    ) external view returns (int24, int24, int256, bytes32) {
        Call storage c = calls[i];
        return (c.p.tickLower, c.p.tickUpper, c.p.liquidityDelta, c.p.salt);
    }

    function setCurrencyDelta(Currency currency, int256 val) external {
        deltaByCurrencyId[currency.toId()] = val;
    }
}

contract ERC20Mock {
    string public name = "MockToken";
    string public symbol = "MOCK";
    uint8 public decimals = 18;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "insufficient");
        unchecked {
            balanceOf[msg.sender] -= amount;
            balanceOf[to] += amount;
        }
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "insufficient");
        uint256 a = allowance[from][msg.sender];
        require(a >= amount, "allowance");
        unchecked {
            balanceOf[from] -= amount;
            balanceOf[to] += amount;
            allowance[from][msg.sender] = a - amount;
        }
        return true;
    }
}

contract PrivateLicenseHookTest is Test, CoFheTest {
    using PoolIdLibrary for PoolKey;

    PrivateLicenseHookHarness private hook;
    IPoolManager private manager;
    PatentMetadataVerifier private verifier;
    MockPoolManager private mockManager;
    PatentERC721 private patentNft;
    LicenseERC20 private licenseErc20;
    ERC20Mock private currency0;

    event PoolStateInitialized(PoolId poolId);

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function setUp() public {
        mockManager = new MockPoolManager();
        manager = IPoolManager(address(mockManager));
        verifier = new PatentMetadataVerifier(
            ITaskMailbox(address(0)),
            address(0),
            0,
            address(this)
        );
        patentNft = new PatentERC721(verifier, address(this));
        patentNft.mint(address(this), "ipfs://example.com/license");
        licenseErc20 = new LicenseERC20(
            patentNft,
            1,
            "https://example.com/license"
        );
        verifier.setPatentErc721(patentNft);

        currency0 = new ERC20Mock();
        currency0.mint(address(this), 1e24);

        bytes memory creationCode = type(PrivateLicenseHookHarness)
            .creationCode;
        uint160 flags = uint160(
            Hooks.BEFORE_INITIALIZE_FLAG |
                Hooks.BEFORE_ADD_LIQUIDITY_FLAG |
                Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG |
                Hooks.BEFORE_SWAP_FLAG |
                Hooks.BEFORE_DONATE_FLAG |
                Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
        );
        bytes memory constructorArgs = abi.encode(
            IPoolManager(address(manager)),
            PatentMetadataVerifier(address(verifier)),
            address(this)
        );
        (address desired, bytes32 salt) = HookMiner.find(
            address(this),
            flags,
            creationCode,
            constructorArgs
        );
        desired = desired; // silence unused var warning
        hook = new PrivateLicenseHookHarness{salt: salt}(
            manager,
            verifier,
            address(this)
        );
    }

    function test_Init_StateInitialization_SetsMappingsAndEmits() public {
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0xAAAA)),
            currency1: Currency.wrap(address(licenseErc20)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });
        PoolId id = key.toId();

        uint64 start = 1000;
        uint32 dur0 = 3600;
        bytes memory params = _buildSimplePrivateConfig(
            start,
            dur0,
            0,
            0,
            0x01,
            0x20,
            0x80
        );

        vm.expectEmit(true, false, false, true, address(hook));
        emit PoolStateInitialized(id);
        hook.initializeState(key, params);

        assertTrue(hook.getIsConfigInitialized(key));
        (uint16 numEpochs, uint16 currentEpoch) = hook.getPoolState(key);
        assertEq(numEpochs, 1);
        assertEq(currentEpoch, 0);

        (uint64 startingTime0, uint32 duration0) = hook.getEpochTiming(key, 0);
        assertEq(startingTime0, start);
        assertEq(duration0, dur0);
        assertEq(hook.getEpochNumPositions(key, 0), 0);
    }

    function test_Init_WithEncryptedPosition_DecryptsOnBeforeInitialize()
        public
    {
        InEuint32 memory inTL = createInEuint32(
            uint32(int32(-600)),
            0,
            address(this)
        );
        InEuint32 memory inTU = createInEuint32(uint32(600), 0, address(this));
        InEuint128 memory inAmt = createInEuint128(
            uint128(1 ether),
            0,
            address(this)
        );
        uint8 ver = 1;
        uint64 start = 1000;
        uint16 epochs = 1;
        uint32 epoch0Offset = 51 + 4 * uint32(epochs);
        uint32 dur0 = 3600;
        uint8 npos0 = 1;
        uint32 pos0Offset = uint32(epoch0Offset + 4 + 1 + 4);

        bytes memory params = bytes.concat(
            bytes8(keccak256("PrivateCampaignConfig")),
            abi.encodePacked(uint8(ver)),
            abi.encodePacked(uint64(start)),
            abi.encodePacked(uint256(0)),
            abi.encodePacked(uint16(epochs)),
            abi.encodePacked(uint32(epoch0Offset)),
            abi.encodePacked(uint32(dur0)),
            abi.encodePacked(uint8(npos0)),
            abi.encodePacked(uint32(pos0Offset)),
            _encodeEvalFromInEuint32(inTL),
            _encodeEvalFromInEuint32(inTU),
            _encodeEvalFromInEuint128(inAmt)
        );

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0xAAAA)),
            currency1: Currency.wrap(address(licenseErc20)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });
        PoolId id = key.toId();

        vm.expectEmit(true, false, false, true, address(hook));
        emit PoolStateInitialized(id);
        hook.initializeState(key, params);

        vm.prank(address(manager));
        hook.beforeInitialize(
            address(this),
            key,
            uint160(TickMath.getSqrtPriceAtTick(0))
        );

        // advance time to simulate async decryption readiness in mocks
        vm.warp(block.timestamp + 20);

        (uint256 tlHash, uint256 tuHash, uint256 amtHash) = hook
            .getEncryptedPositionRaw(key, 0, 0);
        uint32 tlVal = FHE.getDecryptResult(euint32.wrap(tlHash));
        uint32 tuVal = FHE.getDecryptResult(euint32.wrap(tuHash));
        uint128 amtVal = FHE.getDecryptResult(euint128.wrap(amtHash));

        assertEq(int32(uint32(tlVal)), int32(-600));
        assertEq(uint32(tuVal), uint32(600));
        assertEq(uint128(amtVal), uint128(1 ether));
    }

    function test_Swap_FirstEpoch_PendingWhenNotDecrypted_SavesSwapAndReturnsDelta()
        public
    {
        // Build encrypted inputs via CoFhe mocks
        InEuint32 memory inTL = createInEuint32(
            uint32(int32(-600)),
            0,
            address(this)
        );
        InEuint32 memory inTU = createInEuint32(uint32(600), 0, address(this));
        InEuint128 memory inAmt = createInEuint128(
            uint128(1 ether),
            0,
            address(this)
        );

        uint8 ver = 1;
        uint64 start = uint64(block.timestamp + 10);
        uint16 epochs = 1;
        uint32 epoch0Offset = 51 + 4 * uint32(epochs);
        uint32 dur0 = 3600;
        uint8 npos0 = 1;
        uint32 pos0Offset = uint32(epoch0Offset + 4 + 1 + 4);

        bytes memory params = bytes.concat(
            bytes8(keccak256("PrivateCampaignConfig")),
            abi.encodePacked(uint8(ver)),
            abi.encodePacked(uint64(start)),
            abi.encodePacked(uint256(0)),
            abi.encodePacked(uint16(epochs)),
            abi.encodePacked(uint32(epoch0Offset)),
            abi.encodePacked(uint32(dur0)),
            abi.encodePacked(uint8(npos0)),
            abi.encodePacked(uint32(pos0Offset)),
            _encodeEvalFromInEuint32(inTL),
            _encodeEvalFromInEuint32(inTU),
            _encodeEvalFromInEuint128(inAmt)
        );

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(currency0)),
            currency1: Currency.wrap(address(licenseErc20)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });

        vm.expectEmit(true, false, false, true, address(hook));
        emit PoolStateInitialized(key.toId());
        hook.initializeState(key, params);

        // mark verifier VALID to avoid failure path
        bytes32 slot = keccak256(abi.encode(uint256(1), uint256(2)));
        vm.store(address(verifier), slot, bytes32(uint256(uint8(Status.VALID))));

        // enter epoch window; decryption will be requested inside beforeSwap and not ready this block
        vm.warp(start + 1);
        mockManager.resetCounters();

        SwapParams memory sp = SwapParams({
            zeroForOne: true,
            amountSpecified: -1000,
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });

        vm.recordLogs();
        vm.prank(address(manager));
        (bytes4 sel, BeforeSwapDelta d, uint24 fee) = hook.beforeSwap(
            address(this),
            key,
            sp,
            ""
        );

        // callback return values: selector, simulated delta, fee=0
        assertEq(sel, BaseHook.beforeSwap.selector);
        // expected delta is (-amountSpecified on currency0, 0 on currency1)
        BeforeSwapDelta expected = toBeforeSwapDelta(int128(int256(1000)), 0);
        assertEq(BeforeSwapDelta.unwrap(d), BeforeSwapDelta.unwrap(expected));
        assertEq(fee, 0);

        // no liquidity modification or swaps during pending
        assertEq(mockManager.modifyCallCount(), 0);
        assertEq(mockManager.swapCalled(), false);

        // no LiquidityAllocated event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 topic = keccak256("LiquidityAllocated(bytes32,uint16)");
        for (uint256 i = 0; i < logs.length; i++) {
            assertTrue(
                logs[i].topics.length == 0 || logs[i].topics[0] != topic,
                "unexpected LiquidityAllocated"
            );
        }

        // pending swap saved and decryption requested
        assertEq(hook.getPendingSwapSender(key), address(this));
        assertTrue(hook.getIsDecryptionRequested(key, 0));
    }

    function test_Swap_AfterDecrypt_ExecutesPending_Anchors_AppliesPositions()
        public
    {
        // encrypted inputs
        InEuint32 memory inTL = createInEuint32(
            uint32(int32(-600)),
            0,
            address(this)
        );
        InEuint32 memory inTU = createInEuint32(uint32(600), 0, address(this));
        InEuint128 memory inAmt = createInEuint128(
            uint128(1 ether),
            0,
            address(this)
        );

        uint64 start = uint64(block.timestamp + 10);
        uint16 epochs = 1;
        uint32 epoch0Offset = 51 + 4 * uint32(epochs);
        uint32 dur0 = 3600;
        uint8 npos0 = 2;
        uint32 posOffsetsBase = uint32(epoch0Offset + 4 + 1);
        uint32 pos0Offset = posOffsetsBase + 4 * 2;
        bytes memory evalTL = _encodeEvalFromInEuint32(inTL);
        bytes memory evalTU = _encodeEvalFromInEuint32(inTU);
        bytes memory evalAmt = _encodeEvalFromInEuint128(inAmt);
        InEuint128 memory inAmtZero = createInEuint128(uint128(0), 0, address(this));
        uint32 pos1Offset = pos0Offset + uint32(evalTL.length + evalTU.length + evalAmt.length);

        bytes memory params = bytes.concat(
            bytes8(keccak256("PrivateCampaignConfig")),
            abi.encodePacked(uint8(1)),
            abi.encodePacked(uint64(start)),
            abi.encodePacked(uint256(0)),
            abi.encodePacked(uint16(epochs)),
            abi.encodePacked(uint32(epoch0Offset)),
            abi.encodePacked(uint32(dur0)),
            abi.encodePacked(uint8(npos0)),
            abi.encodePacked(uint32(pos0Offset)),
            abi.encodePacked(uint32(pos1Offset)),
            evalTL,
            evalTU,
            evalAmt,
            evalTL,
            evalTU,
            _encodeEvalFromInEuint128(inAmtZero)
        );

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(currency0)),
            currency1: Currency.wrap(address(licenseErc20)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });

        vm.expectEmit(true, false, false, true, address(hook));
        emit PoolStateInitialized(key.toId());
        hook.initializeState(key, params);

        // verifier VALID
        bytes32 slot = keccak256(abi.encode(uint256(1), uint256(2)));
        vm.store(address(verifier), slot, bytes32(uint256(uint8(Status.VALID))));

        // enter epoch window
        vm.warp(start + 1);
        mockManager.resetCounters();

        // First swap (pending path)
        SwapParams memory sp = SwapParams({
            zeroForOne: true,
            amountSpecified: -1000,
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });

        // Set approval so hook can pull tokens from user when executing pending swap
        currency0.approve(address(hook), 1000);
        vm.prank(address(manager));
        (bytes4 sel1, BeforeSwapDelta d1, uint24 fee1) = hook.beforeSwap(
            address(this),
            key,
            sp,
            ""
        );
        assertEq(sel1, BaseHook.beforeSwap.selector);
        BeforeSwapDelta expected1 = toBeforeSwapDelta(int128(int256(1000)), 0);
        assertEq(BeforeSwapDelta.unwrap(d1), BeforeSwapDelta.unwrap(expected1));
        assertEq(fee1, 0);
        assertEq(hook.getPendingSwapSender(key), address(this));

        // make decryption results ready; do NOT fund hook — tokens must be pulled from user
        vm.warp(start + 30);

        // balances before execution
        uint256 userBalBefore = currency0.balanceOf(address(this));
        uint256 hookBalBefore = currency0.balanceOf(address(hook));
        uint256 mgrBalBefore = currency0.balanceOf(address(manager));

        vm.recordLogs();
        mockManager.resetCounters();
        vm.prank(address(manager));
        (bytes4 sel2, BeforeSwapDelta d2, uint24 fee2) = hook.beforeSwap(
            address(this),
            key,
            sp,
            ""
        );

        // callback returns ZERO_DELTA, fee=0
        assertEq(sel2, BaseHook.beforeSwap.selector);
        assertEq(
            BeforeSwapDelta.unwrap(d2),
            BeforeSwapDelta.unwrap(BeforeSwapDeltaLibrary.ZERO_DELTA)
        );
        assertEq(fee2, 0);

        // pending cleared
        assertEq(hook.getPendingSwapSender(key), address(0));

        // balances after execution: user decreased; hook unchanged; manager increased
        uint256 userBalAfter = currency0.balanceOf(address(this));
        uint256 hookBalAfter = currency0.balanceOf(address(hook));
        uint256 mgrBalAfter = currency0.balanceOf(address(manager));
        assertEq(userBalBefore - userBalAfter, 1000);
        assertEq(hookBalAfter, hookBalBefore);
        assertEq(mgrBalAfter - mgrBalBefore, 1000);

        // at least one position add
        uint256 calls = mockManager.modifyCallCount();
        assertTrue(calls >= 1);
        (
            int24 lastL,
            int24 lastU,
            int256 lastLiq,
            bytes32 lastSalt
        ) = mockManager.getCall(calls - 1);
        assertEq(lastL, -600);
        assertEq(lastU, 600);

        uint160 sqrtL = TickMath.getSqrtPriceAtTick(-600);
        uint160 sqrtU = TickMath.getSqrtPriceAtTick(600);
        uint256 expectedLiq = LiquidityAmounts.getLiquidityForAmount1(
            sqrtL,
            sqrtU,
            1 ether
        );
        assertEq(uint256(lastLiq), expectedLiq);
        assertEq(lastSalt, keccak256(abi.encodePacked(uint16(0), uint8(0))));

        // epoch initialized and event emitted
        assertTrue(hook.getIsEpochInitialized(key, 0));
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 topic = keccak256("LiquidityAllocated(bytes32,uint16)");
        bool found;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length > 0 && logs[i].topics[0] == topic) {
                found = true;
                break;
            }
        }
        assertTrue(found);
    }

    function test_Swap_TransitionToNextEpoch_CleansOld_AppliesNew() public {
        // epoch 0: [-600,600], 1e18; epoch 1: [100,700], 2e18
        InEuint32 memory tl0 = createInEuint32(uint32(int32(-600)), 0, address(this));
        InEuint32 memory tu0 = createInEuint32(uint32(600), 0, address(this));
        InEuint128 memory amt0 = createInEuint128(uint128(1 ether), 0, address(this));
        InEuint32 memory tl1 = createInEuint32(uint32(int32(100)), 0, address(this));
        InEuint32 memory tu1 = createInEuint32(uint32(700), 0, address(this));
        InEuint128 memory amt1 = createInEuint128(uint128(2 ether), 0, address(this));

        uint64 start = uint64(block.timestamp + 10);
        uint16 epochs = 2;
        uint32 epoch0Offset = 51 + 4 * uint32(epochs);
        uint32 dur0 = 1000;
        uint8 npos0 = 1;
        uint32 pos0off = epoch0Offset + 4 + 1 + 4; // dur + count + one pos offset
        bytes memory e0 = bytes.concat(
            abi.encodePacked(uint32(dur0)),
            abi.encodePacked(uint8(npos0)),
            abi.encodePacked(uint32(uint32(pos0off))),
            _encodeEvalFromInEuint32(tl0),
            _encodeEvalFromInEuint32(tu0),
            _encodeEvalFromInEuint128(amt0)
        );

        uint32 epoch1Offset = uint32(epoch0Offset + e0.length);
        uint32 dur1 = 2000;
        uint8 npos1 = 1;
        uint32 pos1off = epoch1Offset + 4 + 1 + 4;
        bytes memory e1 = bytes.concat(
            abi.encodePacked(uint32(dur1)),
            abi.encodePacked(uint8(npos1)),
            abi.encodePacked(uint32(uint32(pos1off))),
            _encodeEvalFromInEuint32(tl1),
            _encodeEvalFromInEuint32(tu1),
            _encodeEvalFromInEuint128(amt1)
        );

        bytes memory params = bytes.concat(
            bytes8(keccak256("PrivateCampaignConfig")),
            abi.encodePacked(uint8(1)),
            abi.encodePacked(uint64(start)),
            abi.encodePacked(uint256(0)),
            abi.encodePacked(uint16(epochs)),
            abi.encodePacked(uint32(epoch0Offset)),
            abi.encodePacked(uint32(epoch1Offset)),
            e0,
            e1
        );

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(currency0)),
            currency1: Currency.wrap(address(licenseErc20)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });

        vm.expectEmit(true, false, false, true, address(hook));
        emit PoolStateInitialized(key.toId());
        hook.initializeState(key, params);

        // verifier VALID
        bytes32 slot = keccak256(abi.encode(uint256(1), uint256(2)));
        vm.store(address(verifier), slot, bytes32(uint256(uint8(Status.VALID))));

        // Epoch 0 execution
        vm.warp(start + 1);
        mockManager.resetCounters();
        currency0.approve(address(hook), type(uint256).max);
        SwapParams memory sp = SwapParams({
            zeroForOne: true,
            amountSpecified: -1000,
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });
        vm.prank(address(manager));
        hook.beforeSwap(address(this), key, sp, "");
        // warp to be sure decryption is ready and re-enter to apply
        vm.warp(start + 30);
        mockManager.resetCounters();
        vm.recordLogs();
        vm.prank(address(manager));
        hook.beforeSwap(address(this), key, sp, "");

        assertTrue(hook.getIsEpochInitialized(key, 0));

        // Move into epoch 1: first call triggers pending and decryption request
        vm.warp(start + dur0 + 10);
        mockManager.resetCounters();
        vm.prank(address(manager));
        hook.beforeSwap(address(this), key, sp, "");

        // Warp to allow decryption to be ready, then apply
        vm.warp(start + dur0 + 40);
        mockManager.resetCounters();
        vm.recordLogs();
        vm.prank(address(manager));
        hook.beforeSwap(address(this), key, sp, "");

        // Expect cleanup of epoch 0 and apply of epoch 1 on this second call
        uint256 calls = mockManager.modifyCallCount();
        assertTrue(calls >= 2);
        (
            int24 lastL,
            int24 lastU,
            int256 lastLiq,
            bytes32 lastSalt
        ) = mockManager.getCall(calls - 1);
        assertEq(lastL, 100);
        assertEq(lastU, 700);
        uint160 sqrtL1 = TickMath.getSqrtPriceAtTick(100);
        uint160 sqrtU1 = TickMath.getSqrtPriceAtTick(700);
        uint256 expected1 = LiquidityAmounts.getLiquidityForAmount1(
            sqrtL1,
            sqrtU1,
            2 ether
        );
        assertEq(uint256(lastLiq), expected1);

        (uint16 numE, uint16 curE) = hook.getPoolState(key);
        assertEq(numE, 2);
        assertEq(curE, 1);
        assertFalse(hook.getIsEpochInitialized(key, 0));
        assertTrue(hook.getIsEpochInitialized(key, 1));

        // Event emitted for epoch 1
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 topic = keccak256("LiquidityAllocated(bytes32,uint16)");
        bool found;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length > 0 && logs[i].topics[0] == topic) {
                found = true;
                break;
            }
        }
        assertTrue(found);
    }

    function test_Swap_EmptyPositionsEpoch_Initializes_NoLiquidityChanges() public {
        // Build a single epoch with zero positions
        uint64 start = uint64(block.timestamp + 10);
        uint16 epochs = 1;
        uint32 epoch0Offset = 51 + 4 * uint32(epochs);
        uint32 dur0 = 1000;
        bytes memory params = bytes.concat(
            bytes8(keccak256("PrivateCampaignConfig")),
            abi.encodePacked(uint8(1)),
            abi.encodePacked(uint64(start)),
            abi.encodePacked(uint256(0)),
            abi.encodePacked(uint16(epochs)),
            abi.encodePacked(uint32(epoch0Offset)),
            abi.encodePacked(uint32(dur0)),
            abi.encodePacked(uint8(0)) // num positions = 0
        );

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(currency0)),
            currency1: Currency.wrap(address(licenseErc20)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });

        vm.expectEmit(true, false, false, true, address(hook));
        emit PoolStateInitialized(key.toId());
        hook.initializeState(key, params);

        // verifier VALID
        bytes32 slot = keccak256(abi.encode(uint256(1), uint256(2)));
        vm.store(address(verifier), slot, bytes32(uint256(uint8(Status.VALID))));

        vm.warp(start + 1);
        mockManager.resetCounters();
        vm.recordLogs();
        SwapParams memory sp = SwapParams({
            zeroForOne: true,
            amountSpecified: -100,
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });
        vm.prank(address(manager));
        (bytes4 sel, BeforeSwapDelta d, uint24 fee) = hook.beforeSwap(
            address(this),
            key,
            sp,
            ""
        );

        assertEq(sel, BaseHook.beforeSwap.selector);
        assertEq(
            BeforeSwapDelta.unwrap(d),
            BeforeSwapDelta.unwrap(BeforeSwapDeltaLibrary.ZERO_DELTA)
        );
        assertEq(fee, 0);
        assertTrue(hook.getIsEpochInitialized(key, 0));
        assertEq(mockManager.modifyCallCount(), 0);

        // Event emitted once
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 topic = keccak256("LiquidityAllocated(bytes32,uint16)");
        bool found;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length > 0 && logs[i].topics[0] == topic) {
                found = true;
                break;
            }
        }
        assertTrue(found);
    }

    function test_InitializeState_WrongCurrencyOrder_Reverts() public {
        // currency1 must be LicenseERC20; using a token with patentId()==0 triggers WrongCurrencyOrder
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(currency0)),
            currency1: Currency.wrap(address(new PatentZeroToken())),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });

        uint64 start = uint64(block.timestamp + 10);
        uint16 epochs = 1;
        uint32 epoch0Offset = 51 + 4 * uint32(epochs);
        bytes memory params = bytes.concat(
            bytes8(keccak256("PrivateCampaignConfig")),
            abi.encodePacked(uint8(1)),
            abi.encodePacked(uint64(start)),
            abi.encodePacked(uint256(0)),
            abi.encodePacked(uint16(epochs)),
            abi.encodePacked(uint32(epoch0Offset)),
            abi.encodePacked(uint32(1000)),
            abi.encodePacked(uint8(0))
        );

        vm.expectRevert(AbstractLicenseHook.WrongCurrencyOrder.selector);
        hook.initializeState(key, params);
    }

    function test_BeforeSwap_RedeemNotAllowed_WhenOneForZero() public {
        // minimal config with one position
        InEuint32 memory tl = createInEuint32(uint32(int32(-10)), 0, address(this));
        InEuint32 memory tu = createInEuint32(uint32(10), 0, address(this));
        InEuint128 memory amt = createInEuint128(uint128(1 ether), 0, address(this));

        uint64 start = uint64(block.timestamp + 10);
        uint16 epochs = 1;
        uint32 epoch0Offset = 51 + 4 * uint32(epochs);
        uint32 posOff = epoch0Offset + 4 + 1 + 4;
        bytes memory params = bytes.concat(
            bytes8(keccak256("PrivateCampaignConfig")),
            abi.encodePacked(uint8(1)),
            abi.encodePacked(uint64(start)),
            abi.encodePacked(uint256(0)),
            abi.encodePacked(uint16(epochs)),
            abi.encodePacked(uint32(epoch0Offset)),
            abi.encodePacked(uint32(1000)),
            abi.encodePacked(uint8(1)),
            abi.encodePacked(uint32(posOff)),
            _encodeEvalFromInEuint32(tl),
            _encodeEvalFromInEuint32(tu),
            _encodeEvalFromInEuint128(amt)
        );

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(currency0)),
            currency1: Currency.wrap(address(licenseErc20)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });
        vm.expectEmit(true, false, false, true, address(hook));
        emit PoolStateInitialized(key.toId());
        hook.initializeState(key, params);

        // VALID verifier; warp into window
        bytes32 slot = keccak256(abi.encode(uint256(1), uint256(2)));
        vm.store(address(verifier), slot, bytes32(uint256(uint8(Status.VALID))));
        vm.warp(start + 1);

        SwapParams memory sp = SwapParams({
            zeroForOne: false,
            amountSpecified: -1,
            sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
        });
        vm.prank(address(manager));
        vm.expectRevert(AbstractLicenseHook.RedeemNotAllowed.selector);
        hook.beforeSwap(address(this), key, sp, "");
    }

    function test_BeforeSwap_ExactOutputNotAllowed_Reverts() public {
        // same config as above
        InEuint32 memory tl = createInEuint32(uint32(int32(-10)), 0, address(this));
        InEuint32 memory tu = createInEuint32(uint32(10), 0, address(this));
        InEuint128 memory amt = createInEuint128(uint128(1 ether), 0, address(this));
        uint64 start = uint64(block.timestamp + 10);
        uint16 epochs = 1;
        uint32 epoch0Offset = 51 + 4 * uint32(epochs);
        uint32 posOff = epoch0Offset + 4 + 1 + 4;
        bytes memory params = bytes.concat(
            bytes8(keccak256("PrivateCampaignConfig")),
            abi.encodePacked(uint8(1)),
            abi.encodePacked(uint64(start)),
            abi.encodePacked(uint256(0)),
            abi.encodePacked(uint16(epochs)),
            abi.encodePacked(uint32(epoch0Offset)),
            abi.encodePacked(uint32(1000)),
            abi.encodePacked(uint8(1)),
            abi.encodePacked(uint32(posOff)),
            _encodeEvalFromInEuint32(tl),
            _encodeEvalFromInEuint32(tu),
            _encodeEvalFromInEuint128(amt)
        );

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(currency0)),
            currency1: Currency.wrap(address(licenseErc20)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });
        vm.expectEmit(true, false, false, true, address(hook));
        emit PoolStateInitialized(key.toId());
        hook.initializeState(key, params);
        bytes32 slot = keccak256(abi.encode(uint256(1), uint256(2)));
        vm.store(address(verifier), slot, bytes32(uint256(uint8(Status.VALID))));
        vm.warp(start + 1);

        SwapParams memory sp = SwapParams({
            zeroForOne: true,
            amountSpecified: 1,
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });
        vm.prank(address(manager));
        vm.expectRevert(PrivateLicenseHook.ExactOutputNotAllowed.selector);
        hook.beforeSwap(address(this), key, sp, "");
    }

    function test_BeforeSwap_CampaignWindow_Reverts() public {
        // empty epoch config is enough to test windows
        uint64 start = uint64(block.timestamp + 1000);
        uint16 epochs = 1;
        uint32 epoch0Offset = 51 + 4 * uint32(epochs);
        uint32 dur = 10;
        bytes memory params = bytes.concat(
            bytes8(keccak256("PrivateCampaignConfig")),
            abi.encodePacked(uint8(1)),
            abi.encodePacked(uint64(start)),
            abi.encodePacked(uint256(0)),
            abi.encodePacked(uint16(epochs)),
            abi.encodePacked(uint32(epoch0Offset)),
            abi.encodePacked(uint32(dur)),
            abi.encodePacked(uint8(0))
        );
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(currency0)),
            currency1: Currency.wrap(address(licenseErc20)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });
        vm.expectEmit(true, false, false, true, address(hook));
        emit PoolStateInitialized(key.toId());
        hook.initializeState(key, params);

        // before start
        vm.warp(start - 1);
        vm.prank(address(manager));
        vm.expectRevert(AbstractLicenseHook.CampaignNotStarted.selector);
        hook.beforeSwap(
            address(this),
            key,
            SwapParams({zeroForOne: true, amountSpecified: -1, sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1}),
            ""
        );

        // after end
        vm.warp(start + dur + 1);
        vm.prank(address(manager));
        vm.expectRevert(AbstractLicenseHook.CampaignEnded.selector);
        hook.beforeSwap(
            address(this),
            key,
            SwapParams({zeroForOne: true, amountSpecified: -1, sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1}),
            ""
        );
    }

    function test_HandleDeltas_NegativeDelta_Settles() public {
        // one-position config
        InEuint32 memory tl = createInEuint32(uint32(int32(-10)), 0, address(this));
        InEuint32 memory tu = createInEuint32(uint32(10), 0, address(this));
        InEuint128 memory amt = createInEuint128(uint128(1 ether), 0, address(this));
        uint64 start = uint64(block.timestamp + 10);
        uint16 epochs = 1;
        uint32 epoch0Offset = 51 + 4 * uint32(epochs);
        uint32 posOff = epoch0Offset + 4 + 1 + 4;
        bytes memory params = bytes.concat(
            bytes8(keccak256("PrivateCampaignConfig")),
            abi.encodePacked(uint8(1)),
            abi.encodePacked(uint64(start)),
            abi.encodePacked(uint256(0)),
            abi.encodePacked(uint16(epochs)),
            abi.encodePacked(uint32(epoch0Offset)),
            abi.encodePacked(uint32(1000)),
            abi.encodePacked(uint8(1)),
            abi.encodePacked(uint32(posOff)),
            _encodeEvalFromInEuint32(tl),
            _encodeEvalFromInEuint32(tu),
            _encodeEvalFromInEuint128(amt)
        );
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(currency0)),
            currency1: Currency.wrap(address(licenseErc20)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });
        vm.expectEmit(true, false, false, true, address(hook));
        emit PoolStateInitialized(key.toId());
        hook.initializeState(key, params);
        bytes32 slot = keccak256(abi.encode(uint256(1), uint256(2)));
        vm.store(address(verifier), slot, bytes32(uint256(uint8(Status.VALID))));
        vm.warp(start + 1);

        // pending path
        vm.prank(address(manager));
        hook.beforeSwap(
            address(this),
            key,
            SwapParams({zeroForOne: true, amountSpecified: -100, sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1}),
            ""
        );

        // user approves hook to pull for pending swap execution
        currency0.approve(address(hook), type(uint256).max);

        // set negative delta and give hook funds + approval to pay
        mockManager.setCurrencyDelta(key.currency0, -5);
        currency0.mint(address(hook), 5);
        vm.prank(address(hook));
        currency0.approve(address(hook), 5);

        // apply path
        vm.warp(start + 40);
        mockManager.resetCounters();
        vm.prank(address(manager));
        hook.beforeSwap(
            address(this),
            key,
            SwapParams({zeroForOne: true, amountSpecified: -100, sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1}),
            ""
        );

        assertTrue(mockManager.syncCalled());
        assertTrue(mockManager.settleCalled());
    }

    function test_HandleDeltas_PositiveDelta_Takes() public {
        InEuint32 memory tl = createInEuint32(uint32(int32(-10)), 0, address(this));
        InEuint32 memory tu = createInEuint32(uint32(10), 0, address(this));
        InEuint128 memory amt = createInEuint128(uint128(1 ether), 0, address(this));
        uint64 start = uint64(block.timestamp + 10);
        uint16 epochs = 1;
        uint32 epoch0Offset = 51 + 4 * uint32(epochs);
        uint32 posOff = epoch0Offset + 4 + 1 + 4;
        bytes memory params = bytes.concat(
            bytes8(keccak256("PrivateCampaignConfig")),
            abi.encodePacked(uint8(1)),
            abi.encodePacked(uint64(start)),
            abi.encodePacked(uint256(0)),
            abi.encodePacked(uint16(epochs)),
            abi.encodePacked(uint32(epoch0Offset)),
            abi.encodePacked(uint32(1000)),
            abi.encodePacked(uint8(1)),
            abi.encodePacked(uint32(posOff)),
            _encodeEvalFromInEuint32(tl),
            _encodeEvalFromInEuint32(tu),
            _encodeEvalFromInEuint128(amt)
        );
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(currency0)),
            currency1: Currency.wrap(address(licenseErc20)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });
        vm.expectEmit(true, false, false, true, address(hook));
        emit PoolStateInitialized(key.toId());
        hook.initializeState(key, params);
        bytes32 slot = keccak256(abi.encode(uint256(1), uint256(2)));
        vm.store(address(verifier), slot, bytes32(uint256(uint8(Status.VALID))));
        vm.warp(start + 1);
        // pending path
        vm.prank(address(manager));
        hook.beforeSwap(
            address(this),
            key,
            SwapParams({zeroForOne: true, amountSpecified: -100, sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1}),
            ""
        );
        // set positive delta
        mockManager.setCurrencyDelta(key.currency0, 7);

        // user approves hook to pull for pending swap execution
        currency0.approve(address(hook), type(uint256).max);
        // apply path
        vm.warp(start + 40);
        mockManager.resetCounters();
        vm.prank(address(manager));
        hook.beforeSwap(
            address(this),
            key,
            SwapParams({zeroForOne: true, amountSpecified: -100, sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1}),
            ""
        );
        assertTrue(hook.getIsEpochInitialized(key, 0));
    }

    // Note: OngoingMaintenance guard is unreachable in current implementation,
    // since pending swaps are executed at the start of beforeSwap, clearing pending state.

    function _buildSimplePrivateConfig(
        uint64 start,
        uint32 dur0,
        uint256 totalTokens,
        uint8 numPositions,
        uint8 secZone,
        uint8 utype32,
        uint8 utype128
    ) internal pure returns (bytes memory params) {
        // Header
        bytes8 sig = bytes8(keccak256("PrivateCampaignConfig"));
        uint8 ver = 1;
        uint16 epochs = 1;

        // Offsets
        uint32 epoch0Offset = uint32(51 + 4 * uint32(epochs)); // HEADER_SIZE(51) + 4*numEpochs
        // Epoch 0 layout:
        // [duration(4)][numPos(1)][posOffsets(4)][positions...]
        bytes memory epoch0;
        if (numPositions == 0) {
            epoch0 = bytes.concat(bytes4(dur0), bytes1(uint8(0)));
        } else {
            uint32 posOffsetsBase = uint32(epoch0Offset + 4 + 1);
            uint32 pos0Offset = posOffsetsBase + 4; // after offsets table

            // Minimal EVALs (sigLen=0) => 36 bytes each, three of them
            bytes memory eval32 = bytes.concat(
                bytes32(uint256(0x1234)),
                bytes1(secZone),
                bytes1(utype32),
                bytes2(uint16(0))
            );
            bytes memory eval128 = bytes.concat(
                bytes32(uint256(0x5678)),
                bytes1(secZone),
                bytes1(utype128),
                bytes2(uint16(0))
            );

            epoch0 = bytes.concat(
                bytes4(dur0),
                bytes1(numPositions),
                bytes4(pos0Offset),
                eval32, // tickLower
                eval32, // tickUpper
                eval128 // amountAllocated
            );
        }

        params = bytes.concat(
            sig,
            abi.encodePacked(uint8(ver)),
            abi.encodePacked(uint64(start)),
            abi.encodePacked(uint256(totalTokens)),
            abi.encodePacked(uint16(epochs)),
            abi.encodePacked(uint32(epoch0Offset)),
            epoch0
        );
    }

    function _encodeEvalFromInEuint32(
        InEuint32 memory x
    ) internal pure returns (bytes memory) {
        return
            bytes.concat(
                bytes32(x.ctHash),
                bytes1(x.securityZone),
                bytes1(x.utype),
                bytes2(uint16(x.signature.length)),
                x.signature
            );
    }

    function _encodeEvalFromInEuint128(
        InEuint128 memory x
    ) internal pure returns (bytes memory) {
        return
            bytes.concat(
                bytes32(x.ctHash),
                bytes1(x.securityZone),
                bytes1(x.utype),
                bytes2(uint16(x.signature.length)),
                x.signature
            );
    }
}
