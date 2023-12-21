// SPDX-License-Identifier: Apache-2.0.
pragma solidity >=0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ETH_ADDRESS, ETH_NAME, ETH_SYMBOL, ETH_DECIMALS} from "./Constants.sol";

library TokenUtils {

  using SafeERC20 for IERC20;

  uint256 constant private READ_GAS_LIMIT = 20_000;

  error TokenUtils__InvalidDepositEthValue(uint256 value, uint256 expected);
  error TokenUtils__EthTransferFailed(address to, uint256 value);
  error TokenUtils__TransferToZero();

  function readMetadataDecimals(address token) 
    internal 
    view 
    returns (uint8 decimals)
  {
    decimals = (token == ETH_ADDRESS)
      ? ETH_DECIMALS
      : IERC20Metadata(token).decimals{ gas: READ_GAS_LIMIT }();
  }

  function readMetadataName(address token) 
    internal 
    view 
    returns (string memory name)
  {
    name = (token == ETH_ADDRESS)
      ? ETH_NAME
      : IERC20Metadata(token).name{ gas: READ_GAS_LIMIT }();
  }

  function readMetadataSymbol(address token) 
    internal 
    view 
    returns (string memory symbol)
  {
    symbol = (token == ETH_ADDRESS)
      ? ETH_SYMBOL
      : IERC20Metadata(token).symbol{ gas: READ_GAS_LIMIT }();
  }

  function transferFundsFrom(
    address token, 
    address from, 
    uint256 amount
  ) internal {
    if (token == ETH_ADDRESS) {
      if (msg.value < amount) {
        revert TokenUtils__InvalidDepositEthValue({
          value: msg.value,
          expected: amount
        });
      }
      /* ETH received, everything's fine */
    } else {
      /* Transfer ERC20 tokens, prior approval is needed */
        IERC20(token).safeTransferFrom({
          from: from,
          to: address(this),
          value: amount
        });
    }
  }

  function transferFundsTo(address token, address to, uint256 amount) internal {
    if (to == address(0)) {
      revert TokenUtils__TransferToZero();
    }
    if (token == ETH_ADDRESS) {
      (bool isSuccess,) = to.call{value: amount}("");
      if (!isSuccess) {
        revert TokenUtils__EthTransferFailed({
          to: to,
          value: amount
        });
      }
    } else {
      IERC20(token).safeTransfer(to, amount);
    }
  }
}
