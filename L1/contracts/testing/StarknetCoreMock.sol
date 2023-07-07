// SPDX-License-Identifier: Apache-2.0.
pragma solidity 0.8.17;

import "../interfaces/starknet/IStarknetMessaging.sol";

contract StarknetCoreMock is IStarknetMessaging {
    ////////////////
    // Data Types //
    ////////////////

    struct Message {
        address from;
        uint256 to;
        uint256 selector;
        uint256[] payload;
    }

    /////////////
    // Storage //
    /////////////

    uint256 public constant MAX_L1_MSG_FEE = 1 ether;
    uint256 public currentNonce = 19012023;
    uint256 public messageCancellationDelay = 5 minutes;

    mapping(bytes32 => uint256) public l2ToL1Messages;
    mapping(bytes32 => uint256) public l1ToL2Messages;
    mapping(bytes32 => uint256) public l1ToL2MessageCancellations;

    /////////////////
    // For Testing //
    /////////////////

    Message private lastReceivedMessage;
    uint256 public invokedSendMessageToL2Count = 0;
    uint256 public invokedConsumeMessageFromL2Count = 0;
    uint256 public invokedStartL1ToL2MessageCancellation = 0;
    uint256 public invokedCancelL1ToL2MessageCount = 0;

    function inspectLastReceivedMessage()
        external 
        view 
        returns (address from, uint256 to, uint256 selector, uint256[] memory payload)
    {
        Message memory message = lastReceivedMessage;
        from = message.from;
        to = message.to;
        selector = message.selector;
        payload = message.payload;
    }

    ////////////////
    // Mock Setup //
    ////////////////

    function setMessageCancellationDelay(uint256 delay) external {
        messageCancellationDelay = delay;
    }

    function resetCounters() external {
        invokedSendMessageToL2Count = 0;
        invokedConsumeMessageFromL2Count = 0;
        invokedStartL1ToL2MessageCancellation = 0;
        invokedCancelL1ToL2MessageCount = 0;
    }

    function addL2ToL1Message(
        uint256 fromAddress,
        address sender,
        uint256[] calldata payload
    ) external returns (bytes32) {
        bytes32 msgHash = getL2ToL1MsgHash(fromAddress, sender, payload);
        l2ToL1Messages[msgHash] += 1;
        return msgHash;
    }

    ///////////////////
    // IStarknetCore //
    ///////////////////

    function getMaxL1MsgFee() external pure returns (uint256) {
        return MAX_L1_MSG_FEE;
    }

    function sendMessageToL2(
        uint256 toAddress,
        uint256 selector,
        uint256[] calldata payload
    ) external payable override returns (bytes32, uint256) {
        invokedSendMessageToL2Count += 1;
        require(msg.value > 0, "L1_MSG_FEE_MUST_BE_GREATER_THAN_0");
        require(msg.value <= MAX_L1_MSG_FEE, "MAX_L1_MSG_FEE_EXCEEDED");
        uint256 nonce = currentNonce++;
        emit LogMessageToL2(msg.sender, toAddress, selector, payload, nonce, msg.value);
        bytes32 msgHash = getL1ToL2MsgHash(toAddress, selector, payload, nonce);
        // Note that the inclusion of the unique nonce in the message hash implies that
        // l1ToL2Messages()[msgHash] was not accessed before.
        l1ToL2Messages[msgHash] = msg.value + 1;
        lastReceivedMessage = Message({
            from: msg.sender,
            to: toAddress,
            selector: selector,
            payload: payload
        });
        return (msgHash, nonce);
    }

    function consumeMessageFromL2(
        uint256 fromAddress,
        uint256[] calldata payload
    ) external override returns (bytes32) {
        invokedConsumeMessageFromL2Count += 1;
        bytes32 msgHash = getL2ToL1MsgHash(fromAddress, msg.sender, payload);
        require(l2ToL1Messages[msgHash] > 0, "INVALID_MESSAGE_TO_CONSUME");
        emit ConsumedMessageToL1(fromAddress, msg.sender, payload);
        l2ToL1Messages[msgHash] -= 1;
        return msgHash;
    }

    function startL1ToL2MessageCancellation(
        uint256 toAddress,
        uint256 selector,
        uint256[] calldata payload,
        uint256 nonce
    ) external override returns (bytes32) {
        invokedStartL1ToL2MessageCancellation += 1;
        emit MessageToL2CancellationStarted(msg.sender, toAddress, selector, payload, nonce);
        bytes32 msgHash = getL1ToL2MsgHash(toAddress, selector, payload, nonce);
        uint256 msgFeePlusOne = l1ToL2Messages[msgHash];
        require(msgFeePlusOne > 0, "NO_MESSAGE_TO_CANCEL");
        l1ToL2MessageCancellations[msgHash] = block.timestamp;
        return msgHash;
    }

    function cancelL1ToL2Message(
        uint256 toAddress,
        uint256 selector,
        uint256[] calldata payload,
        uint256 nonce
    ) external override returns (bytes32) {
        invokedCancelL1ToL2MessageCount += 1;
        emit MessageToL2Canceled(msg.sender, toAddress, selector, payload, nonce);
        bytes32 msgHash = getL1ToL2MsgHash(toAddress, selector, payload, nonce);
        uint256 msgFeePlusOne = l1ToL2Messages[msgHash];
        require(msgFeePlusOne != 0, "NO_MESSAGE_TO_CANCEL");

        uint256 requestTime = l1ToL2MessageCancellations[msgHash];
        require(requestTime != 0, "MESSAGE_CANCELLATION_NOT_REQUESTED");

        uint256 cancelAllowedTime = requestTime + messageCancellationDelay;
        require(cancelAllowedTime >= requestTime, "CANCEL_ALLOWED_TIME_OVERFLOW");
        require(block.timestamp >= cancelAllowedTime, "MESSAGE_CANCELLATION_NOT_ALLOWED_YET");

        l1ToL2Messages[msgHash] = 0;
        return msgHash;
    }

    /////////////
    // Private //
    /////////////

    function getL1ToL2MsgHash(
        uint256 toAddress,
        uint256 selector,
        uint256[] calldata payload,
        uint256 nonce
    ) private view returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    uint256(uint160(msg.sender)),
                    toAddress,
                    nonce,
                    selector,
                    payload.length,
                    payload
                )
            );
    }

    function getL2ToL1MsgHash(
        uint256 fromAddress,
        address toAddress,
        uint256[] calldata payload
    ) private pure returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    fromAddress,
                    uint256(uint160(toAddress)),
                    payload.length,
                    payload
                )
            );
    }
}
