// SPDX-License-Identifier: Apache-2.0.
pragma solidity >=0.8.0;

import {Types} from '../Types.sol';

/// @title Public interface for Starkway contract
/// @notice Contains Starkway's functions available for public
interface IStarkway {
  //////////
  // Read //
  //////////

  /// @notice Provides the state of Starkway: connected contracts and fee-related settings
  /// @dev A single function to fetch all state values for a better performance
  /// @return _vault Address of StarkwayVault contract (immutable value)
  /// @return _starknet Address of Starknet messaging contract on L1
  /// @return _starkwayL2 Address of Starkway contract on L2 (immutable value)
  /// @return _defaultFeeRate The default fee rate for deposits
  /// @return _maxFeeRate The maximum fee rate for deposits (immutable value)
  function getStarkwayState() 
    external 
    view 
    returns (
      address _vault,
      address _starknet,
      uint256 _starkwayL2,
      uint256 _defaultFeeRate,
      uint256 _maxFeeRate
    );

  /// @notice Calculates fees for deposit transaction
  /// @dev `calculateFees` must be called to precalculate fees that are required as inputs for deposit
  /// @param token Address of the deposited token
  /// @param deposit Deposit amount (final amount to be received on Starknet, fees are payed on top)
  /// @return depositFee Deposit fee payed in deposited token to Starkway
  /// @return starknetFee L1-to-L2 message fee payed in ETH to Starknet
  function calculateFees(address token, uint256 deposit)
    external
    view
    returns (uint256 depositFee, uint256 starknetFee);

  /// @notice Provides deposit settings for a token
  /// @param token Token of interest
  /// @return minDeposit Minimal deposit amount allowed
  /// @return maxDeposit Max deposit amount allowed
  /// @return minFee Minimal fee taken for deposit
  /// @return maxFee Max fee taked for deposit
  /// @return useCustomFeeRate If custom fee segments are used to calculate deposit fee for the token
  /// @return feeSegments Fee segments customizing fee behaviour for the token
  function getTokenSettings(address token) external view returns (
    uint256 minDeposit,
    uint256 maxDeposit,
    uint256 minFee,
    uint256 maxFee,
    bool useCustomFeeRate,
    Types.FeeSegment[] calldata feeSegments
  );

  ///////////
  // Write //
  ///////////

  /// @notice Performs a deposit of funds from L1 to L2. Deposits support ERC20 tokens and native ETH
  /// @dev To get precalculated `depositFee` and `starknetFee`, `calculateFees` function must be called
  /// @dev For ETH deposits a fake address of 'e's should be provided: 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE
  /// @param token Address of the deposited token
  /// @param recipientAddressL2 Address of deposit recipient on L2
  /// @param deposit Deposit amount (doesn't include depositFee)
  /// @param depositFee Deposit fee payed in deposited token
  /// @param starknetFee Starknet messaging fee payed in ETH
  function depositFunds(
    address token,
    uint256 recipientAddressL2,
    uint256 deposit,
    uint256 depositFee,
    uint256 starknetFee
  )
    external
    payable
    returns (bytes32 msgHash, uint256 nonce);

  /// @notice Performs a deposit with a custom attached message. Deposits support ERC20 tokens and native ETH
  /// @dev To get precalculated `depositFee` and `starknetFee`, `calculateFees` function must be called
  /// @dev For ETH deposits a fake address of 'e's should be provided: 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE
  /// @param token Address of the deposited token
  /// @param recipientAddressL2 Address of deposit recipient on L2
  /// @param deposit Deposit amount (doesn't include depositFee)
  /// @param depositFee Deposit fee payed in deposited token to Starkway
  /// @param starknetFee L1-to-L2 messaging fee payed in ETH to Starknet
  /// @param messageRecipientL2 Address of deposit message recipient on Starknet (may differ from recipientAddressL2)
  /// @param messagePayload Custom payload that will be attached to general deposit info and provided to the message recipient on L2
  function depositFundsWithMessage(
    address token,
    uint256 recipientAddressL2,
    uint256 deposit,
    uint256 depositFee,
    uint256 starknetFee,
    uint256 messageRecipientL2,
    uint256[] calldata messagePayload
  )
    external
    payable
    returns (bytes32 msgHash, uint256 nonce);

  /// @notice Completes a withdrawal of funds from L2 to L1
  /// @param token Address of the withdrawn token
  /// @param recipientAddressL1 Address of the recipient on L1
  /// @param senderAddressL2 Address of the sender on L2
  /// @param amount Withdrawal amount
  function withdrawFunds(
    address token,
    address recipientAddressL1,
    uint256 senderAddressL2,
    uint256 amount
  ) external;

  /// @notice Starts the deposit cancelation process
  /// @dev Deposit cancelation depends on Starknet messaging mechanism and requires two calls.
  /// @dev The first call initiates cancelation of L1-to-L2 message and the second one (after a delay) completes the cancelation.
  /// @param token Address of the deposited token
  /// @param recipientAddressL2 Address of deposit recipient on L2
  /// @param deposit Deposit amount (doesn't include depositFee)
  /// @param depositFee Deposit fee
  /// @param messageRecipientL2 The recipient of deposit message (For deposits without a message zero address is expected)
  /// @param messagePayload Custom message payload (For deposits without a message empty array is expected)
  /// @param nonce Nonce value used for L1-to-L2 deposit message (Can be fetched from Deposit/DepositWithMessage event data)
  function startDepositCancelation(
    address token,
    uint256 recipientAddressL2,
    uint256 deposit,
    uint256 depositFee,
    uint256 messageRecipientL2,
    uint256[] calldata messagePayload,
    uint256 nonce
  ) external;

  /// @notice Finishes the deposit cancelation process
  /// @dev Must be called when a required cancelation delay has passed (Delay value in Starknet contract)
  /// @param deposit Deposit amount (doesn't include depositFee)
  /// @param depositFee Deposit fee
  /// @param messageRecipientL2 The recipient of deposit message (For deposits without a message zero address is expected)
  /// @param messagePayload Custom message payload (For deposits without a message empty array is expected)
  /// @param nonce Nonce value used for L1-to-L2 deposit message (Can be fetched from Deposit/DepositWithMessage event data)
  function finishDepositCancelation(
    address token,
    uint256 recipientAddressL2,
    uint256 deposit,
    uint256 depositFee,
    uint256 messageRecipientL2,
    uint256[] calldata messagePayload,
    uint256 nonce
  ) external;
}
