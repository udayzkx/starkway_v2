// SPDX-License-Identifier: Apache-2.0.
pragma solidity >=0.8.0;

import {IStarkwayVault} from './IStarkwayVault.sol';

/// @title Interface for authorized management of StarkwayVault
/// @notice Contains StarkwayVault's functions available only for authorized callers
interface IStarkwayVaultAuthorized is IStarkwayVault {

  ///////////////////
  // Starkway-only //
  ///////////////////

  /// @notice Deposits funds to vault on behalf of a connected Starkway contract
  /// @dev Callable only by connected Starkway contract
  /// @param token Address of the deposited token
  /// @param from Address of the depositor
  /// @param amount Amount of the deposit (includes deposit fee)
  function depositFunds(address token, address from, uint256 amount) external payable;

  /// @notice Withdraws funds from vault. Callable only by verified Starkway contracts
  /// @dev Callable only by connected Starkway contract
  /// @param token Address of the withdrawn token
  /// @param to Address of the withdrawal recipient
  /// @param amount Amount of the withdrawal
  function withdrawFunds(address token, address to, uint256 amount) external;

  ////////////////
  // Owner-only //
  ////////////////

  /// @notice Updates address of Starknet messaging contract
  /// @dev Callable only by Owner
  /// @param newAddress Address of new Starknet messaging contract
  function updateStarknetAddressTo(address newAddress) external;

  /// @notice Starts a connection process for a new Starkway contract
  /// @dev Callable only by Owner
  /// @param starkway Address of a new Starkway contract
  function startConnectionProcess(address starkway) external;

  /// @notice Completes a connection process for a new Starkway contract
  /// @dev Callable only by Owner
  /// @param starkway Address of a new Starkway contract
  function finalizeConnectionProcess(address starkway) external;

  /// @notice Cancels an ongoing connection process for a new Starkway contract
  /// @dev Callable only by Owner
  /// @param starkway Address of a new Starkway contract
  function cancelConnectionProcess(address starkway) external;

  /// @notice Disconnects a connected Starkway contract. Reconnection in the future isn't possible
  /// @dev Callable only by Owner
  /// @param starkway Address of Starkway contract to be disconnected
  function disconnectStarkway(address starkway) external;

  /// @notice Fallback to be used by owner in case token's name or symbol are incompatible.
  /// @dev Callable only by Owner.
  /// @dev If some problem arises fetching token's metadata name() or symbol(), it may cause automatic 
  /// @dev initialization of the token to fail. This fallback function makes it possible to initialize
  /// @dev these tokens. `name` and `symbol` are used only for presentation purposes. `decimals` property
  /// @dev affects calculations and thus must be fetched from token contract directly in any case.
  /// @dev If token contract doesn't implement `decimals()` function, it can't be supported by Starkway.
  /// @param token Address of the token to be initialized
  /// @param fallbackName Fallback value for `name` property
  /// @param fallbackSymbol Fallback value for `symbol` property
  function initTokenFallback(
    address token,
    string calldata fallbackName,
    string calldata fallbackSymbol
  ) external payable;
}
