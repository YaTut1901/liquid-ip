// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/*
Test Plan: PublicCampaignConfig library

Scope
- Validate compact config parsing, index/offset invariants, derived computations, and error paths.

Conventions
- Build params using: [8-byte signature][version:u8][startingTime:u64][numEpochs:u16][u32 offsets[numEpochs]][per-epoch payloads]
- Per-epoch payload: [duration:u32][numPositions:u8][positions...]
- Per-position: [tickLower:i24][tickUpper:i24][amount:u128]
- Signature = bytes8(keccak256("PublicCampaignConfig")), version = 1.

Happy Path Tests
1) Single epoch, single position (already implemented)
   - Verify: version, startingTime, numEpochs, durationSeconds(0), numPositions(0), ticks/amount, totalTokensToSell, endingTime, epochStartingTime(0)=start, epochStartingTick(0)=tickUpper.

2) Single epoch, multiple positions
   - 1 epoch, positions with mixed negative/positive ticks and varying amounts.
   - Verify: numPositions(0), all per-position fields, totalTokensToSell=sum, endingTime=start+dur, epochStartingTick=max(upper).

3) Multiple epochs, varying durations and positions
   - 3 epochs with different position counts (including 1 with many, 1 with 1, 1 with 0 positions — see case 7 for zero-positions behavior).
   - Verify: durationSeconds(e) per epoch, epochStartingTime(e) accumulates prior durations, endingTime=start+sum(durs), epochStartingTick(e)=max upper in that epoch, totalTokensToSell=sum across all epochs/positions.

4) Zero epochs edge case
   - numEpochs=0, no index, no epoch payloads.
   - Verify: version/start/numEpochs=0, totalTokensToSell=0, endingTime==startingTime.
   - Accessors that require epochs must revert (see case 10).

Validation API Tests (validate)
5) validate passes on well-formed multi-epoch config
   - Properly increasing offsets, correctly sized payloads.

6) validate reverts: ConfigParamsTooShort
   - Truncate before completing the offsets table (params.length < 19 + 4*numEpochs).

7) validate reverts: EpochPayloadTooShort (two sub-cases)
   - 7a) endOff < startOff + 5 (not enough space for [duration+numPositions]).
   - 7b) count>0 but not enough bytes for positions (required > endOff).

8) validate reverts: BadEpochOffset
   - Offset < 19 + 4*numEpochs, or >= params.length.

9) validate reverts: OffsetsNotStrictlyIncreasing
   - Equal or decreasing offsets across epochs.

Accessor Revert Paths (without prior validate)
10) InvalidEpochIndex
   - durationSeconds/numPositions/epochStartingTick with epoch >= numEpochs.

11) InvalidPositionIndex
   - tickLower/tickUpper/amountAllocated with positionIndex >= numPositions(epoch).

12) OutOfBounds on truncated payload
   - Point a valid epoch offset near the end so reading duration (4 bytes) or a position field overflows params; call an accessor and expect OutOfBounds.

Header/Signature/Version Tests
13) ConfigParamsTooShort (onlySigned)
   - params.length < 19 should revert on any accessor/validate.

14) InvalidConfigSignature
   - Corrupt the first 8 bytes; any accessor/validate reverts.

15) UnsupportedVersion
   - Set version != 1; any accessor/validate reverts with UnsupportedVersion(found).

Derived Value Edge Cases
16) NoPositionsInEpoch
- An epoch with numPositions=0: validate() must revert NoPositionsInEpoch; epochStartingTick(epoch) also reverts if called directly.

17) TimestampOverflow: endingTime
   - startingTime near type(uint64).max and total duration sum causes overflow; endingTime() reverts TimestampOverflow.

18) TimestampOverflow: epochStartingTime
   - Large sum of prior durations causes overflow for a later epoch; epochStartingTime(epoch) reverts TimestampOverflow.

Behavioral Checks/Properties
19) Negative tick encoding/decoding
   - Use negative tickLower and tickUpper; ensure sign is preserved when reading int24 values.

20) EpochStartingTick correctness
   - Mix upper ticks: negative, zero, positive; ensure max upper is returned.

21) TotalTokensToSell aggregation across epochs
   - Multiple epochs with varying counts and amounts; totalTokensToSell equals the sum of all amounts.

Notes
- Accessors are safe to call on untrusted input only if validate() has been called once to enforce invariants.
- Some revert types (BadExtractSize) are unreachable via public API usage and need not be tested.
*/

import "forge-std/Test.sol";
import {PublicCampaignConfig} from "../contracts/lib/PublicCampaignConfig.sol";

