import { expect, assert } from 'chai';
import { BigNumber, BigNumberish, ContractReceipt, Event } from 'ethers';
import { ENV } from './env';

/////////////////////////
// Deposit Cancelation //
/////////////////////////

export function expectDataInEvent<T>(event: Event, key: string): T {
  if (event.args === undefined) {
    assert.fail('Failed to get event data: No args in the event');
  }
  const value = event.args[key];
  if (value === undefined) {
    assert.fail(`Failed to get event data: Nothing found for key ${key}`);
  }
  return value as T;
}

export function expectEventInReceipt(receipt: ContractReceipt | undefined, predicate: (event: Event) => boolean): Event {
  if (receipt === undefined) {
    assert.fail('Failed to get event: empty receipt');
  }
  if (receipt.events === undefined || receipt.events.length == 0) {
    assert.fail('Failed to get event: no events in the receipt');
  }
  const result = receipt.events?.find(e => predicate(e));
  if (result === undefined) {
    assert.fail('Failed to get event: no matching event found');
  }
  return result;
}

export async function expectBalance(address: string, expectedBalance: BigNumberish) {
  const actualBalance = await ENV.testToken.balanceOf(address);
  expect(actualBalance).to.eq(expectedBalance);
}

export async function expectStarknetCalls(expectedCalls: {
  sendMessageToL2?: number;
  consumeMessageFromL2?: number;
  startL1ToL2MessageCancellation?: number;
  cancelL1ToL2Message?: number
}) {
  const mock = ENV.starknetCoreMock;
  // 1. sendMessageToL2
  const expectedSendMessageCount = expectedCalls.sendMessageToL2 || 0;
  expect(
    await mock.invokedSendMessageToL2Count()
  ).to.eq(
    expectedSendMessageCount, 
    `Expected sendMessageToL2 calls count is ${expectedSendMessageCount}`
  );
  // 2. consumeMessageFromL2
  const expectedConsumeMessageCount = expectedCalls.consumeMessageFromL2 || 0;
  expect(
    await mock.invokedConsumeMessageFromL2Count()
  ).to.eq(
    expectedConsumeMessageCount, 
    `Expected consumeMessageFromL2 calls count is ${expectedConsumeMessageCount}`
  );
  // 3. startL1ToL2MessageCancellation
  const expectedStartCancelationCount = expectedCalls.startL1ToL2MessageCancellation || 0;
  expect(
    await mock.invokedStartL1ToL2MessageCancellation()
  ).to.eq(
    expectedStartCancelationCount, 
    `Expected startL1ToL2MessageCancellation calls count is ${expectedStartCancelationCount}`
  );
  // 4. cancelL1ToL2Message
  const expectedCancelCount = expectedCalls.cancelL1ToL2Message || 0;
  expect(
    await mock.invokedCancelL1ToL2MessageCount()
  ).to.eq(
    expectedCancelCount, 
    `Expected cancelL1ToL2Message calls count is ${expectedCancelCount}`
  );
  // 5. Reset counters
  await mock.resetCounters();
}

export async function expectL1ToL2Message(params: {
  from: BigNumberish,
  to: BigNumberish,
  selector: BigNumberish,
}) {
  const msg = await ENV.starknetCoreMock.inspectLastReceivedMessage();
  expect(msg.from).to.eq(params.from);
  expect(msg.to).to.eq(params.to);
  expect(msg.selector).to.eq(params.selector);
}

export async function expectDepositMessage(params: { 
  recipient: BigNumberish, 
  contents: BigNumberish[]
}) {
  await expectL1ToL2MessagePayload(payload => {
    expect(payload[7]).to.be.eq(params.recipient);
    expect(payload[8]).to.be.eq(params.contents.length);
    params.contents.forEach((value, index) => 
      expect(payload[9 + index]).to.eq(value)
    );
  });
}

export async function expectL1ToL2MessagePayload(validatePayload: (payload: BigNumber[]) => void) {
  const msg = await ENV.starknetCoreMock.inspectLastReceivedMessage();
  validatePayload(msg.payload);
}

export function expectPayloadToBeEqual(actualPayload: BigNumber[], expectedPayload: BigNumberish[]) {
  expect(actualPayload.length).to.be.eq(expectedPayload.length)
  actualPayload.forEach((val, index) => 
    expect(val).to.be.eq(expectedPayload[index])
  )
}
