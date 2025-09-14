// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/**
 * @title PublicCampaignConfig
 * @notice Library for encoding and validating packed campaign configuration data (PUBLIC fields)
 * @dev This library defines a compact, versioned packed-bytes format for PUBLIC configs where
 *      all field values are plaintext. It preserves random access via indices while minimizing
 *      ABI padding overhead by using big-endian packed integers.
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
 * ### Signature + Header (19 bytes total):
 * - `signature`: bytes8 - Magic signature (first 8 bytes of keccak256("PublicCampaignConfig"))
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
 * [8-byte signature][version][startingTime][numEpochs]
 * [index: epoch0Offset(4B), epoch1Offset(4B), ...]
 * [epoch0 @ epoch0Offset: duration][numPos0][pos0...]
 * [epoch1 @ epoch1Offset: duration][numPos1][pos0...]
 * ...
 * ```
 *
 * ## Size Efficiency:
 * - Signature + Header: 19 bytes
 * - Index: numEpochs × 4 bytes
 * - Each epoch: 5 bytes + (numPositions × 22 bytes)
 *
 * ## Endianness and Offsets
 * - All multi-byte integers in this format are big-endian (network byte order).
 * - Epoch offsets are absolute byte offsets from the start of `params`.
 *
 * @custom:gas-optimization Uses assembly for efficient calldata reading without bounds checking
 */
library PublicCampaignConfig {
    bytes8 internal constant CONFIG_SIGNATURE =
        bytes8(keccak256("PublicCampaignConfig"));
    uint8 internal constant SUPPORTED_VERSION = 1;

    error ConfigParamsTooShort();
    error InvalidConfigSignature();
    error UnsupportedVersion(uint8 found);
    error InvalidEpochIndex();
    error BadEpochOffset();
    error BadExtractSize();
    error OutOfBounds();
    error InvalidPositionIndex();
    error NoPositionsInEpoch();
    error NoEpochs();
    error TimestampOverflow();
    error OffsetsNotStrictlyIncreasing();
    error EpochPayloadTooShort();
    error EpochsNotTightlyPacked();
    error PositionsNotTightlyPacked();

    /// @dev Ensures `params` has the expected magic signature and supported version
    ///      before allowing any reads. Also checks the minimum header length.
    modifier onlySigned(bytes calldata params) {
        // Require at least the 19-byte header to be present before any reads
        if (params.length < 19) revert ConfigParamsTooShort();

        // Read first 8 bytes directly from calldata for precise erroring
        uint64 sig;
        assembly {
            sig := shr(192, calldataload(params.offset))
        }
        if (bytes8(sig) != CONFIG_SIGNATURE) revert InvalidConfigSignature();

        // Enforce supported version to avoid silent misparsing of future formats
        uint8 v = uint8(params[8]);
        if (v != SUPPORTED_VERSION) revert UnsupportedVersion(v);
        _;
    }

    /// @notice Returns the encoding format version declared in `params`.
    /// @param params Packed configuration bytes.
    /// @return Format version byte.
    function version(
        bytes calldata params
    ) internal pure onlySigned(params) returns (uint8) {
        return uint8(_read(params, 8, 1)); // 1 byte after 8-byte signature
    }

    /// @notice Returns the global campaign start timestamp (seconds since epoch).
    /// @param params Packed configuration bytes.
    /// @return Campaign starting time.
    function startingTime(
        bytes calldata params
    ) internal pure onlySigned(params) returns (uint64) {
        return uint64(_read(params, 9, 8)); // 8 bytes after signature + version
    }

    /// @notice Returns the total number of epochs encoded in `params`.
    /// @param params Packed configuration bytes.
    /// @return Number of epochs.
    function numEpochs(
        bytes calldata params
    ) internal pure onlySigned(params) returns (uint16) {
        return uint16(_read(params, 17, 2)); // 2 bytes after signature + version + startingTime
    }

    /// @notice Returns the duration (in seconds) of `epochNumber`.
    /// @param params Packed configuration bytes.
    /// @param epochNumber 0-based epoch index.
    /// @return Duration in seconds.
    function durationSeconds(
        bytes calldata params,
        uint16 epochNumber
    ) internal pure onlySigned(params) returns (uint32) {
        uint256 offset = _epochStartOffset(params, epochNumber);
        return uint32(_read(params, uint32(offset), 4)); // 4 bytes at epoch start
    }

    /// @notice Returns the number of positions defined in `epochNumber`.
    /// @param params Packed configuration bytes.
    /// @param epochNumber 0-based epoch index.
    /// @return Number of positions (0-255).
    function numPositions(
        bytes calldata params,
        uint16 epochNumber
    ) internal pure onlySigned(params) returns (uint8) {
        uint256 offset = _epochStartOffset(params, epochNumber) + 4; // skip duration
        return uint8(_read(params, uint32(offset), 1)); // 1 byte after duration
    }

    /// @notice Returns the lower tick bound for a position.
    /// @param params Packed configuration bytes.
    /// @param epochNumber 0-based epoch index.
    /// @param positionIndex 0-based position index within the epoch.
    /// @return tickLowerInt24 Lower bound tick.
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

    /// @notice Returns the upper tick bound for a position.
    /// @param params Packed configuration bytes.
    /// @param epochNumber 0-based epoch index.
    /// @param positionIndex 0-based position index within the epoch.
    /// @return tickUpperInt24 Upper bound tick.
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

    /// @notice Returns the token amount allocated to a position.
    /// @param params Packed configuration bytes.
    /// @param epochNumber 0-based epoch index.
    /// @param positionIndex 0-based position index within the epoch.
    /// @return amount uint128 amount allocated.
    function amountAllocated(
        bytes calldata params,
        uint16 epochNumber,
        uint8 positionIndex
    ) internal pure onlySigned(params) returns (uint128) {
        return uint128(_positionField(params, epochNumber, positionIndex, 6, 16));
    }

    /// @notice Returns the total tokens to sell across all positions.
    /// @dev Derived value: sum of every position's `amountAllocated` in all epochs.
    /// @param params Packed configuration bytes.
    /// @return total Sum of amounts across the entire config.
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

    /// @notice Returns the starting tick of an epoch, defined as max of all `tickUpper` in the epoch.
    /// @param params Packed configuration bytes.
    /// @param epochNumber 0-based epoch index.
    /// @return startingTick The computed epoch starting tick.
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
            uint32 dur = uint32(_read(params, uint32(epochOff), 4));
            sum += dur;
        }
        uint256 endTs = uint256(start) + sum;
        if (endTs > type(uint64).max) revert TimestampOverflow();
        return uint64(endTs);
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
            uint32 dur = uint32(_read(params, uint32(epochOff), 4));
            sum += dur;
        }
        uint256 epochStartTs = uint256(start) + sum;
        if (epochStartTs > type(uint64).max) revert TimestampOverflow();
        return uint64(epochStartTs);
    }

    /// @notice Validate epoch index and payload layout for monotonicity and size bounds
    /// @dev IMPORTANT: Call once on any untrusted `params` before using other read helpers.
    ///      Reverts if any invariant fails; on success it guarantees subsequent reads are safe
    ///      under the validated packing assumptions.
    function validate(
        bytes calldata params
    ) internal pure onlySigned(params) {
        uint16 epochs = numEpochs(params);
        if (epochs == 0) revert NoEpochs();
        // Offsets table immediately follows the 19-byte header
        uint256 offsetsBase = 19;
        uint256 indexBytes = uint256(epochs) * 4;
        if (params.length < offsetsBase + indexBytes) revert ConfigParamsTooShort();

        uint256 minEpochArea = offsetsBase + indexBytes;

        // Pass 1: validate bounds and strict monotonicity of epoch offsets
        uint32 prev;
        for (uint16 e = 0; e < epochs; e++) {
            uint32 abs = uint32(_read(params, uint32(offsetsBase + uint256(e) * 4), 4));
            if (abs < minEpochArea || abs >= params.length) revert BadEpochOffset();
            if (e != 0 && abs <= prev) revert OffsetsNotStrictlyIncreasing();
            // Enforce tight packing of epoch 0: it must start right after the offsets table
            if (e == 0 && abs != minEpochArea) revert EpochsNotTightlyPacked();
            prev = abs;
        }

        // Pass 2: validate each epoch payload fits within [offset[e], offset[e+1]) and has at least one position
        for (uint16 e = 0; e < epochs; e++) {
            uint256 startOff = uint32(_read(params, uint32(offsetsBase + uint256(e) * 4), 4));
            uint256 endOff = (e + 1 < epochs)
                ? uint32(_read(params, uint32(offsetsBase + uint256(e + 1) * 4), 4))
                : params.length;

            // At least 5 bytes required for [duration(4) + numPositions(1)]
            if (endOff < startOff + 5) revert EpochPayloadTooShort();

            uint8 count = uint8(_read(params, uint32(startOff + 4), 1));
            if (count == 0) revert NoPositionsInEpoch();
            uint256 required = startOff + 5 + uint256(count) * 22;
            // Enforce tight packing: payload must exactly fill the epoch window
            if (required != endOff) revert PositionsNotTightlyPacked();
        }
    }

    /// @dev Reads `size` bytes from `params` at absolute `offset` as big-endian, returning a right-aligned uint256.
    ///      Reverts on out-of-bounds or invalid sizes (0 or > 32).
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

    /// @notice Returns the absolute byte offset (from start of `params`) where epoch `epochNumber` begins.
    /// @dev Layout: [19-byte header][4-byte offsets × numEpochs][epoch payloads...]
    /// @param params Packed configuration bytes.
    /// @param epochNumber 0-based epoch index.
    /// @return Absolute start offset for the epoch payload.
    function _epochStartOffset(
        bytes calldata params,
        uint16 epochNumber
    ) private pure onlySigned(params) returns (uint256) {
        uint16 epochs = numEpochs(params);
        if (epochNumber >= epochs) revert InvalidEpochIndex();

        // Offsets array starts right after the 19-byte header
        uint256 offsetsBase = 19;
        uint256 entryOffset = offsetsBase + uint256(epochNumber) * 4;
        uint32 absOffset = uint32(_read(params, uint32(entryOffset), 4));
        // Basic sanity: must be within params and after the offsets table
        uint256 minEpochArea = offsetsBase + uint256(epochs) * 4;
        if (absOffset < minEpochArea || absOffset >= params.length)
            revert BadEpochOffset();
        return uint256(absOffset);
    }
}
