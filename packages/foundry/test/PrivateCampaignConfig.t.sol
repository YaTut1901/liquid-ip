// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/*
Test Plan: PrivateCampaignConfig library

Scope
- Validate compact config parsing with encrypted EVAL fields, index/offset invariants, derived computations, and error paths.

Conventions
- Build params using: [8-byte signature][version:u8][startingTime:u64][totalTokensToSell:u256][numEpochs:u16][u32 epochOffsets[numEpochs]][per-epoch payloads]
- Per-epoch payload: [duration:u32][numPositions:u8][u32 posOffsets[numPositions]][positions...]
- Per-position payload: [tickLower:EVAL(InEuint32)][tickUpper:EVAL(InEuint32)][amountAllocated:EVAL(InEuint128)]
- EVAL layout: [ctHash:u256][securityZone:u8][utype:u8][sigLen:u16][signature:bytes]
- Signature = bytes8(keccak256("PrivateCampaignConfig")), version = 1.
- All multi-byte integers use big-endian (network byte order). Offsets are absolute from start of params.

Happy Path Tests
1) Single epoch, single position (minimal EVAL signatures)
   - Verify: version, startingTime, totalTokensToSell (from header), numEpochs, per-epoch duration, numPositions, EVAL fields round-trip into InEuint32/128, endingTime, epochStartingTime.

2) Single epoch, multiple positions with varied EVAL signature lengths
   - Use different `sigLen` per EVAL to ensure bounded reads and contiguous packing.

3) Multiple epochs, varying durations and positions
   - 3 epochs with different position counts and varied EVAL sizes.
   - Verify: durationSeconds(e), epochStartingTime(e) accumulates prior durations, endingTime, and all EVAL extractions per position.

Zero Epochs and Index Table
4) Validate reverts: NoEpochs when numEpochs == 0
5) Validate reverts: ConfigParamsTooShort when offsets table is truncated (length < 51 + 4*numEpochs)

Epoch Offsets Invariants
6) Validate reverts: BadEpochOffset when any epoch offset < (51 + 4*numEpochs) or >= params.length
7) Validate reverts: OffsetsNotStrictlyIncreasing when offsets are non-increasing
8) Validate reverts: EpochsNotTightlyPacked when epoch 0 does not start exactly at (51 + 4*numEpochs)

Epoch Payload Minima and Derived Timing
9) Validate reverts: EpochPayloadTooShort when endOff < startOff + 5 (missing [duration+numPositions])
10) endingTime() reverts TimestampOverflow on large sums of durations; epochStartingTime(e) also reverts when overflowed

Position Offsets Invariants (variable-length payloads)
11) Validate reverts: NoPositionsInEpoch when numPositions == 0
12) Validate reverts: BadPositionOffset when any position offset is before the posOffsets array end or >= epochEnd
13) Validate reverts: PositionOffsetsNotStrictlyIncreasing if posOffsets[i] <= posOffsets[i-1]
14) Validate reverts: PositionPayloadsOverlap when variable-length EVAL payloads overlap
15) Validate reverts: PositionsNotTightlyPacked when:
    - posOffsets are not exactly contiguous (each payload must start at previous end), or
    - after the last position there is slack before epoch end

EVAL Boundary Checks (bounded reads)
16) Validate reverts: PositionPayloadCrossesEpochBoundary when an EVAL header or its signature bytes exceed epoch bounds
17) Accessors revert appropriately if malformed payload causes _read beyond params (e.g., truncated EVAL) -> OutOfBounds

Accessors Correctness
18) tickLower/tickUpper return InEuint32 with expected fields (ctHash, securityZone, utype, signature)
19) amountAllocated returns InEuint128 with expected fields
20) numPositions and durationSeconds return correct values per epoch

Out-of-bounds/Truncation
21) Accessors revert: OutOfBounds when reading past params due to truncated EVAL bytes (without prior validate)

Additional Behavioral Checks
22) Mixed EVAL sizes across positions and epochs do not affect derived totals or timings

Notes
- Accessors are safe to call on untrusted input only if validate() has been called once to enforce invariants.
- Some revert types (BadExtractSize) are unreachable via public API usage and need not be tested explicitly.
*/

import "forge-std/Test.sol";
import {PrivateCampaignConfig} from "../contracts/lib/PrivateCampaignConfig.sol";
import {InEuint32, InEuint128} from "@fhenixprotocol/cofhe-contracts/ICofhe.sol";

contract PrivateCampaignConfigHarness {
    using PrivateCampaignConfig for bytes;

    function validateParams(bytes calldata params) external pure {
        params.validate();
    }

    function getVersion(bytes calldata params) external pure returns (uint8) {
        return params.version();
    }

    function getStartingTime(
        bytes calldata params
    ) external pure returns (uint64) {
        return params.startingTime();
    }

    function getNumEpochs(
        bytes calldata params
    ) external pure returns (uint16) {
        return params.numEpochs();
    }

    function getTotalTokens(
        bytes calldata params
    ) external pure returns (uint256) {
        return params.totalTokensToSell();
    }

    function getDuration(
        bytes calldata params,
        uint16 epoch
    ) external pure returns (uint32) {
        return params.durationSeconds(epoch);
    }

    function getNumPositions(
        bytes calldata params,
        uint16 epoch
    ) external pure returns (uint8) {
        return params.numPositions(epoch);
    }

    function getTickLower(
        bytes calldata params,
        uint16 epoch,
        uint8 pos
    ) external pure returns (uint256, uint8, uint8, uint16, bytes32) {
        InEuint32 memory v = params.tickLower(epoch, pos);
        return (
            v.ctHash,
            v.securityZone,
            v.utype,
            uint16(v.signature.length),
            keccak256(v.signature)
        );
    }

    function getTickUpper(
        bytes calldata params,
        uint16 epoch,
        uint8 pos
    ) external pure returns (uint256, uint8, uint8, uint16, bytes32) {
        InEuint32 memory v = params.tickUpper(epoch, pos);
        return (
            v.ctHash,
            v.securityZone,
            v.utype,
            uint16(v.signature.length),
            keccak256(v.signature)
        );
    }

    function getAmount(
        bytes calldata params,
        uint16 epoch,
        uint8 pos
    ) external pure returns (uint256, uint8, uint8, uint16, bytes32) {
        InEuint128 memory v = params.amountAllocated(epoch, pos);
        return (
            v.ctHash,
            v.securityZone,
            v.utype,
            uint16(v.signature.length),
            keccak256(v.signature)
        );
    }

    function getEndingTime(
        bytes calldata params
    ) external pure returns (uint64) {
        return params.endingTime();
    }

    function getEpochStartingTime(
        bytes calldata params,
        uint16 epoch
    ) external pure returns (uint64) {
        return params.epochStartingTime(epoch);
    }

    // no unpack helpers to avoid returning dynamic bytes which increases stack pressure
}

