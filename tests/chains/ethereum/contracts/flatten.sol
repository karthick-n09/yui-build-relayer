// Sources flattened with hardhat v2.22.6 https://hardhat.org

// SPDX-License-Identifier: Apache-2.0 AND MIT

// File @datachainlab/ethereum-ibc-relay-chain/contracts/IIBCContractUpgradableModule.sol@v1.0.0

// Original license: SPDX_License_Identifier: Apache-2.0
pragma solidity ^0.8.20;

interface IIBCContractUpgradableModuleErrors {
    // ------------------- Errors ------------------- //

    error IBCContractUpgradableModuleUnauthorizedUpgrader(address msgSender);
    error IBCContractUpgradableModuleAppInfoProposedWithZeroImpl();
    error IBCContractUpgradableModuleAppInfoNotProposedYet();
    error IBCContractUpgradableModuleAppInfoIsAlreadySet();
    error IBCContractUpgradableModuleChannelNotFound(string portId, string channelId);
    error IBCContractUpgradableModuleAlreadyConsumedAppInfo();
}

interface IIBCContractUpgradableModule {
    // ------------------- Data Structures ------------------- //

    /**
     * @dev Proposed AppInfo data
     * @param implemantation the new implementation address
     * @param initialCalldata the first function call's calldata
     * @param consumed the flag that specifies if this implementation is already deployed
     */
    struct AppInfo {
        address implementation;
        bytes initialCalldata;
        bool consumed;
    }

    // ------------------- Functions ------------------- //

    /**
     * @dev Returns the proposed AppInfo for the given version
     */
    function getAppInfoProposal(string calldata version) external view returns (AppInfo memory);

    /**
     * @dev Propose an Appinfo for the given version
     * @notice This function is only callable by an authorized upgrader.
     *         To upgrade the IBC module contract along with a channel upgrade, the upgrader must
     *         call this function before calling `channelUpgradeInit` or `channelUpgradeTry` of the IBC handler.
     */
    function proposeAppVersion(string calldata version, address implementation, bytes calldata initialCalldata) external;

}


// File @hyperledger-labs/yui-ibc-solidity/contracts/proto/ProtoBufRuntime.sol@v0.1.0

// Original license: SPDX_License_Identifier: Apache-2.0
pragma solidity ^0.8.20;


/**
 * @title Runtime library for ProtoBuf serialization and/or deserialization.
 * All ProtoBuf generated code will use this library.
 */
