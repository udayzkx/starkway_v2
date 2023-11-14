// SPDX-License-Identifier: Apache-2.0.
pragma solidity >=0.8.0;

import {FeltUtils} from "../helpers/FeltUtils.sol";
import {IStarknetMessaging} from "../../interfaces/starknet/IStarknetMessaging.sol";

abstract contract PairedToL2 {

  ////////////
  // Events //
  ////////////

  event StarknetChanged(
    address indexed newAddress,
    address indexed oldAddress 
  );

  /////////////
  // Storage //
  /////////////

  /// @dev Starknet-Messaging contract used for L1 <-> L2 communication
  IStarknetMessaging internal starknet;

  /// @dev Address of Partner contract on L2
  uint256 immutable internal partnerL2;

  /////////////////
  // Constructor //
  /////////////////

  constructor(
    address starknetAddress,
    uint256 partnerL2Address
  ) {
    _setStarknetAddressTo(starknetAddress);
    
    require(partnerL2Address != 0);
    FeltUtils.validateFelt(partnerL2Address);
    partnerL2 = partnerL2Address;
  }

  //////////
  // View //
  //////////

  function getStarknetAndPartner()
    external
    view
    returns (address starknetAddress, uint256 partnerL2Address)
  {
    starknetAddress = address(starknet);
    partnerL2Address = partnerL2;
  }

  /////////////
  // Updates //
  /////////////

  function _setStarknetAddressTo(address newAddress) internal {
    address oldAddress = address(starknet);
    require(newAddress != address(0));
    require(newAddress != oldAddress);

    starknet = IStarknetMessaging(newAddress);

    emit StarknetChanged({
      newAddress: newAddress,
      oldAddress: oldAddress
    });
  }
}
