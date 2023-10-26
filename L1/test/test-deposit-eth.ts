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
} from './helpers/utils';
import { ENV } from './helpers/env';
import { 
  expectStarknetCalls, 
  expectL1ToL2Message, 
  expectDepositMessage 
} from './helpers/expectations';

//////////////////
// ETH Deposits //
//////////////////

describe("ETH Deposits", function () {
  const depositAmount = Const.ONE_ETH;
  let aliceStarkway: Starkway;

  beforeEach(async function () {
    await prepareUsers();
    await deployStarknetCoreMock();
    await deployStarkwayAndVault();
    aliceStarkway = ENV.starkwayContract.connect(ENV.alice);
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
    const fees = await ENV.starkwayContract.calculateFees(Const.ETH_ADDRESS, depositAmount);
    const deposit = prepareDeposit(Const.ETH_ADDRESS, depositAmount, fees.depositFee, fees.starknetFee);
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
    const fees = await ENV.starkwayContract.calculateFees(Const.ETH_ADDRESS, depositAmount);
    const deposit = prepareDeposit(Const.ETH_ADDRESS, depositAmount, fees.depositFee, fees.starknetFee);
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
    const initFee = ENV.vault.calculateInitializationFee(Const.ETH_ADDRESS);
    await ENV.vault.initToken(Const.ETH_ADDRESS, { value: initFee });
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
    const fees = await ENV.starkwayContract.calculateFees(Const.ETH_ADDRESS, depositAmount);
    const deposit = prepareDeposit(Const.ETH_ADDRESS, 999_999, 999, fees.starknetFee);
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
    const initFee = ENV.vault.calculateInitializationFee(Const.ETH_ADDRESS);
    await ENV.vault.initToken(Const.ETH_ADDRESS, { value: initFee });
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
    const fees = await ENV.starkwayContract.calculateFees(Const.ETH_ADDRESS, depositAmount);
    const tooLargeAmount = Const.ONE_ETH.add(BigNumber.from(1));
    const deposit = prepareDeposit(Const.ETH_ADDRESS, tooLargeAmount, 1_000_000, fees.starknetFee);
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
    const fees = await ENV.starkwayContract.calculateFees(Const.ETH_ADDRESS, depositAmount);
    const deposit = prepareDeposit(Const.ETH_ADDRESS, depositAmount, fees.depositFee, fees.starknetFee);
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
    const fees = await ENV.starkwayContract.calculateFees(Const.ETH_ADDRESS, depositAmount);
    const deposit = prepareDeposit(Const.ETH_ADDRESS, depositAmount, fees.depositFee, fees.starknetFee);

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

  it("Successful Deposit when ETH is not yet initialized", async function () {
    // Snapshot balance
    const vaultBalanceBefore = await ethers.provider.getBalance(ENV.vault.address);
    
    // Calculate fee
    const fees = await ENV.starkwayContract.calculateFees(Const.ETH_ADDRESS, depositAmount);
    const deposit = prepareDeposit(Const.ETH_ADDRESS, depositAmount, fees.depositFee, fees.starknetFee);

    // Make deposit
    await expect(aliceStarkway.depositFunds(
      Const.ETH_ADDRESS,
      Const.ALICE_L2_ADDRESS,
      deposit.depositAmount,
      deposit.feeAmount,
      deposit.starknetFee,
      { value: deposit.msgValue }
    ))
      .to.emit(ENV.vault, "TokenInitialized")
      .to.emit(ENV.vault, "DepositToVault")
      .to.emit(ENV.starkwayContract, "Deposit");

    // Check StarknetCore messages sent
    await expectStarknetCalls({ sendMessageToL2: 2 });

    // Check Vault balance
    const vaultBalanceAfter = await ethers.provider.getBalance(ENV.vault.address);
    expect(vaultBalanceAfter).to.be.eq(
      vaultBalanceBefore.add(deposit.totalAmount)
    );
  });

  it("Successful Deposit when ETH is already initialized", async function () {
    // Prepare
    const initFee = ENV.vault.calculateInitializationFee(Const.ETH_ADDRESS);
    await ENV.vault.initToken(Const.ETH_ADDRESS, { value: initFee });
    await expectStarknetCalls({ sendMessageToL2: 1 });
    const vaultBalanceBefore = await ethers.provider.getBalance(ENV.vault.address);

    // Calculate fee
    const fees = await ENV.starkwayContract.calculateFees(Const.ETH_ADDRESS, depositAmount);
    const deposit = prepareDeposit(Const.ETH_ADDRESS, depositAmount, fees.depositFee, fees.starknetFee);

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
    const initFee = ENV.vault.calculateInitializationFee(Const.ETH_ADDRESS);
    await ENV.vault.initToken(Const.ETH_ADDRESS, { value: initFee });
    await expectStarknetCalls({ sendMessageToL2: 1 });
    const vaultBalanceBefore = await ethers.provider.getBalance(ENV.vault.address);

    // Calculate fee
    const fees = await ENV.starkwayContract.calculateFees(Const.ETH_ADDRESS, depositAmount);
    const deposit = prepareDeposit(Const.ETH_ADDRESS, depositAmount, fees.depositFee, fees.starknetFee);

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
});
