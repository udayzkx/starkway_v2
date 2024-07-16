// SPDX-License-Identifier: Apache-2.0.
pragma solidity 0.8.17;

// External imports
import {Ownable} from "./openzeppelin/Ownable.sol";
import {Ownable2Step} from "./openzeppelin/Ownable2Step.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

// Internal imports
import {IStarknetMessaging} from "../interfaces/starknet/IStarknetMessaging.sol";
import {FeltUtils} from "./helpers/FeltUtils.sol";
import {IStarkway} from "../interfaces/starkway/IStarkway.sol";
import {IStarkwayAuthorized} from "../interfaces/starkway/IStarkwayAuthorized.sol";
import {IStarkwayAggregate} from "../interfaces/IStarkwayAggregate.sol";
import {IStarkwayVaultAuthorized} from "../interfaces/vault/IStarkwayVaultAuthorized.sol";
import {PairedToL2} from "./base_contracts/PairedToL2.sol";
import {Types} from "../interfaces/Types.sol";
import {
  DEPOSIT_HANDLER,
  DEPOSIT_WITH_MESSAGE_HANDLER,
  ETH_ADDRESS,
  FEE_RATE_FRACTION
} from "./helpers/Constants.sol";

contract Starkway is IStarkwayAggregate,
                     Ownable2Step,
                     PairedToL2,
                     ReentrancyGuard {

  using SafeERC20 for IERC20;

  ///////////
  // Types //
  ///////////

  /// @notice Struct for storing deposit-related setting for a token. Occupies 4+ storage slots
  struct DepositSettings {
    /// @notice Min allowed deposit amount
    uint256 minDeposit;
    /// @notice Max allowed deposit amount (0 means unlimited)
    uint256 maxDeposit;
    /// @notice Lower limit for deposit fee
    uint256 minFee;
    /// @notice Upper limit for deposit fee (0 means unlimited)
    uint256 maxFee;
    /// @notice Fee segments used to customize fee calculation based on deposit amount
    Types.FeeSegment[] feeSegments;
  }

  /////////////
  // Storage //
  /////////////

  /// @notice Max possible deposit fee rate (300 means 3%)
  uint256 public constant MAX_FEE_RATE = 300;
  
  /// @notice Default fee rate which is used for tokens with no deposit settings
  uint256 internal defaultFeeRate;

  /// @dev StarkwayVault is responsible for locked funds ownership, transfers and token initialization
  IStarkwayVaultAuthorized immutable internal vault;

  /// @dev Stores token deposit settings by token address
  mapping(address => DepositSettings) internal settingsByToken;

  /// @dev Stores flags indicating if deposits for a token are disabled
  mapping(address => bool) internal isTokenDisabled;

  /// @dev Stores address of the previous Starkway version
  address public previousStarkway;

  /// @dev Helper map for executing failed withdrawals
  mapping(bytes32 => uint256) public consumedL2ToL1Messages;

  /////////////////
  // Constructor //
  /////////////////

  constructor(
    address vaultAddress_,
    address starknetAddress_,
    uint256 starkwayL2Address_,
    uint256 defaultFeeRate_,
    address previousStarkway_
  ) 
    Ownable(msg.sender)
    PairedToL2(starknetAddress_, starkwayL2Address_)
  {
    if (vaultAddress_ == address(0)) {
      revert ZeroAddressError();
    }
    vault = IStarkwayVaultAuthorized(vaultAddress_);

    if (defaultFeeRate_ > MAX_FEE_RATE) {
      revert DefaultFeeRateTooHigh();
    }
    defaultFeeRate = defaultFeeRate_;
    previousStarkway = previousStarkway_;
  }

  //////////
  // Read //
  //////////

  /// @inheritdoc IStarkway
  function getStarkwayState()
    external 
    view 
    returns (
      address _vault,
      address _starknet,
      uint256 _starkwayL2,
      uint256 _defaultFeeRate,
      uint256 _maxFeeRate
    )
  {
    _vault = address(vault);
    _starknet = address(starknet);
    _starkwayL2 = partnerL2;
    _defaultFeeRate = defaultFeeRate;
    _maxFeeRate = MAX_FEE_RATE;
  }

  /// @inheritdoc IStarkway
  function prepareDeposit(
    address token, 
    address senderAddressL1,
    uint256 recipientAddressL2,
    uint256 deposit,
    uint256 messageRecipientL2,
    uint256[] calldata messagePayload
  ) 
    external 
    view 
    returns (uint256 depositFee, Types.L1ToL2Message memory depositMessage)
  {
    // 1. Ensure deposits for the token are enabled and it's been initialized in Vault
    _checkTokenDepositsEnabled(token);
    _checkTokenInitialized(token);

    // 2. Calculate deposit fee
    DepositSettings storage settings = settingsByToken[token];
    depositFee = _calculateDepositFee(settings, deposit);

    // 3. Prepare L1-to-L2 message
    (uint256 selector, uint256[] memory payload) = _prepareSelectorAndPayload({
      token: token, 
      senderAddressL1: senderAddressL1, 
      recipientAddressL2: recipientAddressL2, 
      deposit: deposit, 
      depositFee: depositFee, 
      messageRecipientL2: messageRecipientL2, 
      messagePayload: messagePayload
    });
    depositMessage = Types.L1ToL2Message({
      fromAddress: address(this),
      toAddress: partnerL2,
      selector: selector,
      payload: payload
    });
  }

  /// @inheritdoc IStarkwayAuthorized
  function validateTokenSettings(
    address token,
    uint256 minDeposit,
    uint256 maxDeposit,
    uint256 minFee,
    uint256 maxFee,
    bool useCustomFeeRate,
    Types.FeeSegment[] calldata feeSegments
  ) external view {
    _validateTokenSettings({
      token: token,
      minDeposit: minDeposit,
      maxDeposit: maxDeposit,
      minFee: minFee,
      maxFee: maxFee,
      useCustomFeeRate: useCustomFeeRate,
      feeSegments: feeSegments
    });
  }

  /// @inheritdoc IStarkway
  function getTokenSettings(address token) 
    external
    view
    returns (
      uint256 minDeposit,
      uint256 maxDeposit,
      uint256 minFee,
      uint256 maxFee,
      bool useCustomFeeRate,
      Types.FeeSegment[] memory feeSegments
    )
  {
    DepositSettings memory settings = settingsByToken[token];
    minDeposit = settings.minDeposit;
    maxDeposit = settings.maxDeposit;
    minFee = settings.minFee;
    maxFee = settings.maxFee;
    feeSegments = settings.feeSegments;
    useCustomFeeRate = feeSegments.length > 0;
  }

  ///////////
  // Write //
  ///////////

  /// @inheritdoc IStarkway
  function depositFunds(
    address token,
    uint256 recipientAddressL2,
    uint256 deposit,
    uint256 depositFee,
    uint256 starknetMsgFee
  )
    external
    payable
    returns (bytes32 msgHash, uint256 nonce)
  {
    // 1. Prepare payload for L1-to-L2 message
    uint256[] memory payload = _buildDepositPayload({
      token: token,
      senderAddressL1: msg.sender,
      recipientAddressL2: recipientAddressL2,
      deposit: deposit,
      depositFee: depositFee
    });
    
    // 2. Transfer funds and send message to Starknet
    (msgHash, nonce) = _processDeposit({
      token: token,
      recipientAddressL2: recipientAddressL2,
      deposit: deposit,
      depositFee: depositFee,
      starknetMsgFee: starknetMsgFee,
      selectorL2: DEPOSIT_HANDLER,
      payload: payload
    });

    // 3. Emit event
    emit Deposit({
      token: token,
      senderAddressL1: msg.sender,
      recipientAddressL2: recipientAddressL2,
      deposit: deposit,
      depositFee: depositFee,
      starknetMsgFee: starknetMsgFee,
      msgHash: msgHash,
      nonce: nonce
    });
  }

  /// @inheritdoc IStarkway
  function depositFundsWithMessage(
    address token,
    uint256 recipientAddressL2,
    uint256 deposit,
    uint256 depositFee,
    uint256 starknetMsgFee,
    uint256 messageRecipientL2,
    uint256[] calldata messagePayload
  )
    external
    payable
    returns (bytes32 msgHash, uint256 nonce) 
  {
    // 1. Validate message recipient
    if (messageRecipientL2 == 0) {
      revert ZeroAddressError();
    }
    FeltUtils.validateFelt(messageRecipientL2);

    // 2. Prepare payload for L1-to-L2 message
    uint[] memory payload = _buildDepositWithMessagePayload({
      token: token,
      senderAddressL1: msg.sender,
      recipientAddressL2: recipientAddressL2,
      deposit: deposit,
      depositFee: depositFee,
      messageRecipientL2: messageRecipientL2,
      messagePayload: messagePayload
    });

    // 3. Transfer funds and send message to Starknet
    (msgHash, nonce) = _processDeposit({
      token: token,
      recipientAddressL2: recipientAddressL2,
      deposit: deposit,
      depositFee: depositFee,
      starknetMsgFee: starknetMsgFee,
      selectorL2: DEPOSIT_WITH_MESSAGE_HANDLER,
      payload: payload
    });

    // 4. Emit event
    emit DepositWithMessage({
      token: token,
      senderAddressL1: msg.sender,
      recipientAddressL2: recipientAddressL2,
      deposit: deposit,
      depositFee: depositFee,
      starknetMsgFee: starknetMsgFee,
      msgHash: msgHash,
      nonce: nonce,
      messageRecipientL2: messageRecipientL2,
      messagePayload: messagePayload
    });
  }

  /// @inheritdoc IStarkway
  function withdrawFunds(
    address token,
    address recipientAddressL1,
    uint256 senderAddressL2,
    uint256 amount
  ) external {
    _processWithdrawal({
      token: token,
      recipientAddressL1: recipientAddressL1,
      senderAddressL2: senderAddressL2,
      amount: amount
    });
  }

  /// @inheritdoc IStarkway
  function startDepositCancelation(
    address token,
    uint256 recipientAddressL2,
    uint256 deposit,
    uint256 depositFee,
    uint256 messageRecipientL2,
    uint256[] calldata messagePayload,
    uint256 nonce
  ) external {
    _startDepositCancelation({
      token: token, 
      senderAddressL1: msg.sender,
      recipientAddressL2: recipientAddressL2,
      deposit: deposit,
      depositFee: depositFee,
      messageRecipientL2: messageRecipientL2,
      messagePayload: messagePayload,
      nonce: nonce
    });
  }

  /// @inheritdoc IStarkway
  function finishDepositCancelation(
    address token,
    uint256 recipientAddressL2,
    uint256 deposit,
    uint256 depositFee,
    uint256 messageRecipientL2,
    uint256[] calldata messagePayload,
    uint256 nonce
  ) external {
    _finishDepositCancelation({
      token: token,
      senderAddressL1: msg.sender,
      recipientAddressL2: recipientAddressL2,
      deposit: deposit,
      depositFee: depositFee,
      messageRecipientL2: messageRecipientL2,
      messagePayload: messagePayload,
      nonce: nonce
    });
  }

  ////////////////
  // Owner-only //
  ////////////////

  /// @inheritdoc IStarkwayAuthorized
  function setDefaultDepositFeeRate(uint256 feeRate) external onlyOwner {
    if (feeRate > MAX_FEE_RATE) {
      revert DefaultFeeRateTooHigh();
    }
    defaultFeeRate = feeRate;
  }

  /// @inheritdoc IStarkwayAuthorized
  function disableDepositsForToken(address token) external onlyOwner {
    if (!isTokenDisabled[token]) {
      isTokenDisabled[token] = true;
      emit DepositsForTokenDisabled(token);
    }
  }

  /// @inheritdoc IStarkwayAuthorized
  function enableDepositsForToken(address token) external onlyOwner {
    if (isTokenDisabled[token]) {
      isTokenDisabled[token] = false;
      emit DepositsForTokenEnabled(token);
    }
  }

  /// @inheritdoc IStarkwayAuthorized
  function updateTokenSettings(
    address token,
    uint256 minDeposit,
    uint256 maxDeposit,
    uint256 minFee,
    uint256 maxFee,
    bool useCustomFeeRate,
    Types.FeeSegment[] calldata feeSegments
  ) external onlyOwner {
    // 1. Validate settings
    _validateTokenSettings({
      token: token,
      minDeposit: minDeposit,
      maxDeposit: maxDeposit,
      minFee: minFee,
      maxFee: maxFee,
      useCustomFeeRate: useCustomFeeRate,
      feeSegments: feeSegments
    });

    // 2. Update min/max values
    DepositSettings storage settings = settingsByToken[token];
    settings.minDeposit = minDeposit;
    settings.maxDeposit = maxDeposit;
    settings.minFee = minFee;
    settings.maxFee = maxFee;

    // 3. Update segments
    if (settings.feeSegments.length > 0) {
      delete settings.feeSegments;
    }
    uint256 segmentsLength = feeSegments.length;
    for (uint256 i; i < segmentsLength;) {
      settings.feeSegments.push(feeSegments[i]);
      unchecked { ++i; }
    }

    // 4. Emit update event
    emit TokenSettingsUpdate(token);
  }

  /// @inheritdoc IStarkwayAuthorized
  function clearTokenSettings(address token) external onlyOwner {
    // 1. Ensure token is initialized
    _checkTokenInitialized(token);

    // 2. Clear settings
    DepositSettings storage settings = settingsByToken[token];
    settings.minDeposit = 0;
    settings.maxDeposit = 0;
    settings.minFee = 0;
    settings.maxFee = 0;
    delete settings.feeSegments;

    // 3. Emit update event
    emit TokenSettingsUpdate(token);
  }

  /// @inheritdoc IStarkwayAuthorized
  function processWithdrawalsBatch(WithdrawalInfo[] calldata withdrawals) external onlyOwner {
    uint256 totalWithdrawals = withdrawals.length;
    for (uint256 i; i < totalWithdrawals;) {
      WithdrawalInfo calldata info = withdrawals[i];
      _processWithdrawal({
        token: info.token,
        recipientAddressL1: info.recipientAddressL1,
        senderAddressL2: info.senderAddressL2,
        amount: info.amount
      });
      unchecked { ++i; }
    }
  }

  /// @inheritdoc IStarkwayAuthorized
  function processFailedWithdrawals(
    WithdrawalInfo[] calldata withdrawals,
    address withdrawTo
  ) external onlyOwner {
    uint256 starkwayL2 = partnerL2;
    address oldStarkwayL1 = previousStarkway;
    uint256 totalWithdrawals = withdrawals.length;
    for (uint256 i; i < totalWithdrawals;) {
      WithdrawalInfo calldata info = withdrawals[i];
      _processFailedWithdrawal({
        starkwayL2: starkwayL2,
        oldStarkwayL1: oldStarkwayL1,
        withdrawTo: withdrawTo,
        token: info.token,
        recipientAddressL1: info.recipientAddressL1,
        senderAddressL2: info.senderAddressL2,
        amount: info.amount
      });
      unchecked { ++i; }
    }
  }

  /// @inheritdoc IStarkwayAuthorized
  function startDepositCancelationByOwner(
    address token,
    address senderAddressL1,
    uint256 recipientAddressL2,
    uint256 deposit,
    uint256 depositFee,
    uint256 messageRecipientL2,
    uint256[] calldata messagePayload,
    uint256 nonce
  ) external onlyOwner {
    _startDepositCancelation({
      token: token,
      senderAddressL1: senderAddressL1,
      recipientAddressL2: recipientAddressL2,
      deposit: deposit,
      depositFee: depositFee,
      messageRecipientL2: messageRecipientL2,
      messagePayload: messagePayload,
      nonce: nonce
    });
  }

  /// @inheritdoc IStarkwayAuthorized
  function finishDepositCancelationByOwner(
    address token,
    address senderAddressL1,
    uint256 recipientAddressL2,
    uint256 deposit,
    uint256 depositFee,
    uint256 messageRecipientL2,
    uint256[] calldata messagePayload,
    uint256 nonce
  ) external onlyOwner {
    _finishDepositCancelation({
      token: token,
      senderAddressL1: senderAddressL1,
      recipientAddressL2: recipientAddressL2,
      deposit: deposit,
      depositFee: depositFee,
      messageRecipientL2: messageRecipientL2,
      messagePayload: messagePayload,
      nonce: nonce
    });
  }

  ////////////
  // Guards //
  ////////////

  function _checkTokenInitialized(address token) private view {
    if (!vault.isTokenInitialized(token)) {
      revert TokenNotInitialized();
    }
  }

  function _checkTokenDepositsEnabled(address token) private view {
    if (isTokenDisabled[token]) {
      revert TokenDepositsDisabled();
    }
  }

  function _checkDepositFee(uint256 fee, uint256 deposit, DepositSettings memory settings) private view {
    uint256 expectedFee = _calculateDepositFee(settings, deposit);
    if (fee != expectedFee) {
      revert InvalidDepositFee({
        actual: fee,
        expected: expectedFee
      });
    }
  }

  function _checkEthValue(uint256 msgValue, uint256 expectedValue) private pure {
    if (msgValue != expectedValue) {
      revert InvalidEthValue({
        actual: msgValue,
        expected: expectedValue
      });
    }
  }

  function _checkDepositAmount(
    uint256 deposit, 
    uint256 minDeposit, 
    uint256 maxDeposit
  ) private pure {
    bool isLess = deposit < minDeposit;
    bool isHigher = maxDeposit != 0 && deposit > maxDeposit;
    if (isLess || isHigher) {
      revert InvalidDepositAmount({
        actual: deposit,
        min: minDeposit,
        max: maxDeposit
      });
    }
  }

  /////////////
  // Private //
  /////////////

  function _calculateDepositFee(DepositSettings memory settings, uint256 deposit)
    internal
    view 
    returns (uint256 fee)
  {
    fee = (deposit * _resolveDepositFeeRate(settings, deposit))/ FEE_RATE_FRACTION ;
    if (fee < settings.minFee) {
      fee = settings.minFee;
    } else if (settings.maxFee != 0 && fee > settings.maxFee) {
      fee = settings.maxFee;
    }
  }

  function _resolveDepositFeeRate(DepositSettings memory settings, uint256 amount) 
    private 
    view 
    returns (uint256) 
  { 
    uint256 length = settings.feeSegments.length;
    if (length == 0) {
      return defaultFeeRate;
    }
    for (uint256 i; i < length;) {
      Types.FeeSegment memory seg = settings.feeSegments[i];
      uint256 toAmount = seg.toAmount;
      if (amount <= toAmount || toAmount == 0) {
        return seg.feeRate;
      }
      unchecked { ++i; }
    }
    revert NoMatchingFeeSegment();
  }

  function _validateTokenSettings(
    address token,
    uint256 minDeposit,
    uint256 maxDeposit,
    uint256 minFee,
    uint256 maxFee,
    bool useCustomFeeRate,
    Types.FeeSegment[] calldata feeSegments
   ) private view {
    // 1. Validate token is initialized
    _checkTokenInitialized(token);

    // 2. Validate min/max amounts
    if (maxDeposit != 0 && minDeposit > maxDeposit) revert InvalidMaxDeposit();
    if (maxFee != 0 && minFee > maxFee) revert InvalidMaxFee();
    if (minFee > minDeposit) revert InvalidMinFee();

    // 3. Validate segments
    if (useCustomFeeRate) {
      if (feeSegments.length == 0) revert SegmentsMustExist();

      uint256 prevToAmount = minDeposit;
      uint256 prevFeeRate = MAX_FEE_RATE;
      bool isMaxReached = false;
      uint256 segmentsLength = feeSegments.length; 
      for (uint256 i; i < segmentsLength;) {
        Types.FeeSegment calldata seg = feeSegments[i];
        if (isMaxReached) revert InvalidFeeSegments();
        if (seg.toAmount == 0) {
          isMaxReached = true;
        } else if (seg.toAmount < prevToAmount) {
          revert InvalidFeeSegments();
        }

        if (seg.feeRate > prevFeeRate) revert SegmentRateTooHigh();

        prevFeeRate = seg.feeRate;
        prevToAmount = seg.toAmount;

        unchecked { ++i; }
      }

      if (prevToAmount != 0) {
        bool isTopRangeFullyCovered = maxDeposit != 0 && maxDeposit <= prevToAmount;
        if (!isTopRangeFullyCovered) revert InvalidMaxDeposit();
      }
    } else {
      if (feeSegments.length != 0) revert SegmentsMustBeEmpty();
    }
  }

  function _processDeposit(
    address token,
    uint256 recipientAddressL2,
    uint256 deposit,
    uint256 depositFee,
    uint256 starknetMsgFee,
    uint256 selectorL2,
    uint256[] memory payload
  )
    private
    returns (bytes32 msgHash, uint256 nonce) 
  {
    // 1. Validate amount and recipient
    if (deposit == 0) revert ZeroAmountError();
    if (recipientAddressL2 == 0) revert ZeroAddressError();
    FeltUtils.validateFelt(recipientAddressL2);
    
    // 2. Validate deposit parameters
    (uint256 totalDeposit, uint256 vaultValue) = _validateAndPrepareDepositParams({
      token: token,
      deposit: deposit,
      depositFee: depositFee
    });
    _checkEthValue(msg.value, vaultValue + starknetMsgFee);

    // 3. Deposit funds to Vault
    vault.depositFunds{value: vaultValue}({
      token: token,
      from: msg.sender,
      amount: totalDeposit
    });

    // 4. Send Starknet message to L2
    (msgHash, nonce) = starknet.sendMessageToL2{value: starknetMsgFee}({
        toAddress: partnerL2,
        selector: selectorL2,
        payload: payload
    });
  }

  function _processWithdrawal(
    address token,
    address recipientAddressL1,
    uint256 senderAddressL2,
    uint256 amount
  )
    private
  {
    // 1. Consume Starknet message from L2
    uint256[] memory payload = _buildWithdrawalPayload({
      token: token,
      recipientAddressL1: recipientAddressL1,
      senderAddressL2: senderAddressL2,
      amount: amount
    });
    starknet.consumeMessageFromL2({
      fromAddress: partnerL2,
      payload: payload
    });

    // 2. Transfer tokens to user
    vault.withdrawFunds({
      token: token,
      to: recipientAddressL1,
      amount: amount
    });

    // 3. Emit event
    emit Withdrawal({
      token: token,
      recipientAddressL1: recipientAddressL1,
      senderAddressL2: senderAddressL2,
      amount: amount
    });
  }

  function _processFailedWithdrawal(
    uint256 starkwayL2,
    address oldStarkwayL1,
    address withdrawTo,
    address token,
    address recipientAddressL1,
    uint256 senderAddressL2,
    uint256 amount
  )
    private
  {
    // 1. Build L2-to-L1 message payload
    uint256[] memory payload = _buildWithdrawalPayload({
      token: token,
      recipientAddressL1: recipientAddressL1,
      senderAddressL2: senderAddressL2,
      amount: amount
    });

    // 2. Check message can be consumed
    bytes32 msgHash = _getL2ToL1MsgHash(
      starkwayL2,
      oldStarkwayL1,
      payload
    );
    uint256 availableMessages = starknet.l2ToL1Messages(msgHash);
    uint256 consumedMessages = consumedL2ToL1Messages[msgHash];
    if (availableMessages == 0) {
      revert ("No message to be consumed");
    }
    if (availableMessages <= consumedMessages) {
      revert ("Message already consumed");
    }
    consumedL2ToL1Messages[msgHash] = consumedMessages + 1;

    // 3. Transfer tokens to user
    vault.withdrawFunds({
      token: token,
      to: withdrawTo,
      amount: amount
    });

    // 4. Emit event
    emit FailedWithdrawalProcessed({
      token: token,
      recipientAddressL1: recipientAddressL1,
      senderAddressL2: senderAddressL2,
      msgHash: msgHash,
      amount: amount
    });
  }

  function _validateAndPrepareDepositParams(
    address token, 
    uint256 deposit,
    uint256 depositFee
  ) 
    private 
    view 
    returns (uint256 depositWithFee, uint256 vaultCallValue)
  {
    DepositSettings storage settings = settingsByToken[token];
    _checkTokenDepositsEnabled(token);
    _checkDepositAmount(deposit, settings.minDeposit, settings.maxDeposit);
    _checkDepositFee(depositFee, deposit, settings);
    depositWithFee = deposit + depositFee;
    vaultCallValue = token == ETH_ADDRESS ? depositWithFee : 0;
  }

  function _startDepositCancelation(
    address token,
    address senderAddressL1,
    uint256 recipientAddressL2,
    uint256 deposit,
    uint256 depositFee,
    uint256 messageRecipientL2,
    uint256[] calldata messagePayload,
    uint256 nonce
  ) private {
    // 1. Start message cancelation
    (uint256 selector, uint256[] memory payload) = _prepareSelectorAndPayload({
      token: token, 
      senderAddressL1: senderAddressL1, 
      recipientAddressL2: recipientAddressL2, 
      deposit: deposit, 
      depositFee: depositFee, 
      messageRecipientL2: messageRecipientL2, 
      messagePayload: messagePayload
    });
    starknet.startL1ToL2MessageCancellation({
      toAddress: partnerL2,
      selector: selector,
      payload: payload,
      nonce: nonce
    });

    // 2. Emit event
    emit DepositCancelationStarted({
      token: token,
      senderAddressL1: senderAddressL1,
      recipientAddressL2: recipientAddressL2,
      amount: deposit + depositFee
    });
  }

  function _finishDepositCancelation(
    address token, 
    address senderAddressL1, 
    uint256 recipientAddressL2,
    uint256 deposit, 
    uint256 depositFee,
    uint256 messageRecipientL2,
    uint256[] calldata messagePayload,
    uint256 nonce
  ) private {
    // 1. Finish message cancelation
    (uint256 selector, uint256[] memory payload) = _prepareSelectorAndPayload({
      token: token, 
      senderAddressL1: senderAddressL1, 
      recipientAddressL2: recipientAddressL2, 
      deposit: deposit, 
      depositFee: depositFee, 
      messageRecipientL2: messageRecipientL2, 
      messagePayload: messagePayload
    });
    starknet.cancelL1ToL2Message({
      toAddress: partnerL2,
      selector: selector,
      payload: payload,
      nonce: nonce
    });

    // 2. Transfer funds back to user
    uint256 amount = deposit + depositFee;
    vault.withdrawFunds({
      token: token,
      to: senderAddressL1,
      amount: amount
    });
    
    // 3. Emit event
    emit DepositCanceled({
      token: token,
      senderAddressL1: senderAddressL1,
      recipientAddressL2: recipientAddressL2,
      amount: amount
    });
  }

  function _prepareSelectorAndPayload(
    address token, 
    address senderAddressL1, 
    uint256 recipientAddressL2,
    uint256 deposit, 
    uint256 depositFee,
    uint256 messageRecipientL2,
    uint256[] calldata messagePayload
  )
    private
    pure
    returns (uint256 selector, uint256[] memory payload)
  {
    if (messageRecipientL2 == 0) {
      require(messagePayload.length == 0);
      selector = DEPOSIT_HANDLER;
      payload = _buildDepositPayload({
        token: token, 
        senderAddressL1: senderAddressL1, 
        recipientAddressL2: recipientAddressL2, 
        deposit: deposit, 
        depositFee: depositFee
      });
    } else {
      selector = DEPOSIT_WITH_MESSAGE_HANDLER;
      payload = _buildDepositWithMessagePayload({
        token: token, 
        senderAddressL1: senderAddressL1, 
        recipientAddressL2: recipientAddressL2, 
        deposit: deposit, 
        depositFee: depositFee,
        messageRecipientL2: messageRecipientL2,
        messagePayload: messagePayload
      }); 
    }
  }

  function _buildDepositPayload(
    address token,
    address senderAddressL1,
    uint256 recipientAddressL2,
    uint256 deposit,
    uint256 depositFee
  ) 
    private 
    pure 
    returns (uint256[] memory) 
  {
    uint256[] memory payload = new uint[](7);
    (uint256 depositLow, uint256 depositHigh) = FeltUtils.splitIntoLowHigh(deposit);
    (uint256 feeLow, uint256 feeHigh) = FeltUtils.splitIntoLowHigh(depositFee);
    payload[0] = uint256(uint160(token));
    payload[1] = uint256(uint160(senderAddressL1));
    payload[2] = recipientAddressL2;
    payload[3] = depositLow;
    payload[4] = depositHigh;
    payload[5] = feeLow;
    payload[6] = feeHigh;
    return payload;
  }

  function _buildWithdrawalPayload(
    address token,
    uint256 senderAddressL2,
    address recipientAddressL1,
    uint256 amount
  ) 
    private 
    pure 
    returns (uint256[] memory) 
  {
    (uint256 amountLow, uint256 amountHigh) = FeltUtils.splitIntoLowHigh(amount);
    uint256[] memory payload = new uint256[](5);
    payload[0] = uint256(uint160(token));
    payload[1] = uint256(uint160(recipientAddressL1));
    payload[2] = senderAddressL2;
    payload[3] = amountLow;
    payload[4] = amountHigh;
    return payload;
  }

  function _buildDepositWithMessagePayload(
    address token,
    address senderAddressL1,
    uint256 recipientAddressL2,
    uint256 deposit,
    uint256 depositFee,
    uint256 messageRecipientL2,
    uint256[] calldata messagePayload
  ) 
    private 
    pure 
    returns (uint256[] memory) 
  {
    uint256 msgLength = messagePayload.length;
    uint256[] memory payload = new uint[](9 + msgLength);
    (uint256 depositLow, uint256 depositHigh) = FeltUtils.splitIntoLowHigh(deposit);
    (uint256 feeLow, uint256 feeHigh) = FeltUtils.splitIntoLowHigh(depositFee);
    payload[0] = uint256(uint160(token));
    payload[1] = uint256(uint160(senderAddressL1));
    payload[2] = recipientAddressL2;
    payload[3] = depositLow;
    payload[4] = depositHigh;
    payload[5] = feeLow;
    payload[6] = feeHigh;

    // Append message
    payload[7] = messageRecipientL2;
    payload[8] = msgLength;
    for (uint256 i; i < msgLength; ) {
      uint256 msgElement = messagePayload[i];
      FeltUtils.validateFelt(msgElement);
      payload[9 + i] = msgElement;
      unchecked { ++i; }
    }

    return payload;
  }

  function _getL2ToL1MsgHash(
    uint256 fromAddress,
    address toAddress,
    uint256[] memory payload
  ) private pure returns (bytes32) {
    return keccak256(
      abi.encodePacked(
        fromAddress,
        uint256(uint160(toAddress)),
        payload.length,
        payload
      )
    );
  }
}