library ProtoBufRuntime {
  // Types defined in ProtoBuf
  enum WireType { Varint, Fixed64, LengthDelim, StartGroup, EndGroup, Fixed32 }
  // Constants for bytes calculation
  uint256 constant WORD_LENGTH = 32;
  uint256 constant HEADER_SIZE_LENGTH_IN_BYTES = 4;
  uint256 constant BYTE_SIZE = 8;
  uint256 constant REMAINING_LENGTH = WORD_LENGTH - HEADER_SIZE_LENGTH_IN_BYTES;
  string constant OVERFLOW_MESSAGE = "length overflow";

  //Storages
  /**
   * @dev Encode to storage location using assembly to save storage space.
   * @param location The location of storage
   * @param encoded The encoded ProtoBuf bytes
   */
  function encodeStorage(bytes storage location, bytes memory encoded)
    internal
  {
    /**
     * This code use the first four bytes as size,
     * and then put the rest of `encoded` bytes.
     */
    uint256 length = encoded.length;
    uint256 firstWord;
    uint256 wordLength = WORD_LENGTH;
    uint256 remainingLength = REMAINING_LENGTH;

    assembly {
      firstWord := mload(add(encoded, wordLength))
    }
    firstWord =
      (firstWord >> (BYTE_SIZE * HEADER_SIZE_LENGTH_IN_BYTES)) |
      (length << (BYTE_SIZE * REMAINING_LENGTH));

    assembly {
      sstore(location.slot, firstWord)
    }

    if (length > REMAINING_LENGTH) {
      length -= REMAINING_LENGTH;
      for (uint256 i = 0; i < ceil(length, WORD_LENGTH); i++) {
        assembly {
          let offset := add(mul(i, wordLength), remainingLength)
          let slotIndex := add(i, 1)
          sstore(
            add(location.slot, slotIndex),
            mload(add(add(encoded, wordLength), offset))
          )
        }
      }
    }
  }

  /**
   * @dev Decode storage location using assembly using the format in `encodeStorage`.
   * @param location The location of storage
   * @return The encoded bytes
   */
  function decodeStorage(bytes storage location)
    internal
    view
    returns (bytes memory)
  {
    /**
     * This code is to decode the first four bytes as size,
     * and then decode the rest using the decoded size.
     */
    uint256 firstWord;
    uint256 remainingLength = REMAINING_LENGTH;
    uint256 wordLength = WORD_LENGTH;

    assembly {
      firstWord := sload(location.slot)
    }

    uint256 length = firstWord >> (BYTE_SIZE * REMAINING_LENGTH);
    bytes memory encoded = new bytes(length);

    assembly {
      mstore(add(encoded, remainingLength), firstWord)
    }

    if (length > REMAINING_LENGTH) {
      length -= REMAINING_LENGTH;
      for (uint256 i = 0; i < ceil(length, WORD_LENGTH); i++) {
        assembly {
          let offset := add(mul(i, wordLength), remainingLength)
          let slotIndex := add(i, 1)
          mstore(
            add(add(encoded, wordLength), offset),
            sload(add(location.slot, slotIndex))
          )
        }
      }
    }
    return encoded;
  }

  /**
   * @dev Fast memory copy of bytes using assembly.
   * @param src The source memory address
   * @param dest The destination memory address
   * @param len The length of bytes to copy
   */
  function copyBytes(uint256 src, uint256 dest, uint256 len) internal pure {
    if (len == 0) {
      return;
    }

    // Copy word-length chunks while possible
    for (; len > WORD_LENGTH; len -= WORD_LENGTH) {
      assembly {
        mstore(dest, mload(src))
      }
      dest += WORD_LENGTH;
      src += WORD_LENGTH;
    }

    // Copy remaining bytes
    uint256 mask = 256**(WORD_LENGTH - len) - 1;
    assembly {
      let srcpart := and(mload(src), not(mask))
      let destpart := and(mload(dest), mask)
      mstore(dest, or(destpart, srcpart))
    }
  }

  /**
   * @dev Use assembly to get memory address.
   * @param r The in-memory bytes array
   * @return The memory address of `r`
   */
  function getMemoryAddress(bytes memory r) internal pure returns (uint256) {
    uint256 addr;
    assembly {
      addr := r
    }
    return addr;
  }

  /**
   * @dev Implement Math function of ceil
   * @param a The denominator
   * @param m The numerator
   * @return r The result of ceil(a/m)
   */
  function ceil(uint256 a, uint256 m) internal pure returns (uint256 r) {
    return (a + m - 1) / m;
  }

  // Decoders
  /**
   * This section of code `_decode_(u)int(32|64)`, `_decode_enum` and `_decode_bool`
   * is to decode ProtoBuf native integers,
   * using the `varint` encoding.
   */

  /**
   * @dev Decode integers
   * @param p The memory offset of `bs`
   * @param bs The bytes array to be decoded
   * @return The decoded integer
   * @return The length of `bs` used to get decoded
   */
  function _decode_uint32(uint256 p, bytes memory bs)
    internal
    pure
    returns (uint32, uint256)
  {
    (uint256 varint, uint256 sz) = _decode_varint(p, bs);
    return (uint32(varint), sz);
  }

  /**
   * @dev Decode integers
   * @param p The memory offset of `bs`
   * @param bs The bytes array to be decoded
   * @return The decoded integer
   * @return The length of `bs` used to get decoded
   */
  function _decode_uint64(uint256 p, bytes memory bs)
    internal
    pure
    returns (uint64, uint256)
  {
    (uint256 varint, uint256 sz) = _decode_varint(p, bs);
    return (uint64(varint), sz);
  }

  /**
   * @dev Decode integers
   * @param p The memory offset of `bs`
   * @param bs The bytes array to be decoded
   * @return The decoded integer
   * @return The length of `bs` used to get decoded
   */
  function _decode_int32(uint256 p, bytes memory bs)
    internal
    pure
    returns (int32, uint256)
  {
    (uint256 varint, uint256 sz) = _decode_varint(p, bs);
    int32 r;
    assembly {
      r := varint
    }
    return (r, sz);
  }

  /**
   * @dev Decode integers
   * @param p The memory offset of `bs`
   * @param bs The bytes array to be decoded
   * @return The decoded integer
   * @return The length of `bs` used to get decoded
   */
  function _decode_int64(uint256 p, bytes memory bs)
    internal
    pure
    returns (int64, uint256)
  {
    (uint256 varint, uint256 sz) = _decode_varint(p, bs);
    int64 r;
    assembly {
      r := varint
    }
    return (r, sz);
  }

  /**
   * @dev Decode enum
   * @param p The memory offset of `bs`
   * @param bs The bytes array to be decoded
   * @return The decoded enum's integer
   * @return The length of `bs` used to get decoded
   */
  function _decode_enum(uint256 p, bytes memory bs)
    internal
    pure
    returns (int64, uint256)
  {
    return _decode_int64(p, bs);
  }

  /**
   * @dev Decode enum
   * @param p The memory offset of `bs`
   * @param bs The bytes array to be decoded
   * @return The decoded boolean
   * @return The length of `bs` used to get decoded
   */
  function _decode_bool(uint256 p, bytes memory bs)
    internal
    pure
    returns (bool, uint256)
  {
    (uint256 varint, uint256 sz) = _decode_varint(p, bs);
    if (varint == 0) {
      return (false, sz);
    }
    return (true, sz);
  }

  /**
   * This section of code `_decode_sint(32|64)`
   * is to decode ProtoBuf native signed integers,
   * using the `zig-zag` encoding.
   */

  /**
   * @dev Decode signed integers
   * @param p The memory offset of `bs`
   * @param bs The bytes array to be decoded
   * @return The decoded integer
   * @return The length of `bs` used to get decoded
   */
  function _decode_sint32(uint256 p, bytes memory bs)
    internal
    pure
    returns (int32, uint256)
  {
    (int256 varint, uint256 sz) = _decode_varints(p, bs);
    return (int32(varint), sz);
  }

  /**
   * @dev Decode signed integers
   * @param p The memory offset of `bs`
   * @param bs The bytes array to be decoded
   * @return The decoded integer
   * @return The length of `bs` used to get decoded
   */
  function _decode_sint64(uint256 p, bytes memory bs)
    internal
    pure
    returns (int64, uint256)
  {
    (int256 varint, uint256 sz) = _decode_varints(p, bs);
    return (int64(varint), sz);
  }

  /**
   * @dev Decode string
   * @param p The memory offset of `bs`
   * @param bs The bytes array to be decoded
   * @return The decoded string
   * @return The length of `bs` used to get decoded
   */
  function _decode_string(uint256 p, bytes memory bs)
    internal
    pure
    returns (string memory, uint256)
  {
    (bytes memory x, uint256 sz) = _decode_lendelim(p, bs);
    return (string(x), sz);
  }

  /**
   * @dev Decode bytes array
   * @param p The memory offset of `bs`
   * @param bs The bytes array to be decoded
   * @return The decoded bytes array
   * @return The length of `bs` used to get decoded
   */
  function _decode_bytes(uint256 p, bytes memory bs)
    internal
    pure
    returns (bytes memory, uint256)
  {
    return _decode_lendelim(p, bs);
  }

  /**
   * @dev Decode ProtoBuf key
   * @param p The memory offset of `bs`
   * @param bs The bytes array to be decoded
   * @return The decoded field ID
   * @return The decoded WireType specified in ProtoBuf
   * @return The length of `bs` used to get decoded
   */
  function _decode_key(uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256, WireType, uint256)
  {
    (uint256 x, uint256 n) = _decode_varint(p, bs);
    WireType typeId = WireType(x & 7);
    uint256 fieldId = x / 8;
    return (fieldId, typeId, n);
  }

  /**
   * @dev Decode ProtoBuf varint
   * @param p The memory offset of `bs`
   * @param bs The bytes array to be decoded
   * @return The decoded unsigned integer
   * @return The length of `bs` used to get decoded
   */
  function _decode_varint(uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256, uint256)
  {
    /**
     * Read a byte.
     * Use the lower 7 bits and shift it to the left,
     * until the most significant bit is 0.
     * Refer to https://developers.google.com/protocol-buffers/docs/encoding
     */
    uint256 x = 0;
    uint256 sz = 0;
    uint256 length = bs.length + WORD_LENGTH;
    assembly {
      let b := 0x80
      p := add(bs, p)
      for {

      } eq(0x80, and(b, 0x80)) {

      } {
        if eq(lt(sub(p, bs), length), 0) {
          mstore(
            0,
            0x08c379a000000000000000000000000000000000000000000000000000000000
          ) //error function selector
          mstore(4, 32)
          mstore(36, 15)
          mstore(
            68,
            0x6c656e677468206f766572666c6f770000000000000000000000000000000000
          ) // length overflow in hex
          revert(0, 83)
        }
        let tmp := mload(p)
        let pos := 0
        for {

        } and(eq(0x80, and(b, 0x80)), lt(pos, 32)) {

        } {
          if eq(lt(sub(p, bs), length), 0) {
            mstore(
              0,
              0x08c379a000000000000000000000000000000000000000000000000000000000
            ) //error function selector
            mstore(4, 32)
            mstore(36, 15)
            mstore(
              68,
              0x6c656e677468206f766572666c6f770000000000000000000000000000000000
            ) // length overflow in hex
            revert(0, 83)
          }
          b := byte(pos, tmp)
          x := or(x, shl(mul(7, sz), and(0x7f, b)))
          sz := add(sz, 1)
          pos := add(pos, 1)
          p := add(p, 0x01)
        }
      }
    }
    return (x, sz);
  }

  /**
   * @dev Decode ProtoBuf zig-zag encoding
   * @param p The memory offset of `bs`
   * @param bs The bytes array to be decoded
   * @return The decoded signed integer
   * @return The length of `bs` used to get decoded
   */
  function _decode_varints(uint256 p, bytes memory bs)
    internal
    pure
    returns (int256, uint256)
  {
    /**
     * Refer to https://developers.google.com/protocol-buffers/docs/encoding
     */
    (uint256 u, uint256 sz) = _decode_varint(p, bs);
    int256 s;
    assembly {
      s := xor(shr(1, u), add(not(and(u, 1)), 1))
    }
    return (s, sz);
  }

  /**
   * @dev Decode ProtoBuf fixed-length encoding
   * @param p The memory offset of `bs`
   * @param bs The bytes array to be decoded
   * @return The decoded unsigned integer
   * @return The length of `bs` used to get decoded
   */
  function _decode_uintf(uint256 p, bytes memory bs, uint256 sz)
    internal
    pure
    returns (uint256, uint256)
  {
    /**
     * Refer to https://developers.google.com/protocol-buffers/docs/encoding
     */
    uint256 x = 0;
    uint256 length = bs.length + WORD_LENGTH;
    assert(p + sz <= length);
    assembly {
      let i := 0
      p := add(bs, p)
      let tmp := mload(p)
      for {

      } lt(i, sz) {

      } {
        x := or(x, shl(mul(8, i), byte(i, tmp)))
        p := add(p, 0x01)
        i := add(i, 1)
      }
    }
    return (x, sz);
  }

  /**
   * `_decode_(s)fixed(32|64)` is the concrete implementation of `_decode_uintf`
   */
  function _decode_fixed32(uint256 p, bytes memory bs)
    internal
    pure
    returns (uint32, uint256)
  {
    (uint256 x, uint256 sz) = _decode_uintf(p, bs, 4);
    return (uint32(x), sz);
  }

  function _decode_fixed64(uint256 p, bytes memory bs)
    internal
    pure
    returns (uint64, uint256)
  {
    (uint256 x, uint256 sz) = _decode_uintf(p, bs, 8);
    return (uint64(x), sz);
  }

  function _decode_sfixed32(uint256 p, bytes memory bs)
    internal
    pure
    returns (int32, uint256)
  {
    (uint256 x, uint256 sz) = _decode_uintf(p, bs, 4);
    int256 r;
    assembly {
      r := x
    }
    return (int32(r), sz);
  }

  function _decode_sfixed64(uint256 p, bytes memory bs)
    internal
    pure
    returns (int64, uint256)
  {
    (uint256 x, uint256 sz) = _decode_uintf(p, bs, 8);
    int256 r;
    assembly {
      r := x
    }
    return (int64(r), sz);
  }

  /**
   * @dev Decode bytes array
   * @param p The memory offset of `bs`
   * @param bs The bytes array to be decoded
   * @return The decoded bytes array
   * @return The length of `bs` used to get decoded
   */
  function _decode_lendelim(uint256 p, bytes memory bs)
    internal
    pure
    returns (bytes memory, uint256)
  {
    /**
     * First read the size encoded in `varint`, then use the size to read bytes.
     */
    (uint256 len, uint256 sz) = _decode_varint(p, bs);
    bytes memory b = new bytes(len);
    uint256 length = bs.length + WORD_LENGTH;
    assert(p + sz + len <= length);
    uint256 sourcePtr;
    uint256 destPtr;
    assembly {
      destPtr := add(b, 32)
      sourcePtr := add(add(bs, p), sz)
    }
    copyBytes(sourcePtr, destPtr, len);
    return (b, sz + len);
  }

  /**
   * @dev Skip the decoding of a single field
   * @param wt The WireType of the field
   * @param p The memory offset of `bs`
   * @param bs The bytes array to be decoded
   * @return The length of `bs` to skipped
   */
  function _skip_field_decode(WireType wt, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    if (wt == ProtoBufRuntime.WireType.Fixed64) {
      return 8;
    } else if (wt == ProtoBufRuntime.WireType.Fixed32) {
      return 4;
    } else if (wt == ProtoBufRuntime.WireType.Varint) {
      (, uint256 size) = ProtoBufRuntime._decode_varint(p, bs);
      return size;
    } else {
      require(wt == ProtoBufRuntime.WireType.LengthDelim);
      (uint256 len, uint256 size) = ProtoBufRuntime._decode_varint(p, bs);
      return size + len;
    }
  }

  // Encoders
  /**
   * @dev Encode ProtoBuf key
   * @param x The field ID
   * @param wt The WireType specified in ProtoBuf
   * @param p The offset of bytes array `bs`
   * @param bs The bytes array to encode
   * @return The length of encoded bytes
   */
  function _encode_key(uint256 x, WireType wt, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    uint256 i;
    assembly {
      i := or(mul(x, 8), mod(wt, 8))
    }
    return _encode_varint(i, p, bs);
  }

  /**
   * @dev Encode ProtoBuf varint
   * @param x The unsigned integer to be encoded
   * @param p The offset of bytes array `bs`
   * @param bs The bytes array to encode
   * @return The length of encoded bytes
   */
  function _encode_varint(uint256 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    /**
     * Refer to https://developers.google.com/protocol-buffers/docs/encoding
     */
    uint256 sz = 0;
    assembly {
      let bsptr := add(bs, p)
      let byt := and(x, 0x7f)
      for {

      } gt(shr(7, x), 0) {

      } {
        mstore8(bsptr, or(0x80, byt))
        bsptr := add(bsptr, 1)
        sz := add(sz, 1)
        x := shr(7, x)
        byt := and(x, 0x7f)
      }
      mstore8(bsptr, byt)
      sz := add(sz, 1)
    }
    return sz;
  }

  /**
   * @dev Encode ProtoBuf zig-zag encoding
   * @param x The signed integer to be encoded
   * @param p The offset of bytes array `bs`
   * @param bs The bytes array to encode
   * @return The length of encoded bytes
   */
  function _encode_varints(int256 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    /**
     * Refer to https://developers.google.com/protocol-buffers/docs/encoding
     */
    uint256 encodedInt = _encode_zigzag(x);
    return _encode_varint(encodedInt, p, bs);
  }

  /**
   * @dev Encode ProtoBuf bytes
   * @param xs The bytes array to be encoded
   * @param p The offset of bytes array `bs`
   * @param bs The bytes array to encode
   * @return The length of encoded bytes
   */
  function _encode_bytes(bytes memory xs, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    uint256 xsLength = xs.length;
    uint256 sz = _encode_varint(xsLength, p, bs);
    uint256 count = 0;
    assembly {
      let bsptr := add(bs, add(p, sz))
      let xsptr := add(xs, 32)
      for {

      } lt(count, xsLength) {

      } {
        mstore8(bsptr, byte(0, mload(xsptr)))
        bsptr := add(bsptr, 1)
        xsptr := add(xsptr, 1)
        count := add(count, 1)
      }
    }
    return sz + count;
  }

  /**
   * @dev Encode ProtoBuf string
   * @param xs The string to be encoded
   * @param p The offset of bytes array `bs`
   * @param bs The bytes array to encode
   * @return The length of encoded bytes
   */
  function _encode_string(string memory xs, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_bytes(bytes(xs), p, bs);
  }

  /**
   * `_encode_(u)int(32|64)`, `_encode_enum` and `_encode_bool`
   * are concrete implementation of `_encode_varint`
   */
  function _encode_uint32(uint32 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_varint(x, p, bs);
  }

  function _encode_uint64(uint64 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_varint(x, p, bs);
  }

  function _encode_int32(int32 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    uint64 twosComplement;
    assembly {
      twosComplement := x
    }
    return _encode_varint(twosComplement, p, bs);
  }

  function _encode_int64(int64 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    uint64 twosComplement;
    assembly {
      twosComplement := x
    }
    return _encode_varint(twosComplement, p, bs);
  }

  function _encode_enum(int32 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_int32(x, p, bs);
  }

  function _encode_bool(bool x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    if (x) {
      return _encode_varint(1, p, bs);
    } else return _encode_varint(0, p, bs);
  }

  /**
   * `_encode_sint(32|64)`, `_encode_enum` and `_encode_bool`
   * are the concrete implementation of `_encode_varints`
   */
  function _encode_sint32(int32 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_varints(x, p, bs);
  }

  function _encode_sint64(int64 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_varints(x, p, bs);
  }

  /**
   * `_encode_(s)fixed(32|64)` is the concrete implementation of `_encode_uintf`
   */
  function _encode_fixed32(uint32 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_uintf(x, p, bs, 4);
  }

  function _encode_fixed64(uint64 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_uintf(x, p, bs, 8);
  }

  function _encode_sfixed32(int32 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    uint32 twosComplement;
    assembly {
      twosComplement := x
    }
    return _encode_uintf(twosComplement, p, bs, 4);
  }

  function _encode_sfixed64(int64 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    uint64 twosComplement;
    assembly {
      twosComplement := x
    }
    return _encode_uintf(twosComplement, p, bs, 8);
  }

  /**
   * @dev Encode ProtoBuf fixed-length integer
   * @param x The unsigned integer to be encoded
   * @param p The offset of bytes array `bs`
   * @param bs The bytes array to encode
   * @return The length of encoded bytes
   */
  function _encode_uintf(uint256 x, uint256 p, bytes memory bs, uint256 sz)
    internal
    pure
    returns (uint256)
  {
    assembly {
      let bsptr := add(sz, add(bs, p))
      let count := sz
      for {

      } gt(count, 0) {

      } {
        bsptr := sub(bsptr, 1)
        mstore8(bsptr, byte(sub(32, count), x))
        count := sub(count, 1)
      }
    }
    return sz;
  }

  /**
   * @dev Encode ProtoBuf zig-zag signed integer
   * @param i The unsigned integer to be encoded
   * @return The encoded unsigned integer
   */
  function _encode_zigzag(int256 i) internal pure returns (uint256) {
    if (i >= 0) {
      return uint256(i) * 2;
    } else return uint256(i * -2) - 1;
  }

  // Estimators
  /**
   * @dev Estimate the length of encoded LengthDelim
   * @param i The length of LengthDelim
   * @return The estimated encoded length
   */
  function _sz_lendelim(uint256 i) internal pure returns (uint256) {
    return i + _sz_varint(i);
  }

  /**
   * @dev Estimate the length of encoded ProtoBuf field ID
   * @param i The field ID
   * @return The estimated encoded length
   */
  function _sz_key(uint256 i) internal pure returns (uint256) {
    if (i < 16) {
      return 1;
    } else if (i < 2048) {
      return 2;
    } else if (i < 262144) {
      return 3;
    } else {
      revert("not supported");
    }
  }

  /**
   * @dev Estimate the length of encoded ProtoBuf varint
   * @param i The unsigned integer
   * @return The estimated encoded length
   */
  function _sz_varint(uint256 i) internal pure returns (uint256) {
    uint256 count = 1;
    assembly {
      i := shr(7, i)
      for {

      } gt(i, 0) {

      } {
        i := shr(7, i)
        count := add(count, 1)
      }
    }
    return count;
  }

  /**
   * `_sz_(u)int(32|64)` and `_sz_enum` are the concrete implementation of `_sz_varint`
   */
  function _sz_uint32(uint32 i) internal pure returns (uint256) {
    return _sz_varint(i);
  }

  function _sz_uint64(uint64 i) internal pure returns (uint256) {
    return _sz_varint(i);
  }

  function _sz_int32(int32 i) internal pure returns (uint256) {
    if (i < 0) {
      return 10;
    } else return _sz_varint(uint32(i));
  }

  function _sz_int64(int64 i) internal pure returns (uint256) {
    if (i < 0) {
      return 10;
    } else return _sz_varint(uint64(i));
  }

  function _sz_enum(int64 i) internal pure returns (uint256) {
    if (i < 0) {
      return 10;
    } else return _sz_varint(uint64(i));
  }

  /**
   * `_sz_sint(32|64)` and `_sz_enum` are the concrete implementation of zig-zag encoding
   */
  function _sz_sint32(int32 i) internal pure returns (uint256) {
    return _sz_varint(_encode_zigzag(i));
  }

  function _sz_sint64(int64 i) internal pure returns (uint256) {
    return _sz_varint(_encode_zigzag(i));
  }

  /**
   * `_estimate_packed_repeated_(uint32|uint64|int32|int64|sint32|sint64)`
   */
  function _estimate_packed_repeated_uint32(uint32[] memory a) internal pure returns (uint256) {
    uint256 e = 0;
    for (uint i = 0; i < a.length; i++) {
      e += _sz_uint32(a[i]);
    }
    return e;
  }

  function _estimate_packed_repeated_uint64(uint64[] memory a) internal pure returns (uint256) {
    uint256 e = 0;
    for (uint i = 0; i < a.length; i++) {
      e += _sz_uint64(a[i]);
    }
    return e;
  }

  function _estimate_packed_repeated_int32(int32[] memory a) internal pure returns (uint256) {
    uint256 e = 0;
    for (uint i = 0; i < a.length; i++) {
      e += _sz_int32(a[i]);
    }
    return e;
  }

  function _estimate_packed_repeated_int64(int64[] memory a) internal pure returns (uint256) {
    uint256 e = 0;
    for (uint i = 0; i < a.length; i++) {
      e += _sz_int64(a[i]);
    }
    return e;
  }

  function _estimate_packed_repeated_sint32(int32[] memory a) internal pure returns (uint256) {
    uint256 e = 0;
    for (uint i = 0; i < a.length; i++) {
      e += _sz_sint32(a[i]);
    }
    return e;
  }

  function _estimate_packed_repeated_sint64(int64[] memory a) internal pure returns (uint256) {
    uint256 e = 0;
    for (uint i = 0; i < a.length; i++) {
      e += _sz_sint64(a[i]);
    }
    return e;
  }

  // Element counters for packed repeated fields
  function _count_packed_repeated_varint(uint256 p, uint256 len, bytes memory bs) internal pure returns (uint256) {
    uint256 count = 0;
    uint256 end = p + len;
    while (p < end) {
      uint256 sz;
      (, sz) = _decode_varint(p, bs);
      p += sz;
      count += 1;
    }
    return count;
  }

  // Soltype extensions
  /**
   * @dev Decode Solidity integer and/or fixed-size bytes array, filling from lowest bit.
   * @param n The maximum number of bytes to read
   * @param p The offset of bytes array `bs`
   * @param bs The bytes array to encode
   * @return The bytes32 representation
   * @return The number of bytes used to decode
   */
  function _decode_sol_bytesN_lower(uint8 n, uint256 p, bytes memory bs)
    internal
    pure
    returns (bytes32, uint256)
  {
    uint256 r;
    (uint256 len, uint256 sz) = _decode_varint(p, bs);
    if (len + sz > n + 3) {
      revert(OVERFLOW_MESSAGE);
    }
    p += 3;
    assert(p < bs.length + WORD_LENGTH);
    assembly {
      r := mload(add(p, bs))
    }
    for (uint256 i = len - 2; i < WORD_LENGTH; i++) {
      r /= 256;
    }
    return (bytes32(r), len + sz);
  }

  /**
   * @dev Decode Solidity integer and/or fixed-size bytes array, filling from highest bit.
   * @param n The maximum number of bytes to read
   * @param p The offset of bytes array `bs`
   * @param bs The bytes array to encode
   * @return The bytes32 representation
   * @return The number of bytes used to decode
   */
  function _decode_sol_bytesN(uint8 n, uint256 p, bytes memory bs)
    internal
    pure
    returns (bytes32, uint256)
  {
    (uint256 len, uint256 sz) = _decode_varint(p, bs);
    uint256 wordLength = WORD_LENGTH;
    uint256 byteSize = BYTE_SIZE;
    if (len + sz > n + 3) {
      revert(OVERFLOW_MESSAGE);
    }
    p += 3;
    bytes32 acc;
    assert(p < bs.length + WORD_LENGTH);
    assembly {
      acc := mload(add(p, bs))
      let difference := sub(wordLength, sub(len, 2))
      let bits := mul(byteSize, difference)
      acc := shl(bits, shr(bits, acc))
    }
    return (acc, len + sz);
  }

  /*
   * `_decode_sol*` are the concrete implementation of decoding Solidity types
   */
  function _decode_sol_address(uint256 p, bytes memory bs)
    internal
    pure
    returns (address, uint256)
  {
    (bytes32 r, uint256 sz) = _decode_sol_bytesN(20, p, bs);
    return (address(bytes20(r)), sz);
  }

  function _decode_sol_bool(uint256 p, bytes memory bs)
    internal
    pure
    returns (bool, uint256)
  {
    (uint256 r, uint256 sz) = _decode_sol_uintN(1, p, bs);
    if (r == 0) {
      return (false, sz);
    }
    return (true, sz);
  }

  function _decode_sol_uint(uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256, uint256)
  {
    return _decode_sol_uint256(p, bs);
  }

  function _decode_sol_uintN(uint8 n, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256, uint256)
  {
    (bytes32 u, uint256 sz) = _decode_sol_bytesN_lower(n, p, bs);
    uint256 r;
    assembly {
      r := u
    }
    return (r, sz);
  }

  function _decode_sol_uint8(uint256 p, bytes memory bs)
    internal
    pure
    returns (uint8, uint256)
  {
    (uint256 r, uint256 sz) = _decode_sol_uintN(1, p, bs);
    return (uint8(r), sz);
  }

  function _decode_sol_uint16(uint256 p, bytes memory bs)
    internal
    pure
    returns (uint16, uint256)
  {
    (uint256 r, uint256 sz) = _decode_sol_uintN(2, p, bs);
    return (uint16(r), sz);
  }

  function _decode_sol_uint24(uint256 p, bytes memory bs)
    internal
    pure
    returns (uint24, uint256)
  {
    (uint256 r, uint256 sz) = _decode_sol_uintN(3, p, bs);
    return (uint24(r), sz);
  }

  function _decode_sol_uint32(uint256 p, bytes memory bs)
    internal
    pure
    returns (uint32, uint256)
  {
    (uint256 r, uint256 sz) = _decode_sol_uintN(4, p, bs);
    return (uint32(r), sz);
  }

  function _decode_sol_uint40(uint256 p, bytes memory bs)
    internal
    pure
    returns (uint40, uint256)
  {
    (uint256 r, uint256 sz) = _decode_sol_uintN(5, p, bs);
    return (uint40(r), sz);
  }

  function _decode_sol_uint48(uint256 p, bytes memory bs)
    internal
    pure
    returns (uint48, uint256)
  {
    (uint256 r, uint256 sz) = _decode_sol_uintN(6, p, bs);
    return (uint48(r), sz);
  }

  function _decode_sol_uint56(uint256 p, bytes memory bs)
    internal
    pure
    returns (uint56, uint256)
  {
    (uint256 r, uint256 sz) = _decode_sol_uintN(7, p, bs);
    return (uint56(r), sz);
  }

  function _decode_sol_uint64(uint256 p, bytes memory bs)
    internal
    pure
    returns (uint64, uint256)
  {
    (uint256 r, uint256 sz) = _decode_sol_uintN(8, p, bs);
    return (uint64(r), sz);
  }

  function _decode_sol_uint72(uint256 p, bytes memory bs)
    internal
    pure
    returns (uint72, uint256)
  {
    (uint256 r, uint256 sz) = _decode_sol_uintN(9, p, bs);
    return (uint72(r), sz);
  }

  function _decode_sol_uint80(uint256 p, bytes memory bs)
    internal
    pure
    returns (uint80, uint256)
  {
    (uint256 r, uint256 sz) = _decode_sol_uintN(10, p, bs);
    return (uint80(r), sz);
  }

  function _decode_sol_uint88(uint256 p, bytes memory bs)
    internal
    pure
    returns (uint88, uint256)
  {
    (uint256 r, uint256 sz) = _decode_sol_uintN(11, p, bs);
    return (uint88(r), sz);
  }

  function _decode_sol_uint96(uint256 p, bytes memory bs)
    internal
    pure
    returns (uint96, uint256)
  {
    (uint256 r, uint256 sz) = _decode_sol_uintN(12, p, bs);
    return (uint96(r), sz);
  }

  function _decode_sol_uint104(uint256 p, bytes memory bs)
    internal
    pure
    returns (uint104, uint256)
  {
    (uint256 r, uint256 sz) = _decode_sol_uintN(13, p, bs);
    return (uint104(r), sz);
  }

  function _decode_sol_uint112(uint256 p, bytes memory bs)
    internal
    pure
    returns (uint112, uint256)
  {
    (uint256 r, uint256 sz) = _decode_sol_uintN(14, p, bs);
    return (uint112(r), sz);
  }

  function _decode_sol_uint120(uint256 p, bytes memory bs)
    internal
    pure
    returns (uint120, uint256)
  {
    (uint256 r, uint256 sz) = _decode_sol_uintN(15, p, bs);
    return (uint120(r), sz);
  }

  function _decode_sol_uint128(uint256 p, bytes memory bs)
    internal
    pure
    returns (uint128, uint256)
  {
    (uint256 r, uint256 sz) = _decode_sol_uintN(16, p, bs);
    return (uint128(r), sz);
  }

  function _decode_sol_uint136(uint256 p, bytes memory bs)
    internal
    pure
    returns (uint136, uint256)
  {
    (uint256 r, uint256 sz) = _decode_sol_uintN(17, p, bs);
    return (uint136(r), sz);
  }

  function _decode_sol_uint144(uint256 p, bytes memory bs)
    internal
    pure
    returns (uint144, uint256)
  {
    (uint256 r, uint256 sz) = _decode_sol_uintN(18, p, bs);
    return (uint144(r), sz);
  }

  function _decode_sol_uint152(uint256 p, bytes memory bs)
    internal
    pure
    returns (uint152, uint256)
  {
    (uint256 r, uint256 sz) = _decode_sol_uintN(19, p, bs);
    return (uint152(r), sz);
  }

  function _decode_sol_uint160(uint256 p, bytes memory bs)
    internal
    pure
    returns (uint160, uint256)
  {
    (uint256 r, uint256 sz) = _decode_sol_uintN(20, p, bs);
    return (uint160(r), sz);
  }

  function _decode_sol_uint168(uint256 p, bytes memory bs)
    internal
    pure
    returns (uint168, uint256)
  {
    (uint256 r, uint256 sz) = _decode_sol_uintN(21, p, bs);
    return (uint168(r), sz);
  }

  function _decode_sol_uint176(uint256 p, bytes memory bs)
    internal
    pure
    returns (uint176, uint256)
  {
    (uint256 r, uint256 sz) = _decode_sol_uintN(22, p, bs);
    return (uint176(r), sz);
  }

  function _decode_sol_uint184(uint256 p, bytes memory bs)
    internal
    pure
    returns (uint184, uint256)
  {
    (uint256 r, uint256 sz) = _decode_sol_uintN(23, p, bs);
    return (uint184(r), sz);
  }

  function _decode_sol_uint192(uint256 p, bytes memory bs)
    internal
    pure
    returns (uint192, uint256)
  {
    (uint256 r, uint256 sz) = _decode_sol_uintN(24, p, bs);
    return (uint192(r), sz);
  }

  function _decode_sol_uint200(uint256 p, bytes memory bs)
    internal
    pure
    returns (uint200, uint256)
  {
    (uint256 r, uint256 sz) = _decode_sol_uintN(25, p, bs);
    return (uint200(r), sz);
  }

  function _decode_sol_uint208(uint256 p, bytes memory bs)
    internal
    pure
    returns (uint208, uint256)
  {
    (uint256 r, uint256 sz) = _decode_sol_uintN(26, p, bs);
    return (uint208(r), sz);
  }

  function _decode_sol_uint216(uint256 p, bytes memory bs)
    internal
    pure
    returns (uint216, uint256)
  {
    (uint256 r, uint256 sz) = _decode_sol_uintN(27, p, bs);
    return (uint216(r), sz);
  }

  function _decode_sol_uint224(uint256 p, bytes memory bs)
    internal
    pure
    returns (uint224, uint256)
  {
    (uint256 r, uint256 sz) = _decode_sol_uintN(28, p, bs);
    return (uint224(r), sz);
  }

  function _decode_sol_uint232(uint256 p, bytes memory bs)
    internal
    pure
    returns (uint232, uint256)
  {
    (uint256 r, uint256 sz) = _decode_sol_uintN(29, p, bs);
    return (uint232(r), sz);
  }

  function _decode_sol_uint240(uint256 p, bytes memory bs)
    internal
    pure
    returns (uint240, uint256)
  {
    (uint256 r, uint256 sz) = _decode_sol_uintN(30, p, bs);
    return (uint240(r), sz);
  }

  function _decode_sol_uint248(uint256 p, bytes memory bs)
    internal
    pure
    returns (uint248, uint256)
  {
    (uint256 r, uint256 sz) = _decode_sol_uintN(31, p, bs);
    return (uint248(r), sz);
  }

  function _decode_sol_uint256(uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256, uint256)
  {
    (uint256 r, uint256 sz) = _decode_sol_uintN(32, p, bs);
    return (uint256(r), sz);
  }

  function _decode_sol_int(uint256 p, bytes memory bs)
    internal
    pure
    returns (int256, uint256)
  {
    return _decode_sol_int256(p, bs);
  }

  function _decode_sol_intN(uint8 n, uint256 p, bytes memory bs)
    internal
    pure
    returns (int256, uint256)
  {
    (bytes32 u, uint256 sz) = _decode_sol_bytesN_lower(n, p, bs);
    int256 r;
    assembly {
      r := u
      r := signextend(sub(sz, 4), r)
    }
    return (r, sz);
  }

  function _decode_sol_bytes(uint8 n, uint256 p, bytes memory bs)
    internal
    pure
    returns (bytes32, uint256)
  {
    (bytes32 u, uint256 sz) = _decode_sol_bytesN(n, p, bs);
    return (u, sz);
  }

  function _decode_sol_int8(uint256 p, bytes memory bs)
    internal
    pure
    returns (int8, uint256)
  {
    (int256 r, uint256 sz) = _decode_sol_intN(1, p, bs);
    return (int8(r), sz);
  }

  function _decode_sol_int16(uint256 p, bytes memory bs)
    internal
    pure
    returns (int16, uint256)
  {
    (int256 r, uint256 sz) = _decode_sol_intN(2, p, bs);
    return (int16(r), sz);
  }

  function _decode_sol_int24(uint256 p, bytes memory bs)
    internal
    pure
    returns (int24, uint256)
  {
    (int256 r, uint256 sz) = _decode_sol_intN(3, p, bs);
    return (int24(r), sz);
  }

  function _decode_sol_int32(uint256 p, bytes memory bs)
    internal
    pure
    returns (int32, uint256)
  {
    (int256 r, uint256 sz) = _decode_sol_intN(4, p, bs);
    return (int32(r), sz);
  }

  function _decode_sol_int40(uint256 p, bytes memory bs)
    internal
    pure
    returns (int40, uint256)
  {
    (int256 r, uint256 sz) = _decode_sol_intN(5, p, bs);
    return (int40(r), sz);
  }

  function _decode_sol_int48(uint256 p, bytes memory bs)
    internal
    pure
    returns (int48, uint256)
  {
    (int256 r, uint256 sz) = _decode_sol_intN(6, p, bs);
    return (int48(r), sz);
  }

  function _decode_sol_int56(uint256 p, bytes memory bs)
    internal
    pure
    returns (int56, uint256)
  {
    (int256 r, uint256 sz) = _decode_sol_intN(7, p, bs);
    return (int56(r), sz);
  }

  function _decode_sol_int64(uint256 p, bytes memory bs)
    internal
    pure
    returns (int64, uint256)
  {
    (int256 r, uint256 sz) = _decode_sol_intN(8, p, bs);
    return (int64(r), sz);
  }

  function _decode_sol_int72(uint256 p, bytes memory bs)
    internal
    pure
    returns (int72, uint256)
  {
    (int256 r, uint256 sz) = _decode_sol_intN(9, p, bs);
    return (int72(r), sz);
  }

  function _decode_sol_int80(uint256 p, bytes memory bs)
    internal
    pure
    returns (int80, uint256)
  {
    (int256 r, uint256 sz) = _decode_sol_intN(10, p, bs);
    return (int80(r), sz);
  }

  function _decode_sol_int88(uint256 p, bytes memory bs)
    internal
    pure
    returns (int88, uint256)
  {
    (int256 r, uint256 sz) = _decode_sol_intN(11, p, bs);
    return (int88(r), sz);
  }

  function _decode_sol_int96(uint256 p, bytes memory bs)
    internal
    pure
    returns (int96, uint256)
  {
    (int256 r, uint256 sz) = _decode_sol_intN(12, p, bs);
    return (int96(r), sz);
  }

  function _decode_sol_int104(uint256 p, bytes memory bs)
    internal
    pure
    returns (int104, uint256)
  {
    (int256 r, uint256 sz) = _decode_sol_intN(13, p, bs);
    return (int104(r), sz);
  }

  function _decode_sol_int112(uint256 p, bytes memory bs)
    internal
    pure
    returns (int112, uint256)
  {
    (int256 r, uint256 sz) = _decode_sol_intN(14, p, bs);
    return (int112(r), sz);
  }

  function _decode_sol_int120(uint256 p, bytes memory bs)
    internal
    pure
    returns (int120, uint256)
  {
    (int256 r, uint256 sz) = _decode_sol_intN(15, p, bs);
    return (int120(r), sz);
  }

  function _decode_sol_int128(uint256 p, bytes memory bs)
    internal
    pure
    returns (int128, uint256)
  {
    (int256 r, uint256 sz) = _decode_sol_intN(16, p, bs);
    return (int128(r), sz);
  }

  function _decode_sol_int136(uint256 p, bytes memory bs)
    internal
    pure
    returns (int136, uint256)
  {
    (int256 r, uint256 sz) = _decode_sol_intN(17, p, bs);
    return (int136(r), sz);
  }

  function _decode_sol_int144(uint256 p, bytes memory bs)
    internal
    pure
    returns (int144, uint256)
  {
    (int256 r, uint256 sz) = _decode_sol_intN(18, p, bs);
    return (int144(r), sz);
  }

  function _decode_sol_int152(uint256 p, bytes memory bs)
    internal
    pure
    returns (int152, uint256)
  {
    (int256 r, uint256 sz) = _decode_sol_intN(19, p, bs);
    return (int152(r), sz);
  }

  function _decode_sol_int160(uint256 p, bytes memory bs)
    internal
    pure
    returns (int160, uint256)
  {
    (int256 r, uint256 sz) = _decode_sol_intN(20, p, bs);
    return (int160(r), sz);
  }

  function _decode_sol_int168(uint256 p, bytes memory bs)
    internal
    pure
    returns (int168, uint256)
  {
    (int256 r, uint256 sz) = _decode_sol_intN(21, p, bs);
    return (int168(r), sz);
  }

  function _decode_sol_int176(uint256 p, bytes memory bs)
    internal
    pure
    returns (int176, uint256)
  {
    (int256 r, uint256 sz) = _decode_sol_intN(22, p, bs);
    return (int176(r), sz);
  }

  function _decode_sol_int184(uint256 p, bytes memory bs)
    internal
    pure
    returns (int184, uint256)
  {
    (int256 r, uint256 sz) = _decode_sol_intN(23, p, bs);
    return (int184(r), sz);
  }

  function _decode_sol_int192(uint256 p, bytes memory bs)
    internal
    pure
    returns (int192, uint256)
  {
    (int256 r, uint256 sz) = _decode_sol_intN(24, p, bs);
    return (int192(r), sz);
  }

  function _decode_sol_int200(uint256 p, bytes memory bs)
    internal
    pure
    returns (int200, uint256)
  {
    (int256 r, uint256 sz) = _decode_sol_intN(25, p, bs);
    return (int200(r), sz);
  }

  function _decode_sol_int208(uint256 p, bytes memory bs)
    internal
    pure
    returns (int208, uint256)
  {
    (int256 r, uint256 sz) = _decode_sol_intN(26, p, bs);
    return (int208(r), sz);
  }

  function _decode_sol_int216(uint256 p, bytes memory bs)
    internal
    pure
    returns (int216, uint256)
  {
    (int256 r, uint256 sz) = _decode_sol_intN(27, p, bs);
    return (int216(r), sz);
  }

  function _decode_sol_int224(uint256 p, bytes memory bs)
    internal
    pure
    returns (int224, uint256)
  {
    (int256 r, uint256 sz) = _decode_sol_intN(28, p, bs);
    return (int224(r), sz);
  }

  function _decode_sol_int232(uint256 p, bytes memory bs)
    internal
    pure
    returns (int232, uint256)
  {
    (int256 r, uint256 sz) = _decode_sol_intN(29, p, bs);
    return (int232(r), sz);
  }

  function _decode_sol_int240(uint256 p, bytes memory bs)
    internal
    pure
    returns (int240, uint256)
  {
    (int256 r, uint256 sz) = _decode_sol_intN(30, p, bs);
    return (int240(r), sz);
  }

  function _decode_sol_int248(uint256 p, bytes memory bs)
    internal
    pure
    returns (int248, uint256)
  {
    (int256 r, uint256 sz) = _decode_sol_intN(31, p, bs);
    return (int248(r), sz);
  }

  function _decode_sol_int256(uint256 p, bytes memory bs)
    internal
    pure
    returns (int256, uint256)
  {
    (int256 r, uint256 sz) = _decode_sol_intN(32, p, bs);
    return (int256(r), sz);
  }

  function _decode_sol_bytes1(uint256 p, bytes memory bs)
    internal
    pure
    returns (bytes1, uint256)
  {
    (bytes32 r, uint256 sz) = _decode_sol_bytes(1, p, bs);
    return (bytes1(r), sz);
  }

  function _decode_sol_bytes2(uint256 p, bytes memory bs)
    internal
    pure
    returns (bytes2, uint256)
  {
    (bytes32 r, uint256 sz) = _decode_sol_bytes(2, p, bs);
    return (bytes2(r), sz);
  }

  function _decode_sol_bytes3(uint256 p, bytes memory bs)
    internal
    pure
    returns (bytes3, uint256)
  {
    (bytes32 r, uint256 sz) = _decode_sol_bytes(3, p, bs);
    return (bytes3(r), sz);
  }

  function _decode_sol_bytes4(uint256 p, bytes memory bs)
    internal
    pure
    returns (bytes4, uint256)
  {
    (bytes32 r, uint256 sz) = _decode_sol_bytes(4, p, bs);
    return (bytes4(r), sz);
  }

  function _decode_sol_bytes5(uint256 p, bytes memory bs)
    internal
    pure
    returns (bytes5, uint256)
  {
    (bytes32 r, uint256 sz) = _decode_sol_bytes(5, p, bs);
    return (bytes5(r), sz);
  }

  function _decode_sol_bytes6(uint256 p, bytes memory bs)
    internal
    pure
    returns (bytes6, uint256)
  {
    (bytes32 r, uint256 sz) = _decode_sol_bytes(6, p, bs);
    return (bytes6(r), sz);
  }

  function _decode_sol_bytes7(uint256 p, bytes memory bs)
    internal
    pure
    returns (bytes7, uint256)
  {
    (bytes32 r, uint256 sz) = _decode_sol_bytes(7, p, bs);
    return (bytes7(r), sz);
  }

  function _decode_sol_bytes8(uint256 p, bytes memory bs)
    internal
    pure
    returns (bytes8, uint256)
  {
    (bytes32 r, uint256 sz) = _decode_sol_bytes(8, p, bs);
    return (bytes8(r), sz);
  }

  function _decode_sol_bytes9(uint256 p, bytes memory bs)
    internal
    pure
    returns (bytes9, uint256)
  {
    (bytes32 r, uint256 sz) = _decode_sol_bytes(9, p, bs);
    return (bytes9(r), sz);
  }

  function _decode_sol_bytes10(uint256 p, bytes memory bs)
    internal
    pure
    returns (bytes10, uint256)
  {
    (bytes32 r, uint256 sz) = _decode_sol_bytes(10, p, bs);
    return (bytes10(r), sz);
  }

  function _decode_sol_bytes11(uint256 p, bytes memory bs)
    internal
    pure
    returns (bytes11, uint256)
  {
    (bytes32 r, uint256 sz) = _decode_sol_bytes(11, p, bs);
    return (bytes11(r), sz);
  }

  function _decode_sol_bytes12(uint256 p, bytes memory bs)
    internal
    pure
    returns (bytes12, uint256)
  {
    (bytes32 r, uint256 sz) = _decode_sol_bytes(12, p, bs);
    return (bytes12(r), sz);
  }

  function _decode_sol_bytes13(uint256 p, bytes memory bs)
    internal
    pure
    returns (bytes13, uint256)
  {
    (bytes32 r, uint256 sz) = _decode_sol_bytes(13, p, bs);
    return (bytes13(r), sz);
  }

  function _decode_sol_bytes14(uint256 p, bytes memory bs)
    internal
    pure
    returns (bytes14, uint256)
  {
    (bytes32 r, uint256 sz) = _decode_sol_bytes(14, p, bs);
    return (bytes14(r), sz);
  }

  function _decode_sol_bytes15(uint256 p, bytes memory bs)
    internal
    pure
    returns (bytes15, uint256)
  {
    (bytes32 r, uint256 sz) = _decode_sol_bytes(15, p, bs);
    return (bytes15(r), sz);
  }

  function _decode_sol_bytes16(uint256 p, bytes memory bs)
    internal
    pure
    returns (bytes16, uint256)
  {
    (bytes32 r, uint256 sz) = _decode_sol_bytes(16, p, bs);
    return (bytes16(r), sz);
  }

  function _decode_sol_bytes17(uint256 p, bytes memory bs)
    internal
    pure
    returns (bytes17, uint256)
  {
    (bytes32 r, uint256 sz) = _decode_sol_bytes(17, p, bs);
    return (bytes17(r), sz);
  }

  function _decode_sol_bytes18(uint256 p, bytes memory bs)
    internal
    pure
    returns (bytes18, uint256)
  {
    (bytes32 r, uint256 sz) = _decode_sol_bytes(18, p, bs);
    return (bytes18(r), sz);
  }

  function _decode_sol_bytes19(uint256 p, bytes memory bs)
    internal
    pure
    returns (bytes19, uint256)
  {
    (bytes32 r, uint256 sz) = _decode_sol_bytes(19, p, bs);
    return (bytes19(r), sz);
  }

  function _decode_sol_bytes20(uint256 p, bytes memory bs)
    internal
    pure
    returns (bytes20, uint256)
  {
    (bytes32 r, uint256 sz) = _decode_sol_bytes(20, p, bs);
    return (bytes20(r), sz);
  }

  function _decode_sol_bytes21(uint256 p, bytes memory bs)
    internal
    pure
    returns (bytes21, uint256)
  {
    (bytes32 r, uint256 sz) = _decode_sol_bytes(21, p, bs);
    return (bytes21(r), sz);
  }

  function _decode_sol_bytes22(uint256 p, bytes memory bs)
    internal
    pure
    returns (bytes22, uint256)
  {
    (bytes32 r, uint256 sz) = _decode_sol_bytes(22, p, bs);
    return (bytes22(r), sz);
  }

  function _decode_sol_bytes23(uint256 p, bytes memory bs)
    internal
    pure
    returns (bytes23, uint256)
  {
    (bytes32 r, uint256 sz) = _decode_sol_bytes(23, p, bs);
    return (bytes23(r), sz);
  }

  function _decode_sol_bytes24(uint256 p, bytes memory bs)
    internal
    pure
    returns (bytes24, uint256)
  {
    (bytes32 r, uint256 sz) = _decode_sol_bytes(24, p, bs);
    return (bytes24(r), sz);
  }

  function _decode_sol_bytes25(uint256 p, bytes memory bs)
    internal
    pure
    returns (bytes25, uint256)
  {
    (bytes32 r, uint256 sz) = _decode_sol_bytes(25, p, bs);
    return (bytes25(r), sz);
  }

  function _decode_sol_bytes26(uint256 p, bytes memory bs)
    internal
    pure
    returns (bytes26, uint256)
  {
    (bytes32 r, uint256 sz) = _decode_sol_bytes(26, p, bs);
    return (bytes26(r), sz);
  }

  function _decode_sol_bytes27(uint256 p, bytes memory bs)
    internal
    pure
    returns (bytes27, uint256)
  {
    (bytes32 r, uint256 sz) = _decode_sol_bytes(27, p, bs);
    return (bytes27(r), sz);
  }

  function _decode_sol_bytes28(uint256 p, bytes memory bs)
    internal
    pure
    returns (bytes28, uint256)
  {
    (bytes32 r, uint256 sz) = _decode_sol_bytes(28, p, bs);
    return (bytes28(r), sz);
  }

  function _decode_sol_bytes29(uint256 p, bytes memory bs)
    internal
    pure
    returns (bytes29, uint256)
  {
    (bytes32 r, uint256 sz) = _decode_sol_bytes(29, p, bs);
    return (bytes29(r), sz);
  }

  function _decode_sol_bytes30(uint256 p, bytes memory bs)
    internal
    pure
    returns (bytes30, uint256)
  {
    (bytes32 r, uint256 sz) = _decode_sol_bytes(30, p, bs);
    return (bytes30(r), sz);
  }

  function _decode_sol_bytes31(uint256 p, bytes memory bs)
    internal
    pure
    returns (bytes31, uint256)
  {
    (bytes32 r, uint256 sz) = _decode_sol_bytes(31, p, bs);
    return (bytes31(r), sz);
  }

  function _decode_sol_bytes32(uint256 p, bytes memory bs)
    internal
    pure
    returns (bytes32, uint256)
  {
    return _decode_sol_bytes(32, p, bs);
  }

  /*
   * `_encode_sol*` are the concrete implementation of encoding Solidity types
   */
  function _encode_sol_address(address x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol(uint256(uint160(x)), 20, p, bs);
  }

  function _encode_sol_uint(uint256 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol(uint256(x), 32, p, bs);
  }

  function _encode_sol_uint8(uint8 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol(uint256(x), 1, p, bs);
  }

  function _encode_sol_uint16(uint16 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol(uint256(x), 2, p, bs);
  }

  function _encode_sol_uint24(uint24 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol(uint256(x), 3, p, bs);
  }

  function _encode_sol_uint32(uint32 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol(uint256(x), 4, p, bs);
  }

  function _encode_sol_uint40(uint40 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol(uint256(x), 5, p, bs);
  }

  function _encode_sol_uint48(uint48 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol(uint256(x), 6, p, bs);
  }

  function _encode_sol_uint56(uint56 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol(uint256(x), 7, p, bs);
  }

  function _encode_sol_uint64(uint64 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol(uint256(x), 8, p, bs);
  }

  function _encode_sol_uint72(uint72 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol(uint256(x), 9, p, bs);
  }

  function _encode_sol_uint80(uint80 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol(uint256(x), 10, p, bs);
  }

  function _encode_sol_uint88(uint88 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol(uint256(x), 11, p, bs);
  }

  function _encode_sol_uint96(uint96 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol(uint256(x), 12, p, bs);
  }

  function _encode_sol_uint104(uint104 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol(uint256(x), 13, p, bs);
  }

  function _encode_sol_uint112(uint112 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol(uint256(x), 14, p, bs);
  }

  function _encode_sol_uint120(uint120 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol(uint256(x), 15, p, bs);
  }

  function _encode_sol_uint128(uint128 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol(uint256(x), 16, p, bs);
  }

  function _encode_sol_uint136(uint136 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol(uint256(x), 17, p, bs);
  }

  function _encode_sol_uint144(uint144 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol(uint256(x), 18, p, bs);
  }

  function _encode_sol_uint152(uint152 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol(uint256(x), 19, p, bs);
  }

  function _encode_sol_uint160(uint160 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol(uint256(x), 20, p, bs);
  }

  function _encode_sol_uint168(uint168 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol(uint256(x), 21, p, bs);
  }

  function _encode_sol_uint176(uint176 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol(uint256(x), 22, p, bs);
  }

  function _encode_sol_uint184(uint184 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol(uint256(x), 23, p, bs);
  }

  function _encode_sol_uint192(uint192 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol(uint256(x), 24, p, bs);
  }

  function _encode_sol_uint200(uint200 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol(uint256(x), 25, p, bs);
  }

  function _encode_sol_uint208(uint208 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol(uint256(x), 26, p, bs);
  }

  function _encode_sol_uint216(uint216 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol(uint256(x), 27, p, bs);
  }

  function _encode_sol_uint224(uint224 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol(uint256(x), 28, p, bs);
  }

  function _encode_sol_uint232(uint232 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol(uint256(x), 29, p, bs);
  }

  function _encode_sol_uint240(uint240 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol(uint256(x), 30, p, bs);
  }

  function _encode_sol_uint248(uint248 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol(uint256(x), 31, p, bs);
  }

  function _encode_sol_uint256(uint256 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol(uint256(x), 32, p, bs);
  }

  function _encode_sol_int(int256 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol(x, 32, p, bs);
  }

  function _encode_sol_int8(int8 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol(int256(x), 1, p, bs);
  }

  function _encode_sol_int16(int16 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol(int256(x), 2, p, bs);
  }

  function _encode_sol_int24(int24 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol(int256(x), 3, p, bs);
  }

  function _encode_sol_int32(int32 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol(int256(x), 4, p, bs);
  }

  function _encode_sol_int40(int40 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol(int256(x), 5, p, bs);
  }

  function _encode_sol_int48(int48 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol(int256(x), 6, p, bs);
  }

  function _encode_sol_int56(int56 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol(int256(x), 7, p, bs);
  }

  function _encode_sol_int64(int64 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol(int256(x), 8, p, bs);
  }

  function _encode_sol_int72(int72 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol(int256(x), 9, p, bs);
  }

  function _encode_sol_int80(int80 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol(int256(x), 10, p, bs);
  }

  function _encode_sol_int88(int88 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol(int256(x), 11, p, bs);
  }

  function _encode_sol_int96(int96 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol(int256(x), 12, p, bs);
  }

  function _encode_sol_int104(int104 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol(int256(x), 13, p, bs);
  }

  function _encode_sol_int112(int112 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol(int256(x), 14, p, bs);
  }

  function _encode_sol_int120(int120 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol(int256(x), 15, p, bs);
  }

  function _encode_sol_int128(int128 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol(int256(x), 16, p, bs);
  }

  function _encode_sol_int136(int136 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol(int256(x), 17, p, bs);
  }

  function _encode_sol_int144(int144 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol(int256(x), 18, p, bs);
  }

  function _encode_sol_int152(int152 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol(int256(x), 19, p, bs);
  }

  function _encode_sol_int160(int160 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol(int256(x), 20, p, bs);
  }

  function _encode_sol_int168(int168 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol(int256(x), 21, p, bs);
  }

  function _encode_sol_int176(int176 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol(int256(x), 22, p, bs);
  }

  function _encode_sol_int184(int184 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol(int256(x), 23, p, bs);
  }

  function _encode_sol_int192(int192 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol(int256(x), 24, p, bs);
  }

  function _encode_sol_int200(int200 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol(int256(x), 25, p, bs);
  }

  function _encode_sol_int208(int208 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol(int256(x), 26, p, bs);
  }

  function _encode_sol_int216(int216 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol(int256(x), 27, p, bs);
  }

  function _encode_sol_int224(int224 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol(int256(x), 28, p, bs);
  }

  function _encode_sol_int232(int232 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol(int256(x), 29, p, bs);
  }

  function _encode_sol_int240(int240 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol(int256(x), 30, p, bs);
  }

  function _encode_sol_int248(int248 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol(int256(x), 31, p, bs);
  }

  function _encode_sol_int256(int256 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol(x, 32, p, bs);
  }

  function _encode_sol_bytes1(bytes1 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol_bytes(bytes32(x), 1, p, bs);
  }

  function _encode_sol_bytes2(bytes2 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol_bytes(bytes32(x), 2, p, bs);
  }

  function _encode_sol_bytes3(bytes3 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol_bytes(bytes32(x), 3, p, bs);
  }

  function _encode_sol_bytes4(bytes4 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol_bytes(bytes32(x), 4, p, bs);
  }

  function _encode_sol_bytes5(bytes5 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol_bytes(bytes32(x), 5, p, bs);
  }

  function _encode_sol_bytes6(bytes6 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol_bytes(bytes32(x), 6, p, bs);
  }

  function _encode_sol_bytes7(bytes7 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol_bytes(bytes32(x), 7, p, bs);
  }

  function _encode_sol_bytes8(bytes8 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol_bytes(bytes32(x), 8, p, bs);
  }

  function _encode_sol_bytes9(bytes9 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol_bytes(bytes32(x), 9, p, bs);
  }

  function _encode_sol_bytes10(bytes10 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol_bytes(bytes32(x), 10, p, bs);
  }

  function _encode_sol_bytes11(bytes11 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol_bytes(bytes32(x), 11, p, bs);
  }

  function _encode_sol_bytes12(bytes12 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol_bytes(bytes32(x), 12, p, bs);
  }

  function _encode_sol_bytes13(bytes13 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol_bytes(bytes32(x), 13, p, bs);
  }

  function _encode_sol_bytes14(bytes14 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol_bytes(bytes32(x), 14, p, bs);
  }

  function _encode_sol_bytes15(bytes15 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol_bytes(bytes32(x), 15, p, bs);
  }

  function _encode_sol_bytes16(bytes16 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol_bytes(bytes32(x), 16, p, bs);
  }

  function _encode_sol_bytes17(bytes17 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol_bytes(bytes32(x), 17, p, bs);
  }

  function _encode_sol_bytes18(bytes18 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol_bytes(bytes32(x), 18, p, bs);
  }

  function _encode_sol_bytes19(bytes19 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol_bytes(bytes32(x), 19, p, bs);
  }

  function _encode_sol_bytes20(bytes20 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol_bytes(bytes32(x), 20, p, bs);
  }

  function _encode_sol_bytes21(bytes21 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol_bytes(bytes32(x), 21, p, bs);
  }

  function _encode_sol_bytes22(bytes22 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol_bytes(bytes32(x), 22, p, bs);
  }

  function _encode_sol_bytes23(bytes23 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol_bytes(bytes32(x), 23, p, bs);
  }

  function _encode_sol_bytes24(bytes24 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol_bytes(bytes32(x), 24, p, bs);
  }

  function _encode_sol_bytes25(bytes25 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol_bytes(bytes32(x), 25, p, bs);
  }

  function _encode_sol_bytes26(bytes26 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol_bytes(bytes32(x), 26, p, bs);
  }

  function _encode_sol_bytes27(bytes27 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol_bytes(bytes32(x), 27, p, bs);
  }

  function _encode_sol_bytes28(bytes28 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol_bytes(bytes32(x), 28, p, bs);
  }

  function _encode_sol_bytes29(bytes29 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol_bytes(bytes32(x), 29, p, bs);
  }

  function _encode_sol_bytes30(bytes30 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol_bytes(bytes32(x), 30, p, bs);
  }

  function _encode_sol_bytes31(bytes31 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol_bytes(bytes32(x), 31, p, bs);
  }

  function _encode_sol_bytes32(bytes32 x, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    return _encode_sol_bytes(x, 32, p, bs);
  }

  /**
   * @dev Encode the key of Solidity integer and/or fixed-size bytes array.
   * @param sz The number of bytes used to encode Solidity types
   * @param p The offset of bytes array `bs`
   * @param bs The bytes array to encode
   * @return The number of bytes used to encode
   */
  function _encode_sol_header(uint256 sz, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    uint256 offset = p;
    p += _encode_varint(sz + 2, p, bs);
    p += _encode_key(1, WireType.LengthDelim, p, bs);
    p += _encode_varint(sz, p, bs);
    return p - offset;
  }

  /**
   * @dev Encode Solidity type
   * @param x The unsinged integer to be encoded
   * @param sz The number of bytes used to encode Solidity types
   * @param p The offset of bytes array `bs`
   * @param bs The bytes array to encode
   * @return The number of bytes used to encode
   */
  function _encode_sol(uint256 x, uint256 sz, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    uint256 offset = p;
    uint256 size;
    p += 3;
    size = _encode_sol_raw_other(x, p, bs, sz);
    p += size;
    _encode_sol_header(size, offset, bs);
    return p - offset;
  }

  /**
   * @dev Encode Solidity type
   * @param x The signed integer to be encoded
   * @param sz The number of bytes used to encode Solidity types
   * @param p The offset of bytes array `bs`
   * @param bs The bytes array to encode
   * @return The number of bytes used to encode
   */
  function _encode_sol(int256 x, uint256 sz, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    uint256 offset = p;
    uint256 size;
    p += 3;
    size = _encode_sol_raw_other(x, p, bs, sz);
    p += size;
    _encode_sol_header(size, offset, bs);
    return p - offset;
  }

  /**
   * @dev Encode Solidity type
   * @param x The fixed-size byte array to be encoded
   * @param sz The number of bytes used to encode Solidity types
   * @param p The offset of bytes array `bs`
   * @param bs The bytes array to encode
   * @return The number of bytes used to encode
   */
  function _encode_sol_bytes(bytes32 x, uint256 sz, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint256)
  {
    uint256 offset = p;
    uint256 size;
    p += 3;
    size = _encode_sol_raw_bytes_array(x, p, bs, sz);
    p += size;
    _encode_sol_header(size, offset, bs);
    return p - offset;
  }

  /**
   * @dev Get the actual size needed to encoding an unsigned integer
   * @param x The unsigned integer to be encoded
   * @param sz The maximum number of bytes used to encode Solidity types
   * @return The number of bytes needed for encoding `x`
   */
  function _get_real_size(uint256 x, uint256 sz)
    internal
    pure
    returns (uint256)
  {
    uint256 base = 0xff;
    uint256 realSize = sz;
    while (
      x & (base << (realSize * BYTE_SIZE - BYTE_SIZE)) == 0 && realSize > 0
    ) {
      realSize -= 1;
    }
    if (realSize == 0) {
      realSize = 1;
    }
    return realSize;
  }

  /**
   * @dev Get the actual size needed to encoding an signed integer
   * @param x The signed integer to be encoded
   * @param sz The maximum number of bytes used to encode Solidity types
   * @return The number of bytes needed for encoding `x`
   */
  function _get_real_size(int256 x, uint256 sz)
    internal
    pure
    returns (uint256)
  {
    int256 base = 0xff;
    if (x >= 0) {
      uint256 tmp = _get_real_size(uint256(x), sz);
      int256 remainder = (x & (base << (tmp * BYTE_SIZE - BYTE_SIZE))) >>
        (tmp * BYTE_SIZE - BYTE_SIZE);
      if (remainder >= 128) {
        tmp += 1;
      }
      return tmp;
    }

    uint256 realSize = sz;
    while (
      x & (base << (realSize * BYTE_SIZE - BYTE_SIZE)) ==
      (base << (realSize * BYTE_SIZE - BYTE_SIZE)) &&
      realSize > 0
    ) {
      realSize -= 1;
    }
    {
      int256 remainder = (x & (base << (realSize * BYTE_SIZE - BYTE_SIZE))) >>
        (realSize * BYTE_SIZE - BYTE_SIZE);
      if (remainder < 128) {
        realSize += 1;
      }
    }
    return realSize;
  }

  /**
   * @dev Encode the fixed-bytes array
   * @param x The fixed-size byte array to be encoded
   * @param sz The maximum number of bytes used to encode Solidity types
   * @param p The offset of bytes array `bs`
   * @param bs The bytes array to encode
   * @return The number of bytes needed for encoding `x`
   */
  function _encode_sol_raw_bytes_array(
    bytes32 x,
    uint256 p,
    bytes memory bs,
    uint256 sz
  ) internal pure returns (uint256) {
    /**
     * The idea is to not encode the leading bytes of zero.
     */
    uint256 actualSize = sz;
    for (uint256 i = 0; i < sz; i++) {
      uint8 current = uint8(x[sz - 1 - i]);
      if (current == 0 && actualSize > 1) {
        actualSize--;
      } else {
        break;
      }
    }
    assembly {
      let bsptr := add(bs, p)
      let count := actualSize
      for {

      } gt(count, 0) {

      } {
        mstore8(bsptr, byte(sub(actualSize, count), x))
        bsptr := add(bsptr, 1)
        count := sub(count, 1)
      }
    }
    return actualSize;
  }

  /**
   * @dev Encode the signed integer
   * @param x The signed integer to be encoded
   * @param sz The maximum number of bytes used to encode Solidity types
   * @param p The offset of bytes array `bs`
   * @param bs The bytes array to encode
   * @return The number of bytes needed for encoding `x`
   */
  function _encode_sol_raw_other(
    int256 x,
    uint256 p,
    bytes memory bs,
    uint256 sz
  ) internal pure returns (uint256) {
    /**
     * The idea is to not encode the leading bytes of zero.or one,
     * depending on whether it is positive.
     */
    uint256 realSize = _get_real_size(x, sz);
    assembly {
      let bsptr := add(bs, p)
      let count := realSize
      for {

      } gt(count, 0) {

      } {
        mstore8(bsptr, byte(sub(32, count), x))
        bsptr := add(bsptr, 1)
        count := sub(count, 1)
      }
    }
    return realSize;
  }

  /**
   * @dev Encode the unsigned integer
   * @param x The unsigned integer to be encoded
   * @param sz The maximum number of bytes used to encode Solidity types
   * @param p The offset of bytes array `bs`
   * @param bs The bytes array to encode
   * @return The number of bytes needed for encoding `x`
   */
  function _encode_sol_raw_other(
    uint256 x,
    uint256 p,
    bytes memory bs,
    uint256 sz
  ) internal pure returns (uint256) {
    uint256 realSize = _get_real_size(x, sz);
    assembly {
      let bsptr := add(bs, p)
      let count := realSize
      for {

      } gt(count, 0) {

      } {
        mstore8(bsptr, byte(sub(32, count), x))
        bsptr := add(bsptr, 1)
        count := sub(count, 1)
      }
    }
    return realSize;
  }
}


// File @hyperledger-labs/yui-ibc-solidity/contracts/proto/GoogleProtobufAny.sol@v0.1.0

// Original license: SPDX_License_Identifier: Apache-2.0
pragma solidity ^0.8.20;

