// SPDX-License-Identifier: Apache-2.0.
pragma solidity 0.8.17;

library FeltUtils {

    function splitIntoLowHigh(uint256 value) internal pure returns (uint256 low, uint256 high) {
      low = value & LOW_BITS_MASK;
      high = value >> 128;
  }
}
