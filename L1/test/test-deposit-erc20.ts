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
  DepositParams,
} from './helpers/utils';
import { ENV } from './helpers/env';
import { 
  expectBalance, 
  expectStarknetCalls, 
  expectDepositMessage, 
  expectL1ToL2Message
} from './helpers/expectations';

////////////////////
// ERC20 Deposits //
////////////////////

describe("ERC20 Deposits", function () {
  const depositAmount = tokenAmount(1000);
  let aliceStarkway: Starkway;
  let aliceAddress: string;
  let vaultAddress: string;
  let tokenAddress: string;
  let depositParams: DepositParams;
  let token: string;

  beforeEach(async function () {
    // Deploy
    await prepareUsers();
    await deployStarknetCoreMock();
    await deployStarkwayAndVault();
    await deployTestToken();
    // Set variables
    token = ENV.testToken.address;
    aliceStarkway = ENV.starkwayContract.connect(ENV.alice);
    aliceAddress = await ENV.alice.getAddress();
    vaultAddress = ENV.vault.address;
    tokenAddress = ENV.testToken.address;
    const fees = await aliceStarkway.calculateFees(token, depositAmount);
    depositParams = prepareDeposit(token, depositAmount, fees.depositFee, fees.starknetFee);
    // Mint & approve tokens
    await ENV.testToken.mint(aliceAddress, depositParams.totalAmount);
    await ENV.testToken.connect(ENV.alice).approve(vaultAddress, depositParams.totalAmount);    
  });

  it("Revert Deposit if amount == 0", async function () {
    await expect(aliceStarkway.depositFunds(
      token,
      Const.ALICE_L2_ADDRESS, 
      0,
      depositParams.feeAmount,
      depositParams.starknetFee,
      { value: depositParams.msgValue }
    )).to.be.revertedWithCustomError(ENV.starkwayContract, "ZeroAmountError");
  });

  it("Revert Deposit if L2 address == 0x00", async function () {
    await expect(aliceStarkway.depositFunds(
      token,
      0, 
      depositAmount,
      depositParams.feeAmount,
      depositParams.starknetFee,
      { value: depositParams.msgValue }
    )).to.be.revertedWithCustomError(ENV.starkwayContract, "ZeroAddressError");
  });

  it("Revert Deposit if L2 address is invalid", async function () {
    await expect(aliceStarkway.depositFunds(
      token,
      "0x800000000000011000000000000000000000000000000000000000000000111",
      depositAmount,
      depositParams.feeAmount,
      depositParams.starknetFee,
      { value: depositParams.msgValue }
    )).to.be.revertedWithCustomError(ENV.starkwayContract, "FeltUtils__InvalidFeltError");
  });

  it("Revert Deposit if amount < MIN deposit", async function () {
    // Prepare
    const initFee = ENV.vault.calculateInitializationFee(tokenAddress);
    await ENV.vault.initToken(tokenAddress, { value: initFee });
    await ENV.starkwayContract.updateTokenSettings(
      ENV.testToken.address, // token
      tokenAmount(10), // minDeposit
      tokenAmount(1_000_000_000), // maxDeposit
      0, // minFee
      0, // maxFee
      false, // useCustomFeeRate
      [] // feeSegments
    );
    // Make deposit
    await expect(aliceStarkway.depositFunds(
      token,
      Const.ALICE_L2_ADDRESS,
      tokenAmount(5),
      depositParams.feeAmount,
      depositParams.starknetFee,
      { value: depositParams.msgValue }
    )).to.be.revertedWithCustomError(ENV.starkwayContract, "InvalidDepositAmount");
  });

  it("Revert Deposit if amount > MAX deposit", async function () {
    // Prepare
    const initFee = ENV.vault.calculateInitializationFee(tokenAddress);
    await ENV.vault.initToken(tokenAddress, { value: initFee });
    await ENV.starkwayContract.updateTokenSettings(
      ENV.testToken.address, // token
      tokenAmount(10), // minDeposit
      tokenAmount(900), // maxDeposit
      0, // minFee
      0, // maxFee
      false, // useCustomFeeRate
      [] // feeSegments
    );
    // Make deposit
    await expect(aliceStarkway.depositFunds(
      token,
      Const.ALICE_L2_ADDRESS,
      tokenAmount(1000),
      depositParams.feeAmount,
      depositParams.starknetFee,
      { value: depositParams.msgValue }
    )).to.be.revertedWithCustomError(ENV.starkwayContract, "InvalidDepositAmount");
  });

  it("Revert Deposit with message if message recipient address is 0x00", async function () {
    await expect(aliceStarkway.depositFundsWithMessage(
      token,
      Const.ALICE_L2_ADDRESS, 
      depositParams.depositAmount,
      depositParams.feeAmount,
      depositParams.starknetFee,
      Const.BN_ZERO,
      [],
      { value: depositParams.msgValue }
    )).to.be.revertedWithCustomError(ENV.starkwayContract, "ZeroAddressError");
  });

  it("Revert Deposit with message when a message element > MAX_FELT", async function () {
    // Calculate fee
    const fees = await aliceStarkway.calculateFees(token, depositAmount);
    const deposit = prepareDeposit(token, depositAmount, fees.depositFee, fees.starknetFee);

    // Make deposit
    const depositID = BigNumber.from("0x1234567890");
    const someUserFlag = Const.FIRST_INVALID_FELT_252;
    const message: BigNumberish[] = [
      Const.STARKWAY_L2_ADDRESS,
      token,
      someUserFlag,
      depositID,
      deposit.depositAmount,
      deposit.feeAmount,
      deposit.totalAmount
    ];
    await expect(aliceStarkway.depositFundsWithMessage(
      token,
      Const.ALICE_L2_ADDRESS,
      deposit.depositAmount,
      deposit.feeAmount,
      deposit.starknetFee,
      Const.MSG_RECIPIENT_L2_ADDRESS,
      message,
      { value: deposit.msgValue }
    )).to.be.revertedWithCustomError(ENV.starkwayContract, "FeltUtils__InvalidFeltError");
  });

  it("Success Deposit when token is already initialized", async function () {
    // Prepare
    const initFee = ENV.vault.calculateInitializationFee(tokenAddress);
    await ENV.vault.initToken(tokenAddress, { value: initFee });
    await expectStarknetCalls({ sendMessageToL2: 1 });

    // Calculate fee
    const fees = await aliceStarkway.calculateFees(token, depositAmount);
    const deposit = prepareDeposit(token, depositAmount, fees.depositFee, fees.starknetFee);

    // Make deposit
    await expect(aliceStarkway.depositFunds(
      token,
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

    // Check balances
    await expectBalance(aliceAddress, 0);
    await expectBalance(vaultAddress, deposit.totalAmount);
  });

  it("Success Deposit with message", async function () {
    // Prepare
    const initFee = ENV.vault.calculateInitializationFee(tokenAddress);
    await ENV.vault.initToken(tokenAddress, { value: initFee });
    await expectStarknetCalls({ sendMessageToL2: 1 });

    // Calculate fee
    const fees = await aliceStarkway.calculateFees(token, depositAmount);
    const deposit = prepareDeposit(token, depositAmount, fees.depositFee, fees.starknetFee);

    // Make deposit
    const depositID = BigNumber.from("0x1234567890");
    const someUserFlag = BigNumber.from(1);
    const message: BigNumberish[] = [
      Const.STARKWAY_L2_ADDRESS,
      token,
      someUserFlag,
      depositID,
      deposit.depositAmount,
      deposit.feeAmount,
      deposit.totalAmount
    ];
    await expect(aliceStarkway.depositFundsWithMessage(
      token,
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

    // Check balances
    await expectBalance(aliceAddress, 0);
    await expectBalance(vaultAddress, deposit.totalAmount);
  });
});