library GoogleProtobufAny {


  //struct definition
  struct Data {
    string type_url;
    bytes value;
  }

  // Decoder section

  /**
   * @dev The main decoder for memory
   * @param bs The bytes array to be decoded
   * @return The decoded struct
   */
  function decode(bytes memory bs) internal pure returns (Data memory) {
    (Data memory x, ) = _decode(32, bs, bs.length);
    return x;
  }

  /**
   * @dev The main decoder for storage
   * @param self The in-storage struct
   * @param bs The bytes array to be decoded
   */
  function decode(Data storage self, bytes memory bs) internal {
    (Data memory x, ) = _decode(32, bs, bs.length);
    store(x, self);
  }
  // inner decoder

  /**
   * @dev The decoder for internal usage
   * @param p The offset of bytes array to start decode
   * @param bs The bytes array to be decoded
   * @param sz The number of bytes expected
   * @return The decoded struct
   * @return The number of bytes decoded
   */
  function _decode(uint256 p, bytes memory bs, uint256 sz)
    internal
    pure
    returns (Data memory, uint)
  {
    Data memory r;
    uint[3] memory counters;
    uint256 fieldId;
    ProtoBufRuntime.WireType wireType;
    uint256 bytesRead;
    uint256 offset = p;
    uint256 pointer = p;
    while (pointer < offset + sz) {
      (fieldId, wireType, bytesRead) = ProtoBufRuntime._decode_key(pointer, bs);
      pointer += bytesRead;
      if (fieldId == 1) {
        pointer += _read_type_url(pointer, bs, r, counters);
      }
      else if (fieldId == 2) {
        pointer += _read_value(pointer, bs, r, counters);
      }

      else {
        if (wireType == ProtoBufRuntime.WireType.Fixed64) {
          uint256 size;
          (, size) = ProtoBufRuntime._decode_fixed64(pointer, bs);
          pointer += size;
        }
        if (wireType == ProtoBufRuntime.WireType.Fixed32) {
          uint256 size;
          (, size) = ProtoBufRuntime._decode_fixed32(pointer, bs);
          pointer += size;
        }
        if (wireType == ProtoBufRuntime.WireType.Varint) {
          uint256 size;
          (, size) = ProtoBufRuntime._decode_varint(pointer, bs);
          pointer += size;
        }
        if (wireType == ProtoBufRuntime.WireType.LengthDelim) {
          uint256 size;
          (, size) = ProtoBufRuntime._decode_lendelim(pointer, bs);
          pointer += size;
        }
      }

    }
    return (r, sz);
  }

  // field readers

  /**
   * @dev The decoder for reading a field
   * @param p The offset of bytes array to start decode
   * @param bs The bytes array to be decoded
   * @param r The in-memory struct
   * @param counters The counters for repeated fields
   * @return The number of bytes decoded
   */
  function _read_type_url(
    uint256 p,
    bytes memory bs,
    Data memory r,
    uint[3] memory counters
  ) internal pure returns (uint) {
    /**
     * if `r` is NULL, then only counting the number of fields.
     */
    (string memory x, uint256 sz) = ProtoBufRuntime._decode_string(p, bs);
    if (isNil(r)) {
      counters[1] += 1;
    } else {
      r.type_url = x;
      if (counters[1] > 0) counters[1] -= 1;
    }
    return sz;
  }

  /**
   * @dev The decoder for reading a field
   * @param p The offset of bytes array to start decode
   * @param bs The bytes array to be decoded
   * @param r The in-memory struct
   * @param counters The counters for repeated fields
   * @return The number of bytes decoded
   */
  function _read_value(
    uint256 p,
    bytes memory bs,
    Data memory r,
    uint[3] memory counters
  ) internal pure returns (uint) {
    /**
     * if `r` is NULL, then only counting the number of fields.
     */
    (bytes memory x, uint256 sz) = ProtoBufRuntime._decode_bytes(p, bs);
    if (isNil(r)) {
      counters[2] += 1;
    } else {
      r.value = x;
      if (counters[2] > 0) counters[2] -= 1;
    }
    return sz;
  }


  // Encoder section

  /**
   * @dev The main encoder for memory
   * @param r The struct to be encoded
   * @return The encoded byte array
   */
  function encode(Data memory r) internal pure returns (bytes memory) {
    bytes memory bs = new bytes(_estimate(r));
    uint256 sz = _encode(r, 32, bs);
    assembly {
      mstore(bs, sz)
    }
    return bs;
  }
  // inner encoder

  /**
   * @dev The encoder for internal usage
   * @param r The struct to be encoded
   * @param p The offset of bytes array to start decode
   * @param bs The bytes array to be decoded
   * @return The number of bytes encoded
   */
  function _encode(Data memory r, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint)
  {
    uint256 offset = p;
    uint256 pointer = p;

    pointer += ProtoBufRuntime._encode_key(
      1,
      ProtoBufRuntime.WireType.LengthDelim,
      pointer,
      bs
    );
    pointer += ProtoBufRuntime._encode_string(r.type_url, pointer, bs);
    pointer += ProtoBufRuntime._encode_key(
      2,
      ProtoBufRuntime.WireType.LengthDelim,
      pointer,
      bs
    );
    pointer += ProtoBufRuntime._encode_bytes(r.value, pointer, bs);
    return pointer - offset;
  }
  // nested encoder

  /**
   * @dev The encoder for inner struct
   * @param r The struct to be encoded
   * @param p The offset of bytes array to start decode
   * @param bs The bytes array to be decoded
   * @return The number of bytes encoded
   */
  function _encode_nested(Data memory r, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint)
  {
    /**
     * First encoded `r` into a temporary array, and encode the actual size used.
     * Then copy the temporary array into `bs`.
     */
    uint256 offset = p;
    uint256 pointer = p;
    bytes memory tmp = new bytes(_estimate(r));
    uint256 tmpAddr = ProtoBufRuntime.getMemoryAddress(tmp);
    uint256 bsAddr = ProtoBufRuntime.getMemoryAddress(bs);
    uint256 size = _encode(r, 32, tmp);
    pointer += ProtoBufRuntime._encode_varint(size, pointer, bs);
    ProtoBufRuntime.copyBytes(tmpAddr + 32, bsAddr + pointer, size);
    pointer += size;
    delete tmp;
    return pointer - offset;
  }
  // estimator

  /**
   * @dev The estimator for a struct
   * @param r The struct to be encoded
   * @return The number of bytes encoded in estimation
   */
  function _estimate(
    Data memory r
  ) internal pure returns (uint) {
    uint256 e;
    e += 1 + ProtoBufRuntime._sz_lendelim(bytes(r.type_url).length);
    e += 1 + ProtoBufRuntime._sz_lendelim(r.value.length);
    return e;
  }

  //store function
  /**
   * @dev Store in-memory struct to storage
   * @param input The in-memory struct
   * @param output The in-storage struct
   */
  function store(Data memory input, Data storage output) internal {
    output.type_url = input.type_url;
    output.value = input.value;

  }



  //utility functions
  /**
   * @dev Return an empty struct
   * @return r The empty struct
   */
  function nil() internal pure returns (Data memory r) {
    assembly {
      r := 0
    }
  }

  /**
   * @dev Test whether a struct is empty
   * @param x The struct to be tested
   * @return r True if it is empty
   */
  function isNil(Data memory x) internal pure returns (bool r) {
    assembly {
      r := iszero(x)
    }
  }
}
//library Any


// File @hyperledger-labs/yui-ibc-solidity/contracts/proto/Client.sol@v0.1.0

// Original license: SPDX_License_Identifier: Apache-2.0
pragma solidity ^0.8.20;


library Height {


  //struct definition
  struct Data {
    uint64 revision_number;
    uint64 revision_height;
  }

  // Decoder section

  /**
   * @dev The main decoder for memory
   * @param bs The bytes array to be decoded
   * @return The decoded struct
   */
  function decode(bytes memory bs) internal pure returns (Data memory) {
    (Data memory x, ) = _decode(32, bs, bs.length);
    return x;
  }

  /**
   * @dev The main decoder for storage
   * @param self The in-storage struct
   * @param bs The bytes array to be decoded
   */
  function decode(Data storage self, bytes memory bs) internal {
    (Data memory x, ) = _decode(32, bs, bs.length);
    store(x, self);
  }
  // inner decoder

  /**
   * @dev The decoder for internal usage
   * @param p The offset of bytes array to start decode
   * @param bs The bytes array to be decoded
   * @param sz The number of bytes expected
   * @return The decoded struct
   * @return The number of bytes decoded
   */
  function _decode(uint256 p, bytes memory bs, uint256 sz)
    internal
    pure
    returns (Data memory, uint)
  {
    Data memory r;
    uint256 fieldId;
    ProtoBufRuntime.WireType wireType;
    uint256 bytesRead;
    uint256 offset = p;
    uint256 pointer = p;
    while (pointer < offset + sz) {
      (fieldId, wireType, bytesRead) = ProtoBufRuntime._decode_key(pointer, bs);
      pointer += bytesRead;
      if (fieldId == 1) {
        pointer += _read_revision_number(pointer, bs, r);
      } else
      if (fieldId == 2) {
        pointer += _read_revision_height(pointer, bs, r);
      } else
      {
        pointer += ProtoBufRuntime._skip_field_decode(wireType, pointer, bs);
      }

    }
    return (r, sz);
  }

  // field readers

  /**
   * @dev The decoder for reading a field
   * @param p The offset of bytes array to start decode
   * @param bs The bytes array to be decoded
   * @param r The in-memory struct
   * @return The number of bytes decoded
   */
  function _read_revision_number(
    uint256 p,
    bytes memory bs,
    Data memory r
  ) internal pure returns (uint) {
    (uint64 x, uint256 sz) = ProtoBufRuntime._decode_uint64(p, bs);
    r.revision_number = x;
    return sz;
  }

  /**
   * @dev The decoder for reading a field
   * @param p The offset of bytes array to start decode
   * @param bs The bytes array to be decoded
   * @param r The in-memory struct
   * @return The number of bytes decoded
   */
  function _read_revision_height(
    uint256 p,
    bytes memory bs,
    Data memory r
  ) internal pure returns (uint) {
    (uint64 x, uint256 sz) = ProtoBufRuntime._decode_uint64(p, bs);
    r.revision_height = x;
    return sz;
  }


  // Encoder section

  /**
   * @dev The main encoder for memory
   * @param r The struct to be encoded
   * @return The encoded byte array
   */
  function encode(Data memory r) internal pure returns (bytes memory) {
    bytes memory bs = new bytes(_estimate(r));
    uint256 sz = _encode(r, 32, bs);
    assembly {
      mstore(bs, sz)
    }
    return bs;
  }
  // inner encoder

  /**
   * @dev The encoder for internal usage
   * @param r The struct to be encoded
   * @param p The offset of bytes array to start decode
   * @param bs The bytes array to be decoded
   * @return The number of bytes encoded
   */
  function _encode(Data memory r, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint)
  {
    uint256 offset = p;
    uint256 pointer = p;
    
    if (r.revision_number != 0) {
    pointer += ProtoBufRuntime._encode_key(
      1,
      ProtoBufRuntime.WireType.Varint,
      pointer,
      bs
    );
    pointer += ProtoBufRuntime._encode_uint64(r.revision_number, pointer, bs);
    }
    if (r.revision_height != 0) {
    pointer += ProtoBufRuntime._encode_key(
      2,
      ProtoBufRuntime.WireType.Varint,
      pointer,
      bs
    );
    pointer += ProtoBufRuntime._encode_uint64(r.revision_height, pointer, bs);
    }
    return pointer - offset;
  }
  // nested encoder

  /**
   * @dev The encoder for inner struct
   * @param r The struct to be encoded
   * @param p The offset of bytes array to start decode
   * @param bs The bytes array to be decoded
   * @return The number of bytes encoded
   */
  function _encode_nested(Data memory r, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint)
  {
    /**
     * First encoded `r` into a temporary array, and encode the actual size used.
     * Then copy the temporary array into `bs`.
     */
    uint256 offset = p;
    uint256 pointer = p;
    bytes memory tmp = new bytes(_estimate(r));
    uint256 tmpAddr = ProtoBufRuntime.getMemoryAddress(tmp);
    uint256 bsAddr = ProtoBufRuntime.getMemoryAddress(bs);
    uint256 size = _encode(r, 32, tmp);
    pointer += ProtoBufRuntime._encode_varint(size, pointer, bs);
    ProtoBufRuntime.copyBytes(tmpAddr + 32, bsAddr + pointer, size);
    pointer += size;
    delete tmp;
    return pointer - offset;
  }
  // estimator

  /**
   * @dev The estimator for a struct
   * @param r The struct to be encoded
   * @return The number of bytes encoded in estimation
   */
  function _estimate(
    Data memory r
  ) internal pure returns (uint) {
    uint256 e;
    e += 1 + ProtoBufRuntime._sz_uint64(r.revision_number);
    e += 1 + ProtoBufRuntime._sz_uint64(r.revision_height);
    return e;
  }
  // empty checker

  function _empty(
    Data memory r
  ) internal pure returns (bool) {
    
  if (r.revision_number != 0) {
    return false;
  }

  if (r.revision_height != 0) {
    return false;
  }

    return true;
  }


  //store function
  /**
   * @dev Store in-memory struct to storage
   * @param input The in-memory struct
   * @param output The in-storage struct
   */
  function store(Data memory input, Data storage output) internal {
    output.revision_number = input.revision_number;
    output.revision_height = input.revision_height;

  }



  //utility functions
  /**
   * @dev Return an empty struct
   * @return r The empty struct
   */
  function nil() internal pure returns (Data memory r) {
    assembly {
      r := 0
    }
  }

  /**
   * @dev Test whether a struct is empty
   * @param x The struct to be tested
   * @return r True if it is empty
   */
  function isNil(Data memory x) internal pure returns (bool r) {
    assembly {
      r := iszero(x)
    }
  }
}
//library Height


// File @hyperledger-labs/yui-ibc-solidity/contracts/proto/Channel.sol@v0.1.0

// Original license: SPDX_License_Identifier: Apache-2.0
pragma solidity ^0.8.20;



library Channel {

  //enum definition
  // Solidity enum definitions
  enum State {
    STATE_UNINITIALIZED_UNSPECIFIED,
    STATE_INIT,
    STATE_TRYOPEN,
    STATE_OPEN,
    STATE_CLOSED,
    STATE_FLUSHING,
    STATE_FLUSHCOMPLETE
  }


  // Solidity enum encoder
  function encode_State(State x) internal pure returns (int32) {
    
    if (x == State.STATE_UNINITIALIZED_UNSPECIFIED) {
      return 0;
    }

    if (x == State.STATE_INIT) {
      return 1;
    }

    if (x == State.STATE_TRYOPEN) {
      return 2;
    }

    if (x == State.STATE_OPEN) {
      return 3;
    }

    if (x == State.STATE_CLOSED) {
      return 4;
    }

    if (x == State.STATE_FLUSHING) {
      return 5;
    }

    if (x == State.STATE_FLUSHCOMPLETE) {
      return 6;
    }
    revert();
  }


  // Solidity enum decoder
  function decode_State(int64 x) internal pure returns (State) {
    
    if (x == 0) {
      return State.STATE_UNINITIALIZED_UNSPECIFIED;
    }

    if (x == 1) {
      return State.STATE_INIT;
    }

    if (x == 2) {
      return State.STATE_TRYOPEN;
    }

    if (x == 3) {
      return State.STATE_OPEN;
    }

    if (x == 4) {
      return State.STATE_CLOSED;
    }

    if (x == 5) {
      return State.STATE_FLUSHING;
    }

    if (x == 6) {
      return State.STATE_FLUSHCOMPLETE;
    }
    revert();
  }


  /**
   * @dev The estimator for an packed enum array
   * @return The number of bytes encoded
   */
  function estimate_packed_repeated_State(
    State[] memory a
  ) internal pure returns (uint256) {
    uint256 e = 0;
    for (uint i = 0; i < a.length; i++) {
      e += ProtoBufRuntime._sz_enum(encode_State(a[i]));
    }
    return e;
  }

  // Solidity enum definitions
  enum Order {
    ORDER_NONE_UNSPECIFIED,
    ORDER_UNORDERED,
    ORDER_ORDERED
  }


  // Solidity enum encoder
  function encode_Order(Order x) internal pure returns (int32) {
    
    if (x == Order.ORDER_NONE_UNSPECIFIED) {
      return 0;
    }

    if (x == Order.ORDER_UNORDERED) {
      return 1;
    }

    if (x == Order.ORDER_ORDERED) {
      return 2;
    }
    revert();
  }


  // Solidity enum decoder
  function decode_Order(int64 x) internal pure returns (Order) {
    
    if (x == 0) {
      return Order.ORDER_NONE_UNSPECIFIED;
    }

    if (x == 1) {
      return Order.ORDER_UNORDERED;
    }

    if (x == 2) {
      return Order.ORDER_ORDERED;
    }
    revert();
  }


  /**
   * @dev The estimator for an packed enum array
   * @return The number of bytes encoded
   */
  function estimate_packed_repeated_Order(
    Order[] memory a
  ) internal pure returns (uint256) {
    uint256 e = 0;
    for (uint i = 0; i < a.length; i++) {
      e += ProtoBufRuntime._sz_enum(encode_Order(a[i]));
    }
    return e;
  }

  //struct definition
  struct Data {
    Channel.State state;
    Channel.Order ordering;
    ChannelCounterparty.Data counterparty;
    string[] connection_hops;
    string version;
    uint64 upgrade_sequence;
  }

  // Decoder section

  /**
   * @dev The main decoder for memory
   * @param bs The bytes array to be decoded
   * @return The decoded struct
   */
  function decode(bytes memory bs) internal pure returns (Data memory) {
    (Data memory x, ) = _decode(32, bs, bs.length);
    return x;
  }

  /**
   * @dev The main decoder for storage
   * @param self The in-storage struct
   * @param bs The bytes array to be decoded
   */
  function decode(Data storage self, bytes memory bs) internal {
    (Data memory x, ) = _decode(32, bs, bs.length);
    store(x, self);
  }
  // inner decoder

  /**
   * @dev The decoder for internal usage
   * @param p The offset of bytes array to start decode
   * @param bs The bytes array to be decoded
   * @param sz The number of bytes expected
   * @return The decoded struct
   * @return The number of bytes decoded
   */
  function _decode(uint256 p, bytes memory bs, uint256 sz)
    internal
    pure
    returns (Data memory, uint)
  {
    Data memory r;
    uint[7] memory counters;
    uint256 fieldId;
    ProtoBufRuntime.WireType wireType;
    uint256 bytesRead;
    uint256 offset = p;
    uint256 pointer = p;
    while (pointer < offset + sz) {
      (fieldId, wireType, bytesRead) = ProtoBufRuntime._decode_key(pointer, bs);
      pointer += bytesRead;
      if (fieldId == 1) {
        pointer += _read_state(pointer, bs, r);
      } else
      if (fieldId == 2) {
        pointer += _read_ordering(pointer, bs, r);
      } else
      if (fieldId == 3) {
        pointer += _read_counterparty(pointer, bs, r);
      } else
      if (fieldId == 4) {
        pointer += _read_unpacked_repeated_connection_hops(pointer, bs, nil(), counters);
      } else
      if (fieldId == 5) {
        pointer += _read_version(pointer, bs, r);
      } else
      if (fieldId == 6) {
        pointer += _read_upgrade_sequence(pointer, bs, r);
      } else
      {
        pointer += ProtoBufRuntime._skip_field_decode(wireType, pointer, bs);
      }

    }
    pointer = offset;
    if (counters[4] > 0) {
      require(r.connection_hops.length == 0);
      r.connection_hops = new string[](counters[4]);
    }

    while (pointer < offset + sz) {
      (fieldId, wireType, bytesRead) = ProtoBufRuntime._decode_key(pointer, bs);
      pointer += bytesRead;
      if (fieldId == 4) {
        pointer += _read_unpacked_repeated_connection_hops(pointer, bs, r, counters);
      } else
      {
        pointer += ProtoBufRuntime._skip_field_decode(wireType, pointer, bs);
      }
    }
    return (r, sz);
  }

  // field readers

  /**
   * @dev The decoder for reading a field
   * @param p The offset of bytes array to start decode
   * @param bs The bytes array to be decoded
   * @param r The in-memory struct
   * @return The number of bytes decoded
   */
  function _read_state(
    uint256 p,
    bytes memory bs,
    Data memory r
  ) internal pure returns (uint) {
    (int64 tmp, uint256 sz) = ProtoBufRuntime._decode_enum(p, bs);
    Channel.State x = decode_State(tmp);
    r.state = x;
    return sz;
  }

  /**
   * @dev The decoder for reading a field
   * @param p The offset of bytes array to start decode
   * @param bs The bytes array to be decoded
   * @param r The in-memory struct
   * @return The number of bytes decoded
   */
  function _read_ordering(
    uint256 p,
    bytes memory bs,
    Data memory r
  ) internal pure returns (uint) {
    (int64 tmp, uint256 sz) = ProtoBufRuntime._decode_enum(p, bs);
    Channel.Order x = decode_Order(tmp);
    r.ordering = x;
    return sz;
  }

  /**
   * @dev The decoder for reading a field
   * @param p The offset of bytes array to start decode
   * @param bs The bytes array to be decoded
   * @param r The in-memory struct
   * @return The number of bytes decoded
   */
  function _read_counterparty(
    uint256 p,
    bytes memory bs,
    Data memory r
  ) internal pure returns (uint) {
    (ChannelCounterparty.Data memory x, uint256 sz) = _decode_ChannelCounterparty(p, bs);
    r.counterparty = x;
    return sz;
  }

  /**
   * @dev The decoder for reading a field
   * @param p The offset of bytes array to start decode
   * @param bs The bytes array to be decoded
   * @param r The in-memory struct
   * @param counters The counters for repeated fields
   * @return The number of bytes decoded
   */
  function _read_unpacked_repeated_connection_hops(
    uint256 p,
    bytes memory bs,
    Data memory r,
    uint[7] memory counters
  ) internal pure returns (uint) {
    /**
     * if `r` is NULL, then only counting the number of fields.
     */
    (string memory x, uint256 sz) = ProtoBufRuntime._decode_string(p, bs);
    if (isNil(r)) {
      counters[4] += 1;
    } else {
      r.connection_hops[r.connection_hops.length - counters[4]] = x;
      counters[4] -= 1;
    }
    return sz;
  }

  /**
   * @dev The decoder for reading a field
   * @param p The offset of bytes array to start decode
   * @param bs The bytes array to be decoded
   * @param r The in-memory struct
   * @return The number of bytes decoded
   */
  function _read_version(
    uint256 p,
    bytes memory bs,
    Data memory r
  ) internal pure returns (uint) {
    (string memory x, uint256 sz) = ProtoBufRuntime._decode_string(p, bs);
    r.version = x;
    return sz;
  }

  /**
   * @dev The decoder for reading a field
   * @param p The offset of bytes array to start decode
   * @param bs The bytes array to be decoded
   * @param r The in-memory struct
   * @return The number of bytes decoded
   */
  function _read_upgrade_sequence(
    uint256 p,
    bytes memory bs,
    Data memory r
  ) internal pure returns (uint) {
    (uint64 x, uint256 sz) = ProtoBufRuntime._decode_uint64(p, bs);
    r.upgrade_sequence = x;
    return sz;
  }

  // struct decoder
  /**
   * @dev The decoder for reading a inner struct field
   * @param p The offset of bytes array to start decode
   * @param bs The bytes array to be decoded
   * @return The decoded inner-struct
   * @return The number of bytes used to decode
   */
  function _decode_ChannelCounterparty(uint256 p, bytes memory bs)
    internal
    pure
    returns (ChannelCounterparty.Data memory, uint)
  {
    uint256 pointer = p;
    (uint256 sz, uint256 bytesRead) = ProtoBufRuntime._decode_varint(pointer, bs);
    pointer += bytesRead;
    (ChannelCounterparty.Data memory r, ) = ChannelCounterparty._decode(pointer, bs, sz);
    return (r, sz + bytesRead);
  }


  // Encoder section

  /**
   * @dev The main encoder for memory
   * @param r The struct to be encoded
   * @return The encoded byte array
   */
  function encode(Data memory r) internal pure returns (bytes memory) {
    bytes memory bs = new bytes(_estimate(r));
    uint256 sz = _encode(r, 32, bs);
    assembly {
      mstore(bs, sz)
    }
    return bs;
  }
  // inner encoder

  /**
   * @dev The encoder for internal usage
   * @param r The struct to be encoded
   * @param p The offset of bytes array to start decode
   * @param bs The bytes array to be decoded
   * @return The number of bytes encoded
   */
  function _encode(Data memory r, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint)
  {
    uint256 offset = p;
    uint256 pointer = p;
    uint256 i;
    if (uint(r.state) != 0) {
    pointer += ProtoBufRuntime._encode_key(
      1,
      ProtoBufRuntime.WireType.Varint,
      pointer,
      bs
    );
    int32 _enum_state = encode_State(r.state);
    pointer += ProtoBufRuntime._encode_enum(_enum_state, pointer, bs);
    }
    if (uint(r.ordering) != 0) {
    pointer += ProtoBufRuntime._encode_key(
      2,
      ProtoBufRuntime.WireType.Varint,
      pointer,
      bs
    );
    int32 _enum_ordering = encode_Order(r.ordering);
    pointer += ProtoBufRuntime._encode_enum(_enum_ordering, pointer, bs);
    }
    
    pointer += ProtoBufRuntime._encode_key(
      3,
      ProtoBufRuntime.WireType.LengthDelim,
      pointer,
      bs
    );
    pointer += ChannelCounterparty._encode_nested(r.counterparty, pointer, bs);
    
    if (r.connection_hops.length != 0) {
    for(i = 0; i < r.connection_hops.length; i++) {
      pointer += ProtoBufRuntime._encode_key(
        4,
        ProtoBufRuntime.WireType.LengthDelim,
        pointer,
        bs)
      ;
      pointer += ProtoBufRuntime._encode_string(r.connection_hops[i], pointer, bs);
    }
    }
    if (bytes(r.version).length != 0) {
    pointer += ProtoBufRuntime._encode_key(
      5,
      ProtoBufRuntime.WireType.LengthDelim,
      pointer,
      bs
    );
    pointer += ProtoBufRuntime._encode_string(r.version, pointer, bs);
    }
    if (r.upgrade_sequence != 0) {
    pointer += ProtoBufRuntime._encode_key(
      6,
      ProtoBufRuntime.WireType.Varint,
      pointer,
      bs
    );
    pointer += ProtoBufRuntime._encode_uint64(r.upgrade_sequence, pointer, bs);
    }
    return pointer - offset;
  }
  // nested encoder

  /**
   * @dev The encoder for inner struct
   * @param r The struct to be encoded
   * @param p The offset of bytes array to start decode
   * @param bs The bytes array to be decoded
   * @return The number of bytes encoded
   */
  function _encode_nested(Data memory r, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint)
  {
    /**
     * First encoded `r` into a temporary array, and encode the actual size used.
     * Then copy the temporary array into `bs`.
     */
    uint256 offset = p;
    uint256 pointer = p;
    bytes memory tmp = new bytes(_estimate(r));
    uint256 tmpAddr = ProtoBufRuntime.getMemoryAddress(tmp);
    uint256 bsAddr = ProtoBufRuntime.getMemoryAddress(bs);
    uint256 size = _encode(r, 32, tmp);
    pointer += ProtoBufRuntime._encode_varint(size, pointer, bs);
    ProtoBufRuntime.copyBytes(tmpAddr + 32, bsAddr + pointer, size);
    pointer += size;
    delete tmp;
    return pointer - offset;
  }
  // estimator

  /**
   * @dev The estimator for a struct
   * @param r The struct to be encoded
   * @return The number of bytes encoded in estimation
   */
  function _estimate(
    Data memory r
  ) internal pure returns (uint) {
    uint256 e;uint256 i;
    e += 1 + ProtoBufRuntime._sz_enum(encode_State(r.state));
    e += 1 + ProtoBufRuntime._sz_enum(encode_Order(r.ordering));
    e += 1 + ProtoBufRuntime._sz_lendelim(ChannelCounterparty._estimate(r.counterparty));
    for(i = 0; i < r.connection_hops.length; i++) {
      e += 1 + ProtoBufRuntime._sz_lendelim(bytes(r.connection_hops[i]).length);
    }
    e += 1 + ProtoBufRuntime._sz_lendelim(bytes(r.version).length);
    e += 1 + ProtoBufRuntime._sz_uint64(r.upgrade_sequence);
    return e;
  }
  // empty checker

  function _empty(
    Data memory r
  ) internal pure returns (bool) {
    
  if (uint(r.state) != 0) {
    return false;
  }

  if (uint(r.ordering) != 0) {
    return false;
  }

  if (r.connection_hops.length != 0) {
    return false;
  }

  if (bytes(r.version).length != 0) {
    return false;
  }

  if (r.upgrade_sequence != 0) {
    return false;
  }

    return true;
  }


  //store function
  /**
   * @dev Store in-memory struct to storage
   * @param input The in-memory struct
   * @param output The in-storage struct
   */
  function store(Data memory input, Data storage output) internal {
    output.state = input.state;
    output.ordering = input.ordering;
    ChannelCounterparty.store(input.counterparty, output.counterparty);
    output.connection_hops = input.connection_hops;
    output.version = input.version;
    output.upgrade_sequence = input.upgrade_sequence;

  }


  //array helpers for ConnectionHops
  /**
   * @dev Add value to an array
   * @param self The in-memory struct
   * @param value The value to add
   */
  function addConnectionHops(Data memory self, string memory value) internal pure {
    /**
     * First resize the array. Then add the new element to the end.
     */
    string[] memory tmp = new string[](self.connection_hops.length + 1);
    for (uint256 i = 0; i < self.connection_hops.length; i++) {
      tmp[i] = self.connection_hops[i];
    }
    tmp[self.connection_hops.length] = value;
    self.connection_hops = tmp;
  }


  //utility functions
  /**
   * @dev Return an empty struct
   * @return r The empty struct
   */
  function nil() internal pure returns (Data memory r) {
    assembly {
      r := 0
    }
  }

  /**
   * @dev Test whether a struct is empty
   * @param x The struct to be tested
   * @return r True if it is empty
   */
  function isNil(Data memory x) internal pure returns (bool r) {
    assembly {
      r := iszero(x)
    }
  }
}
//library Channel

library ChannelCounterparty {


  //struct definition
  struct Data {
    string port_id;
    string channel_id;
  }

  // Decoder section

  /**
   * @dev The main decoder for memory
   * @param bs The bytes array to be decoded
   * @return The decoded struct
   */
  function decode(bytes memory bs) internal pure returns (Data memory) {
    (Data memory x, ) = _decode(32, bs, bs.length);
    return x;
  }

  /**
   * @dev The main decoder for storage
   * @param self The in-storage struct
   * @param bs The bytes array to be decoded
   */
  function decode(Data storage self, bytes memory bs) internal {
    (Data memory x, ) = _decode(32, bs, bs.length);
    store(x, self);
  }
  // inner decoder

  /**
   * @dev The decoder for internal usage
   * @param p The offset of bytes array to start decode
   * @param bs The bytes array to be decoded
   * @param sz The number of bytes expected
   * @return The decoded struct
   * @return The number of bytes decoded
   */
  function _decode(uint256 p, bytes memory bs, uint256 sz)
    internal
    pure
    returns (Data memory, uint)
  {
    Data memory r;
    uint256 fieldId;
    ProtoBufRuntime.WireType wireType;
    uint256 bytesRead;
    uint256 offset = p;
    uint256 pointer = p;
    while (pointer < offset + sz) {
      (fieldId, wireType, bytesRead) = ProtoBufRuntime._decode_key(pointer, bs);
      pointer += bytesRead;
      if (fieldId == 1) {
        pointer += _read_port_id(pointer, bs, r);
      } else
      if (fieldId == 2) {
        pointer += _read_channel_id(pointer, bs, r);
      } else
      {
        pointer += ProtoBufRuntime._skip_field_decode(wireType, pointer, bs);
      }

    }
    return (r, sz);
  }

  // field readers

  /**
   * @dev The decoder for reading a field
   * @param p The offset of bytes array to start decode
   * @param bs The bytes array to be decoded
   * @param r The in-memory struct
   * @return The number of bytes decoded
   */
  function _read_port_id(
    uint256 p,
    bytes memory bs,
    Data memory r
  ) internal pure returns (uint) {
    (string memory x, uint256 sz) = ProtoBufRuntime._decode_string(p, bs);
    r.port_id = x;
    return sz;
  }

  /**
   * @dev The decoder for reading a field
   * @param p The offset of bytes array to start decode
   * @param bs The bytes array to be decoded
   * @param r The in-memory struct
   * @return The number of bytes decoded
   */
  function _read_channel_id(
    uint256 p,
    bytes memory bs,
    Data memory r
  ) internal pure returns (uint) {
    (string memory x, uint256 sz) = ProtoBufRuntime._decode_string(p, bs);
    r.channel_id = x;
    return sz;
  }


  // Encoder section

  /**
   * @dev The main encoder for memory
   * @param r The struct to be encoded
   * @return The encoded byte array
   */
  function encode(Data memory r) internal pure returns (bytes memory) {
    bytes memory bs = new bytes(_estimate(r));
    uint256 sz = _encode(r, 32, bs);
    assembly {
      mstore(bs, sz)
    }
    return bs;
  }
  // inner encoder

  /**
   * @dev The encoder for internal usage
   * @param r The struct to be encoded
   * @param p The offset of bytes array to start decode
   * @param bs The bytes array to be decoded
   * @return The number of bytes encoded
   */
  function _encode(Data memory r, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint)
  {
    uint256 offset = p;
    uint256 pointer = p;
    
    if (bytes(r.port_id).length != 0) {
    pointer += ProtoBufRuntime._encode_key(
      1,
      ProtoBufRuntime.WireType.LengthDelim,
      pointer,
      bs
    );
    pointer += ProtoBufRuntime._encode_string(r.port_id, pointer, bs);
    }
    if (bytes(r.channel_id).length != 0) {
    pointer += ProtoBufRuntime._encode_key(
      2,
      ProtoBufRuntime.WireType.LengthDelim,
      pointer,
      bs
    );
    pointer += ProtoBufRuntime._encode_string(r.channel_id, pointer, bs);
    }
    return pointer - offset;
  }
  // nested encoder

  /**
   * @dev The encoder for inner struct
   * @param r The struct to be encoded
   * @param p The offset of bytes array to start decode
   * @param bs The bytes array to be decoded
   * @return The number of bytes encoded
   */
  function _encode_nested(Data memory r, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint)
  {
    /**
     * First encoded `r` into a temporary array, and encode the actual size used.
     * Then copy the temporary array into `bs`.
     */
    uint256 offset = p;
    uint256 pointer = p;
    bytes memory tmp = new bytes(_estimate(r));
    uint256 tmpAddr = ProtoBufRuntime.getMemoryAddress(tmp);
    uint256 bsAddr = ProtoBufRuntime.getMemoryAddress(bs);
    uint256 size = _encode(r, 32, tmp);
    pointer += ProtoBufRuntime._encode_varint(size, pointer, bs);
    ProtoBufRuntime.copyBytes(tmpAddr + 32, bsAddr + pointer, size);
    pointer += size;
    delete tmp;
    return pointer - offset;
  }
  // estimator

  /**
   * @dev The estimator for a struct
   * @param r The struct to be encoded
   * @return The number of bytes encoded in estimation
   */
  function _estimate(
    Data memory r
  ) internal pure returns (uint) {
    uint256 e;
    e += 1 + ProtoBufRuntime._sz_lendelim(bytes(r.port_id).length);
    e += 1 + ProtoBufRuntime._sz_lendelim(bytes(r.channel_id).length);
    return e;
  }
  // empty checker

  function _empty(
    Data memory r
  ) internal pure returns (bool) {
    
  if (bytes(r.port_id).length != 0) {
    return false;
  }

  if (bytes(r.channel_id).length != 0) {
    return false;
  }

    return true;
  }


  //store function
  /**
   * @dev Store in-memory struct to storage
   * @param input The in-memory struct
   * @param output The in-storage struct
   */
  function store(Data memory input, Data storage output) internal {
    output.port_id = input.port_id;
    output.channel_id = input.channel_id;

  }



  //utility functions
  /**
   * @dev Return an empty struct
   * @return r The empty struct
   */
  function nil() internal pure returns (Data memory r) {
    assembly {
      r := 0
    }
  }

  /**
   * @dev Test whether a struct is empty
   * @param x The struct to be tested
   * @return r True if it is empty
   */
  function isNil(Data memory x) internal pure returns (bool r) {
    assembly {
      r := iszero(x)
    }
  }
}
//library ChannelCounterparty

