// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;
import {InEuint32, InEuint128} from "@fhenixprotocol/cofhe-contracts/ICofhe.sol";

/**
 * @title PrivateCampaignConfig
 * @notice Library for encoding and validating packed campaign configuration data with encrypted fields
 * @dev This library documents a compact, versioned packed-bytes format for PRIVATE configs where
 *      field values are provided as COFHE inbound encrypted integers (InEuintX). It preserves
 *      random access via indices while storing self-delimiting encrypted values (EVALs).
 *      Decryption of source values occurs off-chain during config preparation; the on-chain parser
 *      stores/transmits only the encrypted inputs and performs no plaintext decoding itself.
 *
 *      IMPORTANT: Always call validate(params) ONCE on any untrusted payload before using the
 *      read helpers in this library. Validation asserts structural and packing invariants. Without
 *      a prior validate(params) call, consistency is not guaranteed and helper functions may revert
 *      with generic bounds errors on malformed inputs.
 *
 * ## Encoding Format (Version 1)
 *
 * The configuration is encoded as a tightly packed byte array with the following structure:
 *
 * ### Signature + Header (51 bytes total):
 * - `signature`: bytes8 - Magic signature (first 8 bytes of keccak256("PrivateCampaignConfig"))
 * - `version`: uint8 (1 byte) - Format version for future compatibility
 * - `startingTime`: uint64 (8 bytes) - Campaign start timestamp (seconds since epoch)
 * - `totalTokensToSell`: uint256 (32 bytes)
 * - `numEpochs`: uint16 (2 bytes) - Total number of epochs in the campaign
 *
 * ### Epoch Index Section:
 * - `epochOffsets[numEpochs]`: uint32[numEpochs] (4 bytes each)
 *   Absolute offsets (from the start of the config bytes) to each epoch's start
 *
 * ### For each epoch at its indexed offset:
 * - `durationSeconds`: uint32 (4 bytes)
 * - `numPositions`: uint8 (1 byte)
 * - `posOffsets[numPositions]`: uint32[numPositions] – absolute offsets to each position's payload
 * - positions region: concatenation of position payloads
 *
 * ### For each position at its `posOffsets[i]`:
 * - `tickLower`: EVAL(InEuint32)
 * - `tickUpper`: EVAL(InEuint32)
 * - `amountAllocated`: EVAL(InEuint128)
 *
 * ### EVAL (Encrypted Value) layout for any InEuintX:
 * - `ctHash`: uint256 (32 bytes)
 * - `securityZone`: uint8 (1 byte)
 * - `utype`: uint8 (1 byte) — COFHE runtime type id
 * - `sigLen`: uint16 (2 bytes) — length of `signature`
 * - `signature`: bytes — `sigLen` bytes
 *
 * This layout stores exactly what is needed to reconstruct the corresponding `InEuintX` struct in memory:
 * `{ ctHash, securityZone, utype, signature }`.
 *
 * ### Tick encoding notes
 * - There is no `InEuint24`; ticks are provided as `InEuint32`.
 *
 *
 * ## Example Structure:
 * ```
 * [8-byte signature][version][startingTime][totalTokensToSell][numEpochs]
 * [index: epoch0(4B), epoch1(4B), ...]
 * [epoch @ offset: duration:4B][numPos:1B][posOffsets...][positions...]
 * [position @ posOffset: tickLower:EVAL][tickUpper:EVAL][amountAllocated:EVAL]
 * ```
 *
 * ## Size Efficiency:
 * - Signature + Header: 51 bytes
 * - Epoch index: numEpochs × 4 bytes
 * - Per epoch: 4 bytes (duration) + 1 byte (numPositions) + numPositions×4 bytes (posOffsets)
 * - Per position: 3×EVAL (tickLower, tickUpper, amountAllocated)
 * - EVAL size is variable: 36 bytes + signature length
 *
 * ## Endianness and Offsets
 * - All multi-byte integers in this format are big-endian (network byte order).
 * 
 * @custom:gas-optimization Uses assembly for efficient calldata reading without bounds checking
 */
