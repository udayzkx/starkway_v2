// SPDX-License-Identifier: Apache-2.0.
pragma solidity >=0.8.0;

import {IMultiConnectable} from "../../interfaces/multiconnectable/IMultiConnectable.sol";

abstract contract MultiConnectable is IMultiConnectable {

  ///////////////
  // Constants //
  ///////////////

  uint256 immutable internal CONNECTION_DELAY;

  uint256 constant internal STATUS_NOT_CONNECTED = 0;
  uint256 constant internal STATUS_TO_BE_CONNECTED = 1;
  uint256 constant internal STATUS_CONNECTED = 2;
  uint256 constant internal STATUS_DISCONNECTED = 3;

  /////////////
  // Storage //
  /////////////

  /// @dev Stores all ever-connected targets in order, including already disconnected ones
  address[] private allConnectedTargets;

  /// @dev Stores connection statuses by target address
  mapping (address => uint256) private statusByTarget;

  /// @dev Stores associated dates for connection statuses by target address
  /// @dev Stores delay-until date for status STATUS_TO_BE_CONNECTED
  /// @dev Stores connection-finished date for status STATUS_CONNECTED
  /// @dev Stores disconnection date for status STATUS_DISCONNECTED
  mapping (address => uint256) private statusDateByTarget;

  /////////////////
  // Constructor //
  /////////////////

  constructor(uint256 connectionDelay) {
    require(connectionDelay > 0);
    CONNECTION_DELAY = connectionDelay;
  }

  //////////////
  // External //
  //////////////

  /// @notice Provides information for all ever-connected targets, including already disconnected ones
  function getAllConnections()
    external
    view
    returns (ConnectionInfo[] memory)
  {
    uint256 length = allConnectedTargets.length;
    ConnectionInfo[] memory result = new ConnectionInfo[](length);

    for (uint i; i < length;) {
      address target = allConnectedTargets[i];
      uint256 status = statusByTarget[target];
      uint256 statusDate = statusDateByTarget[target];
      result[i] = ConnectionInfo({
        target: target,
        status: status,
        statusDate: statusDate
      });
      unchecked { ++i; }
    }

    return result;
  }

  /// @notice Provides connection status and associated date for target
  function getConnectionState(address target)
    external
    view
    returns (uint256 status, uint256 statusDate)
  {
    status = statusByTarget[target];
    statusDate = statusDateByTarget[target];
  }

  //////////////
  // Internal //
  //////////////

  /// @dev Starts connection process. Can be finalized once CONNECTION_DELAY has passed
  function _startConnectionProcess(address target) internal {
    // 1. Validation
    if (target == address(0)) {
      revert MultiConnectable__ZeroAddress();
    }
    _checkConnectionStatus(target, STATUS_NOT_CONNECTED);
    
    // 2. Update state
    uint256 nowDate = _blockTimestamp();
    uint256 delayUntilDate = nowDate + CONNECTION_DELAY;
    statusByTarget[target] = STATUS_TO_BE_CONNECTED;
    statusDateByTarget[target] = delayUntilDate;

    // 3. Event
    emit ConnectionProcessStarted(target);
  }

  /// @dev Finalized ongoing connection process. Ensures that required CONNECTION_DELAY has passed
  function _finalizeConnectionProcess(address target) internal {
    // 1. Validation
    _checkConnectionStatus(target, STATUS_TO_BE_CONNECTED);
    uint256 delayUntilDate = statusDateByTarget[target];
    uint256 nowDate = _blockTimestamp();
    if (nowDate < delayUntilDate) {
      revert MultiConnectable__TooEarlyToConnect(nowDate, delayUntilDate);
    }

    // 2. Update state
    allConnectedTargets.push(target);
    statusByTarget[target] = STATUS_CONNECTED;
    statusDateByTarget[target] = nowDate;

    // 3. Event
    emit ConnectionProcessFinalized(target);
  }

  /// @dev Cancels ongoing connection process. Resets target's connection state
  function _cancelConnectionProcess(address target) internal {
    // 1. Validation
    _checkConnectionStatus(target, STATUS_TO_BE_CONNECTED);

    // 2. Update state
    statusByTarget[target] = STATUS_NOT_CONNECTED;
    statusDateByTarget[target] = 0;

    // 3. Event
    emit ConnectionProcessCanceled(target);
  }

  /// @dev Disconnects currently connected target. Ensures that at least one connected version remains
  function _disconnect(address target) internal {
    // 1. Validation
    _checkConnectionStatus(target, STATUS_CONNECTED);
    uint256 totalConnectionsCount = allConnectedTargets.length;
    uint256 activeConnectionsCount;
    for (uint256 i; i < totalConnectionsCount;) {
      address targetAtIndex = allConnectedTargets[i];
      uint256 status = statusByTarget[targetAtIndex];
      if (status == STATUS_CONNECTED) {
        unchecked { ++activeConnectionsCount; }
      }
      unchecked { ++i; }
    }
    if (activeConnectionsCount < 2) {
      revert MultiConnectable__MustRemainConnectedVersion();
    }

    // 2. Update state
    uint256 nowDate = _blockTimestamp();
    statusByTarget[target] = STATUS_DISCONNECTED;
    statusDateByTarget[target] = nowDate;

    // 3. Event
    emit TargetDisconnected(target);
  }

  /// @dev Provides current block's timestamp. Separate virtual function is needed for tests
  function _blockTimestamp() internal virtual view returns (uint256 timestamp) {
    timestamp = block.timestamp;
  }

  /////////////
  // Private //
  /////////////

  /// @dev Checks that call arises from connected target. Reverts if not
  function _checkConnectionStatus(address target, uint256 expectedStatus) internal view {
    uint256 status = statusByTarget[target];
    if (status != expectedStatus) {
      revert MultiConnectable__InvalidConnectionStatus(status);
    }
  }
}
