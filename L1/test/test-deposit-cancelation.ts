import { ethers } from 'hardhat';
import { expect } from 'chai';
import { Starkway } from "../typechain-types";
import { BigNumber, BigNumberish } from 'ethers';
import * as Const from './helpers/constants';
import { 
  prepareUsers, 
  deployStarknetCoreMock, 
  tokenAmount,
  deployStarkwayAndVault,
  deployTestToken, 
  prepareDeposit,
  fastForwardEVM,
  ZERO_DEPOSIT_MESSAGE,
  calculateInitFee
} from './helpers/utils';
import { 
  expectEventInReceipt, 
  expectDataInEvent, 
  expectStarknetCalls, 
  expectBalance 
} from './helpers/expectations';
import { ENV } from './helpers/env';

/////////////////////////
// Deposit Cancelation //
/////////////////////////

describe("Deposit cancelation", function () {
  const depositAmount = tokenAmount(1_000);
  let aliceAddress: string;
  let aliceStarkway: Starkway;
  let vaultAddress: string;
  let tokenAddress: string;

  beforeEach(async function () {
    await prepareUsers();
    await deployStarknetCoreMock();
    await deployStarkwayAndVault();
    await deployTestToken();
    
    aliceAddress = await ENV.alice.getAddress();
    aliceStarkway = ENV.starkwayContract.connect(ENV.alice);
    vaultAddress = ENV.vault.address;
    tokenAddress = ENV.testToken.address;
    const initFee = await calculateInitFee(tokenAddress);
    await ENV.vault.initToken(tokenAddress, { value: initFee });
    const deposit = await prepareDeposit({
      token: tokenAddress, 
      amount: depositAmount,
      senderL1: aliceAddress,
      recipientL2: Const.ALICE_L2_ADDRESS
    });
    await ENV.testToken.mint(aliceAddress, deposit.totalAmount);
    await ENV.testToken.connect(ENV.alice).approve(vaultAddress, deposit.totalAmount);
    await ENV.starknetCoreMock.resetCounters();
  });

  it("Cancel ERC20 deposit by User", async function () {
    // Make deposit
    const deposit = await prepareDeposit({
      token: tokenAddress, 
      amount: depositAmount,
      senderL1: aliceAddress,
      recipientL2: Const.ALICE_L2_ADDRESS
    });
    const depositTx = await aliceStarkway.depositFunds(
      tokenAddress,
      Const.ALICE_L2_ADDRESS,
      deposit.depositAmount,
      deposit.feeAmount,
      deposit.starknetFee,
      { value: deposit.msgValue }
    );
    
    // Extract nonce from Deposit event
    const receipt = await depositTx.wait();
    const depositEvent = expectEventInReceipt(
      receipt, 
      (e) => e.address === aliceStarkway.address && e.event === 'Deposit'
    );
    const nonce = expectDataInEvent<BigNumber>(depositEvent, 'nonce');

    // Check mock and balances after deposit
    await expectBalance(aliceAddress, 0);
    await expectBalance(vaultAddress, deposit.totalAmount);
    await expectStarknetCalls({
      sendMessageToL2: 1
    });

    // 2. Start deposit cancelation
    await aliceStarkway.startDepositCancelation(
      tokenAddress,
      Const.ALICE_L2_ADDRESS,
      deposit.depositAmount,
      deposit.feeAmount,
      Const.ZERO_ADDRESS,
      [],
      nonce
    )

    // Check mock and balances after cancelation start
    await expectBalance(aliceAddress, 0);
    await expectBalance(vaultAddress, deposit.totalAmount);
    await expectStarknetCalls({
      startL1ToL2MessageCancellation: 1
    });

    // 3. Finish cancelation
    await fastForwardEVM(600);
    await aliceStarkway.finishDepositCancelation(
      tokenAddress,
      Const.ALICE_L2_ADDRESS,
      deposit.depositAmount,
      deposit.feeAmount,
      Const.ZERO_ADDRESS,
      [],
      nonce
    )

    // Check mock and balances after cancelation finish
    await expectBalance(aliceAddress, deposit.totalAmount);
    await expectBalance(vaultAddress, 0);
    await expectStarknetCalls({
      cancelL1ToL2Message: 1
    });
  });

  it("Cancel ERC20 deposit by Admin", async function () {
    // Make deposit
    const deposit = await prepareDeposit({
      token: tokenAddress, 
      amount: depositAmount,
      senderL1: aliceAddress,
      recipientL2: Const.ALICE_L2_ADDRESS
    });
    const depositTx = await aliceStarkway.depositFunds(
      tokenAddress,
      Const.ALICE_L2_ADDRESS,
      deposit.depositAmount,
      deposit.feeAmount,
      deposit.starknetFee,
      { value: deposit.msgValue }
    );
    
    // Extract nonce from Deposit event
    const receipt = await depositTx.wait();
    const depositEvent = expectEventInReceipt(
      receipt,
      (e) => e.address === aliceStarkway.address && e.event === 'Deposit'
    );
    const nonce = expectDataInEvent<BigNumber>(depositEvent, 'nonce');

    // Check mock and balances after deposit
    await expectBalance(aliceAddress, 0);
    await expectBalance(vaultAddress, deposit.totalAmount);
    await expectStarknetCalls({
      sendMessageToL2: 1
    });

    // 2. Start deposit cancelation
    const adminStarkway = ENV.starkwayContract.connect(ENV.admin);
    await adminStarkway.startDepositCancelationByOwner(
      tokenAddress,
      aliceAddress,
      Const.ALICE_L2_ADDRESS,
      deposit.depositAmount,
      deposit.feeAmount,
      Const.ZERO_ADDRESS,
      [],
      nonce
    );

    // Check mock and balances after cancelation start
    await expectBalance(aliceAddress, 0);
    await expectBalance(vaultAddress, deposit.totalAmount);
    await expectStarknetCalls({
      startL1ToL2MessageCancellation: 1
    });

    // 3. Finish cancelation
    await fastForwardEVM(600);
    await adminStarkway.finishDepositCancelationByOwner(
      tokenAddress,
      aliceAddress,
      Const.ALICE_L2_ADDRESS,
      deposit.depositAmount,
      deposit.feeAmount,
      Const.ZERO_ADDRESS,
      [],
      nonce
    );

    // Check mock and balances after cancelation finish
    await expectBalance(aliceAddress, deposit.totalAmount);
    await expectBalance(vaultAddress, 0);
    await expectStarknetCalls({
      cancelL1ToL2Message: 1
    });
  });

  it("Cancel ERC20 deposit with message by User", async function () {
    // Make deposit
    const deposit = await prepareDeposit({
      token: tokenAddress, 
      amount: depositAmount,
      senderL1: aliceAddress,
      recipientL2: Const.ALICE_L2_ADDRESS
    });
    const depositID = BigNumber.from("0x1234567890");
    const someUserFlag = BigNumber.from(1);
    const message: BigNumberish[] = [
      Const.STARKWAY_L2_ADDRESS,
      tokenAddress,
      someUserFlag,
      depositID,
      deposit.depositAmount,
      deposit.feeAmount,
      deposit.totalAmount
    ];
    const depositTx = await aliceStarkway.depositFundsWithMessage(
      tokenAddress,
      Const.ALICE_L2_ADDRESS,
      deposit.depositAmount,
      deposit.feeAmount,
      deposit.starknetFee,
      Const.MSG_RECIPIENT_L2_ADDRESS,
      message,
      { value: deposit.msgValue }
    );
    
    // Extract nonce from Deposit event
    const receipt = await depositTx.wait();
    const depositEvent = expectEventInReceipt(
      receipt, 
      (e) => e.address === aliceStarkway.address && e.event === 'DepositWithMessage'
    );
    const nonce = expectDataInEvent<BigNumber>(depositEvent, 'nonce');

    // Check mock and balances after deposit
    await expectBalance(aliceAddress, 0);
    await expectBalance(vaultAddress, deposit.totalAmount);
    await expectStarknetCalls({
      sendMessageToL2: 1
    });

    // 2. Start deposit cancelation
    await aliceStarkway.startDepositCancelation(
      tokenAddress,
      Const.ALICE_L2_ADDRESS,
      deposit.depositAmount,
      deposit.feeAmount,
      Const.MSG_RECIPIENT_L2_ADDRESS,
      message,
      nonce
    )

    // Check mock and balances after cancelation start
    await expectBalance(aliceAddress, 0);
    await expectBalance(vaultAddress, deposit.totalAmount);
    await expectStarknetCalls({
      startL1ToL2MessageCancellation: 1
    });

    // 3. Finish cancelation
    await fastForwardEVM(600);
    await aliceStarkway.finishDepositCancelation(
      tokenAddress,
      Const.ALICE_L2_ADDRESS,
      deposit.depositAmount,
      deposit.feeAmount,
      Const.MSG_RECIPIENT_L2_ADDRESS,
      message,
      nonce
    )

    // Check mock and balances after cancelation finish
    await expectBalance(aliceAddress, deposit.totalAmount);
    await expectBalance(vaultAddress, 0);
    await expectStarknetCalls({
      cancelL1ToL2Message: 1
    });
  });

  it("Cancel ERC20 deposit with message by Admin", async function () {
    // Make deposit
    const deposit = await prepareDeposit({
      token: tokenAddress, 
      amount: depositAmount,
      senderL1: aliceAddress,
      recipientL2: Const.ALICE_L2_ADDRESS
    });
    const depositID = BigNumber.from("0x1234567890");
    const someUserFlag = BigNumber.from(1);
    const message: BigNumberish[] = [
      Const.STARKWAY_L2_ADDRESS,
      tokenAddress,
      someUserFlag,
      depositID,
      deposit.depositAmount,
      deposit.feeAmount,
      deposit.totalAmount
    ];
    const depositTx = await aliceStarkway.depositFundsWithMessage(
      tokenAddress,
      Const.ALICE_L2_ADDRESS,
      deposit.depositAmount,
      deposit.feeAmount,
      deposit.starknetFee,
      Const.MSG_RECIPIENT_L2_ADDRESS,
      message,
      { value: deposit.msgValue }
    );
    
    // Extract nonce from Deposit event
    const receipt = await depositTx.wait();
    const depositEvent = expectEventInReceipt(
      receipt,
      (e) => e.address === aliceStarkway.address && e.event === 'DepositWithMessage'
    );
    const nonce = expectDataInEvent<BigNumber>(depositEvent, 'nonce');

    // Check mock and balances after deposit
    await expectBalance(aliceAddress, 0);
    await expectBalance(vaultAddress, deposit.totalAmount);
    await expectStarknetCalls({
      sendMessageToL2: 1
    });

    // 2. Start deposit cancelation
    const adminStarkway = ENV.starkwayContract.connect(ENV.admin);
    await adminStarkway.startDepositCancelationByOwner(
      tokenAddress,
      aliceAddress,
      Const.ALICE_L2_ADDRESS,
      deposit.depositAmount,
      deposit.feeAmount,
      Const.MSG_RECIPIENT_L2_ADDRESS,
      message,
      nonce
    );

    // Check mock and balances after cancelation start
    await expectBalance(aliceAddress, 0);
    await expectBalance(vaultAddress, deposit.totalAmount);
    await expectStarknetCalls({
      startL1ToL2MessageCancellation: 1
    });

    // 3. Finish cancelation
    await fastForwardEVM(600);
    await adminStarkway.finishDepositCancelationByOwner(
      tokenAddress,
      aliceAddress,
      Const.ALICE_L2_ADDRESS,
      deposit.depositAmount,
      deposit.feeAmount,
      Const.MSG_RECIPIENT_L2_ADDRESS,
      message,
      nonce
    );

    // Check mock and balances after cancelation finish
    await expectBalance(aliceAddress, deposit.totalAmount);
    await expectBalance(vaultAddress, 0);
    await expectStarknetCalls({
      cancelL1ToL2Message: 1
    });
  });
});

describe("Extract Deposit nonce", function () {
  const depositAmount = tokenAmount(1_000);
  let aliceAddress: string;
  let aliceStarkway: Starkway;
  let tokenAddress: string;
  let vaultAddress: string;

  beforeEach(async function () {
    await prepareUsers();
    await deployStarknetCoreMock();
    await deployStarkwayAndVault();
    await deployTestToken();
    
    aliceAddress = await ENV.alice.getAddress();
    aliceStarkway = ENV.starkwayContract.connect(ENV.alice);
    tokenAddress = ENV.testToken.address;
    vaultAddress = ENV.vault.address;
    const initFee = await calculateInitFee(tokenAddress);
    await ENV.vault.initToken(tokenAddress, { value: initFee });
    const deposit = await prepareDeposit({
      token: tokenAddress, 
      amount: depositAmount,
      senderL1: aliceAddress,
      recipientL2: Const.ALICE_L2_ADDRESS
    });
    await ENV.testToken.mint(aliceAddress, deposit.totalAmount);
    await ENV.testToken.connect(ENV.alice).approve(vaultAddress, deposit.totalAmount);
  });

  it("Nonce from Deposit event", async function () {
    // Expected
    const expectedNonce = await ENV.starknetCoreMock.currentNonce();

    // Make deposit
    const deposit = await prepareDeposit({
      token: tokenAddress, 
      amount: depositAmount,
      senderL1: aliceAddress,
      recipientL2: Const.ALICE_L2_ADDRESS
    });
    const depositTx = await aliceStarkway.depositFunds(
      tokenAddress,
      Const.ALICE_L2_ADDRESS,
      deposit.depositAmount,
      deposit.feeAmount,
      deposit.starknetFee,
      { value: deposit.msgValue }
    );
    
    // Extract nonce from Deposit event
    const receipt = await depositTx.wait();
    const depositEvent = expectEventInReceipt(
      receipt, 
      (e) => e.address === aliceStarkway.address && e.event === 'Deposit'
    );
    const nonce = expectDataInEvent<BigNumber>(depositEvent, 'nonce');

    // Check nonce
    expect(nonce).to.eq(expectedNonce);
  });

  it("Nonce from typed events query", async function () {
    // Expected
    const expectedNonce = await ENV.starknetCoreMock.currentNonce();

    // Make deposit
    const deposit = await prepareDeposit({
      token: tokenAddress, 
      amount: depositAmount,
      senderL1: aliceAddress,
      recipientL2: Const.ALICE_L2_ADDRESS
    });
    const depositTx = await aliceStarkway.depositFunds(
      tokenAddress,
      Const.ALICE_L2_ADDRESS,
      deposit.depositAmount,
      deposit.feeAmount,
      deposit.starknetFee,
      { value: deposit.msgValue }
    );
    
    // Query typed Deposit events and get nonce
    await depositTx.wait();
    const depositFilter = aliceStarkway.filters.Deposit(
      tokenAddress,
      aliceAddress,
      Const.ALICE_L2_ADDRESS
    );
    const events = await aliceStarkway.queryFilter(
      depositFilter,
      depositTx.blockNumber,
      depositTx.blockNumber
    );
    const depositEvent = events[0];
    const nonce = expectDataInEvent<BigNumber>(depositEvent, 'nonce');

    // Check nonce
    expect(nonce).to.eq(expectedNonce);
  });

  it("Nonce from raw logs query", async function () {
    // Expected
    const expectedNonce = await ENV.starknetCoreMock.currentNonce();

    // Make deposit
    const deposit = await prepareDeposit({
      token: tokenAddress, 
      amount: depositAmount,
      senderL1: aliceAddress,
      recipientL2: Const.ALICE_L2_ADDRESS
    });
    const depositTx = await aliceStarkway.depositFunds(
      tokenAddress,
      Const.ALICE_L2_ADDRESS,
      deposit.depositAmount,
      deposit.feeAmount,
      deposit.starknetFee,
      { value: deposit.msgValue }
    );
    
    // Extract nonce from raw logs
    await depositTx.wait();
    const filter = aliceStarkway.filters.Deposit(
      tokenAddress,
      aliceAddress,
      Const.ALICE_L2_ADDRESS
    );
    const logs = await ethers.provider.getLogs(filter);
    const depositLog = logs[0];
    const [, , , , nonce] = ethers.utils.defaultAbiCoder.decode(
      ['uint256', 'uint256', 'uint256', 'bytes32', 'uint256'], // Structure of Starkway.Deposit event
      depositLog.data
    );

    // Check nonce
    expect(nonce).to.eq(expectedNonce);
  });
});
