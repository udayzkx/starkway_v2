// SPDX-License-Identifier: Apache-2.0.
pragma solidity >=0.8.0;

import {IMultiConnectableEvents} from "./IMultiConnectableEvents.sol";
import {IMultiConnectableErrors} from "./IMultiConnectableErrors.sol";
import {IMultiConnectableStateInfo} from "./IMultiConnectableStateInfo.sol";

interface IMultiConnectable is IMultiConnectableEvents, 
                               IMultiConnectableErrors,
                               IMultiConnectableStateInfo {}
