// SPDX-License-Identifier: Apache-2.0.
pragma solidity >=0.8.0;

/// @title Interface with all Starkway's events
/// @notice Contains a list of custom events for the Starkway project
interface IStarkwayEvents {

  /// @notice Emitted on successful deposit
  /// @param token Address of the deposited token
  /// @param senderAddressL1 Address of deposit sender on Ethereum Mainnet
  /// @param recipientAddressL2 Address of deposit recipient on Starknet
  /// @param deposit Deposit amount (doesn't include depositFee)
  /// @param depositFee Deposit fee paid in deposited token to Starkway
  /// @param starknetMsgFee L1-to-L2 messaging fee paid in ETH to Starknet
  /// @param msgHash The hash of L1-to-L2 Starknet message
  /// @param nonce Nonce value used for L1-to-L2 Starknet message
  event Deposit(
    address indexed token, 
    address indexed senderAddressL1,
    uint256 indexed recipientAddressL2,
    uint256 deposit,
    uint256 depositFee,
    uint256 starknetMsgFee,
    bytes32 msgHash,
    uint256 nonce
  );

  /// @notice Emitted on successful deposit that has a deposit message attached
  /// @param token Address of the deposited token
  /// @param senderAddressL1 Address of deposit sender on L1
  /// @param recipientAddressL2 Address of deposit recipient on L2
  /// @param deposit Deposit amount (doesn't include depositFee)
  /// @param depositFee Deposit fee paid in deposited token to Starkway
  /// @param starknetMsgFee L1-to-L2 messaging fee paid in ETH to Starknet
  /// @param msgHash The hash of L1-to-L2 Starknet message
  /// @param nonce Nonce value used for L1-to-L2 Starknet message
  /// @param messageRecipientL2 Address of deposit message recipient on Starknet
  /// @param messagePayload Custom payload that will be attached to general deposit info and provided to the message recipient on L2
  event DepositWithMessage(
    address indexed token,
    address indexed senderAddressL1,
    uint256 indexed recipientAddressL2,
    uint256 deposit,
    uint256 depositFee,
    uint256 starknetMsgFee,
    bytes32 msgHash,
    uint256 nonce,
    uint256 messageRecipientL2,
    uint256[] messagePayload
  );

  /// @notice Emitted on successful withdrawal
  /// @param token Address of the withdrawn token
  /// @param recipientAddressL1 Address of withdrawal recipient on Ethereum Mainnet
  /// @param senderAddressL2 Address of withdrawal sender on Starknet
  /// @param amount Withdrawal amount
  event Withdrawal(
    address indexed token, 
    address indexed recipientAddressL1,
    uint256 indexed senderAddressL2,
    uint256 amount
  );

  /// @notice Emitted on initialization of a new token in Starkway
  /// @param token Address of the initialized token
  /// @param msgHash The hash of the initializing L1-to-L2 Starknet message
  event TokenInitialized(
    address indexed token,
    bytes32 msgHash
  );

  /// @notice Emitted when deposit cancelation process starts
  /// @param token Address of the deposited token
  /// @param senderAddressL1 Address of deposit sender on Ethereum Mainnet
  /// @param recipientAddressL2 Address of deposit recipient on Starknet
  /// @param amount Deposit amount (doesn't include deposit fee)
  event DepositCancelationStarted(
    address indexed token,
    address indexed senderAddressL1,
    uint256 indexed recipientAddressL2,
    uint256 amount
  );

  /// @notice Emitted when deposit is successfully canceled
  /// @param token Address of the deposited token
  /// @param senderAddressL1 Address of deposit sender on Ethereum Mainnet
  /// @param recipientAddressL2 Address of deposit recipient on Starknet
  /// @param amount Deposit amount (doesn't include deposit fee)
  event DepositCanceled(
    address indexed token,
    address indexed senderAddressL1,
    uint256 indexed recipientAddressL2,
    uint256 amount
  );

  /// @notice Emitted on token settings update
  /// @param token Address of the token for which settings were updated
  event TokenSettingsUpdate(address indexed token);
}
