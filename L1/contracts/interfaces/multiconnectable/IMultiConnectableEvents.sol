// SPDX-License-Identifier: Apache-2.0.
pragma solidity >=0.8.0;

interface IMultiConnectableEvents {

  /// @notice Emitted when new connection process is started
  event ConnectionProcessStarted(address target);

  /// @notice Emitted when connection proccess is finalized
  event ConnectionProcessFinalized(address target);

  /// @notice Emitted when connection process is canceled
  event ConnectionProcessCanceled(address target);

  /// @notice Emitted when connected target is disconnected
  event TargetDisconnected(address target);
}
