// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/**
 * @title PublicCampaignConfig
 * @notice Library for encoding and validating packed campaign configuration data
 * @dev This library handles compact, gas-efficient encoding of campaign parameters using
 *      a versioned packed-bytes format without ABI padding overhead.
 *
 * ## Encoding Format (Version 1)
 *
 * The configuration is encoded as a tightly packed byte array with the following structure:
 *
 * ### Signature + Header (13 bytes total):
 * - `signature`: bytes2 - Magic signature (first 2 bytes of keccak256("PublicCampaignConfig"))
 * - `version`: uint8 (1 byte) - Format version for future compatibility
 * - `startingTime`: uint64 (8 bytes) - Campaign start timestamp (seconds since epoch)
 * - `numEpochs`: uint16 (2 bytes) - Total number of epochs in the campaign
 *
 * ### Epoch Index Section:
 * - `epochOffsets[numEpochs]`: uint32[numEpochs] (4 bytes each)
 *   Absolute offsets (from the start of the config bytes) to each epoch's start
 *
 * ### For each epoch (5+ bytes overhead) at its indexed offset:
 * - `durationSeconds`: uint32 (4 bytes) - Duration of this epoch in seconds
 * - `numPositions`: uint8 (1 byte) - Number of positions in this epoch (max 255)
 *
 * ### For each position within an epoch (22 bytes):
 * - `tickLower`: int24 (3 bytes) - Lower tick bound of the position
 * - `tickUpper`: int24 (3 bytes) - Upper tick bound of the position
 * - `amountAllocated`: uint128 (16 bytes) - Tokens allocated to this position
 *
 * ## Derived Values (calculated during parsing):
 * - `endingTime`: Computed as startingTime + sum(all epoch durations)
 * - `totalTokensToSell`: Computed as sum(all amountAllocated)
 * - `epochStartingTick`: Computed as max(all tickUpper per epoch)
 * - `epochStartingTime`: Computed as startingTime + sum(all previous epochs durations)
 * 
 * ## Example Structure:
 * ```
 * [2-byte signature][version][startingTime][numEpochs]
 * [index: epoch0Offset(4B), epoch1Offset(4B), ...]
 * [epoch0 @ epoch0Offset: duration][numPos0][pos0...]
 * [epoch1 @ epoch1Offset: duration][numPos1][pos0...]
 * ...
 * ```
 *
 * ## Size Efficiency:
 * - Signature + Header: 13 bytes
 * - Index: numEpochs × 4 bytes
 * - Each epoch: 5 bytes + (numPositions × 22 bytes)
 *
 * @custom:gas-optimization Uses assembly for efficient calldata reading without bounds checking
 */
library PublicCampaignConfig {
    bytes2 internal constant CONFIG_SIGNATURE =
        bytes2(keccak256("PublicCampaignConfig"));

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
        return uint64(_read(params, 3, 8)); // 8 bytes after signature + version
    }

    function numEpochs(
        bytes calldata params
    ) internal pure onlySigned(params) returns (uint16) {
        return uint16(_read(params, 11, 2)); // 2 bytes after signature + version + startingTime
    }

    function durationSeconds(
        bytes calldata params,
        uint16 epochNumber
    ) internal pure onlySigned(params) returns (uint32) {
        uint256 offset = _epochStartOffset(params, epochNumber);
        return uint32(_read(params, uint32(offset), 4)); // 4 bytes at epoch start
    }

    function numPositions(
        bytes calldata params,
        uint16 epochNumber
    ) internal pure onlySigned(params) returns (uint8) {
        uint256 offset = _epochStartOffset(params, epochNumber) + 4; // skip duration
        return uint8(_read(params, uint32(offset), 1)); // 1 byte after duration
    }

    function tickLower(
        bytes calldata params,
        uint16 epochNumber,
        uint8 positionIndex
    ) internal pure onlySigned(params) returns (int24) {
        return
            int24(
                uint24(_positionField(params, epochNumber, positionIndex, 0, 3))
            );
    }

    function tickUpper(
        bytes calldata params,
        uint16 epochNumber,
        uint8 positionIndex
    ) internal pure onlySigned(params) returns (int24) {
        return
            int24(
                uint24(_positionField(params, epochNumber, positionIndex, 3, 3))
            );
    }

    function amountAllocated(
        bytes calldata params,
        uint16 epochNumber,
        uint8 positionIndex
    ) internal pure onlySigned(params) returns (uint128) {
        return uint128(_positionField(params, epochNumber, positionIndex, 6, 16));
    }

    function totalTokensToSell(
        bytes calldata params
    ) internal pure onlySigned(params) returns (uint256) {
        uint256 total;
        uint16 epochs = numEpochs(params);
        for (uint16 e = 0; e < epochs; e++) {
            uint256 epochOff = _epochStartOffset(params, e);
            uint8 count = uint8(_read(params, uint32(epochOff + 4), 1));
            uint256 posBase = epochOff + 5;
            for (uint256 i = 0; i < count; ) {
                uint256 off = posBase + i * 22;
                uint256 amt = _read(params, uint32(off + 6), 16);
                total += amt;
                unchecked { ++i; }
            }
        }
        return total;
    }

    function epochStartingTick(
        bytes calldata params,
        uint16 epochNumber
    ) internal pure onlySigned(params) returns (int24) {
        uint256 epochOff = _epochStartOffset(params, epochNumber);
        uint8 count = uint8(_read(params, uint32(epochOff + 4), 1));
        if (count == 0) revert NoPositionsInEpoch();
        uint256 posBase = epochOff + 5;
        int24 maxUpper = type(int24).min;
        for (uint256 i = 0; i < count; ) {
            uint256 off = posBase + i * 22;
            int24 upper = int24(uint24(_read(params, uint32(off + 3), 3)));
            if (upper > maxUpper) maxUpper = upper;
            unchecked {
                ++i;
            }
        }
        return maxUpper;
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
    /// @dev Layout: [16-byte header][4-byte offsets × numEpochs][epoch payloads...]
    function _epochStartOffset(
        bytes calldata params,
        uint16 epochNumber
    ) private pure onlySigned(params) returns (uint256) {
        uint16 epochs = numEpochs(params);
        if (epochNumber >= epochs) revert InvalidEpochIndex();

        // Offsets array starts right after the 13-byte header
        uint256 offsetsBase = 13;
        uint256 entryOffset = offsetsBase + uint256(epochNumber) * 4;
        uint32 absOffset = uint32(_read(params, uint32(entryOffset), 4));
        // Basic sanity: must be within params and after the offsets table
        uint256 minEpochArea = offsetsBase + uint256(epochs) * 4;
        if (absOffset < minEpochArea || absOffset >= params.length)
            revert BadEpochOffset();
        return uint256(absOffset);
    }
}