contract PrivateCampaignConfigTest is Test {
    PrivateCampaignConfigHarness private harness;

    function setUp() public {
        harness = new PrivateCampaignConfigHarness();
    }

    function _appendEval(
        bytes memory acc,
        uint256 ctHash,
        uint8 securityZone,
        uint8 utype,
        bytes memory signature
    ) private pure returns (bytes memory) {
        return
            bytes.concat(
                acc,
                bytes32(ctHash),
                bytes1(securityZone),
                bytes1(utype),
                bytes2(uint16(signature.length)),
                signature
            );
    }

    function test_HappyPath_SingleEpochSinglePosition_MinimalEVALs() public view {
        uint8 ver = 1;
        uint64 start = 1000;
        uint256 totalTokens = 123456789;
        uint16 epochs = 1;
        uint32 epoch0Offset = uint32(51 + 4 * uint32(epochs)); // header 51 + index

        uint32 dur0 = 3600;
        uint8 npos0 = 1;
        uint32 pos0Offset = uint32(epoch0Offset + 5 + 4 * uint32(npos0)); // start + [duration+numPositions] + posOffsets

        // EVALs with non-empty signatures (varying lengths)
        // tickLower
        uint256 tlCt = 0x1111;
        uint8 tlSz = 1;
        uint8 tlType = 32;
        bytes memory tlSig = hex"01"; // 1-byte signature

        // tickUpper
        uint256 tuCt = 0x2222;
        uint8 tuSz = 1;
        uint8 tuType = 32;
        bytes memory tuSig = hex"02030405060708090a0b0c0d0e0f"; // 15-byte signature

        // amountAllocated
        uint256 amtCt = 0x3333;
        uint8 amtSz = 2;
        uint8 amtType = 128;
        bytes
            memory amtSig = hex"deadbeefcafebabe00112233445566778899aabbccddeeff"; // 24-byte signature

        // Assemble params
        bytes memory params = bytes.concat(
            bytes8(keccak256("PrivateCampaignConfig")),
            abi.encodePacked(uint8(ver)),
            abi.encodePacked(uint64(start)),
            abi.encodePacked(uint256(totalTokens)),
            abi.encodePacked(uint16(epochs)),
            abi.encodePacked(uint32(epoch0Offset)),
            abi.encodePacked(uint32(dur0)),
            abi.encodePacked(uint8(npos0)),
            abi.encodePacked(uint32(pos0Offset))
        );

        // positions region (tickLower -> tickUpper -> amount), tightly packed
        params = _appendEval(params, tlCt, tlSz, tlType, tlSig);
        params = _appendEval(params, tuCt, tuSz, tuType, tuSig);
        params = _appendEval(params, amtCt, amtSz, amtType, amtSig);

        // validate should pass
        harness.validateParams(params);

        // Header reads
        assertEq(harness.getVersion(params), ver);
        assertEq(harness.getStartingTime(params), start);
        assertEq(harness.getNumEpochs(params), epochs);
        assertEq(harness.getTotalTokens(params), totalTokens);

        // Epoch-level reads
        assertEq(harness.getDuration(params, 0), dur0);
        assertEq(harness.getNumPositions(params, 0), npos0);

        // Derived times
        assertEq(harness.getEpochStartingTime(params, 0), start);
        assertEq(harness.getEndingTime(params), start + dur0);

        // Position-level reads (verify EVAL fields)
        {
            (uint256 c, uint8 s, uint8 t, uint16 sl, bytes32 sh) = harness
                .getTickLower(params, 0, 0);
            assertEq(c, tlCt);
            assertEq(s, tlSz);
            assertEq(t, tlType);
            assertEq(sl, uint16(tlSig.length));
            assertEq(sh, keccak256(tlSig));
        }
        {
            (uint256 c, uint8 s, uint8 t, uint16 sl, bytes32 sh) = harness
                .getTickUpper(params, 0, 0);
            assertEq(c, tuCt);
            assertEq(s, tuSz);
            assertEq(t, tuType);
            assertEq(sl, uint16(tuSig.length));
            assertEq(sh, keccak256(tuSig));
        }
        {
            (uint256 c, uint8 s, uint8 t, uint16 sl, bytes32 sh) = harness
                .getAmount(params, 0, 0);
            assertEq(c, amtCt);
            assertEq(s, amtSz);
            assertEq(t, amtType);
            assertEq(sl, uint16(amtSig.length));
            assertEq(sh, keccak256(amtSig));
        }
    }

    function test_HappyPath_SingleEpoch_MultiplePositions_VariedEvalSizes()
        public view
    {
        uint8 ver = 1;
        uint64 start = 4242;
        uint256 totalTokens = 999999999999;
        uint16 epochs = 1;
        uint32 epoch0Offset = uint32(51 + 4 * uint32(epochs));

        uint32 dur0 = 12_345;
        uint8 npos0 = 3;
        uint32 posOffsetsBase = uint32(epoch0Offset + 5);
        uint32 pos0Off = uint32(posOffsetsBase + 4 * uint32(npos0));

        // Position 0 EVALs (small signatures)
        bytes memory p0_tlSig = hex"aa";
        bytes memory p0_tuSig = hex"bbbb";
        bytes memory p0_amtSig = hex"cccccc";

        // Position 1 EVALs (medium signatures)
        bytes memory p1_tlSig = hex"0102030405";
        bytes memory p1_tuSig = hex"0a0b0c0d0e0f10";
        bytes memory p1_amtSig = hex"deadbeefcafebabe0011";

        // Position 2 EVALs (longer signatures)
        bytes memory p2_tlSig = hex"11223344556677889900aabbccddeeff";
        bytes memory p2_tuSig = hex"00112233445566778899aabbccddeeff00112233";
        bytes
            memory p2_amtSig = hex"abcdefabcdefabcdefabcdefabcdefabcdefabcdef";

        // Build position 0 payload
        bytes memory positions;
        positions = _appendEval(positions, 0xaaaa, 1, 32, p0_tlSig);
        positions = _appendEval(positions, 0xbbbb, 1, 32, p0_tuSig);
        positions = _appendEval(positions, 0xcccc, 2, 128, p0_amtSig);
        uint32 pos1Off = uint32(pos0Off + positions.length);

        // position 1 payload
        positions = _appendEval(positions, 0x11112222, 1, 32, p1_tlSig);
        positions = _appendEval(positions, 0x33334444, 1, 32, p1_tuSig);
        positions = _appendEval(positions, 0x55556666, 2, 128, p1_amtSig);
        uint32 pos2Off = uint32(pos0Off + positions.length);

        // position 2 payload
        positions = _appendEval(positions, 0x777788889999, 1, 32, p2_tlSig);
        positions = _appendEval(positions, 0xaaaaBBBBcccc, 1, 32, p2_tuSig);
        positions = _appendEval(positions, 0xDDDD0000EEEE, 2, 128, p2_amtSig);

        // Assemble full params
        bytes memory params = bytes.concat(
            bytes8(keccak256("PrivateCampaignConfig")),
            abi.encodePacked(uint8(ver)),
            abi.encodePacked(uint64(start)),
            abi.encodePacked(uint256(totalTokens)),
            abi.encodePacked(uint16(epochs)),
            abi.encodePacked(uint32(epoch0Offset)),
            abi.encodePacked(uint32(dur0)),
            abi.encodePacked(uint8(npos0)),
            abi.encodePacked(uint32(pos0Off)),
            abi.encodePacked(uint32(pos1Off)),
            abi.encodePacked(uint32(pos2Off)),
            positions
        );

        harness.validateParams(params);

        // Header
        assertEq(harness.getVersion(params), ver);
        assertEq(harness.getStartingTime(params), start);
        assertEq(harness.getNumEpochs(params), epochs);
        assertEq(harness.getTotalTokens(params), totalTokens);

        // Epoch
        assertEq(harness.getDuration(params, 0), dur0);
        assertEq(harness.getNumPositions(params, 0), npos0);

        // Pos 0 checks
        {
            (uint256 c, uint8 s, uint8 t, uint16 sl, bytes32 sh) = harness
                .getTickLower(params, 0, 0);
            assertEq(c, 0xaaaa);
            assertEq(s, 1);
            assertEq(t, 32);
            assertEq(sl, uint16(p0_tlSig.length));
            assertEq(sh, keccak256(p0_tlSig));
        }
        {
            (uint256 c, uint8 s, uint8 t, uint16 sl, bytes32 sh) = harness
                .getTickUpper(params, 0, 0);
            assertEq(c, 0xbbbb);
            assertEq(s, 1);
            assertEq(t, 32);
            assertEq(sl, uint16(p0_tuSig.length));
            assertEq(sh, keccak256(p0_tuSig));
        }
        {
            (uint256 c, uint8 s, uint8 t, uint16 sl, bytes32 sh) = harness
                .getAmount(params, 0, 0);
            assertEq(c, 0xcccc);
            assertEq(s, 2);
            assertEq(t, 128);
            assertEq(sl, uint16(p0_amtSig.length));
            assertEq(sh, keccak256(p0_amtSig));
        }

        // Pos 1 checks
        {
            (uint256 c, uint8 s, uint8 t, uint16 sl, bytes32 sh) = harness
                .getTickLower(params, 0, 1);
            assertEq(c, 0x11112222);
            assertEq(s, 1);
            assertEq(t, 32);
            assertEq(sl, uint16(p1_tlSig.length));
            assertEq(sh, keccak256(p1_tlSig));
        }
        {
            (uint256 c, uint8 s, uint8 t, uint16 sl, bytes32 sh) = harness
                .getTickUpper(params, 0, 1);
            assertEq(c, 0x33334444);
            assertEq(s, 1);
            assertEq(t, 32);
            assertEq(sl, uint16(p1_tuSig.length));
            assertEq(sh, keccak256(p1_tuSig));
        }
        {
            (uint256 c, uint8 s, uint8 t, uint16 sl, bytes32 sh) = harness
                .getAmount(params, 0, 1);
            assertEq(c, 0x55556666);
            assertEq(s, 2);
            assertEq(t, 128);
            assertEq(sl, uint16(p1_amtSig.length));
            assertEq(sh, keccak256(p1_amtSig));
        }

        // Pos 2 checks
        {
            (uint256 c, uint8 s, uint8 t, uint16 sl, bytes32 sh) = harness
                .getTickLower(params, 0, 2);
            assertEq(c, 0x777788889999);
            assertEq(s, 1);
            assertEq(t, 32);
            assertEq(sl, uint16(p2_tlSig.length));
            assertEq(sh, keccak256(p2_tlSig));
        }
        {
            (uint256 c, uint8 s, uint8 t, uint16 sl, bytes32 sh) = harness
                .getTickUpper(params, 0, 2);
            assertEq(c, 0xaaaabbbbcccc);
            assertEq(s, 1);
            assertEq(t, 32);
            assertEq(sl, uint16(p2_tuSig.length));
            assertEq(sh, keccak256(p2_tuSig));
        }
        {
            (uint256 c, uint8 s, uint8 t, uint16 sl, bytes32 sh) = harness
                .getAmount(params, 0, 2);
            assertEq(c, 0xdddd0000eeee);
            assertEq(s, 2);
            assertEq(t, 128);
            assertEq(sl, uint16(p2_amtSig.length));
            assertEq(sh, keccak256(p2_amtSig));
        }
    }

    function test_HappyPath_MultipleEpochs_VariedDurationsAndPositions() public view {
        uint8 ver = 1;
        uint64 start = 7777;
        uint16 epochs = 3;
        uint32 offsetsBase = 51; // header
        uint32 idxBytes = 4 * uint32(epochs);
        uint32 e0Off = offsetsBase + idxBytes;

        // Epoch 0: 2 positions
        uint32 e0Dur = 1000;
        uint8 e0N = 2;
        // build epoch 0 payload
        bytes memory e0;
        e0 = bytes.concat(abi.encodePacked(uint32(e0Dur)), abi.encodePacked(uint8(e0N)));
        uint32 e0PosBase = uint32(e0Off + e0.length + 4 * e0N);
        uint32 e0P0 = e0PosBase;
        bytes memory e0pos;
        e0pos = _appendEval(e0pos, 0xabc, 1, 32, hex"01");
        e0pos = _appendEval(e0pos, 0xdef, 1, 32, hex"02");
        e0pos = _appendEval(e0pos, 0x123, 2, 128, hex"0303");
        uint32 e0P1 = uint32(e0P0 + e0pos.length);
        e0pos = _appendEval(e0pos, 0x456, 1, 32, hex"aa");
        e0pos = _appendEval(e0pos, 0x789, 1, 32, hex"bb");
        e0pos = _appendEval(e0pos, 0x999, 2, 128, hex"cccc");
        e0 = bytes.concat(
            e0,
            abi.encodePacked(uint32(e0P0)),
            abi.encodePacked(uint32(e0P1)),
            e0pos
        );
        uint32 e1Off = uint32(e0Off + e0.length);

        // Epoch 1: 1 position
        uint32 e1Dur = 50;
        uint8 e1N = 1;
        bytes memory e1;
        e1 = bytes.concat(abi.encodePacked(uint32(e1Dur)), abi.encodePacked(uint8(e1N)));
        uint32 e1PosBase = uint32(e1Off + e1.length + 4 * e1N);
        uint32 e1P0 = e1PosBase;
        bytes memory e1pos;
        e1pos = _appendEval(e1pos, 0xABAB, 1, 32, hex"1111");
        e1pos = _appendEval(e1pos, 0xCDCD, 1, 32, hex"2222");
        e1pos = _appendEval(e1pos, 0xEFEF, 2, 128, hex"3333");
        e1 = bytes.concat(
            e1,
            abi.encodePacked(uint32(e1P0)),
            e1pos
        );
        uint32 e2Off = uint32(e1Off + e1.length);

        // Epoch 2: 3 positions
        uint32 e2Dur = 5;
        uint8 e2N = 3;
        bytes memory e2;
        e2 = bytes.concat(abi.encodePacked(uint32(e2Dur)), abi.encodePacked(uint8(e2N)));
        uint32 e2PosBase = uint32(e2Off + e2.length + 4 * e2N);
        uint32 e2P0 = e2PosBase;
        bytes memory e2pos;
        // p0
        e2pos = _appendEval(e2pos, 0x1, 1, 32, hex"01");
        e2pos = _appendEval(e2pos, 0x2, 1, 32, hex"02");
        e2pos = _appendEval(e2pos, 0x3, 2, 128, hex"03");
        uint32 e2P1 = uint32(e2P0 + e2pos.length);
        // p1
        e2pos = _appendEval(e2pos, 0x4, 1, 32, hex"0404");
        e2pos = _appendEval(e2pos, 0x5, 1, 32, hex"0505");
        e2pos = _appendEval(e2pos, 0x6, 2, 128, hex"0606");
        uint32 e2P2 = uint32(e2P1 + (e2pos.length - (e2P1 - e2P0)));
        // p2
        e2pos = _appendEval(e2pos, 0x7, 1, 32, hex"070707");
        e2pos = _appendEval(e2pos, 0x8, 1, 32, hex"080808");
        e2pos = _appendEval(e2pos, 0x9, 2, 128, hex"090909");
        e2 = bytes.concat(
            e2,
            abi.encodePacked(uint32(e2P0)),
            abi.encodePacked(uint32(e2P1)),
            abi.encodePacked(uint32(e2P2)),
            e2pos
        );

        // Assemble params
        bytes memory params = bytes.concat(
            bytes8(keccak256("PrivateCampaignConfig")),
            abi.encodePacked(uint8(ver)),
            abi.encodePacked(uint64(start)),
            abi.encodePacked(uint256(0)), // totalTokens header not used in test checks here
            abi.encodePacked(uint16(epochs)),
            abi.encodePacked(uint32(e0Off)),
            abi.encodePacked(uint32(e1Off)),
            abi.encodePacked(uint32(e2Off)),
            e0,
            e1,
            e2
        );

        harness.validateParams(params);

        // Durations and positions
        assertEq(harness.getDuration(params, 0), e0Dur);
        assertEq(harness.getDuration(params, 1), e1Dur);
        assertEq(harness.getDuration(params, 2), e2Dur);
        assertEq(harness.getNumPositions(params, 0), e0N);
        assertEq(harness.getNumPositions(params, 1), e1N);
        assertEq(harness.getNumPositions(params, 2), e2N);

        // Epoch starting times
        assertEq(harness.getEpochStartingTime(params, 0), start);
        assertEq(harness.getEpochStartingTime(params, 1), start + e0Dur);
        assertEq(
            harness.getEpochStartingTime(params, 2),
            start + e0Dur + e1Dur
        );

        // Spot-check a few EVAL fields
        {
            (uint256 c,,,,) = harness.getTickLower(params, 0, 1);
            assertEq(c, 0x456);
        }
        {
            (uint256 c,,,,) = harness.getTickUpper(params, 1, 0);
            assertEq(c, 0xCDCD);
        }
        {
            (uint256 c,,,,) = harness.getAmount(params, 2, 2);
            assertEq(c, 0x9);
        }
    }

    function test_NoEpochs_Revert() public {
        uint8 ver = 1;
        uint64 start = 1234;
        uint256 totalTokens = 0;
        uint16 epochs = 0; // trigger

        bytes memory params = bytes.concat(
            bytes8(keccak256("PrivateCampaignConfig")),
            abi.encodePacked(uint8(ver)),
            abi.encodePacked(uint64(start)),
            abi.encodePacked(uint256(totalTokens)),
            abi.encodePacked(uint16(epochs))
        );

        vm.expectRevert(PrivateCampaignConfig.NoEpochs.selector);
        harness.validateParams(params);
    }

    function test_ConfigParamsTooShort_Revert() public {
        uint8 ver = 1;
        uint64 start = 2222;
        uint256 totalTokens = 0;
        uint16 epochs = 2; // requires 8 bytes of epoch offsets after header

        // Build only the header, omit the epoch offsets table to trigger truncation
        bytes memory params = bytes.concat(
            bytes8(keccak256("PrivateCampaignConfig")),
            abi.encodePacked(uint8(ver)),
            abi.encodePacked(uint64(start)),
            abi.encodePacked(uint256(totalTokens)),
            abi.encodePacked(uint16(epochs))
        );

        vm.expectRevert(PrivateCampaignConfig.ConfigParamsTooShort.selector);
        harness.validateParams(params);
    }

    // 6) Validate reverts: BadEpochOffset when any epoch offset < (51 + 4*numEpochs) or >= params.length
    function test_BadEpochOffset_Revert() public {
        uint8 ver = 1;
        uint64 start = 3333;
        uint256 totalTokens = 0;
        uint16 epochs = 1;
        uint32 offsetsBase = 51; // header size
        uint32 idxBytes = 4 * epochs;
        uint32 minEpochArea = offsetsBase + idxBytes;

        // Case 1: Epoch offset too small (points before index table)
        bytes memory params1 = bytes.concat(
            bytes8(keccak256("PrivateCampaignConfig")),
            abi.encodePacked(uint8(ver)),
            abi.encodePacked(uint64(start)),
            abi.encodePacked(uint256(totalTokens)),
            abi.encodePacked(uint16(epochs)),
            abi.encodePacked(uint32(minEpochArea - 1)) // Bad offset
        );
        vm.expectRevert(PrivateCampaignConfig.BadEpochOffset.selector);
        harness.validateParams(params1);

        // Case 2: Epoch offset too large (points past end of params)
        // We need enough space for the header + index + an epoch payload.
        // Make a minimal valid epoch payload to calculate its size
        // uint32 dur0 = 100;
        // uint8 npos0 = 1;
        // uint32 posOffsetsBase = minEpochArea + 5;
        // uint32 pos0Off = uint32(posOffsetsBase + 4 * uint32(npos0));
        bytes memory p0_tlSig = hex"01";
        bytes memory p0_tuSig = hex"02";
        bytes memory p0_amtSig = hex"03";
        bytes memory e0pos;
        e0pos = _appendEval(e0pos, 0xabc, 1, 32, p0_tlSig);
        e0pos = _appendEval(e0pos, 0xdef, 1, 32, p0_tuSig);
        e0pos = _appendEval(e0pos, 0x123, 2, 128, p0_amtSig);
        // bytes memory e0 = bytes.concat(
        //     abi.encodePacked(uint32(dur0)),
        //     abi.encodePacked(uint8(npos0)),
        //     abi.encodePacked(uint32(pos0Off)),
        //     e0pos
        // );

        bytes memory params2 = bytes.concat(
            bytes8(keccak256("PrivateCampaignConfig")),
            abi.encodePacked(uint8(ver)),
            abi.encodePacked(uint64(start)),
            abi.encodePacked(uint256(totalTokens)),
            abi.encodePacked(uint16(epochs)),
            abi.encodePacked(uint32(e0pos.length + minEpochArea + 1)) // Bad offset: past end
        );
        vm.expectRevert(PrivateCampaignConfig.BadEpochOffset.selector);
        harness.validateParams(params2);
    }

    // 7) Validate reverts: OffsetsNotStrictlyIncreasing when offsets are non-increasing
    function test_OffsetsNotStrictlyIncreasing_Revert() public {
        uint8 ver = 1;
        uint64 start = 4444;
        uint256 totalTokens = 0;
        uint16 epochs = 2;
        uint32 offsetsBase = 51;
        uint32 idxBytes = 4 * epochs;
        uint32 e0Off = offsetsBase + idxBytes; // Valid start for epoch 0

        // Epoch 1 offset is before or equal to Epoch 0 offset
        bytes memory params = bytes.concat(
            bytes8(keccak256("PrivateCampaignConfig")),
            abi.encodePacked(uint8(ver)),
            abi.encodePacked(uint64(start)),
            abi.encodePacked(uint256(totalTokens)),
            abi.encodePacked(uint16(epochs)),
            abi.encodePacked(uint32(e0Off)),
            abi.encodePacked(uint32(e0Off)), // epoch 1 offset = epoch 0 offset, not strictly increasing
            hex"0102030405" // Minimal epoch payload to extend params.length
        );

        vm.expectRevert(PrivateCampaignConfig.OffsetsNotStrictlyIncreasing.selector);
        harness.validateParams(params);
    }

    // 8) Validate reverts: EpochsNotTightlyPacked when epoch 0 does not start exactly at (51 + 4*numEpochs)
    function test_EpochsNotTightlyPacked_Revert() public {
        uint8 ver = 1;
        uint64 start = 5555;
        uint256 totalTokens = 0;
        uint16 epochs = 1;
        uint32 offsetsBase = 51;
        uint32 idxBytes = 4 * epochs;
        uint32 minEpochArea = offsetsBase + idxBytes; // Expected start of epoch 0

        // Epoch 0 offset is greater than minEpochArea
        bytes memory params = bytes.concat(
            bytes8(keccak256("PrivateCampaignConfig")),
            abi.encodePacked(uint8(ver)),
            abi.encodePacked(uint64(start)),
            abi.encodePacked(uint256(totalTokens)),
            abi.encodePacked(uint16(epochs)),
            abi.encodePacked(uint32(minEpochArea + 1)), // Bad offset: not tightly packed
            hex"0102030405" // Minimal epoch payload to extend params.length
        );

        vm.expectRevert(PrivateCampaignConfig.EpochsNotTightlyPacked.selector);
        harness.validateParams(params);
    }

    // 9) Validate reverts: EpochPayloadTooShort when endOff < startOff + 5 (missing [duration+numPositions])
    function test_EpochPayloadTooShort_Revert() public {
        uint8 ver = 1;
        uint64 start = 6666;
        uint256 totalTokens = 0;
        uint16 epochs = 1;
        uint32 offsetsBase = 51; // header size
        uint32 idxBytes = 4 * epochs;
        uint32 e0Off = offsetsBase + idxBytes; // Expected start of epoch 0 = 55

        // Build params with header and epoch offset, but with a payload shorter than EPOCH_HEADER_MIN_SIZE (5 bytes)
        bytes memory params = bytes.concat(
            bytes8(keccak256("PrivateCampaignConfig")),
            abi.encodePacked(uint8(ver)),
            abi.encodePacked(uint64(start)),
            abi.encodePacked(uint256(totalTokens)),
            abi.encodePacked(uint16(epochs)),
            abi.encodePacked(uint32(e0Off)),
            hex"01020304" // Only 4 bytes, less than EPOCH_HEADER_MIN_SIZE (5)
        );

        vm.expectRevert(PrivateCampaignConfig.EpochPayloadTooShort.selector);
        harness.validateParams(params);
    }

    // 10) endingTime() reverts TimestampOverflow on large sums of durations; epochStartingTime(e) also reverts when overflowed

    function test_TimestampOverflow_EndingTime_Revert() public {
        uint8 ver = 1;
        uint64 start = type(uint64).max - 1; // start near max
        uint256 totalTokens = 0;
        uint16 epochs = 1;
        uint32 offsetsBase = 51;
        uint32 idxBytes = 4 * epochs;
        uint32 e0Off = offsetsBase + idxBytes; // 55

        uint32 dur0 = 2; // Adding 2 should cause overflow
        uint8 npos0 = 1;
        uint32 posOffsetsBase = e0Off + 5;
        uint32 pos0Off = uint32(posOffsetsBase + 4 * uint32(npos0));

        bytes memory p0_tlSig = hex"01";
        bytes memory p0_tuSig = hex"02";
        bytes memory p0_amtSig = hex"03";
        bytes memory e0pos;
        e0pos = _appendEval(e0pos, 0xabc, 1, 32, p0_tlSig);
        e0pos = _appendEval(e0pos, 0xdef, 1, 32, p0_tuSig);
        e0pos = _appendEval(e0pos, 0x123, 2, 128, p0_amtSig);

        bytes memory e0 = bytes.concat(
            abi.encodePacked(uint32(dur0)),
            abi.encodePacked(uint8(npos0)),
            abi.encodePacked(uint32(pos0Off)),
            e0pos
        );

        bytes memory params = bytes.concat(
            bytes8(keccak256("PrivateCampaignConfig")),
            abi.encodePacked(uint8(ver)),
            abi.encodePacked(uint64(start)),
            abi.encodePacked(uint256(totalTokens)),
            abi.encodePacked(uint16(epochs)),
            abi.encodePacked(uint32(e0Off)),
            e0
        );

        vm.expectRevert(PrivateCampaignConfig.TimestampOverflow.selector);
        harness.getEndingTime(params);
    }

    function test_TimestampOverflow_EpochStartingTime_Revert() public {
        uint8 ver = 1;
        uint64 start = type(uint64).max - type(uint32).max + 1; // Corrected starting time for overflow
        uint256 totalTokens = 0;
        uint16 epochs = 2;
        uint32 offsetsBase = 51;
        uint32 idxBytes = 4 * epochs;
        uint32 e0Off = offsetsBase + idxBytes; // 59

        uint32 dur0 = type(uint32).max; // Max duration for epoch 0
        uint8 npos0 = 1;
        uint32 e0PosOffsetsBase = e0Off + 5;
        uint32 e0Pos0Off = uint32(e0PosOffsetsBase + 4 * uint32(npos0));

        bytes memory p0_tlSig = hex"01";
        bytes memory p0_tuSig = hex"02";
        bytes memory p0_amtSig = hex"03";
        bytes memory e0pos_payload;
        e0pos_payload = _appendEval(e0pos_payload, 0xabc, 1, 32, p0_tlSig);
        e0pos_payload = _appendEval(e0pos_payload, 0xdef, 1, 32, p0_tuSig);
        e0pos_payload = _appendEval(e0pos_payload, 0x123, 2, 128, p0_amtSig);

        bytes memory e0_payload = bytes.concat(
            abi.encodePacked(uint32(dur0)),
            abi.encodePacked(uint8(npos0)),
            abi.encodePacked(uint32(e0Pos0Off)),
            e0pos_payload
        );
        // uint32 e1Off = e0Off + uint32(e0_payload.length); // Start of epoch 1

        uint32 dur1 = 2; // Adding 2 should cause overflow for epochStartingTime(1)
        uint8 npos1 = 1;
        uint32 e1PosOffsetsBase = e0Off + uint32(e0_payload.length) + 5; // Start of epoch 1
        uint32 e1Pos0Off = uint32(e1PosOffsetsBase + 4 * uint32(npos1));

        bytes memory p1_tlSig = hex"04";
        bytes memory p1_tuSig = hex"05";
        bytes memory p1_amtSig = hex"06";
        bytes memory e1pos_payload;
        e1pos_payload = _appendEval(e1pos_payload, 0x456, 1, 32, p1_tlSig);
        e1pos_payload = _appendEval(e1pos_payload, 0x789, 1, 32, p1_tuSig);
        e1pos_payload = _appendEval(e1pos_payload, 0x999, 2, 128, p1_amtSig);

        bytes memory e1_payload = bytes.concat(
            abi.encodePacked(uint32(dur1)),
            abi.encodePacked(uint8(npos1)),
            abi.encodePacked(uint32(e1Pos0Off)),
            e1pos_payload
        );

        // Dynamically calculate e1Off and total params length
        uint32 e1Off = e0Off + uint32(e0_payload.length);

        bytes memory params = bytes.concat(
            bytes8(keccak256("PrivateCampaignConfig")),
            abi.encodePacked(uint8(ver)),
            abi.encodePacked(uint64(start)),
            abi.encodePacked(uint256(totalTokens)),
            abi.encodePacked(uint16(epochs)),
            abi.encodePacked(uint32(e0Off)),
            abi.encodePacked(uint32(e1Off)),
            e0_payload,
            e1_payload
        );

        vm.expectRevert(PrivateCampaignConfig.TimestampOverflow.selector);
        harness.getEpochStartingTime(params, 1);
    }

    // 11) Validate reverts: NoPositionsInEpoch when numPositions == 0
    function test_NoPositionsInEpoch_Revert() public {
        uint8 ver = 1;
        uint64 start = 7777;
        uint256 totalTokens = 0;
        uint16 epochs = 1;
        uint32 offsetsBase = 51;
        uint32 idxBytes = 4 * epochs;
        uint32 e0Off = offsetsBase + idxBytes; // 55

        uint32 dur0 = 100;
        uint8 npos0 = 0; // Trigger: No positions in epoch
        // uint32 posOffsetsBase = e0Off + 5; // Placeholder, not actually used if npos0=0

        bytes memory e0 = bytes.concat(
            abi.encodePacked(uint32(dur0)),
            abi.encodePacked(uint8(npos0))
            // No posOffsets or positions because npos0 is 0
        );

        bytes memory params = bytes.concat(
            bytes8(keccak256("PrivateCampaignConfig")),
            abi.encodePacked(uint8(ver)),
            abi.encodePacked(uint64(start)),
            abi.encodePacked(uint256(totalTokens)),
            abi.encodePacked(uint16(epochs)),
            abi.encodePacked(uint32(e0Off)),
            e0
        );

        vm.expectRevert(PrivateCampaignConfig.NoPositionsInEpoch.selector);
        harness.validateParams(params);
    }

    // 12) Validate reverts: BadPositionOffset when any position offset is before the posOffsets array end or >= epochEnd
    function test_BadPositionOffset_Revert() public {
        uint8 ver = 1;
        uint64 start = 8888;
        uint256 totalTokens = 0;
        uint16 epochs = 1;
        uint32 offsetsBase = 51; // header size
        uint32 idxBytes = 4 * epochs;
        uint32 e0Off = offsetsBase + idxBytes; // 55

        uint32 dur0 = 1000;
        uint8 npos0 = 1;
        uint32 posOffsetsBase = e0Off + 5;
        // uint32 expectedPos0Off = uint32(posOffsetsBase + 4 * uint32(npos0));

        bytes memory p0_tlSig = hex"01";
        bytes memory p0_tuSig = hex"02";
        bytes memory p0_amtSig = hex"03";
        bytes memory e0pos_payload;
        e0pos_payload = _appendEval(e0pos_payload, 0xabc, 1, 32, p0_tlSig);
        e0pos_payload = _appendEval(e0pos_payload, 0xdef, 1, 32, p0_tuSig);
        e0pos_payload = _appendEval(e0pos_payload, 0x123, 2, 128, p0_amtSig);

        // --- Case 1: Position offset before posOffsets array end ---
        bytes memory e0_case1 = bytes.concat(
            abi.encodePacked(uint32(dur0)),
            abi.encodePacked(uint8(npos0)),
            abi.encodePacked(uint32(posOffsetsBase - 1)), // Bad offset: before posOffsetsBase
            e0pos_payload
        );
        bytes memory params1 = bytes.concat(
            bytes8(keccak256("PrivateCampaignConfig")),
            abi.encodePacked(uint8(ver)),
            abi.encodePacked(uint64(start)),
            abi.encodePacked(uint256(totalTokens)),
            abi.encodePacked(uint16(epochs)),
            abi.encodePacked(uint32(e0Off)),
            e0_case1
        );
        vm.expectRevert(PrivateCampaignConfig.BadPositionOffset.selector);
        harness.validateParams(params1);

        // --- Case 2: Position offset at or beyond epochEnd ---
        // The epoch end for epoch 0 is params.length in this single epoch setup.
        // So, we need pos0Off to be >= params.length for this test. Since we control e0pos_payload,
        // we can use its length to calculate the exact end.
        uint32 epochEnd_case2 = e0Off + uint32(e0pos_payload.length) + 5 + 4 * npos0; // Calculate expected epoch end

        bytes memory e0_case2 = bytes.concat(
            abi.encodePacked(uint32(dur0)),
            abi.encodePacked(uint8(npos0)),
            abi.encodePacked(uint32(epochEnd_case2)), // Bad offset: at epochEnd
            e0pos_payload
        );
        bytes memory params2 = bytes.concat(
            bytes8(keccak256("PrivateCampaignConfig")),
            abi.encodePacked(uint8(ver)),
            abi.encodePacked(uint64(start)),
            abi.encodePacked(uint256(totalTokens)),
            abi.encodePacked(uint16(epochs)),
            abi.encodePacked(uint32(e0Off)),
            e0_case2
        );
        vm.expectRevert(PrivateCampaignConfig.BadPositionOffset.selector);
        harness.validateParams(params2);
    }

    // 13) Validate reverts: PositionOffsetsNotStrictlyIncreasing if posOffsets[i] <= posOffsets[i-1]
    function test_PositionOffsetsNotStrictlyIncreasing_Revert() public {
        uint8 ver = 1;
        uint64 start = 9999;
        uint256 totalTokens = 0;
        uint16 epochs = 1;
        uint32 offsetsBase = 51; // header size
        uint32 idxBytes = 4 * epochs;
        uint32 e0Off = offsetsBase + idxBytes; // 55

        uint32 dur0 = 1000;
        uint8 npos0 = 2; // Two positions
        uint32 posOffsetsBase = e0Off + 5;
        uint32 p0Off = uint32(posOffsetsBase + 4 * uint32(npos0)); // Start of first position's payload

        bytes memory tlSig = hex"01";
        bytes memory tuSig = hex"02";
        bytes memory amtSig = hex"03";

        bytes memory p0_payload;
        p0_payload = _appendEval(p0_payload, 0x111, 1, 32, tlSig);
        p0_payload = _appendEval(p0_payload, 0x222, 1, 32, tuSig);
        p0_payload = _appendEval(p0_payload, 0x333, 2, 128, amtSig);

        bytes memory p1_payload;
        p1_payload = _appendEval(p1_payload, 0x444, 1, 32, tlSig);
        p1_payload = _appendEval(p1_payload, 0x555, 1, 32, tuSig);
        p1_payload = _appendEval(p1_payload, 0x666, 2, 128, amtSig);

        // Create epoch payload with non-strictly increasing position offsets
        bytes memory e0 = bytes.concat(
            abi.encodePacked(uint32(dur0)),
            abi.encodePacked(uint8(npos0)),
            abi.encodePacked(uint32(p0Off)),
            abi.encodePacked(uint32(p0Off)), // p1Off is not strictly greater than p0Off
            p0_payload,
            p1_payload
        );

        bytes memory params = bytes.concat(
            bytes8(keccak256("PrivateCampaignConfig")),
            abi.encodePacked(uint8(ver)),
            abi.encodePacked(uint64(start)),
            abi.encodePacked(uint256(totalTokens)),
            abi.encodePacked(uint16(epochs)),
            abi.encodePacked(uint32(e0Off)),
            e0
        );

        vm.expectRevert(PrivateCampaignConfig.PositionOffsetsNotStrictlyIncreasing.selector);
        harness.validateParams(params);
    }

    // 14) Validate reverts: PositionPayloadsOverlap when variable-length EVAL payloads overlap
    function test_PositionPayloadsOverlap_Revert() public {
        uint8 ver = 1;
        uint64 start = 10000;
        uint256 totalTokens = 0;
        uint16 epochs = 1;
        uint32 offsetsBase = 51;
        uint32 idxBytes = 4 * epochs;
        uint32 e0Off = offsetsBase + idxBytes; // 55

        uint32 dur0 = 1000;
        uint8 npos0 = 2; // Two positions
        uint32 posOffsetsBase = e0Off + 5;
        uint32 p0Off = uint32(posOffsetsBase + 4 * uint32(npos0)); // Start of first position's payload

        bytes memory tlSig = hex"01";
        bytes memory tuSig = hex"02";
        bytes memory amtSig = hex"03";

        bytes memory p0_payload;
        p0_payload = _appendEval(p0_payload, 0x111, 1, 32, tlSig);
        p0_payload = _appendEval(p0_payload, 0x222, 1, 32, tuSig);
        p0_payload = _appendEval(p0_payload, 0x333, 2, 128, amtSig);

        bytes memory p1_payload;
        p1_payload = _appendEval(p1_payload, 0x444, 1, 32, tlSig);
        p1_payload = _appendEval(p1_payload, 0x555, 1, 32, tuSig);
        p1_payload = _appendEval(p1_payload, 0x666, 2, 128, amtSig);

        // Calculate p1Off to cause overlap
        uint32 p1Off = p0Off + uint32(p0_payload.length) - 1; // Overlap by 1 byte

        // Create epoch payload with overlapping position payloads
        bytes memory e0 = bytes.concat(
            abi.encodePacked(uint32(dur0)),
            abi.encodePacked(uint8(npos0)),
            abi.encodePacked(uint32(p0Off)),
            abi.encodePacked(uint32(p1Off)),
            p0_payload,
            p1_payload
        );

        bytes memory params = bytes.concat(
            bytes8(keccak256("PrivateCampaignConfig")),
            abi.encodePacked(uint8(ver)),
            abi.encodePacked(uint64(start)),
            abi.encodePacked(uint256(totalTokens)),
            abi.encodePacked(uint16(epochs)),
            abi.encodePacked(uint32(e0Off)),
            e0
        );

        vm.expectRevert(PrivateCampaignConfig.PositionPayloadsOverlap.selector);
        harness.validateParams(params);
    }

    // 15) Validate reverts: PositionsNotTightlyPacked when:
    //     - posOffsets are not exactly contiguous (each payload must start at previous end), or
    //     - after the last position there is slack before epoch end

    function test_PositionsNotTightlyPacked_NonContiguous_Revert() public {
        uint8 ver = 1;
        uint64 start = 11111;
        uint256 totalTokens = 0;
        uint16 epochs = 1;
        uint32 offsetsBase = 51;
        uint32 idxBytes = 4 * epochs;
        uint32 e0Off = offsetsBase + idxBytes; // 55

        uint32 dur0 = 1000;
        uint8 npos0 = 2; // Two positions
        uint32 posOffsetsBase = e0Off + 5;
        uint32 p0Off = uint32(posOffsetsBase + 4 * uint32(npos0)); // Start of first position's payload

        bytes memory tlSig = hex"01";
        bytes memory tuSig = hex"02";
        bytes memory amtSig = hex"03";

        bytes memory p0_payload;
        p0_payload = _appendEval(p0_payload, 0x111, 1, 32, tlSig);
        p0_payload = _appendEval(p0_payload, 0x222, 1, 32, tuSig);
        p0_payload = _appendEval(p0_payload, 0x333, 2, 128, amtSig);

        bytes memory p1_payload;
        p1_payload = _appendEval(p1_payload, 0x444, 1, 32, tlSig);
        p1_payload = _appendEval(p1_payload, 0x555, 1, 32, tuSig);
        p1_payload = _appendEval(p1_payload, 0x666, 2, 128, amtSig);

        // Calculate p1Off to create a gap (not tightly packed)
        uint32 p1Off = p0Off + uint32(p0_payload.length) + 1; // 1-byte gap

        // Create epoch payload with non-tightly packed position payloads
        bytes memory e0 = bytes.concat(
            abi.encodePacked(uint32(dur0)),
            abi.encodePacked(uint8(npos0)),
            abi.encodePacked(uint32(p0Off)),
            abi.encodePacked(uint32(p1Off)),
            p0_payload,
            // Add a byte to simulate the gap
            hex"ff",
            p1_payload
        );

        bytes memory params = bytes.concat(
            bytes8(keccak256("PrivateCampaignConfig")),
            abi.encodePacked(uint8(ver)),
            abi.encodePacked(uint64(start)),
            abi.encodePacked(uint256(totalTokens)),
            abi.encodePacked(uint16(epochs)),
            abi.encodePacked(uint32(e0Off)),
            e0
        );

        vm.expectRevert(PrivateCampaignConfig.PositionsNotTightlyPacked.selector);
        harness.validateParams(params);
    }

    function test_PositionsNotTightlyPacked_SlackBeforeEpochEnd_Revert() public {
        uint8 ver = 1;
        uint64 start = 12222;
        uint256 totalTokens = 0;
        uint16 epochs = 1;
        uint32 offsetsBase = 51;
        uint32 idxBytes = 4 * epochs;
        uint32 e0Off = offsetsBase + idxBytes; // 55

        uint32 dur0 = 1000;
        uint8 npos0 = 1; // One position
        uint32 posOffsetsBase = e0Off + 5;
        uint32 p0Off = uint32(posOffsetsBase + 4 * uint32(npos0)); // Start of first position's payload

        bytes memory tlSig = hex"01";
        bytes memory tuSig = hex"02";
        bytes memory amtSig = hex"03";

        bytes memory p0_payload;
        p0_payload = _appendEval(p0_payload, 0x111, 1, 32, tlSig);
        p0_payload = _appendEval(p0_payload, 0x222, 1, 32, tuSig);
        p0_payload = _appendEval(p0_payload, 0x333, 2, 128, amtSig);

        // Create epoch payload with slack after the last position
        bytes memory e0 = bytes.concat(
            abi.encodePacked(uint32(dur0)),
            abi.encodePacked(uint8(npos0)),
            abi.encodePacked(uint32(p0Off)),
            p0_payload,
            // Add a byte to simulate slack
            hex"ff"
        );

        bytes memory params = bytes.concat(
            bytes8(keccak256("PrivateCampaignConfig")),
            abi.encodePacked(uint8(ver)),
            abi.encodePacked(uint64(start)),
            abi.encodePacked(uint256(totalTokens)),
            abi.encodePacked(uint16(epochs)),
            abi.encodePacked(uint32(e0Off)),
            e0
        );

        vm.expectRevert(PrivateCampaignConfig.PositionsNotTightlyPacked.selector);
        harness.validateParams(params);
    }

    // 16) Validate reverts: PositionPayloadCrossesEpochBoundary when an EVAL header or its signature bytes exceed epoch bounds

    function test_PositionPayloadCrossesEpochBoundary_HeaderExceeds_Revert() public {
        uint8 ver = 1;
        uint64 start = 13333;
        uint256 totalTokens = 0;
        uint16 epochs = 1;
        uint32 offsetsBase = 51;
        uint32 idxBytes = 4 * epochs;
        uint32 e0Off = offsetsBase + idxBytes; // 55

        uint32 dur0 = 1000;
        uint8 npos0 = 1; // One position
        uint32 posOffsetsBase = e0Off + 5;
        uint32 p0Off = uint32(posOffsetsBase + 4 * uint32(npos0)); // Start of first position's payload

        bytes memory tlSig = hex"01";
        bytes memory tuSig = hex"02";
        bytes memory amtSig = hex"03";

        bytes memory p0_payload;
        p0_payload = _appendEval(p0_payload, 0x111, 1, 32, tlSig);
        p0_payload = _appendEval(p0_payload, 0x222, 1, 32, tuSig);
        p0_payload = _appendEval(p0_payload, 0x333, 2, 128, amtSig);

        // The epoch end will be set right before EVAL_FIXED_HEADER_SIZE to cause the header to exceed it
        // The length of e0 will be (5 (duration+numPositions) + 4 (posOffset)) + p0_payload length
        // We want endOff to be p0Off + EVAL_FIXED_HEADER_SIZE - 1
        // To achieve this, e0 length should be (EVAL_FIXED_HEADER_SIZE - 1 - p0Off) + 5 + 4
        uint32 expectedEpochEnd = p0Off + 36 - 1; // EVAL_FIXED_HEADER_SIZE is 36

        bytes memory e0 = bytes.concat(
            abi.encodePacked(uint32(dur0)),
            abi.encodePacked(uint8(npos0)),
            abi.encodePacked(uint32(p0Off)),
            // The payload will effectively be truncated to cause the revert
            new bytes(expectedEpochEnd - p0Off)
        );

        bytes memory params = bytes.concat(
            bytes8(keccak256("PrivateCampaignConfig")),
            abi.encodePacked(uint8(ver)),
            abi.encodePacked(uint64(start)),
            abi.encodePacked(uint256(totalTokens)),
            abi.encodePacked(uint16(epochs)),
            abi.encodePacked(uint32(e0Off)),
            e0
        );

        vm.expectRevert(PrivateCampaignConfig.PositionPayloadCrossesEpochBoundary.selector);
        harness.validateParams(params);
    }

    function test_PositionPayloadCrossesEpochBoundary_SignatureExceeds_Revert() public {
        uint8 ver = 1;
        uint64 start = 14444;
        uint256 totalTokens = 0;
        uint16 epochs = 1;
        uint32 offsetsBase = 51;
        uint32 idxBytes = 4 * epochs;
        uint32 e0Off = offsetsBase + idxBytes; // 55

        uint32 dur0 = 1000;
        uint8 npos0 = 1; // One position
        uint32 posOffsetsBase = e0Off + 5;
        uint32 p0Off = uint32(posOffsetsBase + 4 * uint32(npos0)); // Start of first position's payload

        bytes memory tlSig = hex"0102030405"; // A signature with some length
        bytes memory tuSig = hex"02";
        bytes memory amtSig = hex"03";

        bytes memory p0_payload_template;
        p0_payload_template = _appendEval(p0_payload_template, 0x111, 1, 32, tlSig);
        p0_payload_template = _appendEval(p0_payload_template, 0x222, 1, 32, tuSig);
        p0_payload_template = _appendEval(p0_payload_template, 0x333, 2, 128, amtSig);

        // The epoch end will be set exactly at the end of the EVAL fixed header.
        // This means the signature bytes of the tickLower EVAL will extend beyond the epoch boundary.
        uint32 expectedEpochEnd = p0Off + 36; // EVAL_FIXED_HEADER_SIZE is 36

        bytes memory e0 = bytes.concat(
            abi.encodePacked(uint32(dur0)),
            abi.encodePacked(uint8(npos0)),
            abi.encodePacked(uint32(p0Off)),
            // Truncate the payload precisely at the end of the fixed header for tickLower's EVAL
            new bytes(expectedEpochEnd - p0Off)
        );

        bytes memory params = bytes.concat(
            bytes8(keccak256("PrivateCampaignConfig")),
            abi.encodePacked(uint8(ver)),
            abi.encodePacked(uint64(start)),
            abi.encodePacked(uint256(totalTokens)),
            abi.encodePacked(uint16(epochs)),
            abi.encodePacked(uint32(e0Off)),
            e0
        );

        vm.expectRevert(PrivateCampaignConfig.PositionPayloadCrossesEpochBoundary.selector);
        harness.validateParams(params);
    }

    // 17) Accessors revert appropriately if malformed payload causes _read beyond params (e.g., truncated EVAL) -> OutOfBounds

    function test_OutOfBounds_TruncatedCtHash_Revert() public {
        uint8 ver = 1;
        uint64 start = 15555;
        uint256 totalTokens = 0;
        uint16 epochs = 1;
        uint32 offsetsBase = 51;
        uint32 idxBytes = 4 * epochs;
        uint32 e0Off = offsetsBase + idxBytes; // 55

        uint32 dur0 = 1000;
        uint8 npos0 = 1;
        uint32 posOffsetsBase = e0Off + 5;
        uint32 p0Off = uint32(posOffsetsBase + 4 * uint32(npos0)); // Start of first position's payload

        // Create an epoch payload where the first EVAL (tickLower) is truncated within its ctHash field
        // bytes memory e0 = bytes.concat(
        //     abi.encodePacked(uint32(dur0)),
        //     abi.encodePacked(uint8(npos0)),
        //     abi.encodePacked(uint32(p0Off)),
        //     hex"0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f" // 31 bytes (one byte short of ctHash)
        // );

        bytes memory params = bytes.concat(
            bytes8(keccak256("PrivateCampaignConfig")),
            abi.encodePacked(uint8(ver)),
            abi.encodePacked(uint64(start)),
            abi.encodePacked(uint256(totalTokens)),
            abi.encodePacked(uint16(epochs)),
            abi.encodePacked(uint32(e0Off)),
            abi.encodePacked(uint32(dur0)),
            abi.encodePacked(uint8(npos0)),
            abi.encodePacked(uint32(p0Off)),
            hex"0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f" // 31 bytes (one byte short of ctHash)
        );

        vm.expectRevert(PrivateCampaignConfig.PositionPayloadCrossesEpochBoundary.selector);
        harness.getTickLower(params, 0, 0);
    }

    function test_OutOfBounds_TruncatedSecurityZone_Revert() public {
        uint8 ver = 1;
        uint64 start = 16666;
        uint256 totalTokens = 0;
        uint16 epochs = 1;
        uint32 offsetsBase = 51;
        uint32 idxBytes = 4 * epochs;
        uint32 e0Off = offsetsBase + idxBytes; // 55

        uint32 dur0 = 1000;
        uint8 npos0 = 1;
        uint32 posOffsetsBase = e0Off + 5;
        uint32 p0Off = uint32(posOffsetsBase + 4 * uint32(npos0)); // Start of first position's payload

        // Create an epoch payload where the first EVAL (tickLower) is truncated within its securityZone field
        bytes memory e0 = bytes.concat(
            abi.encodePacked(uint32(dur0)),
            abi.encodePacked(uint8(npos0)),
            abi.encodePacked(uint32(p0Off)),
            hex"0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20" // 32 bytes (ctHash is complete, but securityZone is missing)
        );

        bytes memory params = bytes.concat(
            bytes8(keccak256("PrivateCampaignConfig")),
            abi.encodePacked(uint8(ver)),
            abi.encodePacked(uint64(start)),
            abi.encodePacked(uint256(totalTokens)),
            abi.encodePacked(uint16(epochs)),
            abi.encodePacked(uint32(e0Off)),
            e0
        );

        vm.expectRevert(PrivateCampaignConfig.PositionPayloadCrossesEpochBoundary.selector);
        harness.getTickLower(params, 0, 0);
    }

    function test_OutOfBounds_TruncatedUtype_Revert() public {
        uint8 ver = 1;
        uint64 start = 17777;
        uint256 totalTokens = 0;
        uint16 epochs = 1;
        uint32 offsetsBase = 51;
        uint32 idxBytes = 4 * epochs;
        uint32 e0Off = offsetsBase + idxBytes; // 55

        uint32 dur0 = 1000;
        uint8 npos0 = 1;
        uint32 posOffsetsBase = e0Off + 5;
        uint32 p0Off = uint32(posOffsetsBase + 4 * uint32(npos0)); // Start of first position's payload

        // Create an epoch payload where the first EVAL (tickLower) is truncated within its utype field
        bytes memory e0 = bytes.concat(
            abi.encodePacked(uint32(dur0)),
            abi.encodePacked(uint8(npos0)),
            abi.encodePacked(uint32(p0Off)),
            hex"0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f2021" // 33 bytes (ctHash + securityZone complete, utype missing)
        );

        bytes memory params = bytes.concat(
            bytes8(keccak256("PrivateCampaignConfig")),
            abi.encodePacked(uint8(ver)),
            abi.encodePacked(uint64(start)),
            abi.encodePacked(uint256(totalTokens)),
            abi.encodePacked(uint16(epochs)),
            abi.encodePacked(uint32(e0Off)),
            e0
        );

        vm.expectRevert(PrivateCampaignConfig.PositionPayloadCrossesEpochBoundary.selector);
        harness.getTickLower(params, 0, 0);
    }

    function test_OutOfBounds_TruncatedSigLen_Revert() public {
        uint8 ver = 1;
        uint64 start = 18888;
        uint256 totalTokens = 0;
        uint16 epochs = 1;
        uint32 offsetsBase = 51;
        uint32 idxBytes = 4 * epochs;
        uint32 e0Off = offsetsBase + idxBytes; // 55

        uint32 dur0 = 1000;
        uint8 npos0 = 1;
        uint32 posOffsetsBase = e0Off + 5;
        uint32 p0Off = uint32(posOffsetsBase + 4 * uint32(npos0)); // Start of first position's payload

        // Create an epoch payload where the first EVAL (tickLower) is truncated within its sigLen field
        bytes memory e0 = bytes.concat(
            abi.encodePacked(uint32(dur0)),
            abi.encodePacked(uint8(npos0)),
            abi.encodePacked(uint32(p0Off)),
            hex"0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122" // 34 bytes (ctHash + securityZone + utype complete, one byte of sigLen missing)
        );

        bytes memory params = bytes.concat(
            bytes8(keccak256("PrivateCampaignConfig")),
            abi.encodePacked(uint8(ver)),
            abi.encodePacked(uint64(start)),
            abi.encodePacked(uint256(totalTokens)),
            abi.encodePacked(uint16(epochs)),
            abi.encodePacked(uint32(e0Off)),
            e0
        );

        vm.expectRevert(PrivateCampaignConfig.PositionPayloadCrossesEpochBoundary.selector);
        harness.getTickLower(params, 0, 0);
    }

    function test_OutOfBounds_TruncatedSignature_Revert() public {
        uint8 ver = 1;
        uint64 start = 19999;
        uint256 totalTokens = 0;
        uint16 epochs = 1;
        uint32 offsetsBase = 51;
        uint32 idxBytes = 4 * epochs;
        uint32 e0Off = offsetsBase + idxBytes; // 55

        uint32 dur0 = 1000;
        uint8 npos0 = 1;
        uint32 posOffsetsBase = e0Off + 5;
        uint32 p0Off = uint32(posOffsetsBase + 4 * uint32(npos0)); // Start of first position's payload

        uint16 sigLen = 5; // A signature length of 5 bytes
        // Create an EVAL header with this sigLen
        bytes memory evalHeader = bytes.concat(
            bytes32(uint256(0x111)), // ctHash
            bytes1(uint8(1)), // securityZone
            bytes1(uint8(32)), // utype
            bytes2(sigLen) // sigLen
        );

        // The `e0` payload will be constructed such that the EVAL header fits, but the signature
        // is truncated within the params array, triggering OutOfBounds when _readBytes attempts to read it.
        bytes memory e0 = bytes.concat(
            abi.encodePacked(uint32(dur0)),
            abi.encodePacked(uint8(npos0)),
            abi.encodePacked(uint32(p0Off)),
            evalHeader, // EVAL fixed header is complete
            new bytes(sigLen - 1) // Truncate signature by 1 byte, so _readBytes will fail
        );

        bytes memory params = bytes.concat(
            bytes8(keccak256("PrivateCampaignConfig")),
            abi.encodePacked(uint8(ver)),
            abi.encodePacked(uint64(start)),
            abi.encodePacked(uint256(totalTokens)),
            abi.encodePacked(uint16(epochs)),
            abi.encodePacked(uint32(e0Off)),
            e0
        );

        // No call to validate here, as we are specifically testing direct accessor behavior on malformed input
        vm.expectRevert(PrivateCampaignConfig.PositionPayloadCrossesEpochBoundary.selector);
        harness.getTickLower(params, 0, 0);
    }
}