library Timeout {


  //struct definition
  struct Data {
    Height.Data height;
    uint64 timestamp;
  }

  // Decoder section

  /**
   * @dev The main decoder for memory
   * @param bs The bytes array to be decoded
   * @return The decoded struct
   */
  function decode(bytes memory bs) internal pure returns (Data memory) {
    (Data memory x, ) = _decode(32, bs, bs.length);
    return x;
  }

  /**
   * @dev The main decoder for storage
   * @param self The in-storage struct
   * @param bs The bytes array to be decoded
   */
  function decode(Data storage self, bytes memory bs) internal {
    (Data memory x, ) = _decode(32, bs, bs.length);
    store(x, self);
  }
  // inner decoder

  /**
   * @dev The decoder for internal usage
   * @param p The offset of bytes array to start decode
   * @param bs The bytes array to be decoded
   * @param sz The number of bytes expected
   * @return The decoded struct
   * @return The number of bytes decoded
   */
  function _decode(uint256 p, bytes memory bs, uint256 sz)
    internal
    pure
    returns (Data memory, uint)
  {
    Data memory r;
    uint256 fieldId;
    ProtoBufRuntime.WireType wireType;
    uint256 bytesRead;
    uint256 offset = p;
    uint256 pointer = p;
    while (pointer < offset + sz) {
      (fieldId, wireType, bytesRead) = ProtoBufRuntime._decode_key(pointer, bs);
      pointer += bytesRead;
      if (fieldId == 1) {
        pointer += _read_height(pointer, bs, r);
      } else
      if (fieldId == 2) {
        pointer += _read_timestamp(pointer, bs, r);
      } else
      {
        pointer += ProtoBufRuntime._skip_field_decode(wireType, pointer, bs);
      }

    }
    return (r, sz);
  }

  // field readers

  /**
   * @dev The decoder for reading a field
   * @param p The offset of bytes array to start decode
   * @param bs The bytes array to be decoded
   * @param r The in-memory struct
   * @return The number of bytes decoded
   */
  function _read_height(
    uint256 p,
    bytes memory bs,
    Data memory r
  ) internal pure returns (uint) {
    (Height.Data memory x, uint256 sz) = _decode_Height(p, bs);
    r.height = x;
    return sz;
  }

  /**
   * @dev The decoder for reading a field
   * @param p The offset of bytes array to start decode
   * @param bs The bytes array to be decoded
   * @param r The in-memory struct
   * @return The number of bytes decoded
   */
  function _read_timestamp(
    uint256 p,
    bytes memory bs,
    Data memory r
  ) internal pure returns (uint) {
    (uint64 x, uint256 sz) = ProtoBufRuntime._decode_uint64(p, bs);
    r.timestamp = x;
    return sz;
  }

  // struct decoder
  /**
   * @dev The decoder for reading a inner struct field
   * @param p The offset of bytes array to start decode
   * @param bs The bytes array to be decoded
   * @return The decoded inner-struct
   * @return The number of bytes used to decode
   */
  function _decode_Height(uint256 p, bytes memory bs)
    internal
    pure
    returns (Height.Data memory, uint)
  {
    uint256 pointer = p;
    (uint256 sz, uint256 bytesRead) = ProtoBufRuntime._decode_varint(pointer, bs);
    pointer += bytesRead;
    (Height.Data memory r, ) = Height._decode(pointer, bs, sz);
    return (r, sz + bytesRead);
  }


  // Encoder section

  /**
   * @dev The main encoder for memory
   * @param r The struct to be encoded
   * @return The encoded byte array
   */
  function encode(Data memory r) internal pure returns (bytes memory) {
    bytes memory bs = new bytes(_estimate(r));
    uint256 sz = _encode(r, 32, bs);
    assembly {
      mstore(bs, sz)
    }
    return bs;
  }
  // inner encoder

  /**
   * @dev The encoder for internal usage
   * @param r The struct to be encoded
   * @param p The offset of bytes array to start decode
   * @param bs The bytes array to be decoded
   * @return The number of bytes encoded
   */
  function _encode(Data memory r, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint)
  {
    uint256 offset = p;
    uint256 pointer = p;
    
    
    pointer += ProtoBufRuntime._encode_key(
      1,
      ProtoBufRuntime.WireType.LengthDelim,
      pointer,
      bs
    );
    pointer += Height._encode_nested(r.height, pointer, bs);
    
    if (r.timestamp != 0) {
    pointer += ProtoBufRuntime._encode_key(
      2,
      ProtoBufRuntime.WireType.Varint,
      pointer,
      bs
    );
    pointer += ProtoBufRuntime._encode_uint64(r.timestamp, pointer, bs);
    }
    return pointer - offset;
  }
  // nested encoder

  /**
   * @dev The encoder for inner struct
   * @param r The struct to be encoded
   * @param p The offset of bytes array to start decode
   * @param bs The bytes array to be decoded
   * @return The number of bytes encoded
   */
  function _encode_nested(Data memory r, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint)
  {
    /**
     * First encoded `r` into a temporary array, and encode the actual size used.
     * Then copy the temporary array into `bs`.
     */
    uint256 offset = p;
    uint256 pointer = p;
    bytes memory tmp = new bytes(_estimate(r));
    uint256 tmpAddr = ProtoBufRuntime.getMemoryAddress(tmp);
    uint256 bsAddr = ProtoBufRuntime.getMemoryAddress(bs);
    uint256 size = _encode(r, 32, tmp);
    pointer += ProtoBufRuntime._encode_varint(size, pointer, bs);
    ProtoBufRuntime.copyBytes(tmpAddr + 32, bsAddr + pointer, size);
    pointer += size;
    delete tmp;
    return pointer - offset;
  }
  // estimator

  /**
   * @dev The estimator for a struct
   * @param r The struct to be encoded
   * @return The number of bytes encoded in estimation
   */
  function _estimate(
    Data memory r
  ) internal pure returns (uint) {
    uint256 e;
    e += 1 + ProtoBufRuntime._sz_lendelim(Height._estimate(r.height));
    e += 1 + ProtoBufRuntime._sz_uint64(r.timestamp);
    return e;
  }
  // empty checker

  function _empty(
    Data memory r
  ) internal pure returns (bool) {
    
  if (r.timestamp != 0) {
    return false;
  }

    return true;
  }


  //store function
  /**
   * @dev Store in-memory struct to storage
   * @param input The in-memory struct
   * @param output The in-storage struct
   */
  function store(Data memory input, Data storage output) internal {
    Height.store(input.height, output.height);
    output.timestamp = input.timestamp;

  }



  //utility functions
  /**
   * @dev Return an empty struct
   * @return r The empty struct
   */
  function nil() internal pure returns (Data memory r) {
    assembly {
      r := 0
    }
  }

  /**
   * @dev Test whether a struct is empty
   * @param x The struct to be tested
   * @return r True if it is empty
   */
  function isNil(Data memory x) internal pure returns (bool r) {
    assembly {
      r := iszero(x)
    }
  }
}
//library Timeout

library Upgrade {


  //struct definition
  struct Data {
    UpgradeFields.Data fields;
    Timeout.Data timeout;
    uint64 next_sequence_send;
  }

  // Decoder section

  /**
   * @dev The main decoder for memory
   * @param bs The bytes array to be decoded
   * @return The decoded struct
   */
  function decode(bytes memory bs) internal pure returns (Data memory) {
    (Data memory x, ) = _decode(32, bs, bs.length);
    return x;
  }

  /**
   * @dev The main decoder for storage
   * @param self The in-storage struct
   * @param bs The bytes array to be decoded
   */
  function decode(Data storage self, bytes memory bs) internal {
    (Data memory x, ) = _decode(32, bs, bs.length);
    store(x, self);
  }
  // inner decoder

  /**
   * @dev The decoder for internal usage
   * @param p The offset of bytes array to start decode
   * @param bs The bytes array to be decoded
   * @param sz The number of bytes expected
   * @return The decoded struct
   * @return The number of bytes decoded
   */
  function _decode(uint256 p, bytes memory bs, uint256 sz)
    internal
    pure
    returns (Data memory, uint)
  {
    Data memory r;
    uint256 fieldId;
    ProtoBufRuntime.WireType wireType;
    uint256 bytesRead;
    uint256 offset = p;
    uint256 pointer = p;
    while (pointer < offset + sz) {
      (fieldId, wireType, bytesRead) = ProtoBufRuntime._decode_key(pointer, bs);
      pointer += bytesRead;
      if (fieldId == 1) {
        pointer += _read_fields(pointer, bs, r);
      } else
      if (fieldId == 2) {
        pointer += _read_timeout(pointer, bs, r);
      } else
      if (fieldId == 3) {
        pointer += _read_next_sequence_send(pointer, bs, r);
      } else
      {
        pointer += ProtoBufRuntime._skip_field_decode(wireType, pointer, bs);
      }

    }
    return (r, sz);
  }

  // field readers

  /**
   * @dev The decoder for reading a field
   * @param p The offset of bytes array to start decode
   * @param bs The bytes array to be decoded
   * @param r The in-memory struct
   * @return The number of bytes decoded
   */
  function _read_fields(
    uint256 p,
    bytes memory bs,
    Data memory r
  ) internal pure returns (uint) {
    (UpgradeFields.Data memory x, uint256 sz) = _decode_UpgradeFields(p, bs);
    r.fields = x;
    return sz;
  }

  /**
   * @dev The decoder for reading a field
   * @param p The offset of bytes array to start decode
   * @param bs The bytes array to be decoded
   * @param r The in-memory struct
   * @return The number of bytes decoded
   */
  function _read_timeout(
    uint256 p,
    bytes memory bs,
    Data memory r
  ) internal pure returns (uint) {
    (Timeout.Data memory x, uint256 sz) = _decode_Timeout(p, bs);
    r.timeout = x;
    return sz;
  }

  /**
   * @dev The decoder for reading a field
   * @param p The offset of bytes array to start decode
   * @param bs The bytes array to be decoded
   * @param r The in-memory struct
   * @return The number of bytes decoded
   */
  function _read_next_sequence_send(
    uint256 p,
    bytes memory bs,
    Data memory r
  ) internal pure returns (uint) {
    (uint64 x, uint256 sz) = ProtoBufRuntime._decode_uint64(p, bs);
    r.next_sequence_send = x;
    return sz;
  }

  // struct decoder
  /**
   * @dev The decoder for reading a inner struct field
   * @param p The offset of bytes array to start decode
   * @param bs The bytes array to be decoded
   * @return The decoded inner-struct
   * @return The number of bytes used to decode
   */
  function _decode_UpgradeFields(uint256 p, bytes memory bs)
    internal
    pure
    returns (UpgradeFields.Data memory, uint)
  {
    uint256 pointer = p;
    (uint256 sz, uint256 bytesRead) = ProtoBufRuntime._decode_varint(pointer, bs);
    pointer += bytesRead;
    (UpgradeFields.Data memory r, ) = UpgradeFields._decode(pointer, bs, sz);
    return (r, sz + bytesRead);
  }

  /**
   * @dev The decoder for reading a inner struct field
   * @param p The offset of bytes array to start decode
   * @param bs The bytes array to be decoded
   * @return The decoded inner-struct
   * @return The number of bytes used to decode
   */
  function _decode_Timeout(uint256 p, bytes memory bs)
    internal
    pure
    returns (Timeout.Data memory, uint)
  {
    uint256 pointer = p;
    (uint256 sz, uint256 bytesRead) = ProtoBufRuntime._decode_varint(pointer, bs);
    pointer += bytesRead;
    (Timeout.Data memory r, ) = Timeout._decode(pointer, bs, sz);
    return (r, sz + bytesRead);
  }


  // Encoder section

  /**
   * @dev The main encoder for memory
   * @param r The struct to be encoded
   * @return The encoded byte array
   */
  function encode(Data memory r) internal pure returns (bytes memory) {
    bytes memory bs = new bytes(_estimate(r));
    uint256 sz = _encode(r, 32, bs);
    assembly {
      mstore(bs, sz)
    }
    return bs;
  }
  // inner encoder

  /**
   * @dev The encoder for internal usage
   * @param r The struct to be encoded
   * @param p The offset of bytes array to start decode
   * @param bs The bytes array to be decoded
   * @return The number of bytes encoded
   */
  function _encode(Data memory r, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint)
  {
    uint256 offset = p;
    uint256 pointer = p;
    
    
    pointer += ProtoBufRuntime._encode_key(
      1,
      ProtoBufRuntime.WireType.LengthDelim,
      pointer,
      bs
    );
    pointer += UpgradeFields._encode_nested(r.fields, pointer, bs);
    
    
    pointer += ProtoBufRuntime._encode_key(
      2,
      ProtoBufRuntime.WireType.LengthDelim,
      pointer,
      bs
    );
    pointer += Timeout._encode_nested(r.timeout, pointer, bs);
    
    if (r.next_sequence_send != 0) {
    pointer += ProtoBufRuntime._encode_key(
      3,
      ProtoBufRuntime.WireType.Varint,
      pointer,
      bs
    );
    pointer += ProtoBufRuntime._encode_uint64(r.next_sequence_send, pointer, bs);
    }
    return pointer - offset;
  }
  // nested encoder

  /**
   * @dev The encoder for inner struct
   * @param r The struct to be encoded
   * @param p The offset of bytes array to start decode
   * @param bs The bytes array to be decoded
   * @return The number of bytes encoded
   */
  function _encode_nested(Data memory r, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint)
  {
    /**
     * First encoded `r` into a temporary array, and encode the actual size used.
     * Then copy the temporary array into `bs`.
     */
    uint256 offset = p;
    uint256 pointer = p;
    bytes memory tmp = new bytes(_estimate(r));
    uint256 tmpAddr = ProtoBufRuntime.getMemoryAddress(tmp);
    uint256 bsAddr = ProtoBufRuntime.getMemoryAddress(bs);
    uint256 size = _encode(r, 32, tmp);
    pointer += ProtoBufRuntime._encode_varint(size, pointer, bs);
    ProtoBufRuntime.copyBytes(tmpAddr + 32, bsAddr + pointer, size);
    pointer += size;
    delete tmp;
    return pointer - offset;
  }
  // estimator

  /**
   * @dev The estimator for a struct
   * @param r The struct to be encoded
   * @return The number of bytes encoded in estimation
   */
  function _estimate(
    Data memory r
  ) internal pure returns (uint) {
    uint256 e;
    e += 1 + ProtoBufRuntime._sz_lendelim(UpgradeFields._estimate(r.fields));
    e += 1 + ProtoBufRuntime._sz_lendelim(Timeout._estimate(r.timeout));
    e += 1 + ProtoBufRuntime._sz_uint64(r.next_sequence_send);
    return e;
  }
  // empty checker

  function _empty(
    Data memory r
  ) internal pure returns (bool) {
    
  if (r.next_sequence_send != 0) {
    return false;
  }

    return true;
  }


  //store function
  /**
   * @dev Store in-memory struct to storage
   * @param input The in-memory struct
   * @param output The in-storage struct
   */
  function store(Data memory input, Data storage output) internal {
    UpgradeFields.store(input.fields, output.fields);
    Timeout.store(input.timeout, output.timeout);
    output.next_sequence_send = input.next_sequence_send;

  }



  //utility functions
  /**
   * @dev Return an empty struct
   * @return r The empty struct
   */
  function nil() internal pure returns (Data memory r) {
    assembly {
      r := 0
    }
  }

  /**
   * @dev Test whether a struct is empty
   * @param x The struct to be tested
   * @return r True if it is empty
   */
  function isNil(Data memory x) internal pure returns (bool r) {
    assembly {
      r := iszero(x)
    }
  }
}
//library Upgrade

library UpgradeFields {


  //struct definition
  struct Data {
    Channel.Order ordering;
    string[] connection_hops;
    string version;
  }

  // Decoder section

  /**
   * @dev The main decoder for memory
   * @param bs The bytes array to be decoded
   * @return The decoded struct
   */
  function decode(bytes memory bs) internal pure returns (Data memory) {
    (Data memory x, ) = _decode(32, bs, bs.length);
    return x;
  }

  /**
   * @dev The main decoder for storage
   * @param self The in-storage struct
   * @param bs The bytes array to be decoded
   */
  function decode(Data storage self, bytes memory bs) internal {
    (Data memory x, ) = _decode(32, bs, bs.length);
    store(x, self);
  }
  // inner decoder

  /**
   * @dev The decoder for internal usage
   * @param p The offset of bytes array to start decode
   * @param bs The bytes array to be decoded
   * @param sz The number of bytes expected
   * @return The decoded struct
   * @return The number of bytes decoded
   */
  function _decode(uint256 p, bytes memory bs, uint256 sz)
    internal
    pure
    returns (Data memory, uint)
  {
    Data memory r;
    uint[4] memory counters;
    uint256 fieldId;
    ProtoBufRuntime.WireType wireType;
    uint256 bytesRead;
    uint256 offset = p;
    uint256 pointer = p;
    while (pointer < offset + sz) {
      (fieldId, wireType, bytesRead) = ProtoBufRuntime._decode_key(pointer, bs);
      pointer += bytesRead;
      if (fieldId == 1) {
        pointer += _read_ordering(pointer, bs, r);
      } else
      if (fieldId == 2) {
        pointer += _read_unpacked_repeated_connection_hops(pointer, bs, nil(), counters);
      } else
      if (fieldId == 3) {
        pointer += _read_version(pointer, bs, r);
      } else
      {
        pointer += ProtoBufRuntime._skip_field_decode(wireType, pointer, bs);
      }

    }
    pointer = offset;
    if (counters[2] > 0) {
      require(r.connection_hops.length == 0);
      r.connection_hops = new string[](counters[2]);
    }

    while (pointer < offset + sz) {
      (fieldId, wireType, bytesRead) = ProtoBufRuntime._decode_key(pointer, bs);
      pointer += bytesRead;
      if (fieldId == 2) {
        pointer += _read_unpacked_repeated_connection_hops(pointer, bs, r, counters);
      } else
      {
        pointer += ProtoBufRuntime._skip_field_decode(wireType, pointer, bs);
      }
    }
    return (r, sz);
  }

  // field readers

  /**
   * @dev The decoder for reading a field
   * @param p The offset of bytes array to start decode
   * @param bs The bytes array to be decoded
   * @param r The in-memory struct
   * @return The number of bytes decoded
   */
  function _read_ordering(
    uint256 p,
    bytes memory bs,
    Data memory r
  ) internal pure returns (uint) {
    (int64 tmp, uint256 sz) = ProtoBufRuntime._decode_enum(p, bs);
    Channel.Order x = Channel.decode_Order(tmp);
    r.ordering = x;
    return sz;
  }

  /**
   * @dev The decoder for reading a field
   * @param p The offset of bytes array to start decode
   * @param bs The bytes array to be decoded
   * @param r The in-memory struct
   * @param counters The counters for repeated fields
   * @return The number of bytes decoded
   */
  function _read_unpacked_repeated_connection_hops(
    uint256 p,
    bytes memory bs,
    Data memory r,
    uint[4] memory counters
  ) internal pure returns (uint) {
    /**
     * if `r` is NULL, then only counting the number of fields.
     */
    (string memory x, uint256 sz) = ProtoBufRuntime._decode_string(p, bs);
    if (isNil(r)) {
      counters[2] += 1;
    } else {
      r.connection_hops[r.connection_hops.length - counters[2]] = x;
      counters[2] -= 1;
    }
    return sz;
  }

  /**
   * @dev The decoder for reading a field
   * @param p The offset of bytes array to start decode
   * @param bs The bytes array to be decoded
   * @param r The in-memory struct
   * @return The number of bytes decoded
   */
  function _read_version(
    uint256 p,
    bytes memory bs,
    Data memory r
  ) internal pure returns (uint) {
    (string memory x, uint256 sz) = ProtoBufRuntime._decode_string(p, bs);
    r.version = x;
    return sz;
  }


  // Encoder section

  /**
   * @dev The main encoder for memory
   * @param r The struct to be encoded
   * @return The encoded byte array
   */
  function encode(Data memory r) internal pure returns (bytes memory) {
    bytes memory bs = new bytes(_estimate(r));
    uint256 sz = _encode(r, 32, bs);
    assembly {
      mstore(bs, sz)
    }
    return bs;
  }
  // inner encoder

  /**
   * @dev The encoder for internal usage
   * @param r The struct to be encoded
   * @param p The offset of bytes array to start decode
   * @param bs The bytes array to be decoded
   * @return The number of bytes encoded
   */
  function _encode(Data memory r, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint)
  {
    uint256 offset = p;
    uint256 pointer = p;
    uint256 i;
    if (uint(r.ordering) != 0) {
    pointer += ProtoBufRuntime._encode_key(
      1,
      ProtoBufRuntime.WireType.Varint,
      pointer,
      bs
    );
    int32 _enum_ordering = Channel.encode_Order(r.ordering);
    pointer += ProtoBufRuntime._encode_enum(_enum_ordering, pointer, bs);
    }
    if (r.connection_hops.length != 0) {
    for(i = 0; i < r.connection_hops.length; i++) {
      pointer += ProtoBufRuntime._encode_key(
        2,
        ProtoBufRuntime.WireType.LengthDelim,
        pointer,
        bs)
      ;
      pointer += ProtoBufRuntime._encode_string(r.connection_hops[i], pointer, bs);
    }
    }
    if (bytes(r.version).length != 0) {
    pointer += ProtoBufRuntime._encode_key(
      3,
      ProtoBufRuntime.WireType.LengthDelim,
      pointer,
      bs
    );
    pointer += ProtoBufRuntime._encode_string(r.version, pointer, bs);
    }
    return pointer - offset;
  }
  // nested encoder

  /**
   * @dev The encoder for inner struct
   * @param r The struct to be encoded
   * @param p The offset of bytes array to start decode
   * @param bs The bytes array to be decoded
   * @return The number of bytes encoded
   */
  function _encode_nested(Data memory r, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint)
  {
    /**
     * First encoded `r` into a temporary array, and encode the actual size used.
     * Then copy the temporary array into `bs`.
     */
    uint256 offset = p;
    uint256 pointer = p;
    bytes memory tmp = new bytes(_estimate(r));
    uint256 tmpAddr = ProtoBufRuntime.getMemoryAddress(tmp);
    uint256 bsAddr = ProtoBufRuntime.getMemoryAddress(bs);
    uint256 size = _encode(r, 32, tmp);
    pointer += ProtoBufRuntime._encode_varint(size, pointer, bs);
    ProtoBufRuntime.copyBytes(tmpAddr + 32, bsAddr + pointer, size);
    pointer += size;
    delete tmp;
    return pointer - offset;
  }
  // estimator

  /**
   * @dev The estimator for a struct
   * @param r The struct to be encoded
   * @return The number of bytes encoded in estimation
   */
  function _estimate(
    Data memory r
  ) internal pure returns (uint) {
    uint256 e;uint256 i;
    e += 1 + ProtoBufRuntime._sz_enum(Channel.encode_Order(r.ordering));
    for(i = 0; i < r.connection_hops.length; i++) {
      e += 1 + ProtoBufRuntime._sz_lendelim(bytes(r.connection_hops[i]).length);
    }
    e += 1 + ProtoBufRuntime._sz_lendelim(bytes(r.version).length);
    return e;
  }
  // empty checker

  function _empty(
    Data memory r
  ) internal pure returns (bool) {
    
  if (uint(r.ordering) != 0) {
    return false;
  }

  if (r.connection_hops.length != 0) {
    return false;
  }

  if (bytes(r.version).length != 0) {
    return false;
  }

    return true;
  }


  //store function
  /**
   * @dev Store in-memory struct to storage
   * @param input The in-memory struct
   * @param output The in-storage struct
   */
  function store(Data memory input, Data storage output) internal {
    output.ordering = input.ordering;
    output.connection_hops = input.connection_hops;
    output.version = input.version;

  }


  //array helpers for ConnectionHops
  /**
   * @dev Add value to an array
   * @param self The in-memory struct
   * @param value The value to add
   */
  function addConnectionHops(Data memory self, string memory value) internal pure {
    /**
     * First resize the array. Then add the new element to the end.
     */
    string[] memory tmp = new string[](self.connection_hops.length + 1);
    for (uint256 i = 0; i < self.connection_hops.length; i++) {
      tmp[i] = self.connection_hops[i];
    }
    tmp[self.connection_hops.length] = value;
    self.connection_hops = tmp;
  }


  //utility functions
  /**
   * @dev Return an empty struct
   * @return r The empty struct
   */
  function nil() internal pure returns (Data memory r) {
    assembly {
      r := 0
    }
  }

  /**
   * @dev Test whether a struct is empty
   * @param x The struct to be tested
   * @return r True if it is empty
   */
  function isNil(Data memory x) internal pure returns (bool r) {
    assembly {
      r := iszero(x)
    }
  }
}
//library UpgradeFields

library ErrorReceipt {


  //struct definition
  struct Data {
    uint64 sequence;
    string message;
  }

  // Decoder section

  /**
   * @dev The main decoder for memory
   * @param bs The bytes array to be decoded
   * @return The decoded struct
   */
  function decode(bytes memory bs) internal pure returns (Data memory) {
    (Data memory x, ) = _decode(32, bs, bs.length);
    return x;
  }

  /**
   * @dev The main decoder for storage
   * @param self The in-storage struct
   * @param bs The bytes array to be decoded
   */
  function decode(Data storage self, bytes memory bs) internal {
    (Data memory x, ) = _decode(32, bs, bs.length);
    store(x, self);
  }
  // inner decoder

  /**
   * @dev The decoder for internal usage
   * @param p The offset of bytes array to start decode
   * @param bs The bytes array to be decoded
   * @param sz The number of bytes expected
   * @return The decoded struct
   * @return The number of bytes decoded
   */
  function _decode(uint256 p, bytes memory bs, uint256 sz)
    internal
    pure
    returns (Data memory, uint)
  {
    Data memory r;
    uint256 fieldId;
    ProtoBufRuntime.WireType wireType;
    uint256 bytesRead;
    uint256 offset = p;
    uint256 pointer = p;
    while (pointer < offset + sz) {
      (fieldId, wireType, bytesRead) = ProtoBufRuntime._decode_key(pointer, bs);
      pointer += bytesRead;
      if (fieldId == 1) {
        pointer += _read_sequence(pointer, bs, r);
      } else
      if (fieldId == 2) {
        pointer += _read_message(pointer, bs, r);
      } else
      {
        pointer += ProtoBufRuntime._skip_field_decode(wireType, pointer, bs);
      }

    }
    return (r, sz);
  }

  // field readers

  /**
   * @dev The decoder for reading a field
   * @param p The offset of bytes array to start decode
   * @param bs The bytes array to be decoded
   * @param r The in-memory struct
   * @return The number of bytes decoded
   */
  function _read_sequence(
    uint256 p,
    bytes memory bs,
    Data memory r
  ) internal pure returns (uint) {
    (uint64 x, uint256 sz) = ProtoBufRuntime._decode_uint64(p, bs);
    r.sequence = x;
    return sz;
  }

  /**
   * @dev The decoder for reading a field
   * @param p The offset of bytes array to start decode
   * @param bs The bytes array to be decoded
   * @param r The in-memory struct
   * @return The number of bytes decoded
   */
  function _read_message(
    uint256 p,
    bytes memory bs,
    Data memory r
  ) internal pure returns (uint) {
    (string memory x, uint256 sz) = ProtoBufRuntime._decode_string(p, bs);
    r.message = x;
    return sz;
  }


  // Encoder section

  /**
   * @dev The main encoder for memory
   * @param r The struct to be encoded
   * @return The encoded byte array
   */
  function encode(Data memory r) internal pure returns (bytes memory) {
    bytes memory bs = new bytes(_estimate(r));
    uint256 sz = _encode(r, 32, bs);
    assembly {
      mstore(bs, sz)
    }
    return bs;
  }
  // inner encoder

  /**
   * @dev The encoder for internal usage
   * @param r The struct to be encoded
   * @param p The offset of bytes array to start decode
   * @param bs The bytes array to be decoded
   * @return The number of bytes encoded
   */
  function _encode(Data memory r, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint)
  {
    uint256 offset = p;
    uint256 pointer = p;
    
    if (r.sequence != 0) {
    pointer += ProtoBufRuntime._encode_key(
      1,
      ProtoBufRuntime.WireType.Varint,
      pointer,
      bs
    );
    pointer += ProtoBufRuntime._encode_uint64(r.sequence, pointer, bs);
    }
    if (bytes(r.message).length != 0) {
    pointer += ProtoBufRuntime._encode_key(
      2,
      ProtoBufRuntime.WireType.LengthDelim,
      pointer,
      bs
    );
    pointer += ProtoBufRuntime._encode_string(r.message, pointer, bs);
    }
    return pointer - offset;
  }
  // nested encoder

  /**
   * @dev The encoder for inner struct
   * @param r The struct to be encoded
   * @param p The offset of bytes array to start decode
   * @param bs The bytes array to be decoded
   * @return The number of bytes encoded
   */
  function _encode_nested(Data memory r, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint)
  {
    /**
     * First encoded `r` into a temporary array, and encode the actual size used.
     * Then copy the temporary array into `bs`.
     */
    uint256 offset = p;
    uint256 pointer = p;
    bytes memory tmp = new bytes(_estimate(r));
    uint256 tmpAddr = ProtoBufRuntime.getMemoryAddress(tmp);
    uint256 bsAddr = ProtoBufRuntime.getMemoryAddress(bs);
    uint256 size = _encode(r, 32, tmp);
    pointer += ProtoBufRuntime._encode_varint(size, pointer, bs);
    ProtoBufRuntime.copyBytes(tmpAddr + 32, bsAddr + pointer, size);
    pointer += size;
    delete tmp;
    return pointer - offset;
  }
  // estimator

  /**
   * @dev The estimator for a struct
   * @param r The struct to be encoded
   * @return The number of bytes encoded in estimation
   */
  function _estimate(
    Data memory r
  ) internal pure returns (uint) {
    uint256 e;
    e += 1 + ProtoBufRuntime._sz_uint64(r.sequence);
    e += 1 + ProtoBufRuntime._sz_lendelim(bytes(r.message).length);
    return e;
  }
  // empty checker

  function _empty(
    Data memory r
  ) internal pure returns (bool) {
    
  if (r.sequence != 0) {
    return false;
  }

  if (bytes(r.message).length != 0) {
    return false;
  }

    return true;
  }


  //store function
  /**
   * @dev Store in-memory struct to storage
   * @param input The in-memory struct
   * @param output The in-storage struct
   */
  function store(Data memory input, Data storage output) internal {
    output.sequence = input.sequence;
    output.message = input.message;

  }



  //utility functions
  /**
   * @dev Return an empty struct
   * @return r The empty struct
   */
  function nil() internal pure returns (Data memory r) {
    assembly {
      r := 0
    }
  }

  /**
   * @dev Test whether a struct is empty
   * @param x The struct to be tested
   * @return r True if it is empty
   */
  function isNil(Data memory x) internal pure returns (bool r) {
    assembly {
      r := iszero(x)
    }
  }
}
//library ErrorReceipt


// File @hyperledger-labs/yui-ibc-solidity/contracts/core/04-channel/IIBCChannel.sol@v0.1.0

// Original license: SPDX_License_Identifier: Apache-2.0
pragma solidity ^0.8.20;


/// @notice Packet defines a type that carries data across different chains through IBC.
/// @param sequence corresponds to the order of sends and receives, where a packet with an earlier sequence number must be sent and received before a packet with a later sequence number
/// @param sourcePort identifies the port on the sending chain
/// @param sourceChannel identifies the channel end on the sending chain
/// @param destPort identifies the port on the receiving chain
/// @param destChannel identifies the channel end on the receiving chain
/// @param data is an opaque value which can be defined by the application logic of the associated modules
/// @param timeoutHeight indicates a consensus height on the destination chain after which the packet will no longer be processed, and will instead count as having timed-out
/// @param timeoutTimestamp indicates a timestamp on the destination chain after which the packet will no longer be processed, and will instead count as having timed-out
struct Packet {
    uint64 sequence;
    string sourcePort;
    string sourceChannel;
    string destinationPort;
    string destinationChannel;
    bytes data;
    Height.Data timeoutHeight;
    uint64 timeoutTimestamp;
}

interface IIBCChannelHandshake {
    // --------------------- Data Structure --------------------- //

    struct MsgChannelOpenInit {
        string portId;
        Channel.Data channel;
    }

    struct MsgChannelOpenTry {
        string portId;
        Channel.Data channel;
        string counterpartyVersion;
        bytes proofInit;
        Height.Data proofHeight;
    }

    struct MsgChannelOpenAck {
        string portId;
        string channelId;
        string counterpartyVersion;
        string counterpartyChannelId;
        bytes proofTry;
        Height.Data proofHeight;
    }

    struct MsgChannelOpenConfirm {
        string portId;
        string channelId;
        bytes proofAck;
        Height.Data proofHeight;
    }

    struct MsgChannelCloseInit {
        string portId;
        string channelId;
    }

    struct MsgChannelCloseConfirm {
        string portId;
        string channelId;
        bytes proofInit;
        Height.Data proofHeight;
    }

    // --------------------- Events --------------------- //

    /// @param channelId channel identifier
    event GeneratedChannelIdentifier(string channelId);

    // --------------------- Functions --------------------- //

    /**
     * @dev channelOpenInit is called by a module to initiate a channel opening handshake with a module on another chain.
     */
    function channelOpenInit(MsgChannelOpenInit calldata msg_)
        external
        returns (string memory channelId, string memory version);

    /**
     * @dev channelOpenTry is called by a module to accept the first step of a channel opening handshake initiated by a module on another chain.
     */
    function channelOpenTry(MsgChannelOpenTry calldata msg_)
        external
        returns (string memory channelId, string memory version);

    /**
     * @dev channelOpenAck is called by the handshake-originating module to acknowledge the acceptance of the initial request by the counterparty module on the other chain.
     */
    function channelOpenAck(MsgChannelOpenAck calldata msg_) external;

    /**
     * @dev channelOpenConfirm is called by the counterparty module to close their end of the channel, since the other end has been closed.
     */
    function channelOpenConfirm(MsgChannelOpenConfirm calldata msg_) external;

    /**
     * @dev channelCloseInit is called by either module to close their end of the channel. Once closed, channels cannot be reopened.
     */
    function channelCloseInit(MsgChannelCloseInit calldata msg_) external;

    /**
     * @dev channelCloseConfirm is called by the counterparty module to close their end of the
     * channel, since the other end has been closed.
     */
    function channelCloseConfirm(MsgChannelCloseConfirm calldata msg_) external;
}

interface IICS04SendPacket {
    // --------------------- Events --------------------- //

    /// @notice event emitted upon sending a packet
    event SendPacket(
        uint64 sequence,
        string sourcePort,
        string sourceChannel,
        Height.Data timeoutHeight,
        uint64 timeoutTimestamp,
        bytes data
    );

    // --------------------- Functions --------------------- //

    /**
     * @dev sendPacket is called by a module in order to send an IBC packet on a channel.
     * The packet sequence generated for the packet to be sent is returned. An error
     * is returned if one occurs. Also, `timeoutTimestamp` is given in nanoseconds since unix epoch.
     */
    function sendPacket(
        string calldata sourcePort,
        string calldata sourceChannel,
        Height.Data calldata timeoutHeight,
        uint64 timeoutTimestamp,
        bytes calldata data
    ) external returns (uint64);
}

interface IICS04WriteAcknowledgement {
    // --------------------- Events --------------------- //

    /// @notice event emitted upon writing an acknowledgement
    /// @param destinationPortId destination port
    /// @param destinationChannel destination channel
    /// @param sequence packet sequence
    /// @param acknowledgement acknowledgement
    event WriteAcknowledgement(
        string destinationPortId, string destinationChannel, uint64 sequence, bytes acknowledgement
    );

    // --------------------- Functions --------------------- //

    /**
     * @dev writeAcknowledgement writes the packet execution acknowledgement to the state,
     * which will be verified by the counterparty chain using AcknowledgePacket.
     */
    function writeAcknowledgement(
        string calldata destinationPortId,
        string calldata destinationChannel,
        uint64 sequence,
        bytes calldata acknowledgement
    ) external;
}

interface IIBCChannelRecvPacket {
    // --------------------- Data Structure --------------------- //

    struct MsgPacketRecv {
        Packet packet;
        bytes proof;
        Height.Data proofHeight;
    }

    // --------------------- Events --------------------- //

    /// @notice event emitted upon receiving a packet
    event RecvPacket(Packet packet);

    // --------------------- Functions --------------------- //

    /**
     * @dev recvPacket is called by a module in order to receive & process an IBC packet
     * sent on the corresponding channel end on the counterparty chain.
     */
    function recvPacket(MsgPacketRecv calldata msg_) external;
}

interface IIBCChannelAcknowledgePacket {
    // --------------------- Data Structure --------------------- //

    struct MsgPacketAcknowledgement {
        Packet packet;
        bytes acknowledgement;
        bytes proof;
        Height.Data proofHeight;
    }

    // --------------------- Events --------------------- //

    /// @notice event emitted upon acknowledging a packet
    event AcknowledgePacket(Packet packet, bytes acknowledgement);

    // --------------------- Functions --------------------- //

    /**
     * @dev AcknowledgePacket is called by a module to process the acknowledgement of a
     * packet previously sent by the calling module on a channel to a counterparty
     * module on the counterparty chain. Its intended usage is within the ante
     * handler. AcknowledgePacket will clean up the packet commitment,
     * which is no longer necessary since the packet has been received and acted upon.
     * It will also increment NextSequenceAck in case of ORDERED channels.
     */
    function acknowledgePacket(MsgPacketAcknowledgement calldata msg_) external;
}

interface IIBCChannelPacketTimeout {
    // --------------------- Data Structure --------------------- //

    struct MsgTimeoutPacket {
        Packet packet;
        bytes proof;
        Height.Data proofHeight;
        uint64 nextSequenceRecv;
    }

    struct MsgTimeoutOnClose {
        Packet packet;
        bytes proofUnreceived;
        bytes proofClose;
        Height.Data proofHeight;
        uint64 nextSequenceRecv;
        uint64 counterpartyUpgradeSequence;
    }

    // --------------------- Events --------------------- //

    /// @notice event emitted upon timeout of a packet
    event TimeoutPacket(Packet packet);

    // --------------------- Functions --------------------- //

    /**
     * @dev TimeoutPacket is called by a module which originally attempted to send a
     * packet to a counterparty module, where the timeout height has passed on the
     * counterparty chain without the packet being committed, to prove that the
     * packet can no longer be executed and to allow the calling module to safely
     * perform appropriate state transitions. Its intended usage is within the
     * ante handler.
     */
    function timeoutPacket(MsgTimeoutPacket calldata msg_) external;

    /**
     * @dev TimeoutOnClose is called by a module in order to prove that the channel to
     * which an unreceived packet was addressed has been closed, so the packet will
     * never be received (even if the timeoutHeight has not yet been reached).
     */
    function timeoutOnClose(MsgTimeoutOnClose calldata msg_) external;
}

