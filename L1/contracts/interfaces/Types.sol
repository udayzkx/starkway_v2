// SPDX-License-Identifier: Apache-2.0.
pragma solidity ^0.8.0;

library Types {

  /// @notice Describes a custom fee rate rule for some range of deposit amount
  /// @param feeRate Fee rate to be used to calculate a deposit fee
  /// @param toAmount The upper bound of segment's deposit amount range
  struct FeeSegment {
    uint256 feeRate;
    uint256 toAmount;
  }

  /// @notice Describes a Starknet message to be sent from L1 to L2
  /// @param fromAddress Address of message's sender
  /// @param toAddress Address of message's recipient
  /// @param selector Function selector to be called in the recipient contract on L2
  /// @param payload Message's payload data
  struct L1ToL2Message {
    address fromAddress;
    uint256 toAddress;
    uint256 selector;
    uint256[] payload;
  }

  /// @notice Struct containing information for an initialized token
  /// @param token Address of the token
  /// @param decimals Decimals value of the token
  /// @param initDate Initialization timestamp of the token
  struct TokenInfo {
    address token;
    uint8 decimals;
    uint88 initDate;
  }
}
