// SPDX-License-Identifier: Apache-2.0.
pragma solidity >=0.8.0;

import {IStarkway} from "./IStarkway.sol";
import {Types} from '../Types.sol';

/// @title Interface for authorized management of Starkway
/// @notice Contains Starkway's functions available only for authorized callers
interface IStarkwayAuthorized is IStarkway {
  //////////
  // Read //
  //////////

  /// @notice Read call to validate deposit-related settings for the token
  /// @dev It's recommended to call `validateTokenSettings` before
  /// @dev `updateTokenSettings` to ensure tx doesn't revert.
  /// @param token Address of the token
  /// @param minDeposit Minimal deposit amount allowed
  /// @param maxDeposit Max deposit amount allowed
  /// @param minFee Minimal fee taken for deposit
  /// @param maxFee Max fee taked for deposit
  /// @param useCustomFeeRate If custom fee segments are used to calculate deposit fee for the token
  /// @param feeSegments Fee segments customizing fee behaviour for the token
  function validateTokenSettings(
    address token,
    uint256 minDeposit,
    uint256 maxDeposit,
    uint256 minFee,
    uint256 maxFee,
    bool useCustomFeeRate,
    Types.FeeSegment[] calldata feeSegments
  ) external view;

  ///////////
  // Write //
  ///////////

  /// @notice Sets a default deposit fee rate. Default deposit fee rate is used if a token has no settings set
  /// @param feeRate Value of deposit fee rate. Values unit equals to 100, so 50 = 0.5% and 300 = 3%
  function setDefaultDepositFeeRate(uint256 feeRate) external;

  /// @notice Disables deposits for a token. Has no effect on withdrawals and deposit cancellation
  /// @dev By default deposits are enabled for all tokens
  /// @dev Does not revert if the token is already disabled, just does nothing
  /// @param token Address of the token to disable
  function disableDepositsForToken(address token) external;

  /// @notice Disables deposits for a token. Has no effect on withdrawals and deposit cancellation
  /// @dev It makes sense to enable a token only if it was disabled before. Otherwise it's enabled by default
  /// @dev Does not revert if the token is already enabled, just does nothing
  /// @param token Address of the token to enable
  function enableDepositsForToken(address token) external;

  /// @notice Updates deposit-related settings for the token
  /// @param token Address of the token
  /// @param minDeposit Minimal deposit amount allowed
  /// @param maxDeposit Max deposit amount allowed
  /// @param minFee Minimal fee taken for deposit
  /// @param maxFee Max fee taked for deposit
  /// @param useCustomFeeRate If custom fee segments are used to calculate deposit fee for the token
  /// @param feeSegments Fee segments customizing fee behaviour for the token
  function updateTokenSettings(
    address token,
    uint256 minDeposit,
    uint256 maxDeposit,
    uint256 minFee,
    uint256 maxFee,
    bool useCustomFeeRate,
    Types.FeeSegment[] calldata feeSegments
  ) external;

  /// @notice Removes all stored deposit settings for the token
  /// @param token Address of the token
  function clearTokenSettings(address token) external;

  /// @notice Lets owner to start a deposit cancelation process on behalf of a user.
  /// @dev May be used as a fallback solution to cancel a failing deposit.
  /// @dev This way the affected user doesn't have to cancel deposit and pay costly L1 fees himself.
  /// @param token Address of the deposited token
  /// @param recipientAddressL2 Address of deposit recipient on L2
  /// @param deposit Deposit amount
  /// @param depositFee Deposit fee
  /// @param messageRecipientL2 The recipient of deposit message
  /// @param messagePayload Custom message payload
  /// @param nonce Nonce value used for L1-to-L2 deposit message
  function startDepositCancelationByOwner(
    address token,
    address senderAddressL1,
    uint256 recipientAddressL2,
    uint256 deposit,
    uint256 depositFee,
    uint256 messageRecipientL2,
    uint256[] calldata messagePayload,
    uint256 nonce
  ) external;

  /// @notice Lets owner to finalize a deposit cancelation process on behalf of a user.
  /// @dev May be used as a fallback solution to cancel a failing deposit.
  /// @dev This way the affected user doesn't have to cancel deposit and pay costly L1 fees himself.
  /// @param token Address of the deposited token
  /// @param recipientAddressL2 Address of deposit recipient on L2
  /// @param deposit Deposit amount
  /// @param depositFee Deposit fee
  /// @param messageRecipientL2 The recipient of deposit message
  /// @param messagePayload Custom message payload
  /// @param nonce Nonce value used for L1-to-L2 deposit message
  function finishDepositCancelationByOwner(
    address token,
    address senderAddressL1,
    uint256 recipientAddressL2,
    uint256 deposit,
    uint256 depositFee,
    uint256 messageRecipientL2,
    uint256[] calldata messagePayload,
    uint256 nonce
  ) external;
}
