// SPDX-License-Identifier: Apache-2.0.
pragma solidity >=0.8.0;

interface IMultiConnectableErrors {

  /// @dev Thrown when target's status doesn't match expected status
  error MultiConnectable__InvalidConnectionStatus(uint256 status);

  /// @dev Thrown when attempting to connect new version, but delay period hasn't passed yet
  error MultiConnectable__TooEarlyToConnect(uint256 nowDate, uint256 delayUntilDate);

  /// @dev Thrown when attempting to disconnect last connected version. At least one must remain connected at any time
  error MultiConnectable__MustRemainConnectedVersion();

  /// @dev Thrown when zero address provided for target
  error MultiConnectable__ZeroAddress();
}