interface IICS04Wrapper is IICS04SendPacket, IICS04WriteAcknowledgement {}

interface IIBCChannelPacketSendRecv is IICS04Wrapper, IIBCChannelRecvPacket, IIBCChannelAcknowledgePacket {}

interface IIBCChannelPacket is IIBCChannelPacketSendRecv, IIBCChannelPacketTimeout {}


// File @openzeppelin/contracts/utils/introspection/IERC165.sol@v5.0.2

// Original license: SPDX_License_Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.0) (utils/introspection/IERC165.sol)

pragma solidity ^0.8.20;

/**
 * @dev Interface of the ERC165 standard, as defined in the
 * https://eips.ethereum.org/EIPS/eip-165[EIP].
 *
 * Implementers can declare support of contract interfaces, which can then be
 * queried by others ({ERC165Checker}).
 *
 * For an implementation, see {ERC165}.
 */
interface IERC165 {
    /**
     * @dev Returns true if this contract implements the interface defined by
     * `interfaceId`. See the corresponding
     * https://eips.ethereum.org/EIPS/eip-165#how-interfaces-are-identified[EIP section]
     * to learn more about how these ids are created.
     *
     * This function call must use less than 30 000 gas.
     */
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}


// File @hyperledger-labs/yui-ibc-solidity/contracts/core/26-router/IIBCModule.sol@v0.1.0

// Original license: SPDX_License_Identifier: Apache-2.0
pragma solidity ^0.8.20;



/**
 * @notice IIBCModuleInitializer is an interface that defines the callbacks that modules must define as specified in ICS-26
 * @dev IBCModules registered with IBCModuleManager via `bindPort` must implement this interface.
 * IERC165's `supportsInterface` must return true for the interface ID of this interface
 */
interface IIBCModuleInitializer is IERC165 {
    struct MsgOnChanOpenInit {
        Channel.Order order;
        string[] connectionHops;
        string portId;
        string channelId;
        ChannelCounterparty.Data counterparty;
        string version;
    }

    struct MsgOnChanOpenTry {
        Channel.Order order;
        string[] connectionHops;
        string portId;
        string channelId;
        ChannelCounterparty.Data counterparty;
        string counterpartyVersion;
    }

    /**
     * @dev onChanOpenInit will verify that the relayer-chosen parameters
     * are valid and perform any custom INIT logic.
     * It may return an error if the chosen parameters are invalid
     * in which case the handshake is aborted.
     * If the provided version string is non-empty, OnChanOpenInit should return
     * the version string if valid or an error if the provided version is invalid.
     * If the version string is empty, OnChanOpenInit is expected to
     * return a default version string representing the version(s) it supports.
     * If there is no default version string for the application,
     * it should return an error if provided version is empty string.
     * onChanOpenInit can also create a new contract instance corresponding to the channel and return the address.
     * Otherwise, it should return the address of this contract.
     */
    function onChanOpenInit(MsgOnChanOpenInit calldata msg_) external returns (address, string memory);

    /**
     * @dev onChanOpenTry will verify the relayer-chosen parameters along with the
     * counterparty-chosen version string and perform custom TRY logic.
     * If the relayer-chosen parameters are invalid, the callback must return
     * an error to abort the handshake. If the counterparty-chosen version is not
     * compatible with this modules supported versions, the callback must return
     * an error to abort the handshake. If the versions are compatible, the try callback
     * must select the final version string and return it to core IBC.
     * onChanOpenTry may also perform custom initialization logic.
     * onChanOpenTry can also create a new contract instance corresponding to the channel and return the address.
     * Otherwise, it should return the address of this contract.
     */
    function onChanOpenTry(MsgOnChanOpenTry calldata msg_) external returns (address, string memory);
}

/**
 * @notice IIBCModule is an interface that defines all the callbacks that modules must define as specified in ICS-26
 * @dev IBC Modules returned by `onChanOpenInit` and `onChanOpenTry` must implement this interface.
 * IERC165's `supportsInterface` must return true for the interface ID of this interface, and the interface ID of IIBCModuleUpgrade if the module supports the channel upgrade
 */
interface IIBCModule is IIBCModuleInitializer {
    struct MsgOnChanOpenAck {
        string portId;
        string channelId;
        string counterpartyVersion;
    }

    struct MsgOnChanOpenConfirm {
        string portId;
        string channelId;
    }

    struct MsgOnChanCloseInit {
        string portId;
        string channelId;
    }

    struct MsgOnChanCloseConfirm {
        string portId;
        string channelId;
    }

    /**
     * @dev OnChanOpenAck will error if the counterparty selected version string
     * is invalid to abort the handshake. It may also perform custom ACK logic.
     */
    function onChanOpenAck(MsgOnChanOpenAck calldata msd_) external;

    /**
     * @dev OnChanOpenConfirm will perform custom CONFIRM logic and may error to abort the handshake.
     */
    function onChanOpenConfirm(MsgOnChanOpenConfirm calldata msg_) external;

    /**
     * @dev OnChanCloseInit will perform custom CLOSE_INIT logic and may error to abort the handshake.
     * NOTE: If the application does not allow the channel to be closed, this function must revert.
     */
    function onChanCloseInit(MsgOnChanCloseInit calldata msg_) external;

    /**
     * @dev OnChanCloseConfirm will perform custom CLOSE_CONFIRM logic and may error to abort the handshake.
     */
    function onChanCloseConfirm(MsgOnChanCloseConfirm calldata msg_) external;

    /**
     * @dev OnRecvPacket must return an acknowledgement that implements the Acknowledgement interface.
     * In the case of an asynchronous acknowledgement, nil should be returned.
     * If the acknowledgement returned is successful, the state changes on callback are written,
     * otherwise the application state changes are discarded. In either case the packet is received
     * and the acknowledgement is written (in synchronous cases).
     */
    function onRecvPacket(Packet calldata, address relayer) external returns (bytes memory);

    /**
     * @dev onAcknowledgementPacket is called when a packet sent by this module has been acknowledged.
     */
    function onAcknowledgementPacket(Packet calldata, bytes calldata acknowledgement, address relayer) external;

    /**
     * @dev onTimeoutPacket is called when a packet sent by this module has timed-out (such that it will not be received on the destination chain).
     */
    function onTimeoutPacket(Packet calldata, address relayer) external;
}


// File @hyperledger-labs/yui-ibc-solidity/contracts/core/26-router/IIBCModuleErrors.sol@v0.1.0

// Original license: SPDX_License_Identifier: Apache-2.0
pragma solidity ^0.8.20;

interface IIBCModuleErrors {
    /// @dev An error indicating that the sender is not the IBC contract
    /// @param sender Address of the sender
    error IBCModuleInvalidSender(address sender);

    /// @dev An error indicating that the channel ordering is not allowed
    /// @param portId Port identifier
    /// @param channelId Channel identifier
    /// @param order Channel ordering type
    error IBCModuleChannelOrderNotAllowed(string portId, string channelId, Channel.Order order);

    /// @dev An error indicating that the channel close is not allowed
    error IBCModuleChannelCloseNotAllowed(string portId, string channelId);
}


// File @openzeppelin/contracts/utils/Context.sol@v5.0.2

// Original license: SPDX_License_Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.1) (utils/Context.sol)

pragma solidity ^0.8.20;

/**
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }

    function _contextSuffixLength() internal view virtual returns (uint256) {
        return 0;
    }
}


// File @hyperledger-labs/yui-ibc-solidity/contracts/apps/commons/IBCAppBase.sol@v0.1.0

// Original license: SPDX_License_Identifier: Apache-2.0
pragma solidity ^0.8.20;





abstract contract AppBase is Context, IERC165, IIBCModuleErrors {
    /**
     * @dev Throws if called by any account other than the IBC contract.
     */
    modifier onlyIBC() {
        _checkIBC();
        _;
    }

    /**
     * @dev Returns the address of the IBC contract.
     */
    function ibcAddress() public view virtual returns (address);

    /**
     * @dev Throws if the sender is not the IBC contract.
     */
    function _checkIBC() internal view virtual {
        if (ibcAddress() != _msgSender()) {
            revert IBCModuleInvalidSender(_msgSender());
        }
    }

    /**
     * @dev Returns true if this contract implements the interface defined by
     * `interfaceId`. See the corresponding
     * https://eips.ethereum.org/EIPS/eip-165#how-interfaces-are-identified[ERC section]
     * to learn more about how these ids are created.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual returns (bool) {
        return interfaceId == type(IERC165).interfaceId || interfaceId == this.ibcAddress.selector;
    }
}

abstract contract IBCAppInitializerBase is AppBase, IIBCModuleInitializer {
    /**
     * @dev See {IERC165-supportsInterface}
     *
     * NOTE: This must return true if the `interfaceId` is equal to the `IIBCModule` interface.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(IERC165, AppBase) returns (bool) {
        return interfaceId == type(IIBCModuleInitializer).interfaceId || super.supportsInterface(interfaceId);
    }
}

/**
 * @dev Base contract of the IBC App protocol
 */
abstract contract IBCAppBase is AppBase, IIBCModule {
    /**
     * @dev See {IIBCModule-onChanOpenInit}
     *
     * NOTE: You should apply an `onlyIBC` modifier to the function if a derived contract overrides it.
     */
    function onChanOpenInit(IIBCModule.MsgOnChanOpenInit calldata)
        external
        virtual
        override
        onlyIBC
        returns (address, string memory)
    {
        return (address(this), "");
    }

    /**
     * @dev See {IIBCModule-onChanOpenTry}
     *
     * NOTE: You should apply an `onlyIBC` modifier to the function if a derived contract overrides it.
     */
    function onChanOpenTry(IIBCModule.MsgOnChanOpenTry calldata)
        external
        virtual
        override
        onlyIBC
        returns (address, string memory)
    {
        return (address(this), "");
    }

    /**
     * @dev See {IIBCModule-onChanOpenAck}
     *
     * NOTE: You should apply an `onlyIBC` modifier to the function if a derived contract overrides it.
     */
    function onChanOpenAck(IIBCModule.MsgOnChanOpenAck calldata) external virtual override onlyIBC {}

    /**
     * @dev See {IIBCModule-onChanOpenConfirm}
     *
     * NOTE: You should apply an `onlyIBC` modifier to the function if a derived contract overrides it.
     */
    function onChanOpenConfirm(IIBCModule.MsgOnChanOpenConfirm calldata) external virtual override onlyIBC {}

    /**
     * @dev See {IIBCModule-onChanCloseInit}
     *
     * NOTE: You should apply an `onlyIBC` modifier to the function if a derived contract overrides it.
     */
    function onChanCloseInit(IIBCModule.MsgOnChanCloseInit calldata) external virtual override onlyIBC {}

    /**
     * @dev See {IIBCModule-onChanCloseConfirm}
     *
     * NOTE: You should apply an `onlyIBC` modifier to the function if a derived contract overrides it.
     */
    function onChanCloseConfirm(IIBCModule.MsgOnChanCloseConfirm calldata) external virtual override onlyIBC {}

    /**
     * @dev See {IIBCModule-onRecvPacket}
     *
     * NOTE: You should apply an `onlyIBC` modifier to the function if a derived contract overrides it.
     */
    function onRecvPacket(Packet calldata, address)
        external
        virtual
        override
        onlyIBC
        returns (bytes memory acknowledgement)
    {}

    /**
     * @dev See {IIBCModule-onAcknowledgementPacket}
     *
     * NOTE: You should apply an `onlyIBC` modifier to the function if a derived contract overrides it.
     */
    function onAcknowledgementPacket(Packet calldata, bytes calldata, address) external virtual override onlyIBC {}

    /**
     * @dev See {IIBCModule-onTimeoutPacket}
     *
     * NOTE: You should apply an `onlyIBC` modifier to the function if a derived contract overrides it.
     */
    function onTimeoutPacket(Packet calldata, address relayer) external virtual override onlyIBC {}

    /**
     * @dev See {IERC165-supportsInterface}
     *
     * NOTE: This must return true if the `interfaceId` is equal to the `IIBCModule` interface.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(IERC165, AppBase) returns (bool) {
        return interfaceId == type(IIBCModule).interfaceId || super.supportsInterface(interfaceId);
    }
}


// File @hyperledger-labs/yui-ibc-solidity/contracts/apps/commons/IIBCChannelUpgradableModule.sol@v0.1.0

// Original license: SPDX_License_Identifier: Apache-2.0
pragma solidity ^0.8.20;

interface IIBCChannelUpgradableModuleErrors {
    // ------------------- Errors ------------------- //

    error IBCChannelUpgradableModuleUnauthorizedUpgrader();
    error IBCChannelUpgradableModuleInvalidTimeout();
    error IBCChannelUpgradableModuleInvalidConnectionHops();
    error IBCChannelUpgradableModuleUpgradeAlreadyExists();
    error IBCChannelUpgradableModuleUpgradeNotFound();
    error IBCChannelUpgradableModuleInvalidUpgrade();

    error IBCChannelUpgradableModuleCannotRemoveInProgressUpgrade();
    /// @param state The current state of the channel
    error IBCChannelUpgradableModuleChannelNotFlushingState(Channel.State state);
    /// @param actual The actual upgrade sequence
    error IBCChannelUpgradableModuleSequenceMismatch(uint64 actual);

    error IBCChannelUpgradableModuleChannelNotFound();
    error IBCChannelUpgradableModuleCannotOverwriteUpgrade();
}

interface IIBCChannelUpgradableModule {
    // ------------------- Data Structures ------------------- //

    /**
     * @dev Proposed upgrade fields
     * @param fields Upgrade fields
     * @param timeout Absolute timeout for the upgrade
     */
    struct UpgradeProposal {
        UpgradeFields.Data fields;
        Timeout.Data timeout;
    }

    /**
     * @dev Allowed transition for the channel upgrade
     * @param flushComplete Whether the upgrade is allowed to transition to the flush complete state
     */
    struct AllowedTransition {
        bool flushComplete;
    }

    // ------------------- Functions ------------------- //

    /**
     * @dev Returns the proposed upgrade for the given port, channel, and sequence
     */
    function getUpgradeProposal(string calldata portId, string calldata channelId)
        external
        view
        returns (UpgradeProposal memory);

    /**
     * @dev Propose an upgrade for the given port, channel, and sequence
     * @notice This function is only callable by an authorized upgrader
     * The upgrader must call this function before calling `channelUpgradeInit` or `channelUpgradeTry` of the IBC handler
     */
    function proposeUpgrade(
        string calldata portId,
        string calldata channelId,
        UpgradeFields.Data calldata upgradeFields,
        Timeout.Data calldata timeout
    ) external;

    /**
     * @dev Removes the proposed upgrade for the given port and channel
     * @notice This function is only callable by an authorized upgrader
     * @param portId Port identifier
     * @param channelId Channel identifier
     */
    function removeUpgradeProposal(string calldata portId, string calldata channelId) external;

    /**
     * @dev Allow the upgrade to transition to the flush complete state
     * @notice This function is only callable by an authorized upgrader
     * WARNING: Before calling this function, the upgrader must ensure that all inflight packets have been received on the receiving chain,
     * and all acknowledgements written have been acknowledged on the sending chain
     */
    function allowTransitionToFlushComplete(string calldata portId, string calldata channelId, uint64 upgradeSequence)
        external;
}


// File @hyperledger-labs/yui-ibc-solidity/contracts/core/02-client/IIBCClient.sol@v0.1.0

// Original license: SPDX_License_Identifier: Apache-2.0
pragma solidity ^0.8.20;

interface IIBCClient {
    // --------------------- Data Structure --------------------- //

    struct MsgCreateClient {
        string clientType;
        bytes protoClientState;
        bytes protoConsensusState;
    }

    struct MsgUpdateClient {
        string clientId;
        bytes protoClientMessage;
    }

    // --------------------- Events --------------------- //

    /// @notice Emitted when a client identifier is generated
    /// @param clientId client identifier
    event GeneratedClientIdentifier(string clientId);

    /**
     * @dev createClient creates a new client state and populates it with a given consensus state
     */
    function createClient(MsgCreateClient calldata msg_) external returns (string memory clientId);

    /**
     * @dev updateClient updates the consensus state and the state root from a provided header
     */
    function updateClient(MsgUpdateClient calldata msg_) external;

    /**
     * @dev routeUpdateClient returns the lc contract address and the calldata to the receiving function of the client message.
     *      Light client contract may encode a client message as other encoding scheme(e.g. ethereum ABI)
     *      Check ADR-001 for details.
     */
    function routeUpdateClient(MsgUpdateClient calldata msg_) external view returns (address, bytes4, bytes memory);

    /**
     * @dev updateClientCommitments updates the commitments of the light client's states corresponding to the given heights.
     *      Check ADR-001 for details.
     */
    function updateClientCommitments(string calldata clientId, Height.Data[] calldata heights) external;
}


// File @hyperledger-labs/yui-ibc-solidity/contracts/core/02-client/IIBCClientErrors.sol@v0.1.0

// Original license: SPDX_License_Identifier: Apache-2.0
pragma solidity ^0.8.20;

interface IIBCClientErrors {
    /// @param clientType the client type
    error IBCClientUnregisteredClientType(string clientType);

    /// @param clientId the client identifier
    error IBCClientClientNotFound(string clientId);

    /// @param clientId the client identifier
    /// @param consensusHeight the consensus height
    error IBCClientConsensusStateNotFound(string clientId, Height.Data consensusHeight);

    /// @param clientId the client identifier
    error IBCClientNotActiveClient(string clientId);

    /// @param selector the function selector
    /// @param args the calldata
    error IBCClientFailedUpdateClient(bytes4 selector, bytes args);
}


// File @hyperledger-labs/yui-ibc-solidity/contracts/proto/Commitment.sol@v0.1.0

// Original license: SPDX_License_Identifier: Apache-2.0
pragma solidity ^0.8.20;


library MerklePrefix {


  //struct definition
  struct Data {
    bytes key_prefix;
  }

  // Decoder section

  /**
   * @dev The main decoder for memory
   * @param bs The bytes array to be decoded
   * @return The decoded struct
   */
  function decode(bytes memory bs) internal pure returns (Data memory) {
    (Data memory x, ) = _decode(32, bs, bs.length);
    return x;
  }

  /**
   * @dev The main decoder for storage
   * @param self The in-storage struct
   * @param bs The bytes array to be decoded
   */
  function decode(Data storage self, bytes memory bs) internal {
    (Data memory x, ) = _decode(32, bs, bs.length);
    store(x, self);
  }
  // inner decoder

  /**
   * @dev The decoder for internal usage
   * @param p The offset of bytes array to start decode
   * @param bs The bytes array to be decoded
   * @param sz The number of bytes expected
   * @return The decoded struct
   * @return The number of bytes decoded
   */
  function _decode(uint256 p, bytes memory bs, uint256 sz)
    internal
    pure
    returns (Data memory, uint)
  {
    Data memory r;
    uint256 fieldId;
    ProtoBufRuntime.WireType wireType;
    uint256 bytesRead;
    uint256 offset = p;
    uint256 pointer = p;
    while (pointer < offset + sz) {
      (fieldId, wireType, bytesRead) = ProtoBufRuntime._decode_key(pointer, bs);
      pointer += bytesRead;
      if (fieldId == 1) {
        pointer += _read_key_prefix(pointer, bs, r);
      } else
      {
        pointer += ProtoBufRuntime._skip_field_decode(wireType, pointer, bs);
      }

    }
    return (r, sz);
  }

  // field readers

  /**
   * @dev The decoder for reading a field
   * @param p The offset of bytes array to start decode
   * @param bs The bytes array to be decoded
   * @param r The in-memory struct
   * @return The number of bytes decoded
   */
  function _read_key_prefix(
    uint256 p,
    bytes memory bs,
    Data memory r
  ) internal pure returns (uint) {
    (bytes memory x, uint256 sz) = ProtoBufRuntime._decode_bytes(p, bs);
    r.key_prefix = x;
    return sz;
  }


  // Encoder section

  /**
   * @dev The main encoder for memory
   * @param r The struct to be encoded
   * @return The encoded byte array
   */
  function encode(Data memory r) internal pure returns (bytes memory) {
    bytes memory bs = new bytes(_estimate(r));
    uint256 sz = _encode(r, 32, bs);
    assembly {
      mstore(bs, sz)
    }
    return bs;
  }
  // inner encoder

  /**
   * @dev The encoder for internal usage
   * @param r The struct to be encoded
   * @param p The offset of bytes array to start decode
   * @param bs The bytes array to be decoded
   * @return The number of bytes encoded
   */
  function _encode(Data memory r, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint)
  {
    uint256 offset = p;
    uint256 pointer = p;
    
    if (r.key_prefix.length != 0) {
    pointer += ProtoBufRuntime._encode_key(
      1,
      ProtoBufRuntime.WireType.LengthDelim,
      pointer,
      bs
    );
    pointer += ProtoBufRuntime._encode_bytes(r.key_prefix, pointer, bs);
    }
    return pointer - offset;
  }
  // nested encoder

  /**
   * @dev The encoder for inner struct
   * @param r The struct to be encoded
   * @param p The offset of bytes array to start decode
   * @param bs The bytes array to be decoded
   * @return The number of bytes encoded
   */
  function _encode_nested(Data memory r, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint)
  {
    /**
     * First encoded `r` into a temporary array, and encode the actual size used.
     * Then copy the temporary array into `bs`.
     */
    uint256 offset = p;
    uint256 pointer = p;
    bytes memory tmp = new bytes(_estimate(r));
    uint256 tmpAddr = ProtoBufRuntime.getMemoryAddress(tmp);
    uint256 bsAddr = ProtoBufRuntime.getMemoryAddress(bs);
    uint256 size = _encode(r, 32, tmp);
    pointer += ProtoBufRuntime._encode_varint(size, pointer, bs);
    ProtoBufRuntime.copyBytes(tmpAddr + 32, bsAddr + pointer, size);
    pointer += size;
    delete tmp;
    return pointer - offset;
  }
  // estimator

  /**
   * @dev The estimator for a struct
   * @param r The struct to be encoded
   * @return The number of bytes encoded in estimation
   */
  function _estimate(
    Data memory r
  ) internal pure returns (uint) {
    uint256 e;
    e += 1 + ProtoBufRuntime._sz_lendelim(r.key_prefix.length);
    return e;
  }
  // empty checker

  function _empty(
    Data memory r
  ) internal pure returns (bool) {
    
  if (r.key_prefix.length != 0) {
    return false;
  }

    return true;
  }


  //store function
  /**
   * @dev Store in-memory struct to storage
   * @param input The in-memory struct
   * @param output The in-storage struct
   */
  function store(Data memory input, Data storage output) internal {
    output.key_prefix = input.key_prefix;

  }



  //utility functions
  /**
   * @dev Return an empty struct
   * @return r The empty struct
   */
  function nil() internal pure returns (Data memory r) {
    assembly {
      r := 0
    }
  }

  /**
   * @dev Test whether a struct is empty
   * @param x The struct to be tested
   * @return r True if it is empty
   */
  function isNil(Data memory x) internal pure returns (bool r) {
    assembly {
      r := iszero(x)
    }
  }
}
//library MerklePrefix


// File @hyperledger-labs/yui-ibc-solidity/contracts/proto/Connection.sol@v0.1.0

// Original license: SPDX_License_Identifier: Apache-2.0
pragma solidity ^0.8.20;



library ConnectionEnd {

  //enum definition
  // Solidity enum definitions
  enum State {
    STATE_UNINITIALIZED_UNSPECIFIED,
    STATE_INIT,
    STATE_TRYOPEN,
    STATE_OPEN
  }


  // Solidity enum encoder
  function encode_State(State x) internal pure returns (int32) {
    
    if (x == State.STATE_UNINITIALIZED_UNSPECIFIED) {
      return 0;
    }

    if (x == State.STATE_INIT) {
      return 1;
    }

    if (x == State.STATE_TRYOPEN) {
      return 2;
    }

    if (x == State.STATE_OPEN) {
      return 3;
    }
    revert();
  }


  // Solidity enum decoder
  function decode_State(int64 x) internal pure returns (State) {
    
    if (x == 0) {
      return State.STATE_UNINITIALIZED_UNSPECIFIED;
    }

    if (x == 1) {
      return State.STATE_INIT;
    }

    if (x == 2) {
      return State.STATE_TRYOPEN;
    }

    if (x == 3) {
      return State.STATE_OPEN;
    }
    revert();
  }


  /**
   * @dev The estimator for an packed enum array
   * @return The number of bytes encoded
   */
  function estimate_packed_repeated_State(
    State[] memory a
  ) internal pure returns (uint256) {
    uint256 e = 0;
    for (uint i = 0; i < a.length; i++) {
      e += ProtoBufRuntime._sz_enum(encode_State(a[i]));
    }
    return e;
  }

  //struct definition
  struct Data {
    string client_id;
    Version.Data[] versions;
    ConnectionEnd.State state;
    Counterparty.Data counterparty;
    uint64 delay_period;
  }

  // Decoder section

  /**
   * @dev The main decoder for memory
   * @param bs The bytes array to be decoded
   * @return The decoded struct
   */
  function decode(bytes memory bs) internal pure returns (Data memory) {
    (Data memory x, ) = _decode(32, bs, bs.length);
    return x;
  }

  /**
   * @dev The main decoder for storage
   * @param self The in-storage struct
   * @param bs The bytes array to be decoded
   */
  function decode(Data storage self, bytes memory bs) internal {
    (Data memory x, ) = _decode(32, bs, bs.length);
    store(x, self);
  }
  // inner decoder

  /**
   * @dev The decoder for internal usage
   * @param p The offset of bytes array to start decode
   * @param bs The bytes array to be decoded
   * @param sz The number of bytes expected
   * @return The decoded struct
   * @return The number of bytes decoded
   */
  function _decode(uint256 p, bytes memory bs, uint256 sz)
    internal
    pure
    returns (Data memory, uint)
  {
    Data memory r;
    uint[6] memory counters;
    uint256 fieldId;
    ProtoBufRuntime.WireType wireType;
    uint256 bytesRead;
    uint256 offset = p;
    uint256 pointer = p;
    while (pointer < offset + sz) {
      (fieldId, wireType, bytesRead) = ProtoBufRuntime._decode_key(pointer, bs);
      pointer += bytesRead;
      if (fieldId == 1) {
        pointer += _read_client_id(pointer, bs, r);
      } else
      if (fieldId == 2) {
        pointer += _read_unpacked_repeated_versions(pointer, bs, nil(), counters);
      } else
      if (fieldId == 3) {
        pointer += _read_state(pointer, bs, r);
      } else
      if (fieldId == 4) {
        pointer += _read_counterparty(pointer, bs, r);
      } else
      if (fieldId == 5) {
        pointer += _read_delay_period(pointer, bs, r);
      } else
      {
        pointer += ProtoBufRuntime._skip_field_decode(wireType, pointer, bs);
      }

    }
    pointer = offset;
    if (counters[2] > 0) {
      require(r.versions.length == 0);
      r.versions = new Version.Data[](counters[2]);
    }

    while (pointer < offset + sz) {
      (fieldId, wireType, bytesRead) = ProtoBufRuntime._decode_key(pointer, bs);
      pointer += bytesRead;
      if (fieldId == 2) {
        pointer += _read_unpacked_repeated_versions(pointer, bs, r, counters);
      } else
      {
        pointer += ProtoBufRuntime._skip_field_decode(wireType, pointer, bs);
      }
    }
    return (r, sz);
  }

  // field readers

  /**
   * @dev The decoder for reading a field
   * @param p The offset of bytes array to start decode
   * @param bs The bytes array to be decoded
   * @param r The in-memory struct
   * @return The number of bytes decoded
   */
  function _read_client_id(
    uint256 p,
    bytes memory bs,
    Data memory r
  ) internal pure returns (uint) {
    (string memory x, uint256 sz) = ProtoBufRuntime._decode_string(p, bs);
    r.client_id = x;
    return sz;
  }

  /**
   * @dev The decoder for reading a field
   * @param p The offset of bytes array to start decode
   * @param bs The bytes array to be decoded
   * @param r The in-memory struct
   * @param counters The counters for repeated fields
   * @return The number of bytes decoded
   */
  function _read_unpacked_repeated_versions(
    uint256 p,
    bytes memory bs,
    Data memory r,
    uint[6] memory counters
  ) internal pure returns (uint) {
    /**
     * if `r` is NULL, then only counting the number of fields.
     */
    (Version.Data memory x, uint256 sz) = _decode_Version(p, bs);
    if (isNil(r)) {
      counters[2] += 1;
    } else {
      r.versions[r.versions.length - counters[2]] = x;
      counters[2] -= 1;
    }
    return sz;
  }

  /**
   * @dev The decoder for reading a field
   * @param p The offset of bytes array to start decode
   * @param bs The bytes array to be decoded
   * @param r The in-memory struct
   * @return The number of bytes decoded
   */
  function _read_state(
    uint256 p,
    bytes memory bs,
    Data memory r
  ) internal pure returns (uint) {
    (int64 tmp, uint256 sz) = ProtoBufRuntime._decode_enum(p, bs);
    ConnectionEnd.State x = decode_State(tmp);
    r.state = x;
    return sz;
  }

  /**
   * @dev The decoder for reading a field
   * @param p The offset of bytes array to start decode
   * @param bs The bytes array to be decoded
   * @param r The in-memory struct
   * @return The number of bytes decoded
   */
  function _read_counterparty(
    uint256 p,
    bytes memory bs,
    Data memory r
  ) internal pure returns (uint) {
    (Counterparty.Data memory x, uint256 sz) = _decode_Counterparty(p, bs);
    r.counterparty = x;
    return sz;
  }

  /**
   * @dev The decoder for reading a field
   * @param p The offset of bytes array to start decode
   * @param bs The bytes array to be decoded
   * @param r The in-memory struct
   * @return The number of bytes decoded
   */
  function _read_delay_period(
    uint256 p,
    bytes memory bs,
    Data memory r
  ) internal pure returns (uint) {
    (uint64 x, uint256 sz) = ProtoBufRuntime._decode_uint64(p, bs);
    r.delay_period = x;
    return sz;
  }

  // struct decoder
  /**
   * @dev The decoder for reading a inner struct field
   * @param p The offset of bytes array to start decode
   * @param bs The bytes array to be decoded
   * @return The decoded inner-struct
   * @return The number of bytes used to decode
   */
  function _decode_Version(uint256 p, bytes memory bs)
    internal
    pure
    returns (Version.Data memory, uint)
  {
    uint256 pointer = p;
    (uint256 sz, uint256 bytesRead) = ProtoBufRuntime._decode_varint(pointer, bs);
    pointer += bytesRead;
    (Version.Data memory r, ) = Version._decode(pointer, bs, sz);
    return (r, sz + bytesRead);
  }

  /**
   * @dev The decoder for reading a inner struct field
   * @param p The offset of bytes array to start decode
   * @param bs The bytes array to be decoded
   * @return The decoded inner-struct
   * @return The number of bytes used to decode
   */
  function _decode_Counterparty(uint256 p, bytes memory bs)
    internal
    pure
    returns (Counterparty.Data memory, uint)
  {
    uint256 pointer = p;
    (uint256 sz, uint256 bytesRead) = ProtoBufRuntime._decode_varint(pointer, bs);
    pointer += bytesRead;
    (Counterparty.Data memory r, ) = Counterparty._decode(pointer, bs, sz);
    return (r, sz + bytesRead);
  }


  // Encoder section

  /**
   * @dev The main encoder for memory
   * @param r The struct to be encoded
   * @return The encoded byte array
   */
  function encode(Data memory r) internal pure returns (bytes memory) {
    bytes memory bs = new bytes(_estimate(r));
    uint256 sz = _encode(r, 32, bs);
    assembly {
      mstore(bs, sz)
    }
    return bs;
  }
  // inner encoder

  /**
   * @dev The encoder for internal usage
   * @param r The struct to be encoded
   * @param p The offset of bytes array to start decode
   * @param bs The bytes array to be decoded
   * @return The number of bytes encoded
   */
  function _encode(Data memory r, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint)
  {
    uint256 offset = p;
    uint256 pointer = p;
    uint256 i;
    if (bytes(r.client_id).length != 0) {
    pointer += ProtoBufRuntime._encode_key(
      1,
      ProtoBufRuntime.WireType.LengthDelim,
      pointer,
      bs
    );
    pointer += ProtoBufRuntime._encode_string(r.client_id, pointer, bs);
    }
    if (r.versions.length != 0) {
    for(i = 0; i < r.versions.length; i++) {
      pointer += ProtoBufRuntime._encode_key(
        2,
        ProtoBufRuntime.WireType.LengthDelim,
        pointer,
        bs)
      ;
      pointer += Version._encode_nested(r.versions[i], pointer, bs);
    }
    }
    if (uint(r.state) != 0) {
    pointer += ProtoBufRuntime._encode_key(
      3,
      ProtoBufRuntime.WireType.Varint,
      pointer,
      bs
    );
    int32 _enum_state = encode_State(r.state);
    pointer += ProtoBufRuntime._encode_enum(_enum_state, pointer, bs);
    }
    
    pointer += ProtoBufRuntime._encode_key(
      4,
      ProtoBufRuntime.WireType.LengthDelim,
      pointer,
      bs
    );
    pointer += Counterparty._encode_nested(r.counterparty, pointer, bs);
    
    if (r.delay_period != 0) {
    pointer += ProtoBufRuntime._encode_key(
      5,
      ProtoBufRuntime.WireType.Varint,
      pointer,
      bs
    );
    pointer += ProtoBufRuntime._encode_uint64(r.delay_period, pointer, bs);
    }
    return pointer - offset;
  }
  // nested encoder

  /**
   * @dev The encoder for inner struct
   * @param r The struct to be encoded
   * @param p The offset of bytes array to start decode
   * @param bs The bytes array to be decoded
   * @return The number of bytes encoded
   */
  function _encode_nested(Data memory r, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint)
  {
    /**
     * First encoded `r` into a temporary array, and encode the actual size used.
     * Then copy the temporary array into `bs`.
     */
    uint256 offset = p;
    uint256 pointer = p;
    bytes memory tmp = new bytes(_estimate(r));
    uint256 tmpAddr = ProtoBufRuntime.getMemoryAddress(tmp);
    uint256 bsAddr = ProtoBufRuntime.getMemoryAddress(bs);
    uint256 size = _encode(r, 32, tmp);
    pointer += ProtoBufRuntime._encode_varint(size, pointer, bs);
    ProtoBufRuntime.copyBytes(tmpAddr + 32, bsAddr + pointer, size);
    pointer += size;
    delete tmp;
    return pointer - offset;
  }
  // estimator

  /**
   * @dev The estimator for a struct
   * @param r The struct to be encoded
   * @return The number of bytes encoded in estimation
   */
  function _estimate(
    Data memory r
  ) internal pure returns (uint) {
    uint256 e;uint256 i;
    e += 1 + ProtoBufRuntime._sz_lendelim(bytes(r.client_id).length);
    for(i = 0; i < r.versions.length; i++) {
      e += 1 + ProtoBufRuntime._sz_lendelim(Version._estimate(r.versions[i]));
    }
    e += 1 + ProtoBufRuntime._sz_enum(encode_State(r.state));
    e += 1 + ProtoBufRuntime._sz_lendelim(Counterparty._estimate(r.counterparty));
    e += 1 + ProtoBufRuntime._sz_uint64(r.delay_period);
    return e;
  }
  // empty checker

  function _empty(
    Data memory r
  ) internal pure returns (bool) {
    
  if (bytes(r.client_id).length != 0) {
    return false;
  }

  if (r.versions.length != 0) {
    return false;
  }

  if (uint(r.state) != 0) {
    return false;
  }

  if (r.delay_period != 0) {
    return false;
  }

    return true;
  }


  //store function
  /**
   * @dev Store in-memory struct to storage
   * @param input The in-memory struct
   * @param output The in-storage struct
   */
  function store(Data memory input, Data storage output) internal {
    output.client_id = input.client_id;

    for(uint256 i2 = 0; i2 < input.versions.length; i2++) {
      output.versions.push(input.versions[i2]);
    }
    
    output.state = input.state;
    Counterparty.store(input.counterparty, output.counterparty);
    output.delay_period = input.delay_period;

  }


  //array helpers for Versions
  /**
   * @dev Add value to an array
   * @param self The in-memory struct
   * @param value The value to add
   */
  function addVersions(Data memory self, Version.Data memory value) internal pure {
    /**
     * First resize the array. Then add the new element to the end.
     */
    Version.Data[] memory tmp = new Version.Data[](self.versions.length + 1);
    for (uint256 i = 0; i < self.versions.length; i++) {
      tmp[i] = self.versions[i];
    }
    tmp[self.versions.length] = value;
    self.versions = tmp;
  }


  //utility functions
  /**
   * @dev Return an empty struct
   * @return r The empty struct
   */
  function nil() internal pure returns (Data memory r) {
    assembly {
      r := 0
    }
  }

  /**
   * @dev Test whether a struct is empty
   * @param x The struct to be tested
   * @return r True if it is empty
   */
  function isNil(Data memory x) internal pure returns (bool r) {
    assembly {
      r := iszero(x)
    }
  }
}
//library ConnectionEnd