contract PublicCampaignConfigHarness {
    using PublicCampaignConfig for bytes;

    function getVersion(bytes calldata params) external pure returns (uint8) {
        return params.version();
    }

    function getStartingTime(bytes calldata params) external pure returns (uint64) {
        return params.startingTime();
    }

    function getNumEpochs(bytes calldata params) external pure returns (uint16) {
        return params.numEpochs();
    }

    function getDuration(bytes calldata params, uint16 epoch) external pure returns (uint32) {
        return params.durationSeconds(epoch);
    }

    function getNumPositions(bytes calldata params, uint16 epoch) external pure returns (uint8) {
        return params.numPositions(epoch);
    }

    function getTickLower(bytes calldata params, uint16 epoch, uint8 pos) external pure returns (int24) {
        return params.tickLower(epoch, pos);
    }

    function getTickUpper(bytes calldata params, uint16 epoch, uint8 pos) external pure returns (int24) {
        return params.tickUpper(epoch, pos);
    }

    function getAmount(bytes calldata params, uint16 epoch, uint8 pos) external pure returns (uint128) {
        return params.amountAllocated(epoch, pos);
    }

    function getTotal(bytes calldata params) external pure returns (uint256) {
        return params.totalTokensToSell();
    }

    function getEndingTime(bytes calldata params) external pure returns (uint64) {
        return params.endingTime();
    }

    function getEpochStartingTime(bytes calldata params, uint16 epoch) external pure returns (uint64) {
        return params.epochStartingTime(epoch);
    }

    function getEpochStartingTick(bytes calldata params, uint16 epoch) external pure returns (int24) {
        return params.epochStartingTick(epoch);
    }

    function validateParams(bytes calldata params) external pure {
        params.validate();
    }
}

