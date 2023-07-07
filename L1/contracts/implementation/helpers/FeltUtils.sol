// SPDX-License-Identifier: Apache-2.0.
pragma solidity 0.8.17;

library FeltUtils {

  error FeltUtils__InvalidFeltError(uint256 value);
  error FeltUtils__StringTooLong(string value);

  uint256 constant private FIELD_PRIME = 0x800000000000011000000000000000000000000000000000000000000000001;
  uint256 constant private LOW_BITS_MASK = (2 ** 128) - 1;

  function validateFelt(uint256 value) internal pure {
    if (value >= FIELD_PRIME) {
      revert FeltUtils__InvalidFeltError(value);
    }
  }

  function splitIntoLowHigh(uint256 value) internal pure returns (uint256 low, uint256 high) {
    low = value & LOW_BITS_MASK;
    high = value >> 128;
  }

  function stringToFelt(string memory str) internal pure returns (uint256 result) {
    bytes memory encoded = bytes(str);
    uint256 length = encoded.length;
    if (length > 32) {
      revert FeltUtils__StringTooLong(str);
    }
    result = uint256(bytes32(encoded));
    result >>= (32 - length) * 8;
    validateFelt(result);
  }
}
