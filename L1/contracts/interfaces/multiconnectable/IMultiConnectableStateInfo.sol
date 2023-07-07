// SPDX-License-Identifier: Apache-2.0.
pragma solidity >=0.8.0;

interface IMultiConnectableStateInfo {

  /// @notice Contains information related to a target
  struct ConnectionInfo {
    address target;
    uint256 status;
    uint256 statusDate;
  }

  /// @notice Provides information for all ever-connected targets, including already disconnected ones
  function getAllConnections() external view returns (ConnectionInfo[] memory);

  /// @notice Provides connection status and associated date for target
  function getConnectionState(address target)
    external
    view
    returns (uint256 status, uint256 statusDate);
}
