// SPDX-License-Identifier: Apache-2.0.
pragma solidity >=0.8.0;

/// @title Helper for Frontend integration
/// @notice Contract with helper functions to simplify an integration on Frontend
/// @dev Should be never called on-chain, because it performs gas-intensive operations.
/// @dev Provides facade functions to make complex fetch operations easier and faster.
interface IStarkwayHelper {

  /// @notice Struct representing token information: address, user's balance and token metadata
  /// @param token Address of the token
  /// @param balance Token balance of the user
  /// @param decimals Token's decimal value
  /// @param symbol Token's symbol
  /// @param name Token's name
  struct ExtTokenInfo {
    address token;
    uint256 balance;
    uint8 decimals;
    string symbol;
    string name;
  }

  /// @notice Provides a list of tokens already initialized in Starkway.
  /// @notice Contains only tokens for which user's balance is non-zero.
  /// @notice Provides token's address, metadata and user's balance for each token.
  /// @dev ETH's token representation with fake address (0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE) is also included.
  /// @dev Keep in mind that calls fetching ETH's decimals/symbol/name will revert, so these values must be hardcoded.
  /// @param starkway The address of the Starkway contract
  /// @param user The address of the user for whom the token balances are queried
  /// @return tokens Array of TokenInfo objects with information about each supported token and the user's balance
  function getSupportedTokensWithBalance(address starkway, address user) 
    external 
    view 
    returns (ExtTokenInfo[] memory tokens);
}
