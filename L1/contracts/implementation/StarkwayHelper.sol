// SPDX-License-Identifier: Apache-2.0.
pragma solidity 0.8.17;

// External imports
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

// Internal imports
import "./helpers/Constants.sol";
import {IStarkwayVault} from "../interfaces/vault/IStarkwayVault.sol";
import {IStarkwayHelper} from "../interfaces/IStarkwayHelper.sol";

uint256 constant CALL_GAS_LIMIT = 6_000;

contract StarkwayHelper is IStarkwayHelper {

  /////////////////
  // For Testing //
  /////////////////

  uint256 public responseMultiplier = 1; // to be removed
  bool public skipZeroBalances = true; // to be removed

  function setResponseMultiplier(uint256 multiplier_) external {
    responseMultiplier = multiplier_;
  }

  function setSkipZeroBalances(bool shouldSkip_) external {
    skipZeroBalances = shouldSkip_;
  }

  /////////////////////
  // IStarkwayHelper //
  /////////////////////

  function getSupportedTokensWithBalance(address starkway, address user) 
    external 
    view 
    returns (TokenInfo[] memory) 
  {
    IStarkwayVault.TokenInfo[] memory tokenAddresses = IStarkwayVault(starkway).getSupportedTokens();
    uint256 totalCount = tokenAddresses.length;
    uint256[] memory tokenBalances = new uint256[](totalCount);
    uint256 nonZeroCount;

    for (uint256 i; i != totalCount; ++i) {
      address token = tokenAddresses[i].token;
      (bool isSuccess, uint256 balance) = getUserBalance(token, user);
      if (balance != 0 && isSuccess) {
        ++nonZeroCount;
        tokenBalances[i] = balance;
      }
    }

    bool _skipZeroBalances = skipZeroBalances;
    uint256 _responseMultiplier = responseMultiplier;
    uint256 singleResponseSize = _skipZeroBalances ? nonZeroCount : totalCount;
    uint256 fullResponseSize = singleResponseSize * _responseMultiplier;
    TokenInfo[] memory response = new TokenInfo[](fullResponseSize);
    bool[] memory didFailAtIndex = new bool[](fullResponseSize);
    uint256 currResponseIndex = 0;
    uint256 failCount = 0;

    // This for loop exists ONLY for testing purposes. Must be deleted later
    for (uint256 j; j < _responseMultiplier; ++j) {

      for (uint256 i; i != totalCount; ++i) {
        uint256 balance = tokenBalances[i];
        if (_skipZeroBalances && balance == 0) { 
          continue; 
        }
        address token = tokenAddresses[i].token;
        (
          bool isSuccess, 
          uint8 decimals, 
          string memory symbol, 
          string memory name
        ) = getTokenMetadata(token);
        if (isSuccess) {
          response[currResponseIndex++] = TokenInfo({
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
    }

    if (failCount == 0) {
      return response;
    } else {
      // Filter out failures
      uint256 filteredIndex;
      uint256 length = fullResponseSize - failCount;
      TokenInfo[] memory filteredResponse = new TokenInfo[](length);
      for (uint256 i; i != fullResponseSize; ++i) {
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