library Counterparty {


  //struct definition
  struct Data {
    string client_id;
    string connection_id;
    MerklePrefix.Data prefix;
  }

  // Decoder section

  /**
   * @dev The main decoder for memory
   * @param bs The bytes array to be decoded
   * @return The decoded struct
   */
  function decode(bytes memory bs) internal pure returns (Data memory) {
    (Data memory x, ) = _decode(32, bs, bs.length);
    return x;
  }

  /**
   * @dev The main decoder for storage
   * @param self The in-storage struct
   * @param bs The bytes array to be decoded
   */
  function decode(Data storage self, bytes memory bs) internal {
    (Data memory x, ) = _decode(32, bs, bs.length);
    store(x, self);
  }
  // inner decoder

  /**
   * @dev The decoder for internal usage
   * @param p The offset of bytes array to start decode
   * @param bs The bytes array to be decoded
   * @param sz The number of bytes expected
   * @return The decoded struct
   * @return The number of bytes decoded
   */
  function _decode(uint256 p, bytes memory bs, uint256 sz)
    internal
    pure
    returns (Data memory, uint)
  {
    Data memory r;
    uint256 fieldId;
    ProtoBufRuntime.WireType wireType;
    uint256 bytesRead;
    uint256 offset = p;
    uint256 pointer = p;
    while (pointer < offset + sz) {
      (fieldId, wireType, bytesRead) = ProtoBufRuntime._decode_key(pointer, bs);
      pointer += bytesRead;
      if (fieldId == 1) {
        pointer += _read_client_id(pointer, bs, r);
      } else
      if (fieldId == 2) {
        pointer += _read_connection_id(pointer, bs, r);
      } else
      if (fieldId == 3) {
        pointer += _read_prefix(pointer, bs, r);
      } else
      {
        pointer += ProtoBufRuntime._skip_field_decode(wireType, pointer, bs);
      }

    }
    return (r, sz);
  }

  // field readers

  /**
   * @dev The decoder for reading a field
   * @param p The offset of bytes array to start decode
   * @param bs The bytes array to be decoded
   * @param r The in-memory struct
   * @return The number of bytes decoded
   */
  function _read_client_id(
    uint256 p,
    bytes memory bs,
    Data memory r
  ) internal pure returns (uint) {
    (string memory x, uint256 sz) = ProtoBufRuntime._decode_string(p, bs);
    r.client_id = x;
    return sz;
  }

  /**
   * @dev The decoder for reading a field
   * @param p The offset of bytes array to start decode
   * @param bs The bytes array to be decoded
   * @param r The in-memory struct
   * @return The number of bytes decoded
   */
  function _read_connection_id(
    uint256 p,
    bytes memory bs,
    Data memory r
  ) internal pure returns (uint) {
    (string memory x, uint256 sz) = ProtoBufRuntime._decode_string(p, bs);
    r.connection_id = x;
    return sz;
  }

  /**
   * @dev The decoder for reading a field
   * @param p The offset of bytes array to start decode
   * @param bs The bytes array to be decoded
   * @param r The in-memory struct
   * @return The number of bytes decoded
   */
  function _read_prefix(
    uint256 p,
    bytes memory bs,
    Data memory r
  ) internal pure returns (uint) {
    (MerklePrefix.Data memory x, uint256 sz) = _decode_MerklePrefix(p, bs);
    r.prefix = x;
    return sz;
  }

  // struct decoder
  /**
   * @dev The decoder for reading a inner struct field
   * @param p The offset of bytes array to start decode
   * @param bs The bytes array to be decoded
   * @return The decoded inner-struct
   * @return The number of bytes used to decode
   */
  function _decode_MerklePrefix(uint256 p, bytes memory bs)
    internal
    pure
    returns (MerklePrefix.Data memory, uint)
  {
    uint256 pointer = p;
    (uint256 sz, uint256 bytesRead) = ProtoBufRuntime._decode_varint(pointer, bs);
    pointer += bytesRead;
    (MerklePrefix.Data memory r, ) = MerklePrefix._decode(pointer, bs, sz);
    return (r, sz + bytesRead);
  }


  // Encoder section

  /**
   * @dev The main encoder for memory
   * @param r The struct to be encoded
   * @return The encoded byte array
   */
  function encode(Data memory r) internal pure returns (bytes memory) {
    bytes memory bs = new bytes(_estimate(r));
    uint256 sz = _encode(r, 32, bs);
    assembly {
      mstore(bs, sz)
    }
    return bs;
  }
  // inner encoder

  /**
   * @dev The encoder for internal usage
   * @param r The struct to be encoded
   * @param p The offset of bytes array to start decode
   * @param bs The bytes array to be decoded
   * @return The number of bytes encoded
   */
  function _encode(Data memory r, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint)
  {
    uint256 offset = p;
    uint256 pointer = p;
    
    if (bytes(r.client_id).length != 0) {
    pointer += ProtoBufRuntime._encode_key(
      1,
      ProtoBufRuntime.WireType.LengthDelim,
      pointer,
      bs
    );
    pointer += ProtoBufRuntime._encode_string(r.client_id, pointer, bs);
    }
    if (bytes(r.connection_id).length != 0) {
    pointer += ProtoBufRuntime._encode_key(
      2,
      ProtoBufRuntime.WireType.LengthDelim,
      pointer,
      bs
    );
    pointer += ProtoBufRuntime._encode_string(r.connection_id, pointer, bs);
    }
    
    pointer += ProtoBufRuntime._encode_key(
      3,
      ProtoBufRuntime.WireType.LengthDelim,
      pointer,
      bs
    );
    pointer += MerklePrefix._encode_nested(r.prefix, pointer, bs);
    
    return pointer - offset;
  }
  // nested encoder

  /**
   * @dev The encoder for inner struct
   * @param r The struct to be encoded
   * @param p The offset of bytes array to start decode
   * @param bs The bytes array to be decoded
   * @return The number of bytes encoded
   */
  function _encode_nested(Data memory r, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint)
  {
    /**
     * First encoded `r` into a temporary array, and encode the actual size used.
     * Then copy the temporary array into `bs`.
     */
    uint256 offset = p;
    uint256 pointer = p;
    bytes memory tmp = new bytes(_estimate(r));
    uint256 tmpAddr = ProtoBufRuntime.getMemoryAddress(tmp);
    uint256 bsAddr = ProtoBufRuntime.getMemoryAddress(bs);
    uint256 size = _encode(r, 32, tmp);
    pointer += ProtoBufRuntime._encode_varint(size, pointer, bs);
    ProtoBufRuntime.copyBytes(tmpAddr + 32, bsAddr + pointer, size);
    pointer += size;
    delete tmp;
    return pointer - offset;
  }
  // estimator

  /**
   * @dev The estimator for a struct
   * @param r The struct to be encoded
   * @return The number of bytes encoded in estimation
   */
  function _estimate(
    Data memory r
  ) internal pure returns (uint) {
    uint256 e;
    e += 1 + ProtoBufRuntime._sz_lendelim(bytes(r.client_id).length);
    e += 1 + ProtoBufRuntime._sz_lendelim(bytes(r.connection_id).length);
    e += 1 + ProtoBufRuntime._sz_lendelim(MerklePrefix._estimate(r.prefix));
    return e;
  }
  // empty checker

  function _empty(
    Data memory r
  ) internal pure returns (bool) {
    
  if (bytes(r.client_id).length != 0) {
    return false;
  }

  if (bytes(r.connection_id).length != 0) {
    return false;
  }

    return true;
  }


  //store function
  /**
   * @dev Store in-memory struct to storage
   * @param input The in-memory struct
   * @param output The in-storage struct
   */
  function store(Data memory input, Data storage output) internal {
    output.client_id = input.client_id;
    output.connection_id = input.connection_id;
    MerklePrefix.store(input.prefix, output.prefix);

  }



  //utility functions
  /**
   * @dev Return an empty struct
   * @return r The empty struct
   */
  function nil() internal pure returns (Data memory r) {
    assembly {
      r := 0
    }
  }

  /**
   * @dev Test whether a struct is empty
   * @param x The struct to be tested
   * @return r True if it is empty
   */
  function isNil(Data memory x) internal pure returns (bool r) {
    assembly {
      r := iszero(x)
    }
  }
}
//library Counterparty

library Version {


  //struct definition
  struct Data {
    string identifier;
    string[] features;
  }

  // Decoder section

  /**
   * @dev The main decoder for memory
   * @param bs The bytes array to be decoded
   * @return The decoded struct
   */
  function decode(bytes memory bs) internal pure returns (Data memory) {
    (Data memory x, ) = _decode(32, bs, bs.length);
    return x;
  }

  /**
   * @dev The main decoder for storage
   * @param self The in-storage struct
   * @param bs The bytes array to be decoded
   */
  function decode(Data storage self, bytes memory bs) internal {
    (Data memory x, ) = _decode(32, bs, bs.length);
    store(x, self);
  }
  // inner decoder

  /**
   * @dev The decoder for internal usage
   * @param p The offset of bytes array to start decode
   * @param bs The bytes array to be decoded
   * @param sz The number of bytes expected
   * @return The decoded struct
   * @return The number of bytes decoded
   */
  function _decode(uint256 p, bytes memory bs, uint256 sz)
    internal
    pure
    returns (Data memory, uint)
  {
    Data memory r;
    uint[3] memory counters;
    uint256 fieldId;
    ProtoBufRuntime.WireType wireType;
    uint256 bytesRead;
    uint256 offset = p;
    uint256 pointer = p;
    while (pointer < offset + sz) {
      (fieldId, wireType, bytesRead) = ProtoBufRuntime._decode_key(pointer, bs);
      pointer += bytesRead;
      if (fieldId == 1) {
        pointer += _read_identifier(pointer, bs, r);
      } else
      if (fieldId == 2) {
        pointer += _read_unpacked_repeated_features(pointer, bs, nil(), counters);
      } else
      {
        pointer += ProtoBufRuntime._skip_field_decode(wireType, pointer, bs);
      }

    }
    pointer = offset;
    if (counters[2] > 0) {
      require(r.features.length == 0);
      r.features = new string[](counters[2]);
    }

    while (pointer < offset + sz) {
      (fieldId, wireType, bytesRead) = ProtoBufRuntime._decode_key(pointer, bs);
      pointer += bytesRead;
      if (fieldId == 2) {
        pointer += _read_unpacked_repeated_features(pointer, bs, r, counters);
      } else
      {
        pointer += ProtoBufRuntime._skip_field_decode(wireType, pointer, bs);
      }
    }
    return (r, sz);
  }

  // field readers

  /**
   * @dev The decoder for reading a field
   * @param p The offset of bytes array to start decode
   * @param bs The bytes array to be decoded
   * @param r The in-memory struct
   * @return The number of bytes decoded
   */
  function _read_identifier(
    uint256 p,
    bytes memory bs,
    Data memory r
  ) internal pure returns (uint) {
    (string memory x, uint256 sz) = ProtoBufRuntime._decode_string(p, bs);
    r.identifier = x;
    return sz;
  }

  /**
   * @dev The decoder for reading a field
   * @param p The offset of bytes array to start decode
   * @param bs The bytes array to be decoded
   * @param r The in-memory struct
   * @param counters The counters for repeated fields
   * @return The number of bytes decoded
   */
  function _read_unpacked_repeated_features(
    uint256 p,
    bytes memory bs,
    Data memory r,
    uint[3] memory counters
  ) internal pure returns (uint) {
    /**
     * if `r` is NULL, then only counting the number of fields.
     */
    (string memory x, uint256 sz) = ProtoBufRuntime._decode_string(p, bs);
    if (isNil(r)) {
      counters[2] += 1;
    } else {
      r.features[r.features.length - counters[2]] = x;
      counters[2] -= 1;
    }
    return sz;
  }


  // Encoder section

  /**
   * @dev The main encoder for memory
   * @param r The struct to be encoded
   * @return The encoded byte array
   */
  function encode(Data memory r) internal pure returns (bytes memory) {
    bytes memory bs = new bytes(_estimate(r));
    uint256 sz = _encode(r, 32, bs);
    assembly {
      mstore(bs, sz)
    }
    return bs;
  }
  // inner encoder

  /**
   * @dev The encoder for internal usage
   * @param r The struct to be encoded
   * @param p The offset of bytes array to start decode
   * @param bs The bytes array to be decoded
   * @return The number of bytes encoded
   */
  function _encode(Data memory r, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint)
  {
    uint256 offset = p;
    uint256 pointer = p;
    uint256 i;
    if (bytes(r.identifier).length != 0) {
    pointer += ProtoBufRuntime._encode_key(
      1,
      ProtoBufRuntime.WireType.LengthDelim,
      pointer,
      bs
    );
    pointer += ProtoBufRuntime._encode_string(r.identifier, pointer, bs);
    }
    if (r.features.length != 0) {
    for(i = 0; i < r.features.length; i++) {
      pointer += ProtoBufRuntime._encode_key(
        2,
        ProtoBufRuntime.WireType.LengthDelim,
        pointer,
        bs)
      ;
      pointer += ProtoBufRuntime._encode_string(r.features[i], pointer, bs);
    }
    }
    return pointer - offset;
  }
  // nested encoder

  /**
   * @dev The encoder for inner struct
   * @param r The struct to be encoded
   * @param p The offset of bytes array to start decode
   * @param bs The bytes array to be decoded
   * @return The number of bytes encoded
   */
  function _encode_nested(Data memory r, uint256 p, bytes memory bs)
    internal
    pure
    returns (uint)
  {
    /**
     * First encoded `r` into a temporary array, and encode the actual size used.
     * Then copy the temporary array into `bs`.
     */
    uint256 offset = p;
    uint256 pointer = p;
    bytes memory tmp = new bytes(_estimate(r));
    uint256 tmpAddr = ProtoBufRuntime.getMemoryAddress(tmp);
    uint256 bsAddr = ProtoBufRuntime.getMemoryAddress(bs);
    uint256 size = _encode(r, 32, tmp);
    pointer += ProtoBufRuntime._encode_varint(size, pointer, bs);
    ProtoBufRuntime.copyBytes(tmpAddr + 32, bsAddr + pointer, size);
    pointer += size;
    delete tmp;
    return pointer - offset;
  }
  // estimator

  /**
   * @dev The estimator for a struct
   * @param r The struct to be encoded
   * @return The number of bytes encoded in estimation
   */
  function _estimate(
    Data memory r
  ) internal pure returns (uint) {
    uint256 e;uint256 i;
    e += 1 + ProtoBufRuntime._sz_lendelim(bytes(r.identifier).length);
    for(i = 0; i < r.features.length; i++) {
      e += 1 + ProtoBufRuntime._sz_lendelim(bytes(r.features[i]).length);
    }
    return e;
  }
  // empty checker

  function _empty(
    Data memory r
  ) internal pure returns (bool) {
    
  if (bytes(r.identifier).length != 0) {
    return false;
  }

  if (r.features.length != 0) {
    return false;
  }

    return true;
  }


  //store function
  /**
   * @dev Store in-memory struct to storage
   * @param input The in-memory struct
   * @param output The in-storage struct
   */
  function store(Data memory input, Data storage output) internal {
    output.identifier = input.identifier;
    output.features = input.features;

  }


  //array helpers for Features
  /**
   * @dev Add value to an array
   * @param self The in-memory struct
   * @param value The value to add
   */
  function addFeatures(Data memory self, string memory value) internal pure {
    /**
     * First resize the array. Then add the new element to the end.
     */
    string[] memory tmp = new string[](self.features.length + 1);
    for (uint256 i = 0; i < self.features.length; i++) {
      tmp[i] = self.features[i];
    }
    tmp[self.features.length] = value;
    self.features = tmp;
  }


  //utility functions
  /**
   * @dev Return an empty struct
   * @return r The empty struct
   */
  function nil() internal pure returns (Data memory r) {
    assembly {
      r := 0
    }
  }

  /**
   * @dev Test whether a struct is empty
   * @param x The struct to be tested
   * @return r True if it is empty
   */
  function isNil(Data memory x) internal pure returns (bool r) {
    assembly {
      r := iszero(x)
    }
  }
}
//library Version


// File @hyperledger-labs/yui-ibc-solidity/contracts/core/03-connection/IIBCConnection.sol@v0.1.0

// Original license: SPDX_License_Identifier: Apache-2.0
pragma solidity ^0.8.20;


interface IIBCConnection {
    // --------------------- Data Structure --------------------- //

    struct MsgConnectionOpenInit {
        string clientId;
        Counterparty.Data counterparty;
        Version.Data version;
        uint64 delayPeriod;
    }

    struct MsgConnectionOpenTry {
        Counterparty.Data counterparty; // counterpartyConnectionIdentifier, counterpartyPrefix and counterpartyClientIdentifier
        uint64 delayPeriod;
        string clientId; // clientID of chainA
        bytes clientStateBytes; // clientState that chainA has for chainB
        Version.Data[] counterpartyVersions; // supported versions of chain A
        bytes proofInit; // proof that chainA stored connectionEnd in state (on ConnOpenInit)
        bytes proofClient; // proof that chainA stored a light client of chainB
        bytes proofConsensus; // proof that chainA stored chainB's consensus state at consensus height
        Height.Data proofHeight; // height at which relayer constructs proof of A storing connectionEnd in state
        Height.Data consensusHeight; // latest height of chain B which chain A has stored in its chain B client
        bytes hostConsensusStateProof; // optional proof data for host state machines that are unable to introspect their own consensus state
    }

    struct MsgConnectionOpenAck {
        string connectionId;
        bytes clientStateBytes; // client state for chainA on chainB
        Version.Data version; // version that ChainB chose in ConnOpenTry
        string counterpartyConnectionId;
        bytes proofTry; // proof that connectionEnd was added to ChainB state in ConnOpenTry
        bytes proofClient; // proof of client state on chainB for chainA
        bytes proofConsensus; // proof that chainB has stored ConsensusState of chainA on its client
        Height.Data proofHeight; // height that relayer constructed proofTry
        Height.Data consensusHeight; // latest height of chainA that chainB has stored on its chainA client
        bytes hostConsensusStateProof; // optional proof data for host state machines that are unable to introspect their own consensus state
    }

    struct MsgConnectionOpenConfirm {
        string connectionId;
        bytes proofAck;
        Height.Data proofHeight;
    }

    // --------------------- Events --------------------- //

    /// @notice Emitted when a connection identifier is generated
    /// @param connectionId connection identifier
    event GeneratedConnectionIdentifier(string connectionId);

    /**
     * @dev connectionOpenInit initialises a connection attempt on chain A. The generated connection identifier
     * is returned.
     */
    function connectionOpenInit(MsgConnectionOpenInit calldata msg_) external returns (string memory connectionId);

    /**
     * @dev connectionOpenTry relays notice of a connection attempt on chain A to chain B (this
     * code is executed on chain B).
     */
    function connectionOpenTry(MsgConnectionOpenTry calldata msg_) external returns (string memory);

    /**
     * @dev connectionOpenAck relays acceptance of a connection open attempt from chain B back
     * to chain A (this code is executed on chain A).
     */
    function connectionOpenAck(MsgConnectionOpenAck calldata msg_) external;

    /**
     * @dev connectionOpenConfirm confirms opening of a connection on chain A to chain B, after
     * which the connection is open on both chains (this code is executed on chain B).
     */
    function connectionOpenConfirm(MsgConnectionOpenConfirm calldata msg_) external;
}


// File @hyperledger-labs/yui-ibc-solidity/contracts/core/03-connection/IIBCConnectionErrors.sol@v0.1.0

// Original license: SPDX_License_Identifier: Apache-2.0
pragma solidity ^0.8.20;


interface IIBCConnectionErrors {
    error IBCConnectionAlreadyConnectionExists();

    /// @param counterpartyConnectionId counterparty connection identifier
    error IBCConnectionInvalidCounterpartyConnectionIdentifier(string counterpartyConnectionId);

    error IBCConnectionEmptyConnectionCounterpartyVersions();

    error IBCConnectionNoMatchingVersionFound();

    error IBCConnectionVersionsAlreadySet();

    error IBCConnectionIBCVersionNotSupported();

    error IBCConnectionInvalidSelfClientState();

    error IBCConnectionInvalidHostConsensusStateProof();

    /// @param state connection state
    error IBCConnectionUnexpectedConnectionState(ConnectionEnd.State state);

    /// @param clientId client identifier
    /// @param path commitment path
    /// @param value value
    /// @param proof proof
    /// @param height proof height
    error IBCConnectionFailedVerifyConnectionState(
        string clientId, bytes path, bytes value, bytes proof, Height.Data height
    );

    /// @param clientId client identifier
    /// @param path commitment path
    /// @param value value
    /// @param proof proof
    /// @param height proof height
    error IBCConnectionFailedVerifyClientState(
        string clientId, bytes path, bytes value, bytes proof, Height.Data height
    );

    /// @param clientId client identifier
    /// @param path commitment path
    /// @param value value
    /// @param proof proof
    /// @param height proof height
    error IBCConnectionFailedVerifyClientConsensusState(
        string clientId, bytes path, bytes value, bytes proof, Height.Data height
    );
}


// File @hyperledger-labs/yui-ibc-solidity/contracts/core/04-channel/IIBCChannelErrors.sol@v0.1.0

// Original license: SPDX_License_Identifier: Apache-2.0
pragma solidity ^0.8.20;


interface IIBCChannelErrors {
    /// @param state channel state
    error IBCChannelUnexpectedChannelState(Channel.State state);

    /// @param portId port identifier
    /// @param channelId channel identifier
    error IBCChannelChannelNotFound(string portId, string channelId);

    /// @param ordering channel ordering
    error IBCChannelUnknownChannelOrder(Channel.Order ordering);

    /// @param clientId client identifier
    /// @param path commitment path
    /// @param value value
    /// @param proof proof
    /// @param height proof height
    error IBCChannelFailedVerifyChannelState(string clientId, bytes path, bytes value, bytes proof, Height.Data height);

    /// @param connectionId connection identifier
    error IBCChannelConnectionNotOpened(string connectionId);

    /// @param counterpartyChannelId counterparty channel identifier
    error IBCChannelCounterpartyChannelIdNotEmpty(string counterpartyChannelId);

    /// @param length length of the connection hops
    error IBCChannelInvalidConnectionHopsLength(uint256 length);

    /// @param connectionId connection identifier
    /// @param length length of the connection hops
    error IBCChannelConnectionMultipleVersionsFound(string connectionId, uint256 length);

    /// @param ordering channel ordering
    error IBCChannelConnectionFeatureNotSupported(Channel.Order ordering);

    /// @notice timeout height and timestamp are both zero
    error IBCChannelZeroPacketTimeout();

    /// @notice receiving chain block height >= packet timeout height
    /// @param timeoutHeight packet timeout height
    /// @param latestHeight latest height of the receiving chain
    error IBCChannelPastPacketTimeoutHeight(Height.Data timeoutHeight, Height.Data latestHeight);

    /// @notice receiving chain block timestamp >= packet timeout timestamp
    /// @param timeoutTimestamp packet timeout timestamp
    /// @param latestTimestamp latest timestamp of the receiving chain
    error IBCChannelPastPacketTimeoutTimestamp(uint64 timeoutTimestamp, uint64 latestTimestamp);

    /// @notice packet timeout has not been reached for height or timestamp
    error IBCChannelTimeoutNotReached();

    /// @param commitment packet receipt commitment
    error IBCChannelUnknownPacketReceiptCommitment(bytes32 commitment);

    /// @param sourcePort source port
    /// @param sourceChannel source channel
    error IBCChannelUnexpectedPacketSource(string sourcePort, string sourceChannel);

    /// @param destinationPort destination port
    /// @param destinationChannel destination channel
    error IBCChannelUnexpectedPacketDestination(string destinationPort, string destinationChannel);

    error IBCChannelCannotRecvNextUpgradePacket(uint64 sequence, uint64 counterpartyNextSequenceSend);

    error IBCChannelPacketAlreadyProcessInPreviousUpgrade(uint64 sequence, uint64 recvStartSequence);

    error IBCChannelAckAlreadyProcessedInPreviousUpgrade(uint64 sequence, uint64 ackStartSequence);

    /// @param currentBlockNumber current block number
    /// @param timeoutHeight packet timeout height
    error IBCChannelTimeoutPacketHeight(uint256 currentBlockNumber, uint64 timeoutHeight);

    /// @param currentTimestamp current timestamp
    /// @param timeoutTimestamp packet timeout timestamp
    error IBCChannelTimeoutPacketTimestamp(uint256 currentTimestamp, uint64 timeoutTimestamp);

    /// @param destinationPort destination port
    /// @param destinationChannel destination channel
    /// @param sequence packet sequence
    error IBCChannelPacketReceiptAlreadyExists(string destinationPort, string destinationChannel, uint64 sequence);

    /// @param expected expected sequence
    error IBCChannelUnexpectedNextSequenceRecv(uint64 expected);

    /// @param portId port identifier
    /// @param channelId channel identifier
    /// @param sequence packet sequence
    error IBCChannelPacketCommitmentNotFound(string portId, string channelId, uint64 sequence);

    /// @param expected expected sequence
    error IBCChannelUnexpectedNextSequenceAck(uint64 expected);

    /// @param expected expected commitment
    /// @param actual actual commitment
    error IBCChannelPacketCommitmentMismatch(bytes32 expected, bytes32 actual);

    /// @param sequence packet sequence
    /// @param nextSequenceRecv next sequence received
    error IBCChannelPacketMaybeAlreadyReceived(uint64 sequence, uint64 nextSequenceRecv);

    /// @param clientId client identifier
    /// @param path commitment path
    /// @param commitment packet commitment
    /// @param proof proof
    /// @param height proof height
    error IBCChannelFailedVerifyPacketCommitment(
        string clientId, bytes path, bytes32 commitment, bytes proof, Height.Data height
    );

    /// @param clientId client identifier
    /// @param path commitment path
    /// @param commitment acknowledgement commitment
    /// @param proof proof
    /// @param height proof height
    error IBCChannelFailedVerifyPacketAcknowledgement(
        string clientId, bytes path, bytes32 commitment, bytes proof, Height.Data height
    );

    /// @param clientId client identifier
    /// @param path commitment path
    /// @param nextSequenceRecv next sequence received
    /// @param proof proof
    /// @param height proof height
    error IBCChannelFailedVerifyNextSequenceRecv(
        string clientId, bytes path, uint64 nextSequenceRecv, bytes proof, Height.Data height
    );

    /// @param clientId client identifier
    /// @param path commitment path
    /// @param proof proof
    /// @param height proof height
    error IBCChannelFailedVerifyPacketReceiptAbsence(string clientId, bytes path, bytes proof, Height.Data height);

    /// @notice acknowledgement cannot be empty
    error IBCChannelEmptyAcknowledgement();

    /// @param destinationPort destination port
    /// @param destinationChannel destination channel
    /// @param sequence packet sequence
    error IBCChannelAcknowledgementAlreadyWritten(string destinationPort, string destinationChannel, uint64 sequence);
}


// File @hyperledger-labs/yui-ibc-solidity/contracts/core/04-channel/IIBCChannelUpgrade.sol@v0.1.0

// Original license: SPDX_License_Identifier: Apache-2.0
pragma solidity ^0.8.20;


interface IIBCChannelUpgradeBase {
    // --------------------- Events --------------------- //

    /// @notice emitted when channelUpgradeInit is successfully executed
    event ChannelUpgradeInit(
        string portId, string channelId, uint64 upgradeSequence, UpgradeFields.Data proposedUpgradeFields
    );

    /// @notice emitted when channelUpgradeTry is successfully executed
    event ChannelUpgradeTry(
        string portId,
        string channelId,
        uint64 upgradeSequence,
        UpgradeFields.Data upgradeFields,
        Timeout.Data timeout,
        uint64 nextSequenceSend
    );

    /// @notice emitted when channelUpgradeAck is successfully executed
    /// @param channelState post channel state (FLUSHING or FLUSHCOMPLETE)
    event ChannelUpgradeAck(
        string portId,
        string channelId,
        uint64 upgradeSequence,
        Channel.State channelState,
        UpgradeFields.Data upgradeFields,
        Timeout.Data timeout,
        uint64 nextSequenceSend
    );

    /// @notice emitted when channelUpgradeConfirm is successfully executed
    /// @param channelState post channel state (FLUSHING or FLUSHCOMPLETE or OPEN)
    event ChannelUpgradeConfirm(string portId, string channelId, uint64 upgradeSequence, Channel.State channelState);

    /// @notice emitted when channelUpgradeOpen is successfully executed
    event ChannelUpgradeOpen(string portId, string channelId, uint64 upgradeSequence);

    /// @notice error when the upgrade attempt fails
    /// @param portId port identifier
    /// @param channelId channel identifier
    /// @param upgradeSequence upgrade sequence
    event WriteErrorReceipt(string portId, string channelId, uint64 upgradeSequence, string message);

    // --------------------- Structs --------------------- //

    enum UpgradeHandshakeError {
        None,
        Overwritten,
        OutOfSync,
        Timeout,
        Cancel,
        IncompatibleProposal,
        AckCallbackFailed
    }

    struct MsgChannelUpgradeInit {
        string portId;
        string channelId;
        UpgradeFields.Data proposedUpgradeFields;
    }

    struct MsgChannelUpgradeTry {
        string portId;
        string channelId;
        uint64 counterpartyUpgradeSequence;
        UpgradeFields.Data counterpartyUpgradeFields;
        string[] proposedConnectionHops;
        ChannelUpgradeProofs proofs;
    }

    struct MsgChannelUpgradeAck {
        string portId;
        string channelId;
        Upgrade.Data counterpartyUpgrade;
        ChannelUpgradeProofs proofs;
    }

    struct MsgChannelUpgradeConfirm {
        string portId;
        string channelId;
        Channel.State counterpartyChannelState;
        Upgrade.Data counterpartyUpgrade;
        ChannelUpgradeProofs proofs;
    }

    struct MsgChannelUpgradeOpen {
        string portId;
        string channelId;
        Channel.State counterpartyChannelState;
        uint64 counterpartyUpgradeSequence;
        bytes proofChannel;
        Height.Data proofHeight;
    }

    struct MsgCancelChannelUpgrade {
        string portId;
        string channelId;
        ErrorReceipt.Data errorReceipt;
        bytes proofUpgradeError;
        Height.Data proofHeight;
    }

    struct MsgTimeoutChannelUpgrade {
        string portId;
        string channelId;
        Channel.Data counterpartyChannel;
        bytes proofChannel;
        Height.Data proofHeight;
    }

    struct ChannelUpgradeProofs {
        bytes proofChannel;
        bytes proofUpgrade;
        Height.Data proofHeight;
    }
}

interface IIBCChannelUpgradeInitTryAck is IIBCChannelUpgradeBase {
    // --------------------- External Functions --------------------- //

    /**
     * @dev channelUpgradeInit is called by a module to initiate a channel upgrade handshake with
     * a module on another chain.
     * The current channel state must be OPEN. The post channel state is always OPEN.
     */
    function channelUpgradeInit(MsgChannelUpgradeInit calldata msg_) external returns (uint64 upgradeSequence);

    /**
     * @dev channelUpgradeTry is called by a module to accept the first step of a channel upgrade handshake initiated by
     * a module on another chain.
     * The current channel state must be OPEN. The post channel state will be OPEN or FLUSHING.
     * If this function is successful, the proposed upgrade will be emitted as event.
     * If the upgrade fails, the upgrade sequence will still be incremented but an error will be returned.
     */
    function channelUpgradeTry(MsgChannelUpgradeTry calldata msg_) external returns (bool ok, uint64 upgradeSequence);

    /**
     * @dev channelUpgradeAck is called by a module to accept the ACKUPGRADE handshake step of the channel upgrade protocol.
     * This method will verify that the counterparty has called the channelUpgradeTry handler.
     * and that its own upgrade is compatible with the selected counterparty version.
     *
     * NOTE: The current channel may be in either the OPEN or FLUSHING state.
     * The channel may be in OPEN if we are in the happy path.
     *   A -> Init (OPEN), B -> Try (FLUSHING), A -> Ack (begins in OPEN, ends in FLUSHING or FLUSHCOMPLETE)
     *
     * The channel may be in FLUSHING if we are in a crossing hellos situation.
     *   A -> Init (OPEN), B -> Init (OPEN) -> A -> Try (FLUSHING), B -> Try (FLUSHING), A -> Ack (begins in FLUSHING, ends in FLUSHING or FLUSHCOMPLETE)
     */
    function channelUpgradeAck(MsgChannelUpgradeAck calldata msg_) external returns (bool);
}

interface IIBCChannelUpgradeConfirmOpenTimeoutCancel is IIBCChannelUpgradeBase {
    // --------------------- External Functions --------------------- //

    /**
     * @dev channelUpgradeConfirm is called on the chain which is on FLUSHING after channelUpgradeAck is called on the counterparty.
     * This will inform the TRY chain of the timeout set on ACK by the counterparty. If the timeout has already exceeded,
     * we will write an error receipt and restore the channel to OPEN state.
     */
    function channelUpgradeConfirm(MsgChannelUpgradeConfirm calldata msg_) external returns (bool);

    /**
     * @dev channelUpgradeOpen is called by a module to complete the channel upgrade handshake and move the channel back to an OPEN state.
     * This method should only be called after both channels have flushed any in-flight packets.
     */
    function channelUpgradeOpen(MsgChannelUpgradeOpen calldata msg_) external;

    /**
     * @dev cancelChannelUpgrade proves that an error receipt was written on the counterparty
     * which constitutes a valid situation where the upgrade should be cancelled.
     * The tx reverts if sufficient evidence for cancelling the upgrade has not been provided.
     */
    function cancelChannelUpgrade(MsgCancelChannelUpgrade calldata msg_) external;

    /**
     * @dev timeoutChannelUpgrade times out an outstanding upgrade.
     * This should be used by the initialising chain when the counterparty chain has not responded to an upgrade proposal within the specified timeout period.
     */
    function timeoutChannelUpgrade(MsgTimeoutChannelUpgrade calldata msg_) external;
}

interface IIBCChannelUpgrade is IIBCChannelUpgradeInitTryAck, IIBCChannelUpgradeConfirmOpenTimeoutCancel {}


// File @hyperledger-labs/yui-ibc-solidity/contracts/core/04-channel/IIBCChannelUpgradeErrors.sol@v0.1.0

// Original license: SPDX_License_Identifier: Apache-2.0
pragma solidity ^0.8.20;



interface IIBCChannelUpgradeErrors is IIBCChannelErrors {
    error IBCChannelUpgradeNoChanges();

    error IBCChannelUpgradeInvalidUpgradeFields();

    /// @notice proposed upgrade must be non-empty
    error IBCChannelUpgradeTryProposedConnectionHopsEmpty();

    /// @notice proposal's connection hops mismatch with the existing proposal
    error IBCChannelUpgradeTryProposedConnectionHopsMismatch();

    /// @param upgrader address of the upgrader
    error IBCChannelUpgradeUnauthorizedChannelUpgrader(address upgrader);

    error IBCChannelUpgradeIncompatibleProposal();

    error IBCChannelUpgradeErrorReceiptEmpty();

    /// @param latestSequence latest upgrade sequence
    /// @param sequence upgrade sequence
    error IBCChannelUpgradeWriteOldErrorReceiptSequence(uint64 latestSequence, uint64 sequence);

    error IBCChannelUpgradeNoExistingUpgrade();

    /// @param state channel state
    error IBCChannelUpgradeNotFlushing(Channel.State state);

    /// @param state channel state
    error IBCChannelUpgradeNotOpenOrFlushing(Channel.State state);

    /// @param state channel state
    error IBCChannelUpgradeCounterpartyNotOpenOrFlushcomplete(Channel.State state);

    /// @notice counterparty channel not flushing or flushcomplete
    /// @param state channel state
    error IBCChannelUpgradeCounterpartyNotFlushingOrFlushcomplete(Channel.State state);

    /// @param state channel state
    error IBCChannelUpgradeNotFlushcomplete(Channel.State state);

    /// @param clientId client identifier
    /// @param path key path
    /// @param value key value
    /// @param proof proof of membership
    /// @param height proof height
    error IBCChannelUpgradeFailedVerifyMembership(
        string clientId, string path, bytes value, bytes proof, Height.Data height
    );

    error IBCChannelUpgradeTimeoutHeightNotReached();

    error IBCChannelUpgradeTimeoutTimestampNotReached();

    error IBCChannelUpgradeInvalidTimeout();

    error IBCChannelUpgradeCounterpartyAlreadyFlushCompleted();

    error IBCChannelUpgradeCounterpartyAlreadyUpgraded();

    error IBCChannelUpgradeTimeoutUnallowedState();

    error IBCChannelUpgradeOldErrorReceiptSequence();

    error IBCChannelUpgradeInvalidErrorReceiptSequence();

    error IBCChannelUpgradeOldCounterpartyUpgradeSequence();

    error IBCChannelUpgradeUnsupportedOrdering(Channel.Order ordering);
}


