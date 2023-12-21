// SPDX-License-Identifier: Apache-2.0.
pragma solidity 0.8.17;

// External imports
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

// Internal imports
import "./helpers/Constants.sol";
import {Types} from "../interfaces/Types.sol";
import {IStarkwayVault} from "../interfaces/vault/IStarkwayVault.sol";
import {IStarkwayHelper} from "../interfaces/IStarkwayHelper.sol";

uint256 constant CALL_GAS_LIMIT = 6_000;

contract StarkwayHelper is IStarkwayHelper {
  /////////////////////
  // IStarkwayHelper //
  /////////////////////

  function getSupportedTokensWithBalance(address starkway, address user) 
    external 
    view 
    returns (ExtTokenInfo[] memory) 
  {
    Types.TokenInfo[] memory supportedTokens = IStarkwayVault(starkway).getSupportedTokens();
    uint256 totalCount = supportedTokens.length;
    uint256[] memory tokenBalances = new uint256[](totalCount);
    uint256 nonZeroCount;

    for (uint256 i; i != totalCount; ++i) {
      address token = supportedTokens[i].token;
      (bool isSuccess, uint256 balance) = getUserBalance(token, user);
      if (balance != 0 && isSuccess) {
        ++nonZeroCount;
        tokenBalances[i] = balance;
      }
    }

    ExtTokenInfo[] memory response = new ExtTokenInfo[](nonZeroCount);
    bool[] memory didFailAtIndex = new bool[](nonZeroCount);
    uint256 currResponseIndex = 0;
    uint256 failCount = 0;

    for (uint256 i; i != totalCount; ++i) {
      uint256 balance = tokenBalances[i];
      if (balance == 0) { 
        continue; 
      }
      address token = supportedTokens[i].token;
      (
        bool isSuccess, 
        uint8 decimals, 
        string memory symbol, 
        string memory name
      ) = getTokenMetadata(token);
      if (isSuccess) {
        response[currResponseIndex++] = ExtTokenInfo({
          token: token,
          balance: balance,
          decimals: decimals,
          symbol: symbol,
          name: name
        });
      } else {
        didFailAtIndex[currResponseIndex++] = true;
        ++failCount;
      }
    }

    if (failCount == 0) {
      return response;
    } else {
      // Filter out failures
      uint256 filteredIndex;
      uint256 length = nonZeroCount - failCount;
      ExtTokenInfo[] memory filteredResponse = new ExtTokenInfo[](length);
      for (uint256 i; i != nonZeroCount; ++i) {
        if (didFailAtIndex[i]) {
          continue;
        }
        filteredResponse[filteredIndex] = response[i];
        ++filteredIndex;
      }
      return filteredResponse;
    }
  }

  /////////////
  // Private //
  /////////////

  function getUserBalance(address token, address user)
    private
    view
    returns (bool isSuccess, uint256 balance)
  {
    if (token == ETH_ADDRESS) {
      return (true, user.balance);
    }
    try IERC20(token).balanceOf{ gas: CALL_GAS_LIMIT }(user) returns (uint256 res) {
      return (true, res);
    } catch {
      return (false, 0);
    }
  }

  function getTokenMetadata(address token)
    private
    view
    returns (bool isSuccess, uint8 decimals, string memory symbol, string memory name)
  {
    if (token == ETH_ADDRESS) {
      return (true, ETH_DECIMALS, ETH_SYMBOL, ETH_NAME);
    }
    try IERC20Metadata(token).decimals{ gas: CALL_GAS_LIMIT }() returns (uint8 res) {
      decimals = res;
    } catch {
      return (false, 0, '', '');
    }
    try IERC20Metadata(token).name{ gas: CALL_GAS_LIMIT }() returns (string memory res) {
      name = res;
    } catch {
      return (false, 0, '', '');
    }
    try IERC20Metadata(token).symbol{ gas: CALL_GAS_LIMIT }() returns (string memory res) {
      symbol = res;
    } catch {
      return (false, 0, '', '');
    }
    isSuccess = true;
  }
}
