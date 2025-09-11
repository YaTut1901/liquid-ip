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
 * ## Encoding Format (Version 1)
 *
 * The configuration is encoded as a tightly packed byte array with the following structure:
 *
 * ### Signature + Header (45 bytes total):
 * - `signature`: bytes2 - Magic signature (first 2 bytes of keccak256("PrivateCampaignConfig"))
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
 * [2-byte signature][version][startingTime][totalTokensToSell][numEpochs]
 * [index: epoch0(4B), epoch1(4B), ...]
 * [epoch @ offset: duration:4B][numPos:1B][posOffsets...][positions...]
 * [position @ posOffset: tickLower:EVAL][tickUpper:EVAL][amountAllocated:EVAL]
 * ```
 *
 * ## Size Notes:
 * - Signature + Header: 45 bytes
 * - Epoch index: numEpochs × 4 bytes
 * - Per epoch: 4 bytes (duration) + 1 byte (numPositions) + numPositions×4 bytes (posOffsets)
 * - Per position: 3×EVAL (tickLower, tickUpper, amountAllocated)
 * - EVAL size is variable: 36 bytes + signature length
 *
 * @custom:gas-optimization Uses assembly for efficient calldata reading without bounds checking
 */
library PrivateCampaignConfig {
    bytes2 internal constant CONFIG_SIGNATURE =
        bytes2(keccak256("PrivateCampaignConfig"));

    error ConfigParamsTooShort();
    error InvalidConfigSignature();
    error InvalidEpochIndex();
    error BadEpochOffset();
    error BadExtractSize();
    error OutOfBounds();
    error InvalidPositionIndex();
    error NoPositionsInEpoch();

    modifier onlySigned(bytes calldata params) {
        uint256 sig = _read(params, 0, 2);
        if (bytes2(uint16(sig)) != CONFIG_SIGNATURE)
            revert InvalidConfigSignature();
        _;
    }

    function version(
        bytes calldata params
    ) internal pure onlySigned(params) returns (uint8) {
        return uint8(_read(params, 2, 1)); // 1 byte after signature
    }

    function startingTime(
        bytes calldata params
    ) internal pure onlySigned(params) returns (uint64) {
        return uint64(_read(params, 3, 8)); // after signature + version
    }

    function numEpochs(
        bytes calldata params
    ) internal pure onlySigned(params) returns (uint16) {
        return uint16(_read(params, 43, 2)); // after signature + version + starting + total
    }

    function totalTokensToSell(
        bytes calldata params
    ) internal pure onlySigned(params) returns (uint256) {
        return _read(params, 11, 32); // after startingTime
    }

    function durationSeconds(
        bytes calldata params,
        uint16 epochNumber
    ) internal pure onlySigned(params) returns (uint32) {
        uint256 base = _epochStartOffset(params, epochNumber);
        return uint32(_read(params, uint32(base), 4));
    }

    function endingTime(
        bytes calldata params
    ) internal pure onlySigned(params) returns (uint64) {
        uint64 start = startingTime(params);
        uint256 sum;
        uint16 epochs = numEpochs(params);
        for (uint16 e = 0; e < epochs; e++) {
            uint256 epochOff = _epochStartOffset(params, e);
            uint32 dur = uint32(_read(params, uint32(epochOff), 4));
            sum += dur;
        }
        return uint64(uint256(start) + sum);
    }

    function epochStartingTime(
        bytes calldata params,
        uint16 epochNumber
    ) internal pure onlySigned(params) returns (uint64) {
        uint64 start = startingTime(params);
        uint256 sum;
        for (uint16 e = 0; e < epochNumber; e++) {
            uint256 epochOff = _epochStartOffset(params, e);
            uint32 dur = uint32(_read(params, uint32(epochOff), 4));
            sum += dur;
        }
        return uint64(uint256(start) + sum);
    }

    function numPositions(
        bytes calldata params,
        uint16 epochNumber
    ) internal pure onlySigned(params) returns (uint8) {
        uint32 epochOff = uint32(_epochStartOffset(params, epochNumber));
        uint32 afterDuration = _skipEval(params, epochOff);
        return uint8(_read(params, afterDuration, 1));
    }

    function tickLower(
        bytes calldata params,
        uint16 epochNumber,
        uint8 positionIndex
    ) internal pure onlySigned(params) returns (InEuint32 memory) {
        (uint32 posOffset,) = _positionOffset(params, epochNumber, positionIndex);
        (InEuint32 memory value,) = _readInEuint32At(params, posOffset);
        return value;
    }

    function tickUpper(
        bytes calldata params,
        uint16 epochNumber,
        uint8 positionIndex
    ) internal pure onlySigned(params) returns (InEuint32 memory) {
        (uint32 posOffset,) = _positionOffset(params, epochNumber, positionIndex);
        (, uint32 nextOffset) = _readInEuint32At(params, posOffset);
        (InEuint32 memory value2,) = _readInEuint32At(params, nextOffset);
        return value2;
    }

    function amountAllocated(
        bytes calldata params,
        uint16 epochNumber,
        uint8 positionIndex
    ) internal pure onlySigned(params) returns (InEuint128 memory) {
        (uint32 posOffset,) = _positionOffset(params, epochNumber, positionIndex);
        (, uint32 afterLower) = _readInEuint32At(params, posOffset);
        (, uint32 afterUpper) = _readInEuint32At(params, afterLower);
        (InEuint128 memory value3,) = _readInEuint128At(params, afterUpper);
        return value3;
    }

    function _read(
        bytes calldata params,
        uint32 offset,
        uint8 size
    ) private pure returns (uint256 r) {
        if (!(size > 0 && size <= 32)) revert BadExtractSize();
        if (uint256(offset) + uint256(size) > params.length)
            revert OutOfBounds();
        assembly {
            r := shr(
                mul(sub(32, size), 8),
                calldataload(add(params.offset, offset))
            )
        }
    }

    function _skipEval(
        bytes calldata params,
        uint32 start
    ) private pure returns (uint32 next) {
        // 32 + 1 + 1 + 2 = 36 bytes header before signature
        uint16 sigLen = uint16(_read(params, start + 34, 2));
        uint256 end = uint256(start) + 36 + uint256(sigLen);
        if (end > params.length) revert OutOfBounds();
        return uint32(end);
    }

    function _readInEuint32At(
        bytes calldata params,
        uint32 start
    ) private pure returns (InEuint32 memory value, uint32 next) {
        uint256 ctHash = _read(params, start, 32);
        uint8 securityZone = uint8(_read(params, start + 32, 1));
        uint8 utype = uint8(_read(params, start + 33, 1));
        uint16 sigLen = uint16(_read(params, start + 34, 2));
        bytes memory signature = _readBytes(params, start + 36, sigLen);
        value = InEuint32({
            ctHash: ctHash,
            securityZone: securityZone,
            utype: utype,
            signature: signature
        });
        next = _skipEval(params, start);
    }

    function _readInEuint128At(
        bytes calldata params,
        uint32 start
    ) private pure returns (InEuint128 memory value, uint32 next) {
        uint256 ctHash = _read(params, start, 32);
        uint8 securityZone = uint8(_read(params, start + 32, 1));
        uint8 utype = uint8(_read(params, start + 33, 1));
        uint16 sigLen = uint16(_read(params, start + 34, 2));
        bytes memory signature = _readBytes(params, start + 36, sigLen);
        value = InEuint128({
            ctHash: ctHash,
            securityZone: securityZone,
            utype: utype,
            signature: signature
        });
        next = _skipEval(params, start);
    }

    function _positionOffset(
        bytes calldata params,
        uint16 epochNumber,
        uint8 positionIndex
    ) private pure returns (uint32 posOffset, uint8 count) {
        uint32 epochOff = uint32(_epochStartOffset(params, epochNumber));
        uint32 afterDuration = epochOff + 4;
        count = uint8(_read(params, afterDuration, 1));
        if (positionIndex >= count) revert InvalidPositionIndex();
        uint32 posOffsetsBase = afterDuration + 1;
        posOffset = uint32(_read(params, posOffsetsBase + uint32(positionIndex) * 4, 4));
        // Basic sanity relative to params bounds
        if (posOffset >= params.length) revert BadEpochOffset();
    }

    function _readBytes(
        bytes calldata params,
        uint32 offset,
        uint32 length
    ) private pure returns (bytes memory out) {
        if (uint256(offset) + uint256(length) > params.length) revert OutOfBounds();
        out = new bytes(length);
        assembly {
            calldatacopy(add(out, 32), add(params.offset, offset), length)
        }
    }

    /// @notice Generic field reader for position records
    /// @param epochNumber 0-based epoch index
    /// @param positionIndex 0-based position index within epoch
    /// @param fieldOffset byte offset within a position record (0,3,6)
    /// @param size number of bytes to read (3 for ticks, 16 for amount)
    function _positionField(
        bytes calldata params,
        uint16 epochNumber,
        uint8 positionIndex,
        uint8 fieldOffset,
        uint8 size
    ) private pure onlySigned(params) returns (uint256) {
        uint256 epochOff = _epochStartOffset(params, epochNumber);
        uint8 count = uint8(_read(params, uint32(epochOff + 4), 1));
        if (positionIndex >= count) revert InvalidPositionIndex();
        uint256 posBase = epochOff + 5 + uint256(positionIndex) * 22;
        return _read(params, uint32(posBase + fieldOffset), size);
    }

    /// @notice Returns the absolute byte offset (from start of params) where epoch `epochNumber` begins
    /// @dev Layout: [45-byte header][4-byte offsets × numEpochs][epoch payloads...]
    function _epochStartOffset(
        bytes calldata params,
        uint16 epochNumber
    ) private pure onlySigned(params) returns (uint256) {
        uint16 epochs = numEpochs(params);
        if (epochNumber >= epochs) revert InvalidEpochIndex();

        // Offsets array starts right after the 45-byte header
        uint256 offsetsBase = 45;
        uint256 entryOffset = offsetsBase + uint256(epochNumber) * 4;
        uint32 absOffset = uint32(_read(params, uint32(entryOffset), 4));
        // Basic sanity: must be within params and after the offsets table
        uint256 minEpochArea = offsetsBase + uint256(epochs) * 4;
        if (absOffset < minEpochArea || absOffset >= params.length)
            revert BadEpochOffset();
        return uint256(absOffset);
    }
}