// File @hyperledger-labs/yui-ibc-solidity/contracts/core/02-client/ILightClient.sol@v0.1.0

// Original license: SPDX_License_Identifier: Apache-2.0
pragma solidity ^0.8.20;

/**
 * @dev This defines an interface for Light Client contract can be integrated with ibc-solidity.
 * You can register the Light Client contract that implements this through `registerClient` on IBCHandler.
 */
interface ILightClient {
    /**
     * @dev ConsensusStateUpdate represents a consensus state update.
     */
    struct ConsensusStateUpdate {
        // commitment for updated consensusState
        bytes32 consensusStateCommitment;
        // updated height
        Height.Data height;
    }

    /**
     * @dev ClientStatus represents the status of a client.
     */
    enum ClientStatus {
        Active,
        Expired,
        Frozen
    }

    /**
     * @dev initializeClient initializes a new client with the given state.
     *      If succeeded, it returns heights at which the consensus state are stored.
     *      The function must be only called by IBCHandler.
     */
    function initializeClient(
        string calldata clientId,
        bytes calldata protoClientState,
        bytes calldata protoConsensusState
    ) external returns (Height.Data memory height);

    /**
     * @dev routeUpdateClient returns the calldata to the receiving function of the client message.
     *      Light client contract may encode a client message as other encoding scheme(e.g. ethereum ABI)
     *      Check ADR-001 for details.
     */
    function routeUpdateClient(string calldata clientId, bytes calldata protoClientMessage)
        external
        pure
        returns (bytes4 selector, bytes memory args);

    /**
     * @dev getTimestampAtHeight returns the timestamp of the consensus state at the given height.
     *      The timestamp is nanoseconds since unix epoch.
     */
    function getTimestampAtHeight(string calldata clientId, Height.Data calldata height)
        external
        view
        returns (uint64);

    /**
     * @dev getLatestHeight returns the latest height of the client state corresponding to `clientId`.
     */
    function getLatestHeight(string calldata clientId) external view returns (Height.Data memory);

    /**
     * @dev getStatus returns the status of the client corresponding to `clientId`.
     */
    function getStatus(string calldata clientId) external view returns (ClientStatus);

    /**
     * @dev getLatestInfo returns the latest height, the latest timestamp, and the status of the client corresponding to `clientId`.
     */
    function getLatestInfo(string calldata clientId)
        external
        view
        returns (Height.Data memory latestHeight, uint64 latestTimestamp, ClientStatus status);

    /**
     * @dev verifyMembership is a generic proof verification method which verifies a proof of the existence of a value at a given CommitmentPath at the specified height.
     * The caller is expected to construct the full CommitmentPath from a CommitmentPrefix and a standardized path (as defined in ICS 24).
     * This function should not perform `call` to the IBC contract. However, `staticcall` is permitted.
     */
    function verifyMembership(
        string calldata clientId,
        Height.Data calldata height,
        uint64 delayTimePeriod,
        uint64 delayBlockPeriod,
        bytes calldata proof,
        bytes calldata prefix,
        bytes calldata path,
        bytes calldata value
    ) external returns (bool);

    /**
     * @dev verifyNonMembership is a generic proof verification method which verifies the absence of a given CommitmentPath at a specified height.
     * The caller is expected to construct the full CommitmentPath from a CommitmentPrefix and a standardized path (as defined in ICS 24).
     * This function should not perform `call` to the IBC contract. However, `staticcall` is permitted.
     */
    function verifyNonMembership(
        string calldata clientId,
        Height.Data calldata height,
        uint64 delayTimePeriod,
        uint64 delayBlockPeriod,
        bytes calldata proof,
        bytes calldata prefix,
        bytes calldata path
    ) external returns (bool);

    /**
     * @dev getClientState returns the clientState corresponding to `clientId`.
     *      If it's not found, the function returns false.
     */
    function getClientState(string calldata clientId) external view returns (bytes memory, bool);

    /**
     * @dev getConsensusState returns the consensusState corresponding to `clientId` and `height`.
     *      If it's not found, the function returns false.
     */
    function getConsensusState(string calldata clientId, Height.Data calldata height)
        external
        view
        returns (bytes memory, bool);
}


// File @hyperledger-labs/yui-ibc-solidity/contracts/core/24-host/IIBCHostConfigurator.sol@v0.1.0

// Original license: SPDX_License_Identifier: Apache-2.0
pragma solidity ^0.8.20;


interface IIBCHostConfigurator {
    /**
     * @dev setExpectedTimePerBlock sets expected time per block.
     * Typically this function should be called by an authority like an IBC contract owner or govenance.
     */
    function setExpectedTimePerBlock(uint64 expectedTimePerBlock_) external;

    /**
     * @dev registerClient registers a new client type into the client registry
     * Typically this function should be called by an authority like an IBC contract owner or govenance.
     * The authority should verify the light client contract is a valid implementation as follows:
     * - The contract implements ILightClient
     * - To avoid reentrancy attack, the contract never performs `call` to the IBC contract directly or indirectly in the `verifyMembership` and the `verifyNonMembership`
     */
    function registerClient(string calldata clientType, ILightClient client) external;

    /**
     * @dev bindPort binds to an unallocated port, failing if the port has already been allocated.
     * Typically this function should be called by an authority like an IBC contract owner or govenance.
     * The authority should verify the light client contract is a valid implementation as follows:
     * - The contract implements IIBCModuleInitializer
     */
    function bindPort(string calldata portId, IIBCModuleInitializer moduleAddress) external;
}


// File @hyperledger-labs/yui-ibc-solidity/contracts/core/24-host/IIBCHostErrors.sol@v0.1.0

// Original license: SPDX_License_Identifier: Apache-2.0
pragma solidity ^0.8.20;

interface IIBCHostErrors {
    /// @param clientType client type
    error IBCHostInvalidClientType(string clientType);

    /// @param clientType client type
    error IBCHostClientTypeAlreadyExists(string clientType);

    /// @param portId port identifier
    error IBCHostInvalidPortIdentifier(string portId);

    /// @param lcAddress light client contract address
    error IBCHostInvalidLightClientAddress(address lcAddress);

    /// @param moduleAddress module contract address
    error IBCHostInvalidModuleAddress(address moduleAddress);

    /// @param portId port identifier
    error IBCHostModulePortNotFound(string portId);

    /// @param portId port identifier
    /// @param channelId channel identifier
    error IBCHostModuleChannelNotFound(string portId, string channelId);

    error IBCHostModuleDoesNotSupportERC165();

    /// @param module module contract address
    /// @param interfaceId expected interface identifier
    error IBCHostModuleDoesNotSupportIIBCModule(address module, bytes4 interfaceId);

    /// @param module module contract address
    /// @param interfaceId expected interface identifier
    error IBCHostModuleDoesNotSupportIIBCModuleInitializer(address module, bytes4 interfaceId);

    /// @param module module contract address
    error IBCHostModuleDoesNotSupportIIBCModuleUpgrade(address module);

    /// @param portId port identifier
    error IBCHostPortCapabilityAlreadyClaimed(string portId);

    /// @param portId port identifier
    /// @param channelId channel identifier
    error IBCHostChannelCapabilityAlreadyClaimed(string portId, string channelId);

    /// @param portId port identifier
    /// @param channelId channel identifier
    /// @param caller caller address
    error IBCHostFailedAuthenticateChannelCapability(string portId, string channelId, address caller);
}


// File @hyperledger-labs/yui-ibc-solidity/contracts/core/04-channel/IBCChannelLib.sol@v0.1.0

// Original license: SPDX_License_Identifier: Apache-2.0
pragma solidity ^0.8.20;


library IBCChannelLib {
    enum PacketReceipt {
        NONE,
        SUCCESSFUL
    }

    string internal constant ORDER_UNORDERED = "ORDER_UNORDERED";
    string internal constant ORDER_ORDERED = "ORDER_ORDERED";

    bytes32 internal constant PACKET_RECEIPT_SUCCESSFUL_KECCAK256 =
        keccak256(abi.encodePacked(PacketReceipt.SUCCESSFUL));

    function receiptCommitmentToReceipt(bytes32 commitment) internal pure returns (PacketReceipt) {
        if (commitment == bytes32(0)) {
            return PacketReceipt.NONE;
        } else if (commitment == PACKET_RECEIPT_SUCCESSFUL_KECCAK256) {
            return PacketReceipt.SUCCESSFUL;
        } else {
            revert IIBCChannelErrors.IBCChannelUnknownPacketReceiptCommitment(commitment);
        }
    }

    function buildConnectionHops(string memory connectionId) internal pure returns (string[] memory hops) {
        hops = new string[](1);
        hops[0] = connectionId;
        return hops;
    }

    function toString(Channel.Order order) internal pure returns (string memory) {
        if (order == Channel.Order.ORDER_UNORDERED) {
            return ORDER_UNORDERED;
        } else if (order == Channel.Order.ORDER_ORDERED) {
            return ORDER_ORDERED;
        } else {
            revert IIBCChannelErrors.IBCChannelUnknownChannelOrder(order);
        }
    }

    function uint64ToBigEndianBytes(uint64 v) internal pure returns (bytes memory) {
        return abi.encodePacked(bytes8(v));
    }
}


// File @hyperledger-labs/yui-ibc-solidity/contracts/core/25-handler/IIBCQuerier.sol@v0.1.0

// Original license: SPDX_License_Identifier: Apache-2.0
pragma solidity ^0.8.20;





interface IIBCQuerier {
    function getCommitmentPrefix() external view returns (bytes memory);

    function getCommitmentsSlot() external pure returns (bytes32);

    function getCommitment(bytes32 hashedPath) external view returns (bytes32);

    function getExpectedTimePerBlock() external view returns (uint64);

    function getIBCModuleByPort(string calldata portId) external view returns (IIBCModuleInitializer);

    function getIBCModuleByChannel(string calldata portId, string calldata channelId)
        external
        view
        returns (IIBCModule);

    function getClientByType(string calldata clientType) external view returns (address);

    function getClientType(string calldata clientId) external view returns (string memory);

    function getClient(string calldata clientId) external view returns (address);

    function getClientState(string calldata clientId) external view returns (bytes memory, bool);

    function getConsensusState(string calldata clientId, Height.Data calldata height)
        external
        view
        returns (bytes memory, bool);

    function getConnection(string calldata connectionId) external view returns (ConnectionEnd.Data memory, bool);

    function getChannel(string calldata portId, string calldata channelId)
        external
        view
        returns (Channel.Data memory, bool);

    function getNextSequenceSend(string calldata portId, string calldata channelId) external view returns (uint64);

    function getNextSequenceRecv(string calldata portId, string calldata channelId) external view returns (uint64);

    function getNextSequenceAck(string calldata portId, string calldata channelId) external view returns (uint64);

    function getPacketReceipt(string calldata portId, string calldata channelId, uint64 sequence)
        external
        view
        returns (IBCChannelLib.PacketReceipt);

    function getChannelUpgrade(string calldata portId, string calldata channelId)
        external
        view
        returns (Upgrade.Data memory, bool);

    function getCanTransitionToFlushComplete(string calldata portId, string calldata channelId)
        external
        view
        returns (bool);
}


// File @hyperledger-labs/yui-ibc-solidity/contracts/core/26-router/IIBCModuleManager.sol@v0.1.0

// Original license: SPDX_License_Identifier: Apache-2.0
pragma solidity ^0.8.20;

interface IIBCModuleManager {
    /// @notice Claim a capability for a port
    /// @param portId the port identifier
    /// @param module the module claiming the capability
    event IBCModuleManagerPortCapabilityClaimed(string portId, address module);
    /// @notice Emitted when a module claims a capability for a channel
    /// @param portId the port identifier
    /// @param channelId the channel identifier
    /// @param module the module claiming the capability
    event IBCModuleManagerChannelCapabilityClaimed(string portId, string channelId, address module);
}


// File @hyperledger-labs/yui-ibc-solidity/contracts/core/25-handler/IIBCHandler.sol@v0.1.0

// Original license: SPDX_License_Identifier: Apache-2.0
pragma solidity ^0.8.20;












/**
 * @dev IIBCHandler is a handler interface supports [ICS-25](https://github.com/cosmos/ibc/tree/main/spec/core/ics-025-handler-interface),
 */
interface IIBCHandler is
    IIBCClient,
    IIBCClientErrors,
    IIBCConnection,
    IIBCConnectionErrors,
    IIBCChannelHandshake,
    IIBCChannelPacket,
    IIBCChannelErrors,
    IIBCChannelUpgrade,
    IIBCChannelUpgradeErrors,
    IIBCHostConfigurator,
    IIBCHostErrors,
    IIBCModuleManager,
    IIBCQuerier
{}


// File @hyperledger-labs/yui-ibc-solidity/contracts/core/26-router/IIBCModuleUpgrade.sol@v0.1.0

// Original license: SPDX_License_Identifier: Apache-2.0
pragma solidity ^0.8.12;

interface IIBCModuleUpgrade {
    /**
     * @dev Returns the absolute timeout for the upgrade
     * @param portId Port identifier
     * @param channelId Channel identifier
     */
    function getUpgradeTimeout(string calldata portId, string calldata channelId)
        external
        view
        returns (Timeout.Data memory);

    /**
     * @dev Returns whether the `msgSender` is an authorized upgrader for the given channel
     * @param portId Port identifier
     * @param channelId Channel identifier
     * @param msgSender sender of the upgrade message
     */
    function isAuthorizedUpgrader(string calldata portId, string calldata channelId, address msgSender)
        external
        view
        returns (bool);

    /**
     * @dev Returns whether the given channel can transition to flush complete at the given upgrade sequence
     * NOTE: this function is never called in some cases where the core contract can guarantee all inflight packets are already acknolwedged
     * @param portId Port identifier
     * @param channelId Channel identifier
     * @param upgradeSequence Upgrade sequence
     * @param msgSender sender of the upgrade message
     */
    function canTransitionToFlushComplete(
        string calldata portId,
        string calldata channelId,
        uint64 upgradeSequence,
        address msgSender
    ) external view returns (bool);

    /**
     * @dev OnChanUpgradeInit enables additional custom logic to be executed when the channel upgrade is initialized.
     * It must validate the proposed version, order, and connection hops.
     * NOTE: in the case of crossing hellos, this callback may be executed on both chains.
     * @param portId Port identifier
     * @param channelId Channel identifier
     * @param upgradeSequence Upgrade sequence
     * @param proposedUpgradeFields Proposed upgrade fields
     */
    function onChanUpgradeInit(
        string calldata portId,
        string calldata channelId,
        uint64 upgradeSequence,
        UpgradeFields.Data calldata proposedUpgradeFields
    ) external view returns (string memory version);

    /**
     * @dev OnChanUpgradeTry enables additional custom logic to be executed in the ChannelUpgradeTry step of the
     * channel upgrade handshake. It must validate the proposed version (provided by the counterparty), order,
     * and connection hops.
     * @param portId Port identifier
     * @param channelId Channel identifier
     * @param upgradeSequence Upgrade sequence
     * @param proposedUpgradeFields Proposed upgrade fields
     */
    function onChanUpgradeTry(
        string calldata portId,
        string calldata channelId,
        uint64 upgradeSequence,
        UpgradeFields.Data calldata proposedUpgradeFields
    ) external view returns (string memory version);

    /**
     * @dev OnChanUpgradeAck enables additional custom logic to be executed in the ChannelUpgradeAck step of the
     * channel upgrade handshake. It must validate the version proposed by the counterparty.
     * @param portId Port identifier
     * @param channelId Channel identifier
     * @param upgradeSequence Upgrade sequence
     * @param counterpartyVersion Counterparty version
     */
    function onChanUpgradeAck(
        string calldata portId,
        string calldata channelId,
        uint64 upgradeSequence,
        string calldata counterpartyVersion
    ) external view;

    /**
     * @dev OnChanUpgradeOpen enables additional custom logic to be executed when the channel upgrade has successfully completed, and the channel
     * has returned to the OPEN state. Any logic associated with changing of the channel fields should be performed
     * in this callback.
     *  @param portId Port identifier
     * @param channelId Channel identifier
     * @param upgradeSequence Upgrade sequence
     */
    function onChanUpgradeOpen(string calldata portId, string calldata channelId, uint64 upgradeSequence) external;
}


// File @hyperledger-labs/yui-ibc-solidity/contracts/apps/commons/IBCChannelUpgradableModule.sol@v0.1.0

// Original license: SPDX_License_Identifier: Apache-2.0
pragma solidity ^0.8.20;





abstract contract IBCChannelUpgradableModuleBase is
    AppBase,
    IIBCModuleUpgrade,
    IIBCChannelUpgradableModule,
    IIBCChannelUpgradableModuleErrors
{
    // ------------------- Storage ------------------- //

    /**
     * @dev Proposed upgrades for each channel
     */
    mapping(string portId => mapping(string channelId => UpgradeProposal)) internal upgradeProposals;
    /**
     * @dev Allowed transitions for each upgrade sequence
     */
    mapping(string portId => mapping(string channelId => mapping(uint64 upgradeSequence => AllowedTransition))) internal
        allowedTransitions;

    // ------------------- Modifiers ------------------- //

    /**
     * @dev Throws if the sender is not an authorized upgrader
     * @param portId Port identifier
     * @param channelId Channel identifier
     */
    modifier onlyAuthorizedUpgrader(string calldata portId, string calldata channelId) {
        if (!_isAuthorizedUpgrader(portId, channelId, _msgSender())) {
            revert IBCChannelUpgradableModuleUnauthorizedUpgrader();
        }
        _;
    }

    // ------------------- Public Functions ------------------- //

    /**
     * @dev See {IIBCChannelUpgradableModule-getUpgradeProposal}
     */
    function getUpgradeProposal(string calldata portId, string calldata channelId)
        public
        view
        virtual
        override
        returns (UpgradeProposal memory)
    {
        return upgradeProposals[portId][channelId];
    }

    /**
     * @dev See {IIBCChannelUpgradableModule-proposeUpgrade}
     */
    function proposeUpgrade(
        string calldata portId,
        string calldata channelId,
        UpgradeFields.Data calldata upgradeFields,
        Timeout.Data calldata timeout
    ) public virtual override onlyAuthorizedUpgrader(portId, channelId) {
        if (timeout.height.revision_number == 0 && timeout.height.revision_height == 0 && timeout.timestamp == 0) {
            revert IBCChannelUpgradableModuleInvalidTimeout();
        }
        if (upgradeFields.ordering == Channel.Order.ORDER_NONE_UNSPECIFIED || upgradeFields.connection_hops.length == 0)
        {
            revert IBCChannelUpgradableModuleInvalidConnectionHops();
        }
        (Channel.Data memory channel, bool found) = IIBCHandler(ibcAddress()).getChannel(portId, channelId);
        if (!found) {
            revert IBCChannelUpgradableModuleChannelNotFound();
        }
        UpgradeProposal storage upgrade = upgradeProposals[portId][channelId];
        if (upgrade.fields.connection_hops.length != 0) {
            // re-proposal is allowed as long as it does not transition to FLUSHING state yet
            if (channel.state != Channel.State.STATE_OPEN) {
                revert IBCChannelUpgradableModuleCannotOverwriteUpgrade();
            }
        }
        upgrade.fields = upgradeFields;
        upgrade.timeout = timeout;
    }

    /**
     * @dev See {IIBCChannelUpgradableModule-allowTransitionToFlushComplete}
     */
    function allowTransitionToFlushComplete(string calldata portId, string calldata channelId, uint64 upgradeSequence)
        public
        virtual
        override
        onlyAuthorizedUpgrader(portId, channelId)
    {
        UpgradeProposal storage upgrade = upgradeProposals[portId][channelId];
        if (upgrade.fields.connection_hops.length == 0) {
            revert IBCChannelUpgradableModuleUpgradeNotFound();
        }
        (, bool found) = IIBCHandler(ibcAddress()).getChannelUpgrade(portId, channelId);
        if (!found) {
            revert IBCChannelUpgradableModuleUpgradeNotFound();
        }
        (Channel.Data memory channel,) = IIBCHandler(ibcAddress()).getChannel(portId, channelId);
        if (channel.state != Channel.State.STATE_FLUSHING) {
            revert IBCChannelUpgradableModuleChannelNotFlushingState(channel.state);
        }
        if (channel.upgrade_sequence != upgradeSequence) {
            revert IBCChannelUpgradableModuleSequenceMismatch(channel.upgrade_sequence);
        }
        allowedTransitions[portId][channelId][upgradeSequence].flushComplete = true;
    }

    /**
     * @dev See {IIBCChannelUpgradableModule-removeUpgradeProposal}
     */
    function removeUpgradeProposal(string calldata portId, string calldata channelId)
        public
        virtual
        onlyAuthorizedUpgrader(portId, channelId)
    {
        _removeUpgradeProposal(portId, channelId);
    }

    // ------------------- IIBCModuleUpgrade ------------------- //

    /**
     * @dev See {IIBCModuleUpgrade-isAuthorizedUpgrader}
     */
    function isAuthorizedUpgrader(string calldata portId, string calldata channelId, address msgSender)
        public
        view
        virtual
        override
        returns (bool)
    {
        return _isAuthorizedUpgrader(portId, channelId, msgSender);
    }

    /**
     * @dev See {IIBCModuleUpgrade-canTransitionToFlushComplete}
     */
    function canTransitionToFlushComplete(
        string calldata portId,
        string calldata channelId,
        uint64 upgradeSequence,
        address
    ) public view virtual override returns (bool) {
        return allowedTransitions[portId][channelId][upgradeSequence].flushComplete;
    }

    /**
     * @dev See {IIBCModuleUpgrade-getUpgradeTimeout}
     */
    function getUpgradeTimeout(string calldata portId, string calldata channelId)
        public
        view
        virtual
        override
        returns (Timeout.Data memory)
    {
        if (upgradeProposals[portId][channelId].fields.connection_hops.length == 0) {
            revert IBCChannelUpgradableModuleUpgradeNotFound();
        }
        return upgradeProposals[portId][channelId].timeout;
    }

    /**
     * @dev See {IIBCModuleUpgrade-onChanUpgradeInit}
     */
    function onChanUpgradeInit(
        string calldata portId,
        string calldata channelId,
        uint64,
        UpgradeFields.Data calldata proposedUpgradeFields
    ) public view virtual override onlyIBC returns (string memory version) {
        UpgradeProposal storage upgrade = upgradeProposals[portId][channelId];
        if (upgrade.fields.connection_hops.length == 0) {
            revert IBCChannelUpgradableModuleUpgradeNotFound();
        }
        if (!equals(upgrade.fields, proposedUpgradeFields)) {
            revert IBCChannelUpgradableModuleInvalidUpgrade();
        }
        return proposedUpgradeFields.version;
    }

    /**
     * @dev See {IIBCModuleUpgrade-onChanUpgradeTry}
     */
    function onChanUpgradeTry(
        string calldata portId,
        string calldata channelId,
        uint64,
        UpgradeFields.Data calldata proposedUpgradeFields
    ) public view virtual override onlyIBC returns (string memory version) {
        UpgradeProposal storage upgrade = upgradeProposals[portId][channelId];
        if (upgrade.fields.connection_hops.length == 0) {
            revert IBCChannelUpgradableModuleUpgradeNotFound();
        }
        if (!equals(upgrade.fields, proposedUpgradeFields)) {
            revert IBCChannelUpgradableModuleInvalidUpgrade();
        }
        return proposedUpgradeFields.version;
    }

    /**
     * @dev See {IIBCModuleUpgrade-onChanUpgradeAck}
     */
    function onChanUpgradeAck(string calldata, string calldata, uint64, string calldata counterpartyVersion)
        public
        view
        virtual
        override
        onlyIBC
    {}

    /**
     * @dev See {IIBCModuleUpgrade-onChanUpgradeOpen}
     */
    function onChanUpgradeOpen(string calldata portId, string calldata channelId, uint64 upgradeSequence)
        public
        virtual
        override
        onlyIBC
    {
        delete upgradeProposals[portId][channelId];
        delete allowedTransitions[portId][channelId][upgradeSequence];
    }

    /**
     * @dev See {IERC165-supportsInterface}
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return super.supportsInterface(interfaceId) || interfaceId == type(IIBCModuleUpgrade).interfaceId
            || interfaceId == type(IIBCChannelUpgradableModule).interfaceId;
    }

    // ------------------- Internal Functions ------------------- //

    /**
     * @dev Returns whether the given address is authorized to upgrade the channel
     */
    function _isAuthorizedUpgrader(string calldata portId, string calldata channelId, address msgSender)
        internal
        view
        virtual
        returns (bool);

    /**
     * @dev Removes the proposed upgrade for the given port and channel
     */
    function _removeUpgradeProposal(string calldata portId, string calldata channelId) internal {
        if (upgradeProposals[portId][channelId].fields.connection_hops.length == 0) {
            revert IBCChannelUpgradableModuleUpgradeNotFound();
        }
        IIBCHandler handler = IIBCHandler(ibcAddress());
        (, bool found) = handler.getChannelUpgrade(portId, channelId);
        if (found) {
            Channel.Data memory channel;
            (channel, found) = handler.getChannel(portId, channelId);
            if (!found) {
                revert IBCChannelUpgradableModuleChannelNotFound();
            }
            if (channel.state != Channel.State.STATE_OPEN) {
                revert IBCChannelUpgradableModuleCannotRemoveInProgressUpgrade();
            }
        }
        delete upgradeProposals[portId][channelId];
    }

    /**
     * @dev Compares two UpgradeFields structs
     */
    function equals(UpgradeFields.Data storage a, UpgradeFields.Data calldata b) internal view returns (bool) {
        if (a.ordering != b.ordering) {
            return false;
        }
        if (a.connection_hops.length != b.connection_hops.length) {
            return false;
        }
        for (uint256 i = 0; i < a.connection_hops.length; i++) {
            if (keccak256(abi.encodePacked(a.connection_hops[i])) != keccak256(abi.encodePacked(b.connection_hops[i])))
            {
                return false;
            }
        }
        return keccak256(abi.encodePacked(a.version)) == keccak256(abi.encodePacked(b.version));
    }
}


// File @datachainlab/ethereum-ibc-relay-chain/contracts/IBCContractUpgradableModule.sol@v1.0.0

// Original license: SPDX_License_Identifier: Apache-2.0
pragma solidity ^0.8.20;



abstract contract IBCContractUpgradableModuleBase is
    IBCChannelUpgradableModuleBase,
    IIBCContractUpgradableModule,
    IIBCContractUpgradableModuleErrors
{
    // ------------------- Storage ------------------- //

    // NOTE: A module should set an initial appVersion struct in contract constructor or initializer
    mapping(string appVersion => AppInfo) internal appInfos;

    // ------------------- Modifiers ------------------- //

    modifier onlyContractUpgrader() {
        address msgSender = _msgSender();
        if (!_isContractUpgrader(msgSender)) {
            revert IBCContractUpgradableModuleUnauthorizedUpgrader(msgSender);
        }
        _;
    }

    // ------------------- Functions ------------------- //

    /**
     * @dev See {IIBCContractUpgradableModule-getAppinfoproposal}
     */
    function getAppInfoProposal(string calldata version)
        external
        view
        override(IIBCContractUpgradableModule)
        returns (AppInfo memory)
    {
        return appInfos[version];
    }

    /**
     * @dev See {IIBCContractUpgradableModule-proposeAppVersion}
     */
    function proposeAppVersion(string calldata version, address implementation, bytes calldata initialCalldata)
        external
        override(IIBCContractUpgradableModule)
        onlyContractUpgrader
    {
        if (implementation == address(0)) {
            revert IBCContractUpgradableModuleAppInfoProposedWithZeroImpl();
        }

        AppInfo storage appInfo = appInfos[version];
        if (appInfo.implementation != address(0)) {
            revert IBCContractUpgradableModuleAppInfoIsAlreadySet();
        }

        appInfos[version] = AppInfo({
            implementation: implementation,
            initialCalldata: initialCalldata,
            consumed: false
        });
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(IBCChannelUpgradableModuleBase)
        returns (bool)
    {
        return super.supportsInterface(interfaceId) ||
            interfaceId == type(IIBCContractUpgradableModule).interfaceId;
    }

    /**
     * @dev See {IIBCModuleUpgrade-onChanUpgradeInit}
     */
    function onChanUpgradeInit(
        string calldata portId,
        string calldata channelId,
        uint64 upgradeSequence,
        UpgradeFields.Data calldata proposedUpgradeFields
    )
        public
        view
        virtual
        override(IBCChannelUpgradableModuleBase)
        onlyIBC
        returns (string memory version)
    {
        version = super.onChanUpgradeInit(portId, channelId, upgradeSequence, proposedUpgradeFields);

        (Channel.Data memory channel, bool found) = IIBCHandler(ibcAddress()).getChannel(portId, channelId);
        if (!found) {
            revert IBCContractUpgradableModuleChannelNotFound(portId, channelId);
        }

        _prepareContractUpgrade(channel.version, version);
    }

    /**
     * @dev See {IIBCModuleUpgrade-onChanUpgradeTry}
     */
    function onChanUpgradeTry(
        string calldata portId,
        string calldata channelId,
        uint64 upgradeSequence,
        UpgradeFields.Data calldata proposedUpgradeFields
    )
        public
        view
        virtual
        override(IBCChannelUpgradableModuleBase)
        onlyIBC
        returns (string memory version)
    {
        version = super.onChanUpgradeTry(portId, channelId, upgradeSequence, proposedUpgradeFields);

        (Channel.Data memory channel, bool found) = IIBCHandler(ibcAddress()).getChannel(portId, channelId);
        if (!found) {
            revert IBCContractUpgradableModuleChannelNotFound(portId, channelId);
        }

        _prepareContractUpgrade(channel.version, version);
    }

    /**
     * @dev See {IIBCModuleUpgrade-onChanUpgradeOpen}
     */
    function onChanUpgradeOpen(
        string calldata portId,
        string calldata channelId,
        uint64 upgradeSequence
    )
        public
        virtual
        override(IBCChannelUpgradableModuleBase)
        onlyIBC
    {
        super.onChanUpgradeOpen(portId, channelId, upgradeSequence);

        (Channel.Data memory channel, bool found) = IIBCHandler(ibcAddress()).getChannel(portId, channelId);
        if (!found) {
            revert IBCContractUpgradableModuleChannelNotFound(portId, channelId);
        }

        _upgradeContract(channel.version);
    }

    // ------------------- Internal Functions ------------------- //

    function _isContractUpgrader(address msgSender) internal view virtual returns (bool);

    function _doUpgradeContract(address implementation, bytes memory initialCalldata) internal virtual;

    // ------------------- Private Functions ------------------- //

    function _prepareContractUpgrade(string memory version, string memory newVersion) private view {
        if (!_compareString(version, newVersion)) {
            AppInfo storage appInfo = appInfos[newVersion];
            if (appInfo.implementation == address(0)) {
                revert IBCContractUpgradableModuleAppInfoNotProposedYet();
            }
            if (appInfo.consumed) {
                revert IBCContractUpgradableModuleAlreadyConsumedAppInfo();
            }
        }
    }

    function _compareString(string memory a, string memory b) private pure returns (bool) {
        if (bytes(a).length != bytes(b).length) {
            return false;
        }
        return keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b));
    }

    function _upgradeContract(string memory newVersion) private {
        AppInfo storage appInfo = appInfos[newVersion];

        if (appInfo.implementation != address(0) && !appInfo.consumed) {
            appInfo.consumed = true;
            _doUpgradeContract(appInfo.implementation, appInfo.initialCalldata);
            delete appInfo.initialCalldata;
        }
    }
}


// File @hyperledger-labs/yui-ibc-solidity/contracts/apps/mock/IBCMockLib.sol@v0.1.0

// Original license: SPDX_License_Identifier: Apache-2.0
pragma solidity ^0.8.20;

library IBCMockLib {
    bytes public constant MOCK_PACKET_DATA = bytes("mock packet data");
    bytes public constant MOCK_FAIL_PACKET_DATA = bytes("mock failed packet data");
    bytes public constant MOCK_ASYNC_PACKET_DATA = bytes("mock async packet data");

    bytes public constant SUCCESSFUL_ACKNOWLEDGEMENT_JSON = bytes('{"result":"bW9jayBhY2tub3dsZWRnZW1lbnQ="}');
    bytes public constant SUCCESSFUL_ASYNC_ACKNOWLEDGEMENT_JSON =
        bytes('{"result":"bW9jayBhc3luYyBhY2tub3dsZWRnZW1lbnQ="}');
    bytes public constant FAILED_ACKNOWLEDGEMENT_JSON = bytes('{"error":"mock failed acknowledgement"}');
}


// File @hyperledger-labs/yui-ibc-solidity/contracts/apps/mock/IIBCMockErrors.sol@v0.1.0

// Original license: SPDX_License_Identifier: Apache-2.0
pragma solidity ^0.8.20;

interface IIBCMockErrors {
    /// @dev An error indicating that the version is unexpected
    /// @param actual Actual version
    /// @param expected Expected version
    error IBCMockUnexpectedVersion(string actual, string expected);

    /// @dev An error indicating that the packet acknowledgement is unexpected
    error IBCMockUnexpectedAcknowledgement(bytes actual, bytes expected);

    /// @dev An error indicating that the packet is unexpected
    error IBCMockUnexpectedPacket(bytes actual);
}


// File @openzeppelin/contracts/access/Ownable.sol@v5.0.2

// Original license: SPDX_License_Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.0) (access/Ownable.sol)

pragma solidity ^0.8.20;

/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * The initial owner is set to the address provided by the deployer. This can
 * later be changed with {transferOwnership}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
