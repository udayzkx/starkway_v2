// SPDX-License-Identifier: Apache-2.0.
pragma solidity 0.8.17;

import {Ownable} from "./openzeppelin/Ownable.sol";
import {Ownable2Step} from "./openzeppelin/Ownable2Step.sol";
import {IStarkwayVault} from "../interfaces/vault/IStarkwayVault.sol";
import {IStarkwayVaultAuthorized} from "../interfaces/vault/IStarkwayVaultAuthorized.sol";
import {PairedToL2} from "./base_contracts/PairedToL2.sol";
import {ETH_ADDRESS, INIT_HANDLER} from "./helpers/Constants.sol";
import {FeltUtils} from "./helpers/FeltUtils.sol";
import {TokenUtils} from "./helpers/TokenUtils.sol";
import {Types} from "../interfaces/Types.sol";
import {MultiConnectable} from "./base_contracts/MultiConnectable.sol";

contract StarkwayVault is IStarkwayVault,
                          IStarkwayVaultAuthorized,
                          Ownable2Step,
                          PairedToL2,
                          MultiConnectable
{
  ///////////////
  // Constants //
  ///////////////

  /// @dev Used to mark tokens as initialized in mapping
  uint256 constant private TOKEN_IS_INITIALIZED = 1;

  /// @dev Used to prevent reentrancy. Stands for released (unlocked) state
  /// @dev Non-zero value to prevent expensive SSTORE operations for zero value
  uint256 constant private IS_RELEASED = 1;

  /// @dev Used to prevent reentrancy. Stands for locked state
  uint256 constant private IS_LOCKED = 2;

  /////////////
  // Storage //
  /////////////

  /// @dev Used to prevent reentrancy
  uint256 private lock = IS_RELEASED;

  /// @dev Stores list of all already initialized tokens
  Types.TokenInfo[] private initializedTokens;

  /// @dev Stores token initialization statuses
  mapping (address => uint256) private initStatusByToken;

  /////////////////
  // Constructor //
  /////////////////

  constructor(
    address starknet,
    uint256 partnerL2,
    uint256 connectionDelay
  ) 
    Ownable(msg.sender)
    PairedToL2(starknet, partnerL2)
    MultiConnectable(connectionDelay)
  {
    emit StarkwayVaultDeployed({
      starknet: starknet,
      partnerL2: partnerL2,
      connectionDelay: connectionDelay
    });
  }

  //////////
  // Read //
  //////////

  /// @inheritdoc IStarkwayVault
  function isTokenInitialized(address token)
    external
    view
    returns (bool isInitialized)
  {
    isInitialized = initStatusByToken[token] == TOKEN_IS_INITIALIZED;
  }

  /// @inheritdoc IStarkwayVault
  function prepareInitMessage(address token) 
    external 
    view 
    returns (Types.L1ToL2Message memory)
  {
    if (initStatusByToken[token] != TOKEN_IS_INITIALIZED) {
      (string memory name, string memory symbol, uint8 decimals) = _getMetadata(token);
      uint256[] memory payload = _prepareInitMessagePayload({
        token: token,
        name: name,
        symbol: symbol,
        decimals: decimals
      });
      return Types.L1ToL2Message({
        fromAddress: address(this),
        toAddress: partnerL2,
        selector: INIT_HANDLER,
        payload: payload
      });
    } else {
      return Types.L1ToL2Message({
        fromAddress: address(0),
        toAddress: 0,
        selector: 0,
        payload: new uint256[](0)
      });
    }
  }

  /// @inheritdoc IStarkwayVault
  function numberOfSupportedTokens() external view returns (uint256) {
    return initializedTokens.length;
  }

  /// @inheritdoc IStarkwayVault
  function getSupportedTokens()
    external 
    view
    returns (Types.TokenInfo[] memory) 
  {
    return initializedTokens;
  }

  //////////////
  // External //
  //////////////

  /// @inheritdoc IStarkwayVault
  function initToken(address token) external payable {
    if (initStatusByToken[token] == TOKEN_IS_INITIALIZED) {
      revert StarkwayVault__TokenAlreadyInitialized();
    }
    (string memory name, string memory symbol, uint8 decimals) = _getMetadata(token);
    _performInitialization({
      token: token,
      name: name,
      symbol: symbol,
      decimals: decimals,
      initFee: msg.value
    });
  }

  ///////////////////
  // Starkway-only //
  ///////////////////

  /// @inheritdoc IStarkwayVaultAuthorized
  function depositFunds(address token, address from, uint256 amount) 
    external
    payable
    onlyStarkway
  {
    // 1. Check token is initialized
    if (initStatusByToken[token] != TOKEN_IS_INITIALIZED) {
      revert StarkwayVault__TokenMustBeInitialized();
    }
    
    // 2. Transfer funds
    TokenUtils.transferFundsFrom({
      token: token,
      from: from,
      amount: amount
    });

    // 3. Emit event
    emit DepositToVault({
      token: token,
      from: from,
      starkway: msg.sender,
      amount: amount
    });
  }

  /// @inheritdoc IStarkwayVaultAuthorized
  function withdrawFunds(address token, address to, uint256 amount) 
    external
    onlyStarkway 
  {
    // 1. Check token is initialized
    if (initStatusByToken[token] != TOKEN_IS_INITIALIZED) {
      revert StarkwayVault__TokenMustBeInitialized();
    }

    // 2. Transfer funds
    TokenUtils.transferFundsTo({
      token: token,
      to: to,
      amount: amount
    });

    // 3. Emit event  
    emit WithdrawalFromVault({
      token: token,
      to: to,
      starkway: msg.sender,
      amount: amount
    });
  }

  ////////////////
  // Owner-only //
  ////////////////

  /// @inheritdoc IStarkwayVaultAuthorized
  function updateStarknetAddressTo(address newAddress) external onlyOwner {
    _setStarknetAddressTo(newAddress);
  }

  /// @inheritdoc IStarkwayVaultAuthorized
  function startConnectionProcess(address starkway) external onlyOwner {
    _startConnectionProcess(starkway);
  }

  /// @inheritdoc IStarkwayVaultAuthorized
  function finalizeConnectionProcess(address starkway) external onlyOwner {
    _finalizeConnectionProcess(starkway);
  }

  /// @inheritdoc IStarkwayVaultAuthorized
  function cancelConnectionProcess(address starkway) external onlyOwner {
    _cancelConnectionProcess(starkway);
  }

  /// @inheritdoc IStarkwayVaultAuthorized
  function disconnectStarkway(address starkway) external onlyOwner {
    _disconnect(starkway);
  }

  /// @inheritdoc IStarkwayVaultAuthorized
  function initTokenFallback(
    address token,
    string calldata fallbackName,
    string calldata fallbackSymbol
  )
    external
    payable
    onlyOwner
  {
    // 1. Check not initialized yet
    if (initStatusByToken[token] == TOKEN_IS_INITIALIZED) {
      revert StarkwayVault__TokenAlreadyInitialized();
    }

    // 2. Try standard flow and retry with fallback name and symbol if error happens
    try IStarkwayVault(address(this)).initToken{ value: msg.value }(token) {
      // Token initialized successfully
      require(initStatusByToken[token] == TOKEN_IS_INITIALIZED);
    } catch {
      // Retrying with fallback name and symbol
      // `Name` and `symbol` are used only for presentation purposes
      // In contrast, decimals affect calculations and MUST be fetched from token contract 
      uint8 decimals = TokenUtils.readMetadataDecimals(token);
      _performInitialization({
        token: token,
        name: fallbackName,
        symbol: fallbackSymbol,
        decimals: decimals,
        initFee: msg.value
      });
    }
  }

  /////////////
  // Private //
  /////////////

  /// @dev Modifier to allow access only for connected Starkway versions
  modifier onlyStarkway() {
    _checkConnectionStatus(msg.sender, STATUS_CONNECTED);
    _;
  }

  /// @dev Performs external view calls to fetch metadata
  function _getMetadata(address token) 
    private 
    view 
    returns (string memory name, string memory symbol, uint8 decimals)
  {
    decimals = TokenUtils.readMetadataDecimals(token);
    name = TokenUtils.readMetadataName(token);
    symbol = TokenUtils.readMetadataSymbol(token);
  }

  /// @dev The core function for token initialization, encapsulates related storage updates
  function _performInitialization(
    address token,
    string memory name,
    string memory symbol,
    uint8 decimals,
    uint256 initFee
  ) private {
    // 1. Validate state and lock
    require(lock == IS_RELEASED);
    require(initStatusByToken[token] != TOKEN_IS_INITIALIZED);
    lock = IS_LOCKED;

    // 2. Get and validate current date
    uint256 dateNow = _blockTimestamp();
    require(dateNow != 0);
    require(dateNow < type(uint88).max);

    // 3. Validate decimals
    if (decimals < 1 || decimals > 18) {
      revert StarkwayVault__InvalidTokenDecimals(decimals);
    }

    // 4. Perform state update
    initStatusByToken[token] = TOKEN_IS_INITIALIZED;
    initializedTokens.push(
      Types.TokenInfo({
        token: token,
        decimals: decimals,
        initDate: uint88(dateNow)
      })
    );

    // 5. Send message to L2
    uint256[] memory payload = _prepareInitMessagePayload({
      token: token,
      name: name, 
      symbol: symbol,
      decimals: decimals
    });
    starknet.sendMessageToL2{value: initFee}({
      toAddress: partnerL2, 
      selector: INIT_HANDLER,
      payload: payload
    });

    // 6. Unlock
    lock = IS_RELEASED;

    // 7. Event
    emit TokenInitialized(token);
  }

  function _prepareInitMessagePayload(
    address token,
    string memory name,
    string memory symbol,
    uint8 decimals
  ) 
    private 
    pure 
    returns (uint256[] memory) 
  {
    uint256[] memory payload = new uint256[](4);
    payload[0] = uint256(uint160(token));
    payload[1] = FeltUtils.stringToFelt(name);
    payload[2] = FeltUtils.stringToFelt(symbol);
    payload[3] = uint256(decimals);
    return payload;
  }
}
