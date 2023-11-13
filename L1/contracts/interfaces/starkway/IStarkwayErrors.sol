// SPDX-License-Identifier: Apache-2.0.
pragma solidity >=0.8.0;

/// @title Interface with all Starkway's custom errors
/// @notice Contains a list of custom errors for Starkway
interface IStarkwayErrors {

  /// @notice If felt value is expected, but invalid value was provided
  /// @param parameter Name of corresponding parameter
  /// @param value The invalid value provided
  error InvalidFelt(string parameter, uint256 value);

  /// @notice If an error happened during a transfer
  error TransferFailed();

  /// @notice If the token is expected to be not initialized, but it already is
  error TokenAlreadyInitialized();

  /// @notice If the token is expected to be already initialized, but is not yet
  error TokenNotInitialized();

  /// @notice If deposits for the token have been disabled
  error TokenDepositsDisabled();

  /// @notice If msg.value provided doesn't match the expected msg.value
  /// @param actual Actual msg.value provided
  /// @param expected The expected eth value
  error InvalidEthValue(uint256 actual, uint256 expected);

  /// @notice If deposit fee doesn't match the expected fee
  /// @param actual Actual deposit fee provided
  /// @param expected Expected deposit fee
  error InvalidDepositFee(uint256 actual, uint256 expected);

  /// @notice If Starknet fee is not valid
  /// @param actual Actual starknet fee provided
  /// @param expected Expected starknet fee
  error InvalidStarknetFee(uint256 actual, uint256 expected);

  /// @notice If deposit amount is not within the acceptable range for the token
  /// @param actual Amount of the deposit
  /// @param min Min deposit amount allowed for the token
  /// @param max Max deposit amount allowed for the token
  error InvalidDepositAmount(uint256 actual, uint256 min, uint256 max);

  /// @notice If no matching fee segment is found
  error NoMatchingFeeSegment();

  /// @notice If the default fee rate is too high
  error DefaultFeeRateTooHigh();

  /// @notice If the amount is zero
  error ZeroAmountError();

  /// @notice If the address is zero
  error ZeroAddressError();

  /// @notice If there is an error during string encoding
  error StringEncodingError();

  /// @notice If the fee segments are invalid
  /// @dev Can happen only during token settings update
  error InvalidFeeSegments();

  /// @notice If the maximum deposit value is invalid
  /// @dev Can happen only during token settings update
  error InvalidMaxDeposit();

  /// @notice If the minimum fee value is invalid
  /// @dev Can happen only during token settings update
  error InvalidMinFee();

  /// @notice If the maximum fee value is invalid
  /// @dev Can happen only during token settings update
  error InvalidMaxFee();

  /// @notice If the segments must be empty but are not
  /// @dev Can happen only during token settings update
  error SegmentsMustBeEmpty();

  /// @notice If the segments must exist but do not
  /// @dev Can happen only during token settings update
  error SegmentsMustExist();

  /// @notice If the segment rate is too high
  /// @dev Can happen only during token settings update
  error SegmentRateTooHigh();
}
