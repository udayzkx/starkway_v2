// SPDX-License-Identifier: Apache-2.0.
pragma solidity >=0.8.0;

import {Types} from '../Types.sol';

/// @title Public interface for StarkwayVault contract
/// @notice Contains structs, events and public functions for StarkwayVault
interface IStarkwayVault {
  ////////////
  // Errors //
  ////////////

  /// @notice If the token is expected to be not initialized in vault, but it already is
  error StarkwayVault__TokenAlreadyInitialized();

  /// @notice If the token is expected to be already initialized, but is not yet
  error StarkwayVault__TokenMustBeInitialized();

  /// @notice If token being initialized has `decimals` value higher than max allowed (24)
  /// @param value `decimals` value of the token
  error StarkwayVault__InvalidTokenDecimals(uint256 value);

  ////////////
  // Events //
  ////////////

  /// @notice Emitted only once upon StarkwayVault deployment
  event StarkwayVaultDeployed(
    address indexed starknet,
    uint256 indexed partnerL2,
    uint256 connectionDelay
  );

  /// @notice Emitted when a new token is initialized in the Vault
  /// @param token Address of the token
  event TokenInitialized(address indexed token);

  /// @notice Emitted on funds deposit to the Vault
  /// @param token Address of the deposited token
  /// @param from Address of the depositor
  /// @param starkway Address of Starkway contract performing the deposit
  /// @param amount Deposit amount
  event DepositToVault(
    address indexed token,
    address indexed from,
    address indexed starkway,
    uint256 amount
  );

  /// @notice Emitted on funds withdrawal from the Vault
  /// @param token Address of the withdrawn token
  /// @param to Address of the withdrawal recipient
  /// @param starkway Address of Starkway contract performing the withdrawal
  /// @param amount Withdrawal amount
  event WithdrawalFromVault(
    address indexed token,
    address indexed to,
    address indexed starkway,
    uint256 amount
  );

  //////////
  // View //
  //////////

  /// @notice Check if the token is already initialized in Starkway
  /// @param token Token of interest
  /// @return isInitialized `true` if already initialized, `false` otherwise
  function isTokenInitialized(address token)
    external
    view
    returns (bool isInitialized);

  /// @notice Calculates L1-to-L2 messaging fee required to be paid for token initialization
  /// @dev If token is not initialized yet, a separate L1-to-L2 message must be sent.
  /// @dev If token is already initialized, 0 value is returned and no messaging fee is paid.
  /// @param token Token to be initialized
  /// @return fee Fee for initialization of the token
  function calculateInitializationFee(address token)
    external
    view
    returns (uint256 fee);

  /// @notice Prepares initialization's Starknet message to be sent from L1 to L2
  /// @dev Should be called by Frontend to calculate the estimated Starknet message fee
  /// @dev If token's already initialized, all-zeroed message will be returned
  /// @param token Address of the token to be initialized
  /// @return L1-to-L2 message to be sent for token initialization
  function prepareInitMessage(address token) 
    external 
    view 
    returns (Types.L1ToL2Message memory);

  /// @notice Provides a number of all tokens initialized in Starkway
  /// @dev Can be used as a quick check to validate cached supported tokens state.
  /// @dev The number of supported tokens can only increase. If value returned equals
  /// @dev the number of cached supported tokens, no change has happened.
  /// @return Number of supported tokens
  function numberOfSupportedTokens() external view returns (uint256);

  /// @notice Provides a list of all tokens initialized in Starkway.
  /// @notice Token info includes its address, decimals and initialization timestamp.
  /// @dev ETH's token representation with fake address (0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE) is also included.
  /// @dev Keep in mind that calls fetching ETH's decimals/symbol/name will revert, so these values must be hardcoded.
  /// @return A list of all initialized tokens
  function getSupportedTokens()
    external 
    view
    returns (Types.TokenInfo[] memory);

  ///////////
  // Write //
  ///////////

  function initToken(address token) external payable;
}