/// @title PrivateCampaignConfig
/// @notice Packed-bytes reader/validator for private (encrypted) campaign configurations using COFHE types.
library PrivateCampaignConfig {
    bytes8 internal constant CONFIG_SIGNATURE =
        bytes8(keccak256("PrivateCampaignConfig"));
    uint8 internal constant SUPPORTED_VERSION = 1;

    // --- Header and layout constants ---
    uint256 internal constant SIGNATURE_SIZE = 8;
    uint256 internal constant VERSION_SIZE = 1;
    uint256 internal constant STARTING_TIME_SIZE = 8;
    uint256 internal constant TOTAL_TOKENS_SIZE = 32;
    uint256 internal constant NUM_EPOCHS_SIZE = 2;

    // Header field offsets (absolute, from start of params)
    uint256 internal constant VERSION_OFFSET = SIGNATURE_SIZE; // 8
    uint256 internal constant STARTING_TIME_OFFSET = VERSION_OFFSET + VERSION_SIZE; // 9
    uint256 internal constant TOTAL_TOKENS_OFFSET = STARTING_TIME_OFFSET + STARTING_TIME_SIZE; // 17
    uint256 internal constant NUM_EPOCHS_OFFSET = TOTAL_TOKENS_OFFSET + TOTAL_TOKENS_SIZE; // 49

    // Header total size and epoch index base
    uint256 internal constant HEADER_SIZE = SIGNATURE_SIZE + VERSION_SIZE + STARTING_TIME_SIZE + TOTAL_TOKENS_SIZE + NUM_EPOCHS_SIZE; // 51
    uint256 internal constant OFFSETS_BASE = HEADER_SIZE; // epoch offsets array starts right after header
    uint256 internal constant OFFSET_ENTRY_SIZE = 4; // uint32 per index

    // Epoch layout
    uint256 internal constant DURATION_SIZE = 4; // uint32
    uint256 internal constant NUM_POSITIONS_SIZE = 1; // uint8
    uint256 internal constant EPOCH_HEADER_MIN_SIZE = DURATION_SIZE + NUM_POSITIONS_SIZE; // 5

    // EVAL (Encrypted Value) layout constants
    uint256 internal constant EVAL_CTHASH_OFFSET = 0;
    uint256 internal constant EVAL_SECURITY_ZONE_OFFSET = 32; // uint8
    uint256 internal constant EVAL_UTYPE_OFFSET = 33; // uint8
    uint256 internal constant EVAL_SIGLEN_OFFSET = 34; // uint16
    uint256 internal constant EVAL_SIGNATURE_OFFSET = 36; // start of signature bytes
    uint256 internal constant EVAL_FIXED_HEADER_SIZE = 36; // 32 + 1 + 1 + 2

    error ConfigParamsTooShort();
    error InvalidConfigSignature();
    error UnsupportedVersion(uint8 found);
    error InvalidEpochIndex();
    error BadEpochOffset();
    error BadPositionOffset();
    error BadExtractSize();
    error OutOfBounds();
    error InvalidPositionIndex();
    error NoPositionsInEpoch();
    error TimestampOverflow();
    error OffsetsNotStrictlyIncreasing();
    error EpochPayloadTooShort();
    error PositionPayloadCrossesEpochBoundary();
    error PositionOffsetsNotStrictlyIncreasing();
    error PositionPayloadsOverlap();
    error EpochsNotTightlyPacked();
    error PositionsNotTightlyPacked();
    error NoEpochs();

    /// @dev Ensures `params` has the expected magic signature and supported version
    ///      before allowing any reads. Also checks the minimum header length.
    modifier onlySigned(bytes calldata params) {
        // Require at least the full header to be present before any reads
        if (params.length < HEADER_SIZE) revert ConfigParamsTooShort();

        // Read first SIGNATURE_SIZE bytes directly from calldata for precise erroring
        uint64 sig;
        assembly ("memory-safe") {
            sig := shr(192, calldataload(params.offset))
        }
        if (bytes8(sig) != CONFIG_SIGNATURE) revert InvalidConfigSignature();

        // Enforce supported version to avoid silent misparsing of future formats
        uint8 v = uint8(params[VERSION_OFFSET]);
        if (v != SUPPORTED_VERSION) revert UnsupportedVersion(v);
        _;
    }

    /// @notice Returns the encoding format version declared in `params`.
    /// @param params Packed configuration bytes.
    /// @return Format version byte.
    function version(
        bytes calldata params
    ) internal pure onlySigned(params) returns (uint8) {
        return uint8(_read(params, uint32(VERSION_OFFSET), uint8(VERSION_SIZE)));
    }

    /// @notice Returns the global campaign start timestamp (seconds since epoch).
    /// @param params Packed configuration bytes.
    /// @return Campaign starting time.
    function startingTime(
        bytes calldata params
    ) internal pure onlySigned(params) returns (uint64) {
        return uint64(_read(params, uint32(STARTING_TIME_OFFSET), uint8(STARTING_TIME_SIZE)));
    }

    /// @notice Returns the total number of epochs encoded in `params`.
    /// @param params Packed configuration bytes.
    /// @return Number of epochs.
    function numEpochs(
        bytes calldata params
    ) internal pure onlySigned(params) returns (uint16) {
        return uint16(_read(params, uint32(NUM_EPOCHS_OFFSET), uint8(NUM_EPOCHS_SIZE)));
    }

    /// @notice Returns the total tokens to sell as provided in the header.
    /// @dev Unlike the public config, this value is not derived; it is stored
    ///      as a 32-byte big-endian integer in the header.
    /// @param params Packed configuration bytes.
    /// @return totalTokensToSellHeader The value from the header.
    function totalTokensToSell(
        bytes calldata params
    ) internal pure onlySigned(params) returns (uint256) {
        return _read(params, uint32(TOTAL_TOKENS_OFFSET), uint8(TOTAL_TOKENS_SIZE));
    }

    /// @notice Returns the duration (in seconds) of `epochNumber`.
    /// @param params Packed configuration bytes.
    /// @param epochNumber 0-based epoch index.
    /// @return Duration in seconds.
    function durationSeconds(
        bytes calldata params,
        uint16 epochNumber
    ) internal pure onlySigned(params) returns (uint32) {
        uint256 base = _epochStartOffset(params, epochNumber);
        return uint32(_read(params, base, uint8(DURATION_SIZE)));
    }

    /// @notice Returns the campaign ending timestamp.
    /// @dev Computed as `startingTime + sum(epoch.durationSeconds)` with overflow check.
    /// @param params Packed configuration bytes.
    /// @return Ending timestamp (seconds since epoch).
    function endingTime(
        bytes calldata params
    ) internal pure onlySigned(params) returns (uint64) {
        uint64 start = startingTime(params);
        uint256 sum;
        uint16 epochs = numEpochs(params);
        for (uint16 e = 0; e < epochs; e++) {
            uint256 epochOff = _epochStartOffset(params, e);
            uint32 dur = uint32(_read(params, uint32(epochOff), uint8(DURATION_SIZE)));
            sum += dur;
        }
        uint256 total = uint256(start) + sum;
        if (total > type(uint64).max) revert TimestampOverflow();
        return uint64(total);
    }

    /// @notice Returns the starting timestamp of `epochNumber`.
    /// @dev Computed as `startingTime + sum(durations of epochs < epochNumber)`.
    /// @param params Packed configuration bytes.
    /// @param epochNumber 0-based epoch index.
    /// @return Epoch starting timestamp.
    function epochStartingTime(
        bytes calldata params,
        uint16 epochNumber
    ) internal pure onlySigned(params) returns (uint64) {
        uint64 start = startingTime(params);
        uint256 sum;
        for (uint16 e = 0; e < epochNumber; e++) {
            uint256 epochOff = _epochStartOffset(params, e);
            uint32 dur = uint32(_read(params, uint32(epochOff), uint8(DURATION_SIZE)));
            sum += dur;
        }
        uint256 total = uint256(start) + sum;
        if (total > type(uint64).max) revert TimestampOverflow();
        return uint64(total);
    }

    /// @notice Returns the number of positions defined in `epochNumber`.
    /// @param params Packed configuration bytes.
    /// @param epochNumber 0-based epoch index.
    /// @return Number of positions (0-255).
    function numPositions(
        bytes calldata params,
        uint16 epochNumber
    ) internal pure onlySigned(params) returns (uint8) {
        uint256 epochOff = _epochStartOffset(params, epochNumber);
        uint256 afterDuration = epochOff + DURATION_SIZE;
        return uint8(_read(params, afterDuration, uint8(NUM_POSITIONS_SIZE)));
    }

    /// @notice Returns the encrypted lower tick bound for a position.
    /// @dev The returned struct is an `InEuint32` reconstructed from the EVAL payload.
    ///      Call `validate(params)` once on untrusted inputs before repeated reads.
    /// @param params Packed configuration bytes.
    /// @param epochNumber 0-based epoch index.
    /// @param positionIndex 0-based position index within the epoch.
    /// @return Encrypted int32 tick lower value (COFHE input type wrapper).
    function tickLower(
        bytes calldata params,
        uint16 epochNumber,
        uint8 positionIndex
    ) internal pure onlySigned(params) returns (InEuint32 memory) {
        (uint256 posOffset, ) = _positionOffset(
            params,
            epochNumber,
            positionIndex
        );
        uint256 epochEnd = _epochEndOffset(params, epochNumber);
        (InEuint32 memory value, ) = _readInEuint32AtBounded(params, posOffset, epochEnd);
        return value;
    }

    /// @notice Returns the encrypted upper tick bound for a position.
    /// @dev The returned struct is an `InEuint32` reconstructed from the EVAL payload.
    /// @param params Packed configuration bytes.
    /// @param epochNumber 0-based epoch index.
    /// @param positionIndex 0-based position index within the epoch.
    /// @return Encrypted int32 tick upper value (COFHE input type wrapper).
    function tickUpper(
        bytes calldata params,
        uint16 epochNumber,
        uint8 positionIndex
    ) internal pure onlySigned(params) returns (InEuint32 memory) {
        (uint256 posOffset, ) = _positionOffset(
            params,
            epochNumber,
            positionIndex
        );
        uint256 epochEnd = _epochEndOffset(params, epochNumber);
        (, uint256 nextOffset) = _readInEuint32AtBounded(params, posOffset, epochEnd);
        (InEuint32 memory value2, ) = _readInEuint32AtBounded(params, nextOffset, epochEnd);
        return value2;
    }

    /// @notice Returns the encrypted token amount allocated to a position.
    /// @dev The returned struct is an `InEuint128` reconstructed from the EVAL payload.
    /// @param params Packed configuration bytes.
    /// @param epochNumber 0-based epoch index.
    /// @param positionIndex 0-based position index within the epoch.
    /// @return Encrypted uint128 amount (COFHE input type wrapper).
    function amountAllocated(
        bytes calldata params,
        uint16 epochNumber,
        uint8 positionIndex
    ) internal pure onlySigned(params) returns (InEuint128 memory) {
        (uint256 posOffset, ) = _positionOffset(
            params,
            epochNumber,
            positionIndex
        );
        uint256 epochEnd = _epochEndOffset(params, epochNumber);
        (, uint256 afterLower) = _readInEuint32AtBounded(params, posOffset, epochEnd);
        (, uint256 afterUpper) = _readInEuint32AtBounded(params, afterLower, epochEnd);
        (InEuint128 memory value3, ) = _readInEuint128AtBounded(params, afterUpper, epochEnd);
        return value3;
    }

    /// @dev Reads `size` bytes from `params` at absolute `offset` as big-endian, returning a right-aligned uint256.
    ///      Reverts on out-of-bounds or invalid sizes (0 or > 32).
    function _read(
        bytes calldata params,
        uint256 offset,
        uint8 size
    ) private pure returns (uint256 r) {
        if (!(size > 0 && size <= 32)) revert BadExtractSize();
        if (offset + uint256(size) > params.length)
            revert OutOfBounds();
        assembly ("memory-safe") {
            r := shr(
                mul(sub(32, size), 8),
                calldataload(add(params.offset, offset))
            )
        }
    }

    /// @dev Skips over one EVAL payload starting at `start` without additional bounds beyond params length.
    /// @return next Absolute offset immediately after the EVAL payload.
    function _skipEval(
        bytes calldata params,
        uint256 start
    ) private pure returns (uint256 next) {
        // Fixed header then signature bytes
        uint16 sigLen = uint16(_read(params, start + EVAL_SIGLEN_OFFSET, 2));
        uint256 end = start + EVAL_FIXED_HEADER_SIZE + uint256(sigLen);
        if (end > params.length) revert OutOfBounds();
        return end;
    }

    /// @dev Like `_skipEval` but asserts the full EVAL fits inside the current epoch window `[start, epochEnd)`.
    /// @return next Absolute offset immediately after the EVAL payload.
    function _nextAfterEvalBounded(
        bytes calldata params,
        uint256 start,
        uint256 epochEnd
    ) private pure returns (uint256 next) {
        // Ensure the EVAL header fits within the epoch window before reading
        if (start + EVAL_FIXED_HEADER_SIZE > epochEnd) revert PositionPayloadCrossesEpochBoundary();
        uint16 sigLen = uint16(_read(params, start + EVAL_SIGLEN_OFFSET, 2));
        uint256 end = start + EVAL_FIXED_HEADER_SIZE + uint256(sigLen);
        if (end > epochEnd) revert PositionPayloadCrossesEpochBoundary();
        return end;
    }

    /// @dev Parses an `InEuint32` EVAL payload starting at `start` and returns the struct and next offset.
    function _readInEuint32At(
        bytes calldata params,
        uint256 start
    ) private pure returns (InEuint32 memory value, uint256 next) {
        uint256 ctHash = _read(params, start + EVAL_CTHASH_OFFSET, 32);
        uint8 securityZone = uint8(_read(params, start + EVAL_SECURITY_ZONE_OFFSET, 1));
        uint8 utype = uint8(_read(params, start + EVAL_UTYPE_OFFSET, 1));
        uint16 sigLen = uint16(_read(params, start + EVAL_SIGLEN_OFFSET, 2));
        bytes memory signature = _readBytes(params, start + EVAL_SIGNATURE_OFFSET, sigLen);
        value = InEuint32({
            ctHash: ctHash,
            securityZone: securityZone,
            utype: utype,
            signature: signature
        });
        next = _skipEval(params, start);
    }

    /// @dev Parses an `InEuint32` EVAL payload ensuring it does not cross `epochEnd`.
    function _readInEuint32AtBounded(
        bytes calldata params,
        uint256 start,
        uint256 epochEnd
    ) private pure returns (InEuint32 memory value, uint256 next) {
        // Ensure the EVAL header fits within the epoch window before reading
        if (start + EVAL_FIXED_HEADER_SIZE > epochEnd) revert PositionPayloadCrossesEpochBoundary();
        uint16 sigLen = uint16(_read(params, start + EVAL_SIGLEN_OFFSET, 2));
        uint256 end = start + EVAL_FIXED_HEADER_SIZE + uint256(sigLen);
        if (end > epochEnd) revert PositionPayloadCrossesEpochBoundary();
        uint256 ctHash = _read(params, start + EVAL_CTHASH_OFFSET, 32);
        uint8 securityZone = uint8(_read(params, start + EVAL_SECURITY_ZONE_OFFSET, 1));
        uint8 utype = uint8(_read(params, start + EVAL_UTYPE_OFFSET, 1));
        bytes memory signature = _readBytes(params, start + EVAL_SIGNATURE_OFFSET, uint256(sigLen));
        value = InEuint32({
            ctHash: ctHash,
            securityZone: securityZone,
            utype: utype,
            signature: signature
        });
        next = end;
    }

    /// @dev Parses an `InEuint128` EVAL payload starting at `start` and returns the struct and next offset.
    function _readInEuint128At(
        bytes calldata params,
        uint256 start
    ) private pure returns (InEuint128 memory value, uint256 next) {
        uint256 ctHash = _read(params, start + EVAL_CTHASH_OFFSET, 32);
        uint8 securityZone = uint8(_read(params, start + EVAL_SECURITY_ZONE_OFFSET, 1));
        uint8 utype = uint8(_read(params, start + EVAL_UTYPE_OFFSET, 1));
        uint16 sigLen = uint16(_read(params, start + EVAL_SIGLEN_OFFSET, 2));
        bytes memory signature = _readBytes(params, start + EVAL_SIGNATURE_OFFSET, sigLen);
        value = InEuint128({
            ctHash: ctHash,
            securityZone: securityZone,
            utype: utype,
            signature: signature
        });
        next = _skipEval(params, start);
    }

    /// @dev Parses an `InEuint128` EVAL payload ensuring it does not cross `epochEnd`.
    function _readInEuint128AtBounded(
        bytes calldata params,
        uint256 start,
        uint256 epochEnd
    ) private pure returns (InEuint128 memory value, uint256 next) {
        // Ensure the EVAL header fits within the epoch window before reading
        if (start + EVAL_FIXED_HEADER_SIZE > epochEnd) revert PositionPayloadCrossesEpochBoundary();
        uint16 sigLen = uint16(_read(params, start + EVAL_SIGLEN_OFFSET, 2));
        uint256 end = start + EVAL_FIXED_HEADER_SIZE + uint256(sigLen);
        if (end > epochEnd) revert PositionPayloadCrossesEpochBoundary();
        uint256 ctHash = _read(params, start + EVAL_CTHASH_OFFSET, 32);
        uint8 securityZone = uint8(_read(params, start + EVAL_SECURITY_ZONE_OFFSET, 1));
        uint8 utype = uint8(_read(params, start + EVAL_UTYPE_OFFSET, 1));
        bytes memory signature = _readBytes(params, start + EVAL_SIGNATURE_OFFSET, uint256(sigLen));
        value = InEuint128({
            ctHash: ctHash,
            securityZone: securityZone,
            utype: utype,
            signature: signature
        });
        next = end;
    }

    /// @dev Reads position offsets table to resolve the absolute offset for `positionIndex` within `epochNumber`.
    ///      Also enforces basic bounds relative to the epoch window.
    /// @return posOffset Absolute byte offset for the start of the position payload.
    /// @return count Number of positions in the epoch.
    function _positionOffset(
        bytes calldata params,
        uint16 epochNumber,
        uint8 positionIndex
    ) private pure returns (uint256 posOffset, uint8 count) {
        uint256 epochOff = _epochStartOffset(params, epochNumber);
        uint256 afterDuration = epochOff + DURATION_SIZE;
        count = uint8(_read(params, afterDuration, 1));
        if (positionIndex >= count) revert InvalidPositionIndex();
        uint256 posOffsetsBase = afterDuration + NUM_POSITIONS_SIZE;
        posOffset = _read(params, posOffsetsBase + uint256(positionIndex) * OFFSET_ENTRY_SIZE, uint8(OFFSET_ENTRY_SIZE));

        // Harden: ensure position payloads are placed after the posOffsets array
        uint256 posOffsetsEnd = posOffsetsBase + uint256(count) * OFFSET_ENTRY_SIZE;
        // Determine the end boundary of this epoch using validated next epoch offset
        uint256 epochEnd = _epochEndOffset(params, epochNumber);

        // Bounds: posOffset must be within [posOffsetsEnd, epochEnd)
        if (posOffset < posOffsetsEnd || posOffset >= epochEnd) revert BadPositionOffset();
    }

    /// @dev Copies `length` bytes from calldata `params` at `offset` into a new bytes array.
    function _readBytes(
        bytes calldata params,
        uint256 offset,
        uint256 length
    ) private pure returns (bytes memory out) {
        if (offset + length > params.length)
            revert OutOfBounds();
        out = new bytes(length);
        assembly ("memory-safe") {
            calldatacopy(add(out, 32), add(params.offset, offset), length)
        }
    }

    /// @notice Validate epoch index and payload layout for monotonicity and size bounds (epoch-level)
    /// @dev IMPORTANT: Call once on any untrusted `params` before using other read helpers.
    ///      Reverts if any invariant fails; on success it guarantees subsequent reads are safe
    ///      under the validated packing assumptions.
    function validate(
        bytes calldata params
    ) internal pure onlySigned(params) {
        // Read numEpochs directly to avoid invoking any functions that are guarded by the modifier
        uint16 epochs = uint16(_read(params, uint32(NUM_EPOCHS_OFFSET), uint8(NUM_EPOCHS_SIZE)));
        if (epochs == 0) revert NoEpochs();
        // Offsets table immediately follows the header
        uint256 offsetsBase = OFFSETS_BASE;
        uint256 indexBytes = uint256(epochs) * OFFSET_ENTRY_SIZE;
        if (params.length < offsetsBase + indexBytes) revert ConfigParamsTooShort();

        uint256 minEpochArea = offsetsBase + indexBytes;

        // Pass 1: validate bounds and strict monotonicity of epoch offsets
        uint256 prev;
        for (uint16 e = 0; e < epochs; e++) {
            uint256 abs = _read(params, offsetsBase + uint256(e) * OFFSET_ENTRY_SIZE, uint8(OFFSET_ENTRY_SIZE));
            if (abs < minEpochArea || abs >= params.length) revert BadEpochOffset();
            if (e != 0 && abs <= prev) revert OffsetsNotStrictlyIncreasing();
            // Enforce tight packing of epoch 0: it must start right after the offsets table
            if (e == 0 && abs != minEpochArea) revert EpochsNotTightlyPacked();
            prev = abs;
        }

        // Pass 2: validate each epoch header and that position offsets array fits in the epoch window
        for (uint16 e = 0; e < epochs; e++) {
            uint256 startOff = _read(params, offsetsBase + uint256(e) * OFFSET_ENTRY_SIZE, uint8(OFFSET_ENTRY_SIZE));
            uint256 endOff = (e + 1 < epochs)
                ? _read(params, offsetsBase + uint256(e + 1) * OFFSET_ENTRY_SIZE, uint8(OFFSET_ENTRY_SIZE))
                : params.length;

            // At least 5 bytes required for [duration(4) + numPositions(1)]
            if (endOff < startOff + EPOCH_HEADER_MIN_SIZE) revert EpochPayloadTooShort();

            uint8 count = uint8(_read(params, startOff + DURATION_SIZE, uint8(NUM_POSITIONS_SIZE)));
            if (count == 0) revert NoPositionsInEpoch();
            uint256 posOffsetsBase = startOff + EPOCH_HEADER_MIN_SIZE;
            uint256 required = posOffsetsBase + uint256(count) * OFFSET_ENTRY_SIZE;
            if (required > endOff) revert EpochPayloadTooShort();

            // Pass 2b: validate each position has 3 full EVALs within [posOffsetsEnd, endOff)
            uint256 posOffsetsEnd = required;
            uint256 prevPosOff;
            uint256 prevEnd;
            uint256 expectedNext = posOffsetsEnd;
            for (uint8 i = 0; i < count; i++) {
                uint256 posOff = _read(params, posOffsetsBase + uint256(i) * OFFSET_ENTRY_SIZE, uint8(OFFSET_ENTRY_SIZE));
                if (posOff < posOffsetsEnd || posOff >= endOff) revert BadPositionOffset();
                if (i != 0) {
                    if (posOff <= prevPosOff) revert PositionOffsetsNotStrictlyIncreasing();
                    if (posOff < prevEnd) revert PositionPayloadsOverlap();
                }
                // Enforce tight packing for positions: each payload starts exactly where the previous ended
                if (posOff != expectedNext) revert PositionsNotTightlyPacked();
                uint256 next1 = _nextAfterEvalBounded(params, posOff, endOff);
                uint256 next2 = _nextAfterEvalBounded(params, next1, endOff);
                uint256 endPos = _nextAfterEvalBounded(params, next2, endOff);
                prevPosOff = posOff;
                prevEnd = endPos;
                expectedNext = endPos;
            }
            // After the last position, enforce there is no slack before the epoch end
            if (expectedNext != endOff) revert PositionsNotTightlyPacked();
        }
    }

    /// @notice Returns the absolute byte offset (from start of `params`) where epoch `epochNumber` begins.
    /// @dev Layout: [51-byte header][4-byte offsets × numEpochs][epoch payloads...]
    /// @param params Packed configuration bytes.
    /// @param epochNumber 0-based epoch index.
    /// @return Absolute start offset for the epoch payload.
    function _epochStartOffset(
        bytes calldata params,
        uint16 epochNumber
    ) private pure returns (uint256) {
        uint16 epochs = numEpochs(params);
        if (epochNumber >= epochs) revert InvalidEpochIndex();

        // Offsets array starts right after the header
        uint256 offsetsBase = OFFSETS_BASE;
        uint256 entryOffset = offsetsBase + uint256(epochNumber) * OFFSET_ENTRY_SIZE;
        uint256 absOffset = _read(params, entryOffset, uint8(OFFSET_ENTRY_SIZE));
        // Basic sanity: must be within params and after the offsets table
        uint256 minEpochArea = offsetsBase + uint256(epochs) * OFFSET_ENTRY_SIZE;
        if (absOffset < minEpochArea || absOffset >= params.length)
            revert BadEpochOffset();
        return absOffset;
    }

    /// @dev Returns the absolute byte offset where `epochNumber` ends (start of next epoch or `params.length`).
    /// @param params Packed configuration bytes.
    /// @param epochNumber 0-based epoch index.
    /// @return Absolute end offset for the epoch payload window.
    function _epochEndOffset(
        bytes calldata params,
        uint16 epochNumber
    ) private pure returns (uint256) {
        uint16 epochs = numEpochs(params);
        uint256 offsetsBase = OFFSETS_BASE;
        uint256 currentStart = _epochStartOffset(params, epochNumber);
        if (epochNumber + 1 < epochs) {
            uint256 nextEpochOff = _read(params, offsetsBase + uint256(epochNumber + 1) * OFFSET_ENTRY_SIZE, uint8(OFFSET_ENTRY_SIZE));
            uint256 minEpochArea = offsetsBase + uint256(epochs) * OFFSET_ENTRY_SIZE;
            if (nextEpochOff < minEpochArea || nextEpochOff > params.length) revert BadEpochOffset();
            if (nextEpochOff <= currentStart) revert OffsetsNotStrictlyIncreasing();
            return nextEpochOff;
        } else {
            return params.length;
        }
    }
}