abstract contract Ownable is Context {
    address private _owner;

    /**
     * @dev The caller account is not authorized to perform an operation.
     */
    error OwnableUnauthorizedAccount(address account);

    /**
     * @dev The owner is not a valid owner account. (eg. `address(0)`)
     */
    error OwnableInvalidOwner(address owner);

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the address provided by the deployer as the initial owner.
     */
    constructor(address initialOwner) {
        if (initialOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _transferOwnership(initialOwner);
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if the sender is not the owner.
     */
    function _checkOwner() internal view virtual {
        if (owner() != _msgSender()) {
            revert OwnableUnauthorizedAccount(_msgSender());
        }
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby disabling any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        if (newOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}


// File @hyperledger-labs/yui-ibc-solidity/contracts/apps/mock/IBCMockApp.sol@v0.1.0

// Original license: SPDX_License_Identifier: Apache-2.0
pragma solidity ^0.8.20;








contract IBCMockApp is IBCAppBase, IIBCMockErrors, Ownable {
    string public constant MOCKAPP_VERSION = "mockapp-1";

    IIBCHandler immutable ibcHandler;

    bool public closeChannelAllowed = true;

    constructor(IIBCHandler ibcHandler_) Ownable(msg.sender) {
        ibcHandler = ibcHandler_;
    }

    function ibcAddress() public view virtual override returns (address) {
        return address(ibcHandler);
    }

    function sendPacket(
        bytes memory message,
        string calldata sourcePort,
        string calldata sourceChannel,
        Height.Data calldata timeoutHeight,
        uint64 timeoutTimestamp
    ) external returns (uint64) {
        return ibcHandler.sendPacket(sourcePort, sourceChannel, timeoutHeight, timeoutTimestamp, message);
    }

    function writeAcknowledgement(string calldata destinationPort, string calldata destinationChannel, uint64 sequence)
        external
    {
        ibcHandler.writeAcknowledgement(
            destinationPort, destinationChannel, sequence, IBCMockLib.SUCCESSFUL_ASYNC_ACKNOWLEDGEMENT_JSON
        );
    }

    function allowCloseChannel(bool allow) public onlyOwner {
        closeChannelAllowed = allow;
    }

    function onRecvPacket(Packet calldata packet, address)
        external
        view
        virtual
        override
        onlyIBC
        returns (bytes memory acknowledgement)
    {
        if (equals(packet.data, IBCMockLib.MOCK_PACKET_DATA)) {
            return IBCMockLib.SUCCESSFUL_ACKNOWLEDGEMENT_JSON;
        } else if (equals(packet.data, IBCMockLib.MOCK_ASYNC_PACKET_DATA)) {
            return bytes("");
        } else {
            return IBCMockLib.FAILED_ACKNOWLEDGEMENT_JSON;
        }
    }

    function onAcknowledgementPacket(Packet calldata packet, bytes calldata acknowledgement, address)
        external
        virtual
        override
        onlyIBC
    {
        if (equals(packet.data, IBCMockLib.MOCK_PACKET_DATA)) {
            if (!equals(acknowledgement, IBCMockLib.SUCCESSFUL_ACKNOWLEDGEMENT_JSON)) {
                revert IBCMockUnexpectedAcknowledgement(acknowledgement, IBCMockLib.SUCCESSFUL_ACKNOWLEDGEMENT_JSON);
            }
        } else if (equals(packet.data, IBCMockLib.MOCK_ASYNC_PACKET_DATA)) {
            if (!equals(acknowledgement, IBCMockLib.SUCCESSFUL_ASYNC_ACKNOWLEDGEMENT_JSON)) {
                revert IBCMockUnexpectedAcknowledgement(
                    acknowledgement, IBCMockLib.SUCCESSFUL_ASYNC_ACKNOWLEDGEMENT_JSON
                );
            }
        } else if (equals(packet.data, IBCMockLib.MOCK_FAIL_PACKET_DATA)) {
            if (!equals(acknowledgement, IBCMockLib.FAILED_ACKNOWLEDGEMENT_JSON)) {
                revert IBCMockUnexpectedAcknowledgement(acknowledgement, IBCMockLib.FAILED_ACKNOWLEDGEMENT_JSON);
            }
        } else {
            revert IBCMockUnexpectedPacket(packet.data);
        }
    }

    function onChanOpenInit(IIBCModule.MsgOnChanOpenInit calldata msg_)
        external
        virtual
        override
        onlyIBC
        returns (address, string memory)
    {
        if (bytes(msg_.version).length != 0 && keccak256(bytes(msg_.version)) != keccak256(bytes(MOCKAPP_VERSION))) {
            revert IBCMockUnexpectedVersion(msg_.version, MOCKAPP_VERSION);
        }
        return (address(this), MOCKAPP_VERSION);
    }

    function onChanOpenTry(IIBCModule.MsgOnChanOpenTry calldata msg_)
        external
        virtual
        override
        onlyIBC
        returns (address, string memory)
    {
        if (keccak256(bytes(msg_.counterpartyVersion)) != keccak256(bytes(MOCKAPP_VERSION))) {
            revert IBCMockUnexpectedVersion(msg_.counterpartyVersion, MOCKAPP_VERSION);
        }
        return (address(this), MOCKAPP_VERSION);
    }

    function onChanCloseInit(IIBCModule.MsgOnChanCloseInit calldata msg_) external virtual override onlyIBC {
        if (!closeChannelAllowed) {
            revert IBCModuleChannelCloseNotAllowed(msg_.portId, msg_.channelId);
        }
    }

    function onChanCloseConfirm(IIBCModule.MsgOnChanCloseConfirm calldata msg_) external virtual override onlyIBC {
        if (!closeChannelAllowed) {
            revert IBCModuleChannelCloseNotAllowed(msg_.portId, msg_.channelId);
        }
    }

    function onTimeoutPacket(Packet calldata packet, address) external view virtual override onlyIBC {
        if (!closeChannelAllowed) {
            revert IBCModuleChannelCloseNotAllowed(packet.sourcePort, packet.sourceChannel);
        }
    }

    function equals(bytes calldata a, bytes memory b) internal pure returns (bool) {
        return keccak256(a) == keccak256(b);
    }
}


// File @openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol@v5.0.2

// Original license: SPDX_License_Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.0) (proxy/utils/Initializable.sol)

pragma solidity ^0.8.20;

/**
 * @dev This is a base contract to aid in writing upgradeable contracts, or any kind of contract that will be deployed
 * behind a proxy. Since proxied contracts do not make use of a constructor, it's common to move constructor logic to an
 * external initializer function, usually called `initialize`. It then becomes necessary to protect this initializer
 * function so it can only be called once. The {initializer} modifier provided by this contract will have this effect.
 *
 * The initialization functions use a version number. Once a version number is used, it is consumed and cannot be
 * reused. This mechanism prevents re-execution of each "step" but allows the creation of new initialization steps in
 * case an upgrade adds a module that needs to be initialized.
 *
 * For example:
 *
 * [.hljs-theme-light.nopadding]
 * ```solidity
 * contract MyToken is ERC20Upgradeable {
 *     function initialize() initializer public {
 *         __ERC20_init("MyToken", "MTK");
 *     }
 * }
 *
 * contract MyTokenV2 is MyToken, ERC20PermitUpgradeable {
 *     function initializeV2() reinitializer(2) public {
 *         __ERC20Permit_init("MyToken");
 *     }
 * }
 * ```
 *
 * TIP: To avoid leaving the proxy in an uninitialized state, the initializer function should be called as early as
 * possible by providing the encoded function call as the `_data` argument to {ERC1967Proxy-constructor}.
 *
 * CAUTION: When used with inheritance, manual care must be taken to not invoke a parent initializer twice, or to ensure
 * that all initializers are idempotent. This is not verified automatically as constructors are by Solidity.
 *
 * [CAUTION]
 * ====
 * Avoid leaving a contract uninitialized.
 *
 * An uninitialized contract can be taken over by an attacker. This applies to both a proxy and its implementation
 * contract, which may impact the proxy. To prevent the implementation contract from being used, you should invoke
 * the {_disableInitializers} function in the constructor to automatically lock it when it is deployed:
 *
 * [.hljs-theme-light.nopadding]
 * ```
 * /// @custom:oz-upgrades-unsafe-allow constructor
 * constructor() {
 *     _disableInitializers();
 * }
 * ```
 * ====
 */
abstract contract Initializable {
    /**
     * @dev Storage of the initializable contract.
     *
     * It's implemented on a custom ERC-7201 namespace to reduce the risk of storage collisions
     * when using with upgradeable contracts.
     *
     * @custom:storage-location erc7201:openzeppelin.storage.Initializable
     */
    struct InitializableStorage {
        /**
         * @dev Indicates that the contract has been initialized.
         */
        uint64 _initialized;
        /**
         * @dev Indicates that the contract is in the process of being initialized.
         */
        bool _initializing;
    }

    // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.Initializable")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant INITIALIZABLE_STORAGE = 0xf0c57e16840df040f15088dc2f81fe391c3923bec73e23a9662efc9c229c6a00;

    /**
     * @dev The contract is already initialized.
     */
    error InvalidInitialization();

    /**
     * @dev The contract is not initializing.
     */
    error NotInitializing();

    /**
     * @dev Triggered when the contract has been initialized or reinitialized.
     */
    event Initialized(uint64 version);

    /**
     * @dev A modifier that defines a protected initializer function that can be invoked at most once. In its scope,
     * `onlyInitializing` functions can be used to initialize parent contracts.
     *
     * Similar to `reinitializer(1)`, except that in the context of a constructor an `initializer` may be invoked any
     * number of times. This behavior in the constructor can be useful during testing and is not expected to be used in
     * production.
     *
     * Emits an {Initialized} event.
     */
    modifier initializer() {
        // solhint-disable-next-line var-name-mixedcase
        InitializableStorage storage $ = _getInitializableStorage();

        // Cache values to avoid duplicated sloads
        bool isTopLevelCall = !$._initializing;
        uint64 initialized = $._initialized;

        // Allowed calls:
        // - initialSetup: the contract is not in the initializing state and no previous version was
        //                 initialized
        // - construction: the contract is initialized at version 1 (no reininitialization) and the
        //                 current contract is just being deployed
        bool initialSetup = initialized == 0 && isTopLevelCall;
        bool construction = initialized == 1 && address(this).code.length == 0;

        if (!initialSetup && !construction) {
            revert InvalidInitialization();
        }
        $._initialized = 1;
        if (isTopLevelCall) {
            $._initializing = true;
        }
        _;
        if (isTopLevelCall) {
            $._initializing = false;
            emit Initialized(1);
        }
    }

    /**
     * @dev A modifier that defines a protected reinitializer function that can be invoked at most once, and only if the
     * contract hasn't been initialized to a greater version before. In its scope, `onlyInitializing` functions can be
     * used to initialize parent contracts.
     *
     * A reinitializer may be used after the original initialization step. This is essential to configure modules that
     * are added through upgrades and that require initialization.
     *
     * When `version` is 1, this modifier is similar to `initializer`, except that functions marked with `reinitializer`
     * cannot be nested. If one is invoked in the context of another, execution will revert.
     *
     * Note that versions can jump in increments greater than 1; this implies that if multiple reinitializers coexist in
     * a contract, executing them in the right order is up to the developer or operator.
     *
     * WARNING: Setting the version to 2**64 - 1 will prevent any future reinitialization.
     *
     * Emits an {Initialized} event.
     */
    modifier reinitializer(uint64 version) {
        // solhint-disable-next-line var-name-mixedcase
        InitializableStorage storage $ = _getInitializableStorage();

        if ($._initializing || $._initialized >= version) {
            revert InvalidInitialization();
        }
        $._initialized = version;
        $._initializing = true;
        _;
        $._initializing = false;
        emit Initialized(version);
    }

    /**
     * @dev Modifier to protect an initialization function so that it can only be invoked by functions with the
     * {initializer} and {reinitializer} modifiers, directly or indirectly.
     */
    modifier onlyInitializing() {
        _checkInitializing();
        _;
    }

    /**
     * @dev Reverts if the contract is not in an initializing state. See {onlyInitializing}.
     */
    function _checkInitializing() internal view virtual {
        if (!_isInitializing()) {
            revert NotInitializing();
        }
    }

    /**
     * @dev Locks the contract, preventing any future reinitialization. This cannot be part of an initializer call.
     * Calling this in the constructor of a contract will prevent that contract from being initialized or reinitialized
     * to any version. It is recommended to use this to lock implementation contracts that are designed to be called
     * through proxies.
     *
     * Emits an {Initialized} event the first time it is successfully executed.
     */
    function _disableInitializers() internal virtual {
        // solhint-disable-next-line var-name-mixedcase
        InitializableStorage storage $ = _getInitializableStorage();

        if ($._initializing) {
            revert InvalidInitialization();
        }
        if ($._initialized != type(uint64).max) {
            $._initialized = type(uint64).max;
            emit Initialized(type(uint64).max);
        }
    }

    /**
     * @dev Returns the highest version that has been initialized. See {reinitializer}.
     */
    function _getInitializedVersion() internal view returns (uint64) {
        return _getInitializableStorage()._initialized;
    }

    /**
     * @dev Returns `true` if the contract is currently initializing. See {onlyInitializing}.
     */
    function _isInitializing() internal view returns (bool) {
        return _getInitializableStorage()._initializing;
    }

    /**
     * @dev Returns a pointer to the storage namespace.
     */
    // solhint-disable-next-line var-name-mixedcase
    function _getInitializableStorage() private pure returns (InitializableStorage storage $) {
        assembly {
            $.slot := INITIALIZABLE_STORAGE
        }
    }
}


// File @openzeppelin/contracts/interfaces/draft-IERC1822.sol@v5.0.2

// Original license: SPDX_License_Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.0) (interfaces/draft-IERC1822.sol)

pragma solidity ^0.8.20;

/**
 * @dev ERC1822: Universal Upgradeable Proxy Standard (UUPS) documents a method for upgradeability through a simplified
 * proxy whose upgrades are fully controlled by the current implementation.
 */
interface IERC1822Proxiable {
    /**
     * @dev Returns the storage slot that the proxiable contract assumes is being used to store the implementation
     * address.
     *
     * IMPORTANT: A proxy pointing at a proxiable contract should not be considered proxiable itself, because this risks
     * bricking a proxy that upgrades to it, by delegating to itself until out of gas. Thus it is critical that this
     * function revert if invoked through a proxy.
     */
    function proxiableUUID() external view returns (bytes32);
}


// File @openzeppelin/contracts/proxy/beacon/IBeacon.sol@v5.0.2

// Original license: SPDX_License_Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.0) (proxy/beacon/IBeacon.sol)

pragma solidity ^0.8.20;

/**
 * @dev This is the interface that {BeaconProxy} expects of its beacon.
 */
interface IBeacon {
    /**
     * @dev Must return an address that can be used as a delegate call target.
     *
     * {UpgradeableBeacon} will check that this address is a contract.
     */
    function implementation() external view returns (address);
}


// File @openzeppelin/contracts/utils/Address.sol@v5.0.2

// Original license: SPDX_License_Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.0) (utils/Address.sol)

pragma solidity ^0.8.20;

/**
 * @dev Collection of functions related to the address type
 */
library Address {
    /**
     * @dev The ETH balance of the account is not enough to perform the operation.
     */
    error AddressInsufficientBalance(address account);

    /**
     * @dev There's no code at `target` (it is not a contract).
     */
    error AddressEmptyCode(address target);

    /**
     * @dev A call to an address target failed. The target may have reverted.
     */
    error FailedInnerCall();

    /**
     * @dev Replacement for Solidity's `transfer`: sends `amount` wei to
     * `recipient`, forwarding all available gas and reverting on errors.
     *
     * https://eips.ethereum.org/EIPS/eip-1884[EIP1884] increases the gas cost
     * of certain opcodes, possibly making contracts go over the 2300 gas limit
     * imposed by `transfer`, making them unable to receive funds via
     * `transfer`. {sendValue} removes this limitation.
     *
     * https://consensys.net/diligence/blog/2019/09/stop-using-soliditys-transfer-now/[Learn more].
     *
     * IMPORTANT: because control is transferred to `recipient`, care must be
     * taken to not create reentrancy vulnerabilities. Consider using
     * {ReentrancyGuard} or the
     * https://solidity.readthedocs.io/en/v0.8.20/security-considerations.html#use-the-checks-effects-interactions-pattern[checks-effects-interactions pattern].
     */
    function sendValue(address payable recipient, uint256 amount) internal {
        if (address(this).balance < amount) {
            revert AddressInsufficientBalance(address(this));
        }

        (bool success, ) = recipient.call{value: amount}("");
        if (!success) {
            revert FailedInnerCall();
        }
    }

    /**
     * @dev Performs a Solidity function call using a low level `call`. A
     * plain `call` is an unsafe replacement for a function call: use this
     * function instead.
     *
     * If `target` reverts with a revert reason or custom error, it is bubbled
     * up by this function (like regular Solidity function calls). However, if
     * the call reverted with no returned reason, this function reverts with a
     * {FailedInnerCall} error.
     *
     * Returns the raw returned data. To convert to the expected return value,
     * use https://solidity.readthedocs.io/en/latest/units-and-global-variables.html?highlight=abi.decode#abi-encoding-and-decoding-functions[`abi.decode`].
     *
     * Requirements:
     *
     * - `target` must be a contract.
     * - calling `target` with `data` must not revert.
     */
    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but also transferring `value` wei to `target`.
     *
     * Requirements:
     *
     * - the calling contract must have an ETH balance of at least `value`.
     * - the called Solidity function must be `payable`.
     */
    function functionCallWithValue(address target, bytes memory data, uint256 value) internal returns (bytes memory) {
        if (address(this).balance < value) {
            revert AddressInsufficientBalance(address(this));
        }
        (bool success, bytes memory returndata) = target.call{value: value}(data);
        return verifyCallResultFromTarget(target, success, returndata);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a static call.
     */
    function functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) {
        (bool success, bytes memory returndata) = target.staticcall(data);
        return verifyCallResultFromTarget(target, success, returndata);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a delegate call.
     */
    function functionDelegateCall(address target, bytes memory data) internal returns (bytes memory) {
        (bool success, bytes memory returndata) = target.delegatecall(data);
        return verifyCallResultFromTarget(target, success, returndata);
    }

    /**
     * @dev Tool to verify that a low level call to smart-contract was successful, and reverts if the target
     * was not a contract or bubbling up the revert reason (falling back to {FailedInnerCall}) in case of an
     * unsuccessful call.
     */
    function verifyCallResultFromTarget(
        address target,
        bool success,
        bytes memory returndata
    ) internal view returns (bytes memory) {
        if (!success) {
            _revert(returndata);
        } else {
            // only check if target is a contract if the call was successful and the return data is empty
            // otherwise we already know that it was a contract
            if (returndata.length == 0 && target.code.length == 0) {
                revert AddressEmptyCode(target);
            }
            return returndata;
        }
    }

    /**
     * @dev Tool to verify that a low level call was successful, and reverts if it wasn't, either by bubbling the
     * revert reason or with a default {FailedInnerCall} error.
     */
    function verifyCallResult(bool success, bytes memory returndata) internal pure returns (bytes memory) {
        if (!success) {
            _revert(returndata);
        } else {
            return returndata;
        }
    }

    /**
     * @dev Reverts with returndata if present. Otherwise reverts with {FailedInnerCall}.
     */
    function _revert(bytes memory returndata) private pure {
        // Look for revert reason and bubble it up if present
        if (returndata.length > 0) {
            // The easiest way to bubble the revert reason is using memory via assembly
            /// @solidity memory-safe-assembly
            assembly {
                let returndata_size := mload(returndata)
                revert(add(32, returndata), returndata_size)
            }
        } else {
            revert FailedInnerCall();
        }
    }
}


// File @openzeppelin/contracts/utils/StorageSlot.sol@v5.0.2

// Original license: SPDX_License_Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.0) (utils/StorageSlot.sol)
// This file was procedurally generated from scripts/generate/templates/StorageSlot.js.

pragma solidity ^0.8.20;

/**
 * @dev Library for reading and writing primitive types to specific storage slots.
 *
 * Storage slots are often used to avoid storage conflict when dealing with upgradeable contracts.
 * This library helps with reading and writing to such slots without the need for inline assembly.
 *
 * The functions in this library return Slot structs that contain a `value` member that can be used to read or write.
 *
 * Example usage to set ERC1967 implementation slot:
 * ```solidity
 * contract ERC1967 {
 *     bytes32 internal constant _IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
 *
 *     function _getImplementation() internal view returns (address) {
 *         return StorageSlot.getAddressSlot(_IMPLEMENTATION_SLOT).value;
 *     }
 *
 *     function _setImplementation(address newImplementation) internal {
 *         require(newImplementation.code.length > 0);
 *         StorageSlot.getAddressSlot(_IMPLEMENTATION_SLOT).value = newImplementation;
 *     }
 * }
 * ```
 */
library StorageSlot {
    struct AddressSlot {
        address value;
    }

    struct BooleanSlot {
        bool value;
    }

    struct Bytes32Slot {
        bytes32 value;
    }

    struct Uint256Slot {
        uint256 value;
    }

    struct StringSlot {
        string value;
    }

    struct BytesSlot {
        bytes value;
    }

    /**
     * @dev Returns an `AddressSlot` with member `value` located at `slot`.
     */
    function getAddressSlot(bytes32 slot) internal pure returns (AddressSlot storage r) {
        /// @solidity memory-safe-assembly
        assembly {
            r.slot := slot
        }
    }

    /**
     * @dev Returns an `BooleanSlot` with member `value` located at `slot`.
     */
    function getBooleanSlot(bytes32 slot) internal pure returns (BooleanSlot storage r) {
        /// @solidity memory-safe-assembly
        assembly {
            r.slot := slot
        }
    }

    /**
     * @dev Returns an `Bytes32Slot` with member `value` located at `slot`.
     */
    function getBytes32Slot(bytes32 slot) internal pure returns (Bytes32Slot storage r) {
        /// @solidity memory-safe-assembly
        assembly {
            r.slot := slot
        }
    }

    /**
     * @dev Returns an `Uint256Slot` with member `value` located at `slot`.
     */
    function getUint256Slot(bytes32 slot) internal pure returns (Uint256Slot storage r) {
        /// @solidity memory-safe-assembly
        assembly {
            r.slot := slot
        }
    }

    /**
     * @dev Returns an `StringSlot` with member `value` located at `slot`.
     */
    function getStringSlot(bytes32 slot) internal pure returns (StringSlot storage r) {
        /// @solidity memory-safe-assembly
        assembly {
            r.slot := slot
        }
    }

    /**
     * @dev Returns an `StringSlot` representation of the string storage pointer `store`.
     */
    function getStringSlot(string storage store) internal pure returns (StringSlot storage r) {
        /// @solidity memory-safe-assembly
        assembly {
            r.slot := store.slot
        }
    }

    /**
     * @dev Returns an `BytesSlot` with member `value` located at `slot`.
     */
    function getBytesSlot(bytes32 slot) internal pure returns (BytesSlot storage r) {
        /// @solidity memory-safe-assembly
        assembly {
            r.slot := slot
        }
    }

    /**
     * @dev Returns an `BytesSlot` representation of the bytes storage pointer `store`.
     */
    function getBytesSlot(bytes storage store) internal pure returns (BytesSlot storage r) {
        /// @solidity memory-safe-assembly
        assembly {
            r.slot := store.slot
        }
    }
}


// File @openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol@v5.0.2

// Original license: SPDX_License_Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.0) (proxy/ERC1967/ERC1967Utils.sol)

pragma solidity ^0.8.20;



/**
 * @dev This abstract contract provides getters and event emitting update functions for
 * https://eips.ethereum.org/EIPS/eip-1967[EIP1967] slots.
 */
library ERC1967Utils {
    // We re-declare ERC-1967 events here because they can't be used directly from IERC1967.
    // This will be fixed in Solidity 0.8.21. At that point we should remove these events.
    /**
     * @dev Emitted when the implementation is upgraded.
     */
    event Upgraded(address indexed implementation);

    /**
     * @dev Emitted when the admin account has changed.
     */
    event AdminChanged(address previousAdmin, address newAdmin);

    /**
     * @dev Emitted when the beacon is changed.
     */
    event BeaconUpgraded(address indexed beacon);

    /**
     * @dev Storage slot with the address of the current implementation.
     * This is the keccak-256 hash of "eip1967.proxy.implementation" subtracted by 1.
     */
    // solhint-disable-next-line private-vars-leading-underscore
    bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    /**
     * @dev The `implementation` of the proxy is invalid.
     */
    error ERC1967InvalidImplementation(address implementation);

    /**
     * @dev The `admin` of the proxy is invalid.
     */
    error ERC1967InvalidAdmin(address admin);

    /**
     * @dev The `beacon` of the proxy is invalid.
     */
    error ERC1967InvalidBeacon(address beacon);

    /**
     * @dev An upgrade function sees `msg.value > 0` that may be lost.
     */
    error ERC1967NonPayable();

    /**
     * @dev Returns the current implementation address.
     */
    function getImplementation() internal view returns (address) {
        return StorageSlot.getAddressSlot(IMPLEMENTATION_SLOT).value;
    }

    /**
     * @dev Stores a new address in the EIP1967 implementation slot.
     */
    function _setImplementation(address newImplementation) private {
        if (newImplementation.code.length == 0) {
            revert ERC1967InvalidImplementation(newImplementation);
        }
        StorageSlot.getAddressSlot(IMPLEMENTATION_SLOT).value = newImplementation;
    }

    /**
     * @dev Performs implementation upgrade with additional setup call if data is nonempty.
     * This function is payable only if the setup call is performed, otherwise `msg.value` is rejected
     * to avoid stuck value in the contract.
     *
     * Emits an {IERC1967-Upgraded} event.
     */
    function upgradeToAndCall(address newImplementation, bytes memory data) internal {
        _setImplementation(newImplementation);
        emit Upgraded(newImplementation);

        if (data.length > 0) {
            Address.functionDelegateCall(newImplementation, data);
        } else {
            _checkNonPayable();
        }
    }

    /**
     * @dev Storage slot with the admin of the contract.
     * This is the keccak-256 hash of "eip1967.proxy.admin" subtracted by 1.
     */
    // solhint-disable-next-line private-vars-leading-underscore
    bytes32 internal constant ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    /**
     * @dev Returns the current admin.
     *
     * TIP: To get this value clients can read directly from the storage slot shown below (specified by EIP1967) using
     * the https://eth.wiki/json-rpc/API#eth_getstorageat[`eth_getStorageAt`] RPC call.
     * `0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103`
     */
    function getAdmin() internal view returns (address) {
        return StorageSlot.getAddressSlot(ADMIN_SLOT).value;
    }

    /**
     * @dev Stores a new address in the EIP1967 admin slot.
     */
    function _setAdmin(address newAdmin) private {
        if (newAdmin == address(0)) {
            revert ERC1967InvalidAdmin(address(0));
        }
        StorageSlot.getAddressSlot(ADMIN_SLOT).value = newAdmin;
    }

    /**
     * @dev Changes the admin of the proxy.
     *
     * Emits an {IERC1967-AdminChanged} event.
     */
    function changeAdmin(address newAdmin) internal {
        emit AdminChanged(getAdmin(), newAdmin);
        _setAdmin(newAdmin);
    }

    /**
     * @dev The storage slot of the UpgradeableBeacon contract which defines the implementation for this proxy.
     * This is the keccak-256 hash of "eip1967.proxy.beacon" subtracted by 1.
     */
    // solhint-disable-next-line private-vars-leading-underscore
    bytes32 internal constant BEACON_SLOT = 0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50;

    /**
     * @dev Returns the current beacon.
     */
    function getBeacon() internal view returns (address) {
        return StorageSlot.getAddressSlot(BEACON_SLOT).value;
    }

    /**
     * @dev Stores a new beacon in the EIP1967 beacon slot.
     */
    function _setBeacon(address newBeacon) private {
        if (newBeacon.code.length == 0) {
            revert ERC1967InvalidBeacon(newBeacon);
        }

        StorageSlot.getAddressSlot(BEACON_SLOT).value = newBeacon;

        address beaconImplementation = IBeacon(newBeacon).implementation();
        if (beaconImplementation.code.length == 0) {
            revert ERC1967InvalidImplementation(beaconImplementation);
        }
    }

    /**
     * @dev Change the beacon and trigger a setup call if data is nonempty.
     * This function is payable only if the setup call is performed, otherwise `msg.value` is rejected
     * to avoid stuck value in the contract.
     *
     * Emits an {IERC1967-BeaconUpgraded} event.
     *
     * CAUTION: Invoking this function has no effect on an instance of {BeaconProxy} since v5, since
     * it uses an immutable beacon without looking at the value of the ERC-1967 beacon slot for
     * efficiency.
     */
    function upgradeBeaconToAndCall(address newBeacon, bytes memory data) internal {
        _setBeacon(newBeacon);
        emit BeaconUpgraded(newBeacon);

        if (data.length > 0) {
            Address.functionDelegateCall(IBeacon(newBeacon).implementation(), data);
        } else {
            _checkNonPayable();
        }
    }

    /**
     * @dev Reverts if `msg.value` is not zero. It can be used to avoid `msg.value` stuck in the contract
     * if an upgrade doesn't perform an initialization call.
     */
    function _checkNonPayable() private {
        if (msg.value > 0) {
            revert ERC1967NonPayable();
        }
    }
}


// File @openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol@v5.0.2

// Original license: SPDX_License_Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.0) (proxy/utils/UUPSUpgradeable.sol)

pragma solidity ^0.8.20;



/**
 * @dev An upgradeability mechanism designed for UUPS proxies. The functions included here can perform an upgrade of an
 * {ERC1967Proxy}, when this contract is set as the implementation behind such a proxy.
 *
 * A security mechanism ensures that an upgrade does not turn off upgradeability accidentally, although this risk is
 * reinstated if the upgrade retains upgradeability but removes the security mechanism, e.g. by replacing
 * `UUPSUpgradeable` with a custom implementation of upgrades.
 *
 * The {_authorizeUpgrade} function must be overridden to include access restriction to the upgrade mechanism.
 */
abstract contract UUPSUpgradeable is Initializable, IERC1822Proxiable {
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    address private immutable __self = address(this);

    /**
     * @dev The version of the upgrade interface of the contract. If this getter is missing, both `upgradeTo(address)`
     * and `upgradeToAndCall(address,bytes)` are present, and `upgradeTo` must be used if no function should be called,
     * while `upgradeToAndCall` will invoke the `receive` function if the second argument is the empty byte string.
     * If the getter returns `"5.0.0"`, only `upgradeToAndCall(address,bytes)` is present, and the second argument must
     * be the empty byte string if no function should be called, making it impossible to invoke the `receive` function
     * during an upgrade.
     */
    string public constant UPGRADE_INTERFACE_VERSION = "5.0.0";

    /**
     * @dev The call is from an unauthorized context.
     */
    error UUPSUnauthorizedCallContext();

    /**
     * @dev The storage `slot` is unsupported as a UUID.
     */
    error UUPSUnsupportedProxiableUUID(bytes32 slot);

    /**
     * @dev Check that the execution is being performed through a delegatecall call and that the execution context is
     * a proxy contract with an implementation (as defined in ERC1967) pointing to self. This should only be the case
     * for UUPS and transparent proxies that are using the current contract as their implementation. Execution of a
     * function through ERC1167 minimal proxies (clones) would not normally pass this test, but is not guaranteed to
     * fail.
     */
    modifier onlyProxy() {
        _checkProxy();
        _;
    }

    /**
     * @dev Check that the execution is not being performed through a delegate call. This allows a function to be
     * callable on the implementing contract but not through proxies.
     */
    modifier notDelegated() {
        _checkNotDelegated();
        _;
    }

    function __UUPSUpgradeable_init() internal onlyInitializing {
    }

    function __UUPSUpgradeable_init_unchained() internal onlyInitializing {
    }
    /**
     * @dev Implementation of the ERC1822 {proxiableUUID} function. This returns the storage slot used by the
     * implementation. It is used to validate the implementation's compatibility when performing an upgrade.
     *
     * IMPORTANT: A proxy pointing at a proxiable contract should not be considered proxiable itself, because this risks
     * bricking a proxy that upgrades to it, by delegating to itself until out of gas. Thus it is critical that this
     * function revert if invoked through a proxy. This is guaranteed by the `notDelegated` modifier.
     */
    function proxiableUUID() external view virtual notDelegated returns (bytes32) {
        return ERC1967Utils.IMPLEMENTATION_SLOT;
    }

    /**
     * @dev Upgrade the implementation of the proxy to `newImplementation`, and subsequently execute the function call
     * encoded in `data`.
     *
     * Calls {_authorizeUpgrade}.
     *
     * Emits an {Upgraded} event.
     *
     * @custom:oz-upgrades-unsafe-allow-reachable delegatecall
     */
    function upgradeToAndCall(address newImplementation, bytes memory data) public payable virtual onlyProxy {
        _authorizeUpgrade(newImplementation);
        _upgradeToAndCallUUPS(newImplementation, data);
    }

    /**
     * @dev Reverts if the execution is not performed via delegatecall or the execution
     * context is not of a proxy with an ERC1967-compliant implementation pointing to self.
     * See {_onlyProxy}.
     */
    function _checkProxy() internal view virtual {
        if (
            address(this) == __self || // Must be called through delegatecall
            ERC1967Utils.getImplementation() != __self // Must be called through an active proxy
        ) {
            revert UUPSUnauthorizedCallContext();
        }
    }

    /**
     * @dev Reverts if the execution is performed via delegatecall.
     * See {notDelegated}.
     */
    function _checkNotDelegated() internal view virtual {
        if (address(this) != __self) {
            // Must not be called through delegatecall
            revert UUPSUnauthorizedCallContext();
        }
    }

    /**
     * @dev Function that should revert when `msg.sender` is not authorized to upgrade the contract. Called by
     * {upgradeToAndCall}.
     *
     * Normally, this function will use an xref:access.adoc[access control] modifier such as {Ownable-onlyOwner}.
     *
     * ```solidity
     * function _authorizeUpgrade(address) internal onlyOwner {}
     * ```
     */
    function _authorizeUpgrade(address newImplementation) internal virtual;

    /**
     * @dev Performs an implementation upgrade with a security check for UUPS proxies, and additional setup call.
     *
     * As a security check, {proxiableUUID} is invoked in the new implementation, and the return value
     * is expected to be the implementation slot in ERC1967.
     *
     * Emits an {IERC1967-Upgraded} event.
     */
    function _upgradeToAndCallUUPS(address newImplementation, bytes memory data) private {
        try IERC1822Proxiable(newImplementation).proxiableUUID() returns (bytes32 slot) {
            if (slot != ERC1967Utils.IMPLEMENTATION_SLOT) {
                revert UUPSUnsupportedProxiableUUID(slot);
            }
            ERC1967Utils.upgradeToAndCall(newImplementation, data);
        } catch {
            // The implementation is not UUPS
            revert ERC1967Utils.ERC1967InvalidImplementation(newImplementation);
        }
    }
}


// File @datachainlab/ethereum-ibc-relay-chain/contracts/IBCContractUpgradableUUPSMockApp.sol@v1.0.0

// Original license: SPDX_License_Identifier: Apache-2.0
pragma solidity ^0.8.20;






contract IBCContractUpgradableUUPSMockApp is
    UUPSUpgradeable,
    IBCMockApp,
    IBCContractUpgradableModuleBase
{
    address immutable _self;     // implementation's address, which is set by the constructor
    address immutable _deployer; // contract deployer, which is set by the constructor
    constructor(IIBCHandler ibcHandler_) IBCMockApp(ibcHandler_) {
        _self = address(this);
        _deployer = msg.sender;
    }

    // ------------------- Functions ------------------- //

    function self() external view returns(address) {
        return _self;
    }

    /**
     * @dev See {Ownable-owner}.
     */
    function owner() public view virtual override(Ownable) returns (address) {
        return _deployer;
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(IBCAppBase, IBCContractUpgradableModuleBase)
        returns (bool)
    {
        return super.supportsInterface(interfaceId) ||
            interfaceId == type(UUPSUpgradeable).interfaceId;
    }

    // ------------------- Internal Functions ------------------- //

    function __IBCContractUpgradableUUPSMockApp_init(string memory initialVersion) internal initializer {
        __UUPSUpgradeable_init();

        AppInfo storage appInfo = appInfos[initialVersion];
        appInfo.implementation = _self;
        appInfo.consumed = true;
    }

    /**
     * @dev See{IBCChannelUpgradableModuleBase-_isAuthorizedUpgrader}
     */
    function _isAuthorizedUpgrader(string calldata, string calldata, address msgSender)
        internal
        view
        virtual
        override(IBCChannelUpgradableModuleBase)
        returns (bool)
    {
        return _isContractUpgrader(msgSender);
    }

    /**
     * @dev See{IBCContractUpgradableModuleBase-_isContractUpgrader}
     */
    function _isContractUpgrader(address msgSender)
        internal
        view
        virtual
        override(IBCContractUpgradableModuleBase)
        returns (bool)
    {
        return msgSender == owner() || msgSender == address(this);
    }

    /**
     * @dev See{IBCContractUpgradableModuleBase-_upgradeContract}
     */
    function _doUpgradeContract(address implementation, bytes memory initialCalldata)
        internal
        virtual
        override(IBCContractUpgradableModuleBase)
    {
        // if there is no implementation update, nothing happens here
        if (ERC1967Utils.getImplementation() != implementation) {
            ERC1967Utils.upgradeToAndCall(implementation, initialCalldata);
        }
    }

    /**
     * @dev See {UUPSupgradeable-_authorizeupgrade}
     */
    function _authorizeUpgrade(address msgSender) internal view virtual override(UUPSUpgradeable) {
        if (!_isContractUpgrader(msgSender)) {
            revert IBCContractUpgradableModuleUnauthorizedUpgrader(msgSender);
        }
    }
}


// File contracts/App.sol

// Original license: SPDX_License_Identifier: Apache-2.0
pragma solidity ^0.8.20;


contract AppV1 is IBCContractUpgradableUUPSMockApp {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(IIBCHandler ibcHandler_) IBCContractUpgradableUUPSMockApp(ibcHandler_) {}

    function __AppV1_init(string memory initialVersion) public initializer {
        __IBCContractUpgradableUUPSMockApp_init(initialVersion);
    }
}

contract AppV2 is AppV1 {
    string public val2;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(IIBCHandler ibcHandler_) AppV1(ibcHandler_) {}

    function __AppV2_init(string memory v_) public reinitializer(2) {
        val2 = v_;
    }
}

contract AppV3 is AppV1 {
    string public val3;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(IIBCHandler ibcHandler_) AppV1(ibcHandler_) {}

    function __AppV3_init(string memory v_) public reinitializer(3) {
        val3 = v_;
    }
}

contract AppV4 is AppV1 {
    string public val4;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(IIBCHandler ibcHandler_) AppV1(ibcHandler_) {}

    function __AppV4_init(string memory v_) public reinitializer(4) {
        val4 = v_;
    }
}

contract AppV5 is AppV1 {
    string public val5;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(IIBCHandler ibcHandler_) AppV1(ibcHandler_) {}

    function __AppV5_init(string memory v_) public reinitializer(5) {
        val5 = v_;
    }
}

contract AppV6 is AppV1 {
    string public val6;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(IIBCHandler ibcHandler_) AppV1(ibcHandler_) {}

    function __AppV6_init(string memory v_) public reinitializer(6) {
        val6 = v_;
    }
}

contract AppV7 is AppV1 {
    string public val7;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(IIBCHandler ibcHandler_) AppV1(ibcHandler_) {}

    function __AppV7_init(string memory v_) public reinitializer(7) {
        val7 = v_;
    }
}

contract AppV8 is AppV1 {
    string public val8;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(IIBCHandler ibcHandler_) AppV1(ibcHandler_) {}

    function __AppV8_init(string memory v_) public reinitializer(8) {
        val8 = v_;
    }
}

contract AppV9 is AppV1 {
    string public val9;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(IIBCHandler ibcHandler_) AppV1(ibcHandler_) {}

    function __AppV9_init(string memory v_) public reinitializer(9) {
        val9 = v_;
    }
}

contract AppV10 is AppV1 {
    string public val10;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(IIBCHandler ibcHandler_) AppV1(ibcHandler_) {}

    function __AppV10_init(string memory v_) public reinitializer(10) {
        val10 = v_;
    }
}