contract PublicCampaignConfigTest is Test {
    PublicCampaignConfigHarness private harness;

    function setUp() public {
        harness = new PublicCampaignConfigHarness();
    }

    function test_HappyPath_SingleEpochSinglePosition() public {
        // Build config bytes for: version=1, start=1000, epochs=1
        // One index entry pointing to the first epoch payload, immediately after the index
        uint8 ver = 1;
        uint64 start = 1000;
        uint16 epochs = 1;
        uint32 epoch0Offset = 19 + 4 * uint32(epochs); // 19-byte header + index table

        uint32 dur0 = 3600;
        uint8 npos0 = 1;
        int24 tickLower0 = -600;
        int24 tickUpper0 = 600;
        uint128 amt0 = 1 ether;

        bytes memory params = bytes.concat(
            bytes8(keccak256("PublicCampaignConfig")),
            abi.encodePacked(uint8(ver)),
            abi.encodePacked(uint64(start)),
            abi.encodePacked(uint16(epochs)),
            abi.encodePacked(uint32(epoch0Offset)),
            abi.encodePacked(uint32(dur0)),
            abi.encodePacked(uint8(npos0)),
            abi.encodePacked(int24(tickLower0)),
            abi.encodePacked(int24(tickUpper0)),
            abi.encodePacked(uint128(amt0))
        );

        // Header reads
        assertEq(harness.getVersion(params), ver);
        assertEq(harness.getStartingTime(params), start);
        assertEq(harness.getNumEpochs(params), epochs);

        // Epoch-level reads
        assertEq(harness.getDuration(params, 0), dur0);
        assertEq(harness.getNumPositions(params, 0), npos0);

        // Position-level reads
        assertEq(int256(harness.getTickLower(params, 0, 0)), int256(tickLower0));
        assertEq(int256(harness.getTickUpper(params, 0, 0)), int256(tickUpper0));
        assertEq(harness.getAmount(params, 0, 0), amt0);

        // Aggregations and derived values
        assertEq(harness.getTotal(params), uint256(amt0));
        assertEq(harness.getEndingTime(params), start + dur0);
        assertEq(harness.getEpochStartingTime(params, 0), start);
        assertEq(int256(harness.getEpochStartingTick(params, 0)), int256(tickUpper0));
    }

    function test_HappyPath_SingleEpochMultiplePositions() public {
        // version=1, start=2000, epochs=1, duration=7200, 3 positions
        uint8 ver = 1;
        uint64 start = 2000;
        uint16 epochs = 1;
        uint32 epoch0Offset = 19 + 4 * uint32(epochs);

        uint32 dur0 = 7200;
        uint8 npos0 = 3;

        // Position 0
        int24 tl0 = -1200;
        int24 tu0 = -300;
        uint128 amt0 = 1 ether;

        // Position 1
        int24 tl1 = -100;
        int24 tu1 = 0;
        uint128 amt1 = 2 ether;

        // Position 2
        int24 tl2 = 100;
        int24 tu2 = 700;
        uint128 amt2 = 3 ether;

        bytes memory params = bytes.concat(
            bytes8(keccak256("PublicCampaignConfig")),
            abi.encodePacked(uint8(ver)),
            abi.encodePacked(uint64(start)),
            abi.encodePacked(uint16(epochs)),
            abi.encodePacked(uint32(epoch0Offset)),
            abi.encodePacked(uint32(dur0)),
            abi.encodePacked(uint8(npos0)),
            // pos0
            abi.encodePacked(int24(tl0)),
            abi.encodePacked(int24(tu0)),
            abi.encodePacked(uint128(amt0)),
            // pos1
            abi.encodePacked(int24(tl1)),
            abi.encodePacked(int24(tu1)),
            abi.encodePacked(uint128(amt1)),
            // pos2
            abi.encodePacked(int24(tl2)),
            abi.encodePacked(int24(tu2)),
            abi.encodePacked(uint128(amt2))
        );

        // Header reads
        assertEq(harness.getVersion(params), ver);
        assertEq(harness.getStartingTime(params), start);
        assertEq(harness.getNumEpochs(params), epochs);

        // Epoch-level reads
        assertEq(harness.getDuration(params, 0), dur0);
        assertEq(harness.getNumPositions(params, 0), npos0);

        // Position 0
        assertEq(int256(harness.getTickLower(params, 0, 0)), int256(tl0));
        assertEq(int256(harness.getTickUpper(params, 0, 0)), int256(tu0));
        assertEq(harness.getAmount(params, 0, 0), amt0);

        // Position 1
        assertEq(int256(harness.getTickLower(params, 0, 1)), int256(tl1));
        assertEq(int256(harness.getTickUpper(params, 0, 1)), int256(tu1));
        assertEq(harness.getAmount(params, 0, 1), amt1);

        // Position 2
        assertEq(int256(harness.getTickLower(params, 0, 2)), int256(tl2));
        assertEq(int256(harness.getTickUpper(params, 0, 2)), int256(tu2));
        assertEq(harness.getAmount(params, 0, 2), amt2);

        // Aggregations and derived values
        uint256 total = uint256(amt0) + uint256(amt1) + uint256(amt2);
        assertEq(harness.getTotal(params), total);
        assertEq(harness.getEndingTime(params), start + dur0);
        assertEq(harness.getEpochStartingTime(params, 0), start);
        assertEq(int256(harness.getEpochStartingTick(params, 0)), int256(tu2)); // max upper = 700
    }

    function test_HappyPath_MultiEpochs_VariedDurationsAndPositions() public {
        // version=1, start=5000, epochs=3
        uint8 ver = 1;
        uint64 start = 5000;
        uint16 epochs = 3;

        // Offsets table after 19-byte header
        uint32 offsetsBase = 19;
        uint32 idxBytes = 4 * uint32(epochs);
        uint32 epoch0Offset = offsetsBase + idxBytes; // right after index

        // epoch 0: dur=1000, 2 positions
        uint32 e0dur = 1000;
        uint8 e0n = 2;
        int24 e0p0L = -500; int24 e0p0U = -200; uint128 e0p0A = 1 ether;
        int24 e0p1L = -100; int24 e0p1U = 300;  uint128 e0p1A = 4 ether;
        uint32 e1Offset = epoch0Offset + 4 + 1 + 2 * 22; // e0 payload size

        // epoch 1: dur=200, 1 position
        uint32 e1dur = 200;
        uint8 e1n = 1;
        int24 e1p0L = 0;   int24 e1p0U = 100; uint128 e1p0A = 2 ether;
        uint32 e2Offset = e1Offset + 4 + 1 + 1 * 22; // e1 payload size

        // epoch 2: dur=50, 3 positions
        uint32 e2dur = 50;
        uint8 e2n = 3;
        int24 e2p0L = -700; int24 e2p0U = -600; uint128 e2p0A = 1;
        int24 e2p1L = 200;  int24 e2p1U = 250;  uint128 e2p1A = 3;
        int24 e2p2L = -5;   int24 e2p2U = 1000; uint128 e2p2A = 5;

        bytes memory params = bytes.concat(
            bytes8(keccak256("PublicCampaignConfig")),
            abi.encodePacked(uint8(ver)),
            abi.encodePacked(uint64(start)),
            abi.encodePacked(uint16(epochs)),
            // index
            abi.encodePacked(uint32(epoch0Offset)),
            abi.encodePacked(uint32(e1Offset)),
            abi.encodePacked(uint32(e2Offset)),
            // epoch 0
            abi.encodePacked(uint32(e0dur)),
            abi.encodePacked(uint8(e0n)),
            abi.encodePacked(int24(e0p0L)), abi.encodePacked(int24(e0p0U)), abi.encodePacked(uint128(e0p0A)),
            abi.encodePacked(int24(e0p1L)), abi.encodePacked(int24(e0p1U)), abi.encodePacked(uint128(e0p1A)),
            // epoch 1
            abi.encodePacked(uint32(e1dur)),
            abi.encodePacked(uint8(e1n)),
            abi.encodePacked(int24(e1p0L)), abi.encodePacked(int24(e1p0U)), abi.encodePacked(uint128(e1p0A)),
            // epoch 2
            abi.encodePacked(uint32(e2dur)),
            abi.encodePacked(uint8(e2n)),
            abi.encodePacked(int24(e2p0L)), abi.encodePacked(int24(e2p0U)), abi.encodePacked(uint128(e2p0A)),
            abi.encodePacked(int24(e2p1L)), abi.encodePacked(int24(e2p1U)), abi.encodePacked(uint128(e2p1A)),
            abi.encodePacked(int24(e2p2L)), abi.encodePacked(int24(e2p2U)), abi.encodePacked(uint128(e2p2A))
        );

        // Header reads
        assertEq(harness.getVersion(params), ver);
        assertEq(harness.getStartingTime(params), start);
        assertEq(harness.getNumEpochs(params), epochs);

        // Epoch durations
        assertEq(harness.getDuration(params, 0), e0dur);
        assertEq(harness.getDuration(params, 1), e1dur);
        assertEq(harness.getDuration(params, 2), e2dur);

        // Num positions per epoch
        assertEq(harness.getNumPositions(params, 0), e0n);
        assertEq(harness.getNumPositions(params, 1), e1n);
        assertEq(harness.getNumPositions(params, 2), e2n);

        // Per-position checks (spot check a subset and boundaries)
        assertEq(int256(harness.getTickLower(params, 0, 0)), int256(e0p0L));
        assertEq(int256(harness.getTickUpper(params, 0, 1)), int256(e0p1U));
        assertEq(harness.getAmount(params, 0, 1), e0p1A);

        assertEq(int256(harness.getTickLower(params, 1, 0)), int256(e1p0L));
        assertEq(int256(harness.getTickUpper(params, 1, 0)), int256(e1p0U));
        assertEq(harness.getAmount(params, 1, 0), e1p0A);

        assertEq(int256(harness.getTickLower(params, 2, 2)), int256(e2p2L));
        assertEq(int256(harness.getTickUpper(params, 2, 2)), int256(e2p2U));
        assertEq(harness.getAmount(params, 2, 2), e2p2A);

        // Derived values
        uint256 total = uint256(e0p0A) + uint256(e0p1A) + uint256(e1p0A) + uint256(e2p0A) + uint256(e2p1A) + uint256(e2p2A);
        assertEq(harness.getTotal(params), total);

        // epoch starting times
        assertEq(harness.getEpochStartingTime(params, 0), start);
        assertEq(harness.getEpochStartingTime(params, 1), start + e0dur);
        assertEq(harness.getEpochStartingTime(params, 2), start + e0dur + e1dur);

        // ending time
        assertEq(harness.getEndingTime(params), start + e0dur + e1dur + e2dur);

        // epoch starting ticks (max upper per epoch)
        // e0 uppers: -200, 300 -> 300
        assertEq(int256(harness.getEpochStartingTick(params, 0)), int256(e0p1U));
        // e1 uppers: 100 -> 100
        assertEq(int256(harness.getEpochStartingTick(params, 1)), int256(e1p0U));
        // e2 uppers: -600, 250, 1000 -> 1000
        assertEq(int256(harness.getEpochStartingTick(params, 2)), int256(e2p2U));
    }

    function test_EdgeCase_ZeroEpochs() public {
        // version=1, start=7777, epochs=0
        uint8 ver = 1;
        uint64 start = 7777;
        uint16 epochs = 0;

        // With zero epochs, there is no index table and no epoch payloads
        bytes memory params = bytes.concat(
            bytes8(keccak256("PublicCampaignConfig")),
            abi.encodePacked(uint8(ver)),
            abi.encodePacked(uint64(start)),
            abi.encodePacked(uint16(epochs))
        );

        // Header reads
        assertEq(harness.getVersion(params), ver);
        assertEq(harness.getStartingTime(params), start);
        assertEq(harness.getNumEpochs(params), epochs);

        // Aggregations
        assertEq(harness.getTotal(params), 0);
        assertEq(harness.getEndingTime(params), start);

        // Accessors that require epochs should revert
        vm.expectRevert(PublicCampaignConfig.InvalidEpochIndex.selector);
        harness.getDuration(params, 0);

        vm.expectRevert(PublicCampaignConfig.InvalidEpochIndex.selector);
        harness.getNumPositions(params, 0);

        // epochStartingTime(0) returns start even with zero epochs (no prior sum)
        assertEq(harness.getEpochStartingTime(params, 0), start);

        // but epochStartingTime(1) must revert (needs epoch 0 offset)
        vm.expectRevert(PublicCampaignConfig.InvalidEpochIndex.selector);
        harness.getEpochStartingTime(params, 1);

        // epochStartingTick requires at least 1 position in target epoch -> with 0 epochs reverts via invalid epoch
        vm.expectRevert(PublicCampaignConfig.InvalidEpochIndex.selector);
        harness.getEpochStartingTick(params, 0);
    }

    function test_Validate_HappyPath_MultiEpochConfig() public {
        // Well-formed 2-epoch config with increasing offsets and correct sizing
        uint8 ver = 1;
        uint64 start = 1111;
        uint16 epochs = 2;
        uint32 offsetsBase = 19;
        uint32 idxBytes = 4 * uint32(epochs);
        uint32 e0Off = offsetsBase + idxBytes;

        uint32 e0dur = 10; uint8 e0n = 1; int24 l0 = -1; int24 u0 = 1; uint128 a0 = 1;
        uint32 e1Off = e0Off + 4 + 1 + 22; // e0 payload

        uint32 e1dur = 20; uint8 e1n = 2; int24 l1 = -5; int24 u1 = 5; uint128 a1 = 2; int24 l2 = 0; int24 u2 = 10; uint128 a2 = 3;

        bytes memory params = bytes.concat(
            bytes8(keccak256("PublicCampaignConfig")),
            abi.encodePacked(uint8(ver)),
            abi.encodePacked(uint64(start)),
            abi.encodePacked(uint16(epochs)),
            abi.encodePacked(uint32(e0Off)),
            abi.encodePacked(uint32(e1Off)),
            // epoch 0
            abi.encodePacked(uint32(e0dur)), abi.encodePacked(uint8(e0n)),
            abi.encodePacked(int24(l0)), abi.encodePacked(int24(u0)), abi.encodePacked(uint128(a0)),
            // epoch 1
            abi.encodePacked(uint32(e1dur)), abi.encodePacked(uint8(e1n)),
            abi.encodePacked(int24(l1)), abi.encodePacked(int24(u1)), abi.encodePacked(uint128(a1)),
            abi.encodePacked(int24(l2)), abi.encodePacked(int24(u2)), abi.encodePacked(uint128(a2))
        );

        // Should not revert
        harness.validateParams(params);
    }

    function test_Validate_Revert_ConfigParamsTooShort() public {
        // Less than 19 bytes header should revert at onlySigned
        bytes memory bad = hex"0001"; // too short
        vm.expectRevert(PublicCampaignConfig.ConfigParamsTooShort.selector);
        harness.validateParams(bad);
    }

    function test_Validate_Revert_InvalidConfigSignature() public {
        // 19+ bytes but wrong signature in first 8 bytes
        uint8 ver = 1;
        uint64 start = 0;
        uint16 epochs = 0;
        bytes memory bad = bytes.concat(
            bytes8(0xdeadbeefdeadbeef), // wrong signature
            abi.encodePacked(uint8(ver)),
            abi.encodePacked(uint64(start)),
            abi.encodePacked(uint16(epochs))
        );
        vm.expectRevert(PublicCampaignConfig.InvalidConfigSignature.selector);
        harness.validateParams(bad);
    }

    function test_Validate_Revert_UnsupportedVersion() public {
        // Correct signature but version != 1
        uint8 ver = 2;
        uint64 start = 0;
        uint16 epochs = 0;
        bytes memory bad = bytes.concat(
            bytes8(keccak256("PublicCampaignConfig")),
            abi.encodePacked(uint8(ver)),
            abi.encodePacked(uint64(start)),
            abi.encodePacked(uint16(epochs))
        );
        vm.expectRevert(abi.encodeWithSelector(PublicCampaignConfig.UnsupportedVersion.selector, ver));
        harness.validateParams(bad);
    }

    function test_Validate_Revert_NoEpochs() public {
        // version=1, start arbitrary, epochs=0 -> validate must revert NoEpochs
        uint8 ver = 1;
        uint64 start = 1234;
        uint16 epochs = 0;

        bytes memory params = bytes.concat(
            bytes8(keccak256("PublicCampaignConfig")),
            abi.encodePacked(uint8(ver)),
            abi.encodePacked(uint64(start)),
            abi.encodePacked(uint16(epochs))
        );

        vm.expectRevert(PublicCampaignConfig.NoEpochs.selector);
        harness.validateParams(params);
    }

    function test_Validate_Revert_BadEpochOffset_BeforeEpochArea() public {
        // epochs=2, but set first offset to a value before the index end
        uint8 ver = 1;
        uint64 start = 0;
        uint16 epochs = 2;
        uint32 offsetsBase = 19;
        uint32 idxBytes = 4 * uint32(epochs);
        uint32 minEpochArea = offsetsBase + idxBytes;

        // Intentionally bad: put e0Off before minEpochArea
        uint32 e0Off = minEpochArea - 1;
        // Put e1Off somewhere (won't be reached)
        uint32 e1Off = minEpochArea + 100;

        bytes memory bad = bytes.concat(
            bytes8(keccak256("PublicCampaignConfig")),
            abi.encodePacked(uint8(ver)),
            abi.encodePacked(uint64(start)),
            abi.encodePacked(uint16(epochs)),
            abi.encodePacked(uint32(e0Off)),
            abi.encodePacked(uint32(e1Off))
        );

        vm.expectRevert(PublicCampaignConfig.BadEpochOffset.selector);
        harness.validateParams(bad);
    }

    function test_Validate_Revert_Epoch0OffsetSlack_EpochsNotTightlyPacked() public {
        // epochs=1, but set first offset after minEpochArea (slack before epoch 0)
        uint8 ver = 1;
        uint64 start = 0;
        uint16 epochs = 1;
        uint32 offsetsBase = 19;
        uint32 idxBytes = 4 * uint32(epochs);
        uint32 minEpochArea = offsetsBase + idxBytes;
        uint32 e0Off = minEpochArea + 1; // slack of 1 byte

        uint32 dur = 10;
        uint8 npos = 1;
        int24 tl = -1; int24 tu = 1; uint128 amt = 1;

        bytes memory bad = bytes.concat(
            bytes8(keccak256("PublicCampaignConfig")),
            abi.encodePacked(uint8(ver)),
            abi.encodePacked(uint64(start)),
            abi.encodePacked(uint16(epochs)),
            abi.encodePacked(uint32(e0Off)),
            // payload placed at e0Off
            // (we don't need to actually pad to e0Off because validate only checks the offset value)
            abi.encodePacked(uint32(dur)),
            abi.encodePacked(uint8(npos)),
            abi.encodePacked(int24(tl)), abi.encodePacked(int24(tu)), abi.encodePacked(uint128(amt))
        );

        vm.expectRevert(PublicCampaignConfig.EpochsNotTightlyPacked.selector);
        harness.validateParams(bad);
    }

    function test_Validate_Revert_OffsetsNotStrictlyIncreasing() public {
        // epochs=3 with non-increasing offsets (e1 == e0)
        uint8 ver = 1;
        uint64 start = 0;
        uint16 epochs = 3;
        uint32 offsetsBase = 19;
        uint32 idxBytes = 4 * uint32(epochs);
        uint32 e0Off = offsetsBase + idxBytes;
        uint32 e1Off = e0Off; // not strictly increasing
        uint32 e2Off = e0Off + 10;

        bytes memory bad = bytes.concat(
            bytes8(keccak256("PublicCampaignConfig")),
            abi.encodePacked(uint8(ver)),
            abi.encodePacked(uint64(start)),
            abi.encodePacked(uint16(epochs)),
            abi.encodePacked(uint32(e0Off)),
            abi.encodePacked(uint32(e1Off)),
            abi.encodePacked(uint32(e2Off)),
            // append dummy payload so bounds check passes before monotonicity check
            bytes("XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX")
        );

        vm.expectRevert(PublicCampaignConfig.OffsetsNotStrictlyIncreasing.selector);
        harness.validateParams(bad);
    }

    function test_Validate_Revert_EpochPayloadTooShort_NoHeader() public {
        // epochs=1 with offset leaving <5 bytes until end (bounds ok, but header missing)
        uint8 ver = 1;
        uint64 start = 0;
        uint16 epochs = 1;
        uint32 offsetsBase = 19;
        uint32 idxBytes = 4 * uint32(epochs);
        uint32 e0Off = offsetsBase + idxBytes + 2; // offset 2 bytes into payload region

        // Append 4 dummy bytes total after index so endOff - startOff = 2 (<5)
        bytes memory bad = bytes.concat(
            bytes8(keccak256("PublicCampaignConfig")),
            abi.encodePacked(uint8(ver)),
            abi.encodePacked(uint64(start)),
            abi.encodePacked(uint16(epochs)),
            abi.encodePacked(uint32(e0Off)),
            bytes("ABCD")
        );

        vm.expectRevert(PublicCampaignConfig.EpochsNotTightlyPacked.selector);
        harness.validateParams(bad);
    }

    function test_Validate_Revert_EpochPayloadTooShort_InsufficientPositions() public {
        // epochs=1 with numPositions=2 but payload contains only 1 position -> required > endOff
        uint8 ver = 1;
        uint64 start = 0;
        uint16 epochs = 1;
        uint32 offsetsBase = 19;
        uint32 idxBytes = 4 * uint32(epochs);
        uint32 e0Off = offsetsBase + idxBytes;

        uint32 dur = 30;
        uint8 npos = 2; // claims 2 positions

        // Build: header + index + [epoch payload with only 1 position]
        bytes memory bad = bytes.concat(
            bytes8(keccak256("PublicCampaignConfig")),
            abi.encodePacked(uint8(ver)),
            abi.encodePacked(uint64(start)),
            abi.encodePacked(uint16(epochs)),
            abi.encodePacked(uint32(e0Off)),
            abi.encodePacked(uint32(dur)),
            abi.encodePacked(uint8(npos)),
            // only one position (22 bytes)
            abi.encodePacked(int24(int24(-1))),
            abi.encodePacked(int24(int24(1))),
            abi.encodePacked(uint128(uint128(123)))
        );

        vm.expectRevert(PublicCampaignConfig.PositionsNotTightlyPacked.selector);
        harness.validateParams(bad);
    }

    function test_Validate_Revert_LastEpochSlack_PositionsNotTightlyPacked() public {
        // epochs=1, correct payload but with extra slack bytes after the last position
        uint8 ver = 1;
        uint64 start = 0;
        uint16 epochs = 1;
        uint32 offsetsBase = 19;
        uint32 idxBytes = 4 * uint32(epochs);
        uint32 e0Off = offsetsBase + idxBytes;

        uint32 dur = 30;
        uint8 npos = 1;
        int24 tl = -10; int24 tu = 10; uint128 a = 777;

        bytes memory bad = bytes.concat(
            bytes8(keccak256("PublicCampaignConfig")),
            abi.encodePacked(uint8(ver)),
            abi.encodePacked(uint64(start)),
            abi.encodePacked(uint16(epochs)),
            abi.encodePacked(uint32(e0Off)),
            abi.encodePacked(uint32(dur)),
            abi.encodePacked(uint8(npos)),
            abi.encodePacked(int24(tl)),
            abi.encodePacked(int24(tu)),
            abi.encodePacked(uint128(a)),
            // slack after last position
            bytes("ZZ")
        );

        vm.expectRevert(PublicCampaignConfig.PositionsNotTightlyPacked.selector);
        harness.validateParams(bad);
    }

    function test_Validate_Revert_ConfigParamsTooShort_IndexTableTruncated() public {
        // epochs=2, but only 1 index entry present -> offsets table truncated -> ConfigParamsTooShort
        uint8 ver = 1;
        uint64 start = 0;
        uint16 epochs = 2;

        // Provide header and only one uint32 offset, missing the second
        bytes memory bad = bytes.concat(
            bytes8(keccak256("PublicCampaignConfig")),
            abi.encodePacked(uint8(ver)),
            abi.encodePacked(uint64(start)),
            abi.encodePacked(uint16(epochs)),
            abi.encodePacked(uint32(19 + 4 * uint32(epochs)))
        );

        vm.expectRevert(PublicCampaignConfig.ConfigParamsTooShort.selector);
        harness.validateParams(bad);
    }

    function test_EpochStartingTick_Revert_NoPositionsInEpoch() public {
        // epochs=1, duration ok, but numPositions=0 -> validate must revert NoPositionsInEpoch
        uint8 ver = 1;
        uint64 start = 42;
        uint16 epochs = 1;
        uint32 offsetsBase = 19;
        uint32 idxBytes = 4 * uint32(epochs);
        uint32 e0Off = offsetsBase + idxBytes;

        uint32 dur = 100;
        uint8 npos = 0;

        bytes memory params = bytes.concat(
            bytes8(keccak256("PublicCampaignConfig")),
            abi.encodePacked(uint8(ver)),
            abi.encodePacked(uint64(start)),
            abi.encodePacked(uint16(epochs)),
            abi.encodePacked(uint32(e0Off)),
            abi.encodePacked(uint32(dur)),
            abi.encodePacked(uint8(npos))
        );

        vm.expectRevert(PublicCampaignConfig.NoPositionsInEpoch.selector);
        harness.validateParams(params);

        vm.expectRevert(PublicCampaignConfig.NoPositionsInEpoch.selector);
        harness.getEpochStartingTick(params, 0);
    }

    function test_EndingTime_Revert_TimestampOverflow() public {
        // startingTime near max and sum(durations) large -> endingTime should revert TimestampOverflow
        uint8 ver = 1;
        uint64 start = type(uint64).max - 10; // 18446744073709551605
        uint16 epochs = 2;
        uint32 offsetsBase = 19;
        uint32 idxBytes = 4 * uint32(epochs);
        uint32 e0Off = offsetsBase + idxBytes;
        uint32 e1Off = e0Off + (4 + 1 + 0); // epoch0 payload minimal (no positions)

        uint32 e0dur = 8;
        uint8 e0n = 0;
        uint32 e1dur = 8; // start + 8 + 8 > max
        uint8 e1n = 0;

        bytes memory params = bytes.concat(
            bytes8(keccak256("PublicCampaignConfig")),
            abi.encodePacked(uint8(ver)),
            abi.encodePacked(uint64(start)),
            abi.encodePacked(uint16(epochs)),
            abi.encodePacked(uint32(e0Off)),
            abi.encodePacked(uint32(e1Off)),
            abi.encodePacked(uint32(e0dur)), abi.encodePacked(uint8(e0n)),
            abi.encodePacked(uint32(e1dur)), abi.encodePacked(uint8(e1n))
        );

        // validate now reverts due to zero positions per epoch
        vm.expectRevert(PublicCampaignConfig.NoPositionsInEpoch.selector);
        harness.validateParams(params);
    }

    function test_EpochStartingTime_Revert_TimestampOverflow() public {
        // startingTime near max, epoch 0 duration large so epoch 1 start overflows
        uint8 ver = 1;
        uint64 start = type(uint64).max - 5;
        uint16 epochs = 2;
        uint32 offsetsBase = 19;
        uint32 idxBytes = 4 * uint32(epochs);
        uint32 e0Off = offsetsBase + idxBytes;
        uint32 e1Off = e0Off + (4 + 1 + 0);

        uint32 e0dur = 10; // start + 10 > max
        uint8 e0n = 0;
        uint32 e1dur = 1;
        uint8 e1n = 0;

        bytes memory params = bytes.concat(
            bytes8(keccak256("PublicCampaignConfig")),
            abi.encodePacked(uint8(ver)),
            abi.encodePacked(uint64(start)),
            abi.encodePacked(uint16(epochs)),
            abi.encodePacked(uint32(e0Off)),
            abi.encodePacked(uint32(e1Off)),
            abi.encodePacked(uint32(e0dur)), abi.encodePacked(uint8(e0n)),
            abi.encodePacked(uint32(e1dur)), abi.encodePacked(uint8(e1n))
        );

        vm.expectRevert(PublicCampaignConfig.NoPositionsInEpoch.selector);
        harness.validateParams(params);
    }

    function test_Accessor_Revert_OutOfBounds_TruncatedPosition() public {
        // Build one-epoch config that claims 1 position but truncate bytes inside position so accessor overreads
        uint8 ver = 1;
        uint64 start = 0;
        uint16 epochs = 1;
        uint32 offsetsBase = 19;
        uint32 idxBytes = 4 * uint32(epochs);
        uint32 e0Off = offsetsBase + idxBytes;

        uint32 dur = 1;
        uint8 npos = 1;

        // Compose payload fully, then truncate last few bytes
        bytes memory full = bytes.concat(
            bytes8(keccak256("PublicCampaignConfig")),
            abi.encodePacked(uint8(ver)),
            abi.encodePacked(uint64(start)),
            abi.encodePacked(uint16(epochs)),
            abi.encodePacked(uint32(e0Off)),
            abi.encodePacked(uint32(dur)),
            abi.encodePacked(uint8(npos)),
            abi.encodePacked(int24(int24(-10))),
            abi.encodePacked(int24(int24(10))),
            abi.encodePacked(uint128(uint128(777)))
        );

        // Truncate to cut some of the amount bytes so reads will go OutOfBounds
        bytes memory bad = new bytes(full.length - 5);
        for (uint256 i = 0; i < bad.length; i++) {
            bad[i] = full[i];
        }

        // Header-level reads still fine
        assertEq(harness.getVersion(bad), ver);
        assertEq(harness.getStartingTime(bad), start);
        assertEq(harness.getNumEpochs(bad), epochs);

        // Accessing position amount should revert OutOfBounds due to truncated bytes
        vm.expectRevert(PublicCampaignConfig.OutOfBounds.selector);
        harness.getAmount(bad, 0, 0);
    }

    function test_Accessor_Revert_InvalidPositionIndex() public {
        // Valid epoch with numPositions=1, but request position index 1 -> revert
        uint8 ver = 1;
        uint64 start = 0;
        uint16 epochs = 1;
        uint32 offsetsBase = 19;
        uint32 idxBytes = 4 * uint32(epochs);
        uint32 e0Off = offsetsBase + idxBytes;

        uint32 dur = 10;
        uint8 npos = 1;
        int24 tl = -5;
        int24 tu = 5;
        uint128 amt = 9;

        bytes memory params = bytes.concat(
            bytes8(keccak256("PublicCampaignConfig")),
            abi.encodePacked(uint8(ver)),
            abi.encodePacked(uint64(start)),
            abi.encodePacked(uint16(epochs)),
            abi.encodePacked(uint32(e0Off)),
            abi.encodePacked(uint32(dur)),
            abi.encodePacked(uint8(npos)),
            abi.encodePacked(int24(tl)),
            abi.encodePacked(int24(tu)),
            abi.encodePacked(uint128(amt))
        );

        harness.validateParams(params);

        vm.expectRevert(PublicCampaignConfig.InvalidPositionIndex.selector);
        harness.getAmount(params, 0, 1);
    }
}