import { ethers } from 'hardhat';
import { expect } from 'chai';
import { Starkway } from "../typechain-types";
import { BigNumber, BigNumberish } from 'ethers';
import * as Const from './helpers/constants';
import { 
  prepareUsers,
  deployStarknetCoreMock,
  deployStarkwayAndVault,
  prepareDeposit,
  calculateInitFee,
  splitUint256,
  DepositMessage,
} from './helpers/utils';
import { ENV } from './helpers/env';
import { 
  expectStarknetCalls, 
  expectL1ToL2Message, 
  expectDepositMessage, 
  expectPayloadToBeEqual
} from './helpers/expectations';

//////////////////
// ETH Deposits //
//////////////////

describe("ETH Deposits", function () {
  const depositAmount = Const.ONE_ETH;
  let aliceStarkway: Starkway;
  let aliceAddress: string;

  beforeEach(async function () {
    await prepareUsers();
    await deployStarknetCoreMock();
    await deployStarkwayAndVault();
    aliceAddress = await ENV.alice.getAddress();
    aliceStarkway = ENV.starkwayContract.connect(ENV.alice);
    const initFee = await calculateInitFee(Const.ETH_ADDRESS)
    await ENV.vault.initToken(Const.ETH_ADDRESS, { value: initFee })
    await ENV.starknetCoreMock.resetCounters();
  });

  it("Revert Deposit if amount == 0", async function () {
    await expect(aliceStarkway.depositFunds(
      Const.ETH_ADDRESS,
      Const.ALICE_L2_ADDRESS,
      0,
      0,
      0,
      { value: 0 }
    )).to.be.revertedWithCustomError(ENV.starkwayContract, "ZeroAmountError");
  });

  it("Revert Deposit if L2 address == 0x00", async function () {
    // Calculate fee
    const deposit = await prepareDeposit({
      token: Const.ETH_ADDRESS, 
      amount: depositAmount,
      senderL1: aliceAddress,
      recipientL2: Const.ALICE_L2_ADDRESS
    });
    // Make deposit
    await expect(aliceStarkway.depositFunds(
      Const.ETH_ADDRESS,
      0,
      deposit.depositAmount,
      deposit.feeAmount,
      deposit.starknetFee,
      { value: deposit.msgValue }
    )).to.be.revertedWithCustomError(ENV.starkwayContract, "ZeroAddressError");
  });

  it("Revert Deposit if L2 address is invalid", async function () {
    // Calculate fee
    const deposit = await prepareDeposit({
      token: Const.ETH_ADDRESS, 
      amount: depositAmount,
      senderL1: aliceAddress,
      recipientL2: Const.ALICE_L2_ADDRESS
    });
    // Make deposit
    await expect(aliceStarkway.depositFunds(
      Const.ETH_ADDRESS,
      "0x800000000000011000000000000000000000000000000000000000000000111",
      deposit.depositAmount,
      deposit.feeAmount,
      deposit.starknetFee,
      { value: deposit.msgValue }
    )).to.be.revertedWithCustomError(ENV.starkwayContract, "FeltUtils__InvalidFeltError");
  });

  it("Revert Deposit if amount < MIN deposit", async function () {
    // Prepare
    await ENV.starkwayContract.updateTokenSettings(
      Const.ETH_ADDRESS, // token
      1_000_000, // minDeposit
      Const.ONE_ETH, // maxDeposit
      0, // minFee
      0, // maxFee
      false, // useCustomFeeRate
      [] // feeSegments
    );
    // Make deposit
    const deposit = await prepareDeposit({
      token: Const.ETH_ADDRESS, 
      amount: 999_999,
      senderL1: aliceAddress,
      recipientL2: Const.ALICE_L2_ADDRESS
    });
    await expect(aliceStarkway.depositFunds(
      Const.ETH_ADDRESS,
      Const.ALICE_L2_ADDRESS,
      deposit.depositAmount,
      deposit.feeAmount,
      deposit.starknetFee,
      { value: deposit.msgValue }
    )).to.be.revertedWithCustomError(ENV.starkwayContract, "InvalidDepositAmount");
  });

  it("Revert Deposit if amount > MAX deposit", async function () {
    // Prepare

    await ENV.starkwayContract.updateTokenSettings(
      Const.ETH_ADDRESS, // token
      0, // minDeposit
      Const.ONE_ETH, // maxDeposit
      0, // minFee
      0, // maxFee
      false, // useCustomFeeRate
      [] // feeSegments
    );
    // Make deposit
    const tooLargeAmount = Const.ONE_ETH.add(BigNumber.from(1));
    const deposit = await prepareDeposit({
      token: Const.ETH_ADDRESS, 
      amount: tooLargeAmount,
      senderL1: aliceAddress,
      recipientL2: Const.ALICE_L2_ADDRESS
    });
    await expect(aliceStarkway.depositFunds(
      Const.ETH_ADDRESS,
      Const.ALICE_L2_ADDRESS,
      deposit.depositAmount,
      deposit.feeAmount,
      deposit.starknetFee,
      { value: deposit.msgValue }
    )).to.be.revertedWithCustomError(ENV.starkwayContract, "InvalidDepositAmount");
  });

  it("Revert Deposit with message if message recipient address is 0x00", async function () {
    // Calculate fee
    const deposit = await prepareDeposit({
      token: Const.ETH_ADDRESS, 
      amount: depositAmount,
      senderL1: aliceAddress,
      recipientL2: Const.ALICE_L2_ADDRESS
    });
    // Make deposit
    await expect(aliceStarkway.depositFundsWithMessage(
      Const.ETH_ADDRESS,
      Const.ALICE_L2_ADDRESS,
      deposit.depositAmount,
      deposit.feeAmount,
      deposit.starknetFee,
      Const.BN_ZERO,
      [],
      { value: deposit.msgValue }
    )).to.be.revertedWithCustomError(ENV.starkwayContract, "ZeroAddressError");
  });

  it("Revert Deposit with message when a message element > MAX_FELT", async function () {
    // Calculate fee
    const deposit = await prepareDeposit({
      token: Const.ETH_ADDRESS, 
      amount: depositAmount,
      senderL1: aliceAddress,
      recipientL2: Const.ALICE_L2_ADDRESS
    });

    // Make deposit
    const depositID = Const.FIRST_INVALID_FELT_252;
    const someUserFlag = BigNumber.from(1);
    const message: BigNumberish[] = [
      Const.STARKWAY_L2_ADDRESS,
      Const.ETH_ADDRESS,
      someUserFlag,
      depositID,
      deposit.depositAmount,
      deposit.feeAmount,
      deposit.totalAmount
    ];
    await expect(aliceStarkway.depositFundsWithMessage(
      Const.ETH_ADDRESS,
      Const.ALICE_L2_ADDRESS,
      deposit.depositAmount,
      deposit.feeAmount,
      deposit.starknetFee,
      Const.MSG_RECIPIENT_L2_ADDRESS,
      message,
      { value: deposit.msgValue }
    )).to.be.revertedWithCustomError(ENV.starkwayContract, "FeltUtils__InvalidFeltError");
  });

  it("Successful Deposit when ETH is already initialized", async function () {
    // Prepare
    const vaultBalanceBefore = await ethers.provider.getBalance(ENV.vault.address);

    // Calculate fee
    const deposit = await prepareDeposit({
      token: Const.ETH_ADDRESS, 
      amount: depositAmount,
      senderL1: aliceAddress,
      recipientL2: Const.ALICE_L2_ADDRESS
    });

    // Make deposit
    await expect(aliceStarkway.depositFunds(
      Const.ETH_ADDRESS,
      Const.ALICE_L2_ADDRESS,
      deposit.depositAmount,
      deposit.feeAmount,
      deposit.starknetFee,
      { value: deposit.msgValue }
    ))
      .to.emit(ENV.vault, "DepositToVault")
      .to.emit(ENV.starkwayContract, "Deposit");

    // Check StarknetCore messages sent
    await expectStarknetCalls({ sendMessageToL2: 1 });

    // Check Starkway balance
    const vaultBalanceAfter = await ethers.provider.getBalance(ENV.vault.address);
    expect(vaultBalanceAfter).to.be.eq(
      vaultBalanceBefore.add(deposit.totalAmount)
    );
  });

  it("Success Deposit with message", async function () {
    // Prepare
    const vaultBalanceBefore = await ethers.provider.getBalance(ENV.vault.address);

    // Calculate fee
    const deposit = await prepareDeposit({
      token: Const.ETH_ADDRESS, 
      amount: depositAmount,
      senderL1: aliceAddress,
      recipientL2: Const.ALICE_L2_ADDRESS
    });

    // Make deposit
    const depositID = BigNumber.from("0x1234567890");
    const someUserFlag = BigNumber.from(1);
    const message: BigNumberish[] = [
      Const.STARKWAY_L2_ADDRESS,
      Const.ETH_ADDRESS,
      someUserFlag,
      depositID,
      deposit.depositAmount,
      deposit.feeAmount,
      deposit.totalAmount
    ];
    await expect(aliceStarkway.depositFundsWithMessage(
      Const.ETH_ADDRESS,
      Const.ALICE_L2_ADDRESS,
      deposit.depositAmount,
      deposit.feeAmount,
      deposit.starknetFee,
      Const.MSG_RECIPIENT_L2_ADDRESS,
      message,
      { value: deposit.msgValue }
    ))
      .to.emit(ENV.vault, "DepositToVault")
      .to.emit(ENV.starkwayContract, "DepositWithMessage");
    
    // Check StarknetCore messages sent
    await expectStarknetCalls({ sendMessageToL2: 1 });
    await expectL1ToL2Message({
      from: aliceStarkway.address,
      to: Const.STARKWAY_L2_ADDRESS,
      selector: Const.DEPOSIT_WITH_MESSAGE_HANDLER
    });
    await expectDepositMessage({
      recipient: Const.MSG_RECIPIENT_L2_ADDRESS,
      contents: message
    });

    // Check Starkway balance
    const vaultBalanceAfter = await ethers.provider.getBalance(ENV.vault.address);
    expect(vaultBalanceAfter).to.be.eq(
      vaultBalanceBefore.add(deposit.totalAmount)
    );
  });

  it("L1-to-L2 message for ETH deposit with no message", async function () {
    const senderL1 = aliceAddress
    const recipientL2 = Const.ALICE_L2_ADDRESS
    const deposit = await prepareDeposit({
      token: Const.ETH_ADDRESS, 
      amount: depositAmount,
      senderL1,
      recipientL2
    })
    const [depositFee, message] = await aliceStarkway.prepareDeposit(
      Const.ETH_ADDRESS,
      senderL1,
      recipientL2,
      deposit.depositAmount,
      0,
      []
    )

    expect(message.fromAddress).to.be.eq(aliceStarkway.address)
    expect(message.toAddress).to.be.eq(Const.STARKWAY_L2_ADDRESS)
    expect(message.selector).to.be.eq(Const.DEPOSIT_HANDLER)

    const depositAmountU256 = splitUint256(depositAmount.toHexString())
    const depositFeeU256 = splitUint256(depositFee.toHexString())
    const expectedPayload = [
      Const.ETH_ADDRESS,
      senderL1,
      recipientL2,
      depositAmountU256.low,
      depositAmountU256.high,
      depositFeeU256.low,
      depositFeeU256.high
    ]
    expectPayloadToBeEqual(message.payload, expectedPayload)
  })

  it("L1-to-L2 message for ETH deposit with a message", async function () {
    const senderL1 = aliceAddress
    const recipientL2 = Const.ALICE_L2_ADDRESS
    const depositID = BigNumber.from("0x1234567890");
    const someUserFlag = BigNumber.from(1);
    const messagePayload: BigNumberish[] = [
      Const.STARKWAY_L2_ADDRESS,
      Const.ETH_ADDRESS,
      someUserFlag,
      depositID,
    ]
    const depositMessage: DepositMessage = {
      recipient: Const.MSG_RECIPIENT_L2_ADDRESS,
      payload: messagePayload
    }
    const [depositFee, message] = await aliceStarkway.prepareDeposit(
      Const.ETH_ADDRESS,
      senderL1,
      recipientL2,
      depositAmount,
      depositMessage.recipient,
      depositMessage.payload
    )

    expect(message.fromAddress).to.be.eq(aliceStarkway.address)
    expect(message.toAddress).to.be.eq(Const.STARKWAY_L2_ADDRESS)
    expect(message.selector).to.be.eq(Const.DEPOSIT_WITH_MESSAGE_HANDLER)

    const depositAmountU256 = splitUint256(depositAmount.toHexString())
    const depositFeeU256 = splitUint256(depositFee.toHexString())
    let expectedPayload: BigNumberish[] = [
      Const.ETH_ADDRESS,
      senderL1,
      recipientL2,
      depositAmountU256.low,
      depositAmountU256.high,
      depositFeeU256.low,
      depositFeeU256.high
    ]
    expectedPayload = [
      ...expectedPayload,
      depositMessage.recipient,
      depositMessage.payload.length,
      ...depositMessage.payload
    ]

    expectPayloadToBeEqual(message.payload, expectedPayload)
  })
});
