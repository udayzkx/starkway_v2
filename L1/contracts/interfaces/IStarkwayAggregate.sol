// SPDX-License-Identifier: Apache-2.0.
pragma solidity >=0.8.0;

import {IStarkway} from "./starkway/IStarkway.sol";
import {IStarkwayErrors} from "./starkway/IStarkwayErrors.sol";
import {IStarkwayEvents} from "./starkway/IStarkwayEvents.sol";
import {IStarkwayAuthorized} from "./starkway/IStarkwayAuthorized.sol";

/// @title Aggregate interface for Starkway with all functions, custom errors and events
/// @notice Aggregates all Starkway interfaces into a single aggregate interface
interface IStarkwayAggregate is IStarkway, IStarkwayErrors, IStarkwayEvents, IStarkwayAuthorized {}
