import { expect } from 'chai';
import { Starkway } from "../typechain-types";
import * as Const from './helpers/constants';
import { 
  prepareUsers, 
  deployStarknetCoreMock, 
  tokenAmount,
  deployStarkwayAndVault,
  deployTestToken, 
  prepareDeposit,
  calculateInitFee,
} from './helpers/utils';
import { ENV } from './helpers/env';
import { BigNumber, Signer } from 'ethers';

////////////////////////
// Failed Withdrawals //
////////////////////////

describe("Process Failed Withdrawals", function () {
  const amount = tokenAmount(1_000);
  let aliceStarkway: Starkway;
  let adminStarkway: Starkway;
  let tokenAddress: string;
  let aliceAddress: string;
  let adminAddress: string;
  let vaultAddress: string;
  const OLD_STARKWAY = Const.DUMMY_ADDRESS;

  beforeEach(async function () {
    await prepareUsers();
    await deployStarknetCoreMock();
    await deployStarkwayAndVault();
    await deployTestToken();
    
    adminStarkway = ENV.starkwayContract.connect(ENV.admin);
    aliceStarkway = ENV.starkwayContract.connect(ENV.alice);
    tokenAddress = ENV.testToken.address;
    aliceAddress = await ENV.alice.getAddress();
    adminAddress = await ENV.admin.getAddress();
    vaultAddress = ENV.vault.address;

    await ENV.testToken.mint(aliceAddress, amount.mul(2));
  });

  it("Failed withdrawal successfully processed", async function () {
    // Approve
    const initFee = calculateInitFee(tokenAddress);
    await ENV.vault.initToken(tokenAddress, { value: initFee });
    const depositParams = await prepareDeposit({
      token: tokenAddress,
      amount,
      senderL1: aliceAddress,
      recipientL2: Const.ALICE_L2_ADDRESS
    });
    await ENV.testToken.connect(ENV.alice).approve(vaultAddress, depositParams.totalAmount);

    // Deposit
    await aliceStarkway.depositFunds(
      tokenAddress,
      Const.ALICE_L2_ADDRESS,
      depositParams.depositAmount,
      depositParams.feeAmount,
      depositParams.starknetFee,
      { value: depositParams.msgValue }
    );
    await ENV.starknetCoreMock.resetCounters();

    // Prepare L2-to-L1 message
    const payload = [
      tokenAddress,
      aliceAddress,
      Const.ALICE_L2_ADDRESS,
      amount,
      0
    ];
    await ENV.starknetCoreMock.addL2ToL1Message(
      Const.STARKWAY_L2_ADDRESS,
      OLD_STARKWAY,
      payload
    );

    // Snapshot balances
    const adminBalanceBefore = await ENV.testToken.balanceOf(adminAddress);
    const vaultBalanceBefore = await ENV.testToken.balanceOf(vaultAddress);

    // Withdraw
    await expect(adminStarkway.processFailedWithdrawals([
      {
        token: tokenAddress,
        recipientAddressL1: aliceAddress,
        senderAddressL2: Const.ALICE_L2_ADDRESS,
        amount
      }
    ], adminAddress))
      .to.emit(ENV.starkwayContract, "FailedWithdrawalProcessed")
    
    // Snapshot updated balances
    const adminBalanceAfter = await ENV.testToken.balanceOf(adminAddress);
    const vaultBalanceAfter = await ENV.testToken.balanceOf(vaultAddress);

    // Check balances
    expect(adminBalanceAfter).to.be.eq(
      adminBalanceBefore.add(amount)
    );
    expect(vaultBalanceAfter).to.be.eq(
      vaultBalanceBefore.sub(amount)
    );
  });

  it("Only admin", async function () {
    // Invalid amount
    await expect(adminStarkway.connect(ENV.rogue).processFailedWithdrawals([
      {
        token: tokenAddress,
        recipientAddressL1: aliceAddress,
        senderAddressL2: Const.ALICE_L2_ADDRESS,
        amount
      }
    ], adminAddress))
      .to
      .be
      .revertedWithCustomError(ENV.starkwayContract, 'OwnableUnauthorizedAccount')
  });

  it("Cannot withdraw twice", async function () {
    // Approve
    const initFee = calculateInitFee(tokenAddress);
    await ENV.vault.initToken(tokenAddress, { value: initFee });
    const depositParams = await prepareDeposit({
      token: tokenAddress,
      amount,
      senderL1: aliceAddress,
      recipientL2: Const.ALICE_L2_ADDRESS
    });
    await ENV.testToken.connect(ENV.alice).approve(vaultAddress, depositParams.totalAmount);

    // Deposit
    await aliceStarkway.depositFunds(
      tokenAddress,
      Const.ALICE_L2_ADDRESS,
      depositParams.depositAmount,
      depositParams.feeAmount,
      depositParams.starknetFee,
      { value: depositParams.msgValue }
    );
    await ENV.starknetCoreMock.resetCounters();

    // Prepare L2-to-L1 message
    const payload = [
      tokenAddress,
      aliceAddress,
      Const.ALICE_L2_ADDRESS,
      amount,
      0
    ];
    await ENV.starknetCoreMock.addL2ToL1Message(
      Const.STARKWAY_L2_ADDRESS,
      OLD_STARKWAY,
      payload
    );

    // Withdraw 1st call
    await expect(adminStarkway.processFailedWithdrawals([
      {
        token: tokenAddress,
        recipientAddressL1: aliceAddress,
        senderAddressL2: Const.ALICE_L2_ADDRESS,
        amount
      }
    ], adminAddress))
      .to.emit(ENV.starkwayContract, "FailedWithdrawalProcessed")

    // Withdraw 2nd call
    await expect(adminStarkway.processFailedWithdrawals([
      {
        token: tokenAddress,
        recipientAddressL1: aliceAddress,
        senderAddressL2: Const.ALICE_L2_ADDRESS,
        amount
      }
    ], adminAddress))
      .to
      .be
      .revertedWith("Message already consumed")
  });

  it("Revert on invalid recipient", async function () {
    // Invalid amount
    await expect(adminStarkway.processFailedWithdrawals([
      {
        token: tokenAddress,
        recipientAddressL1: Const.DUMMY_ADDRESS,
        senderAddressL2: Const.ALICE_L2_ADDRESS,
        amount
      }
    ], adminAddress))
      .to
      .be
      .revertedWith("No message to be consumed")
  });

  it("Revert on invalid sender", async function () {
    // Invalid amount
    await expect(adminStarkway.processFailedWithdrawals([
      {
        token: tokenAddress,
        recipientAddressL1: aliceAddress,
        senderAddressL2: Const.MSG_RECIPIENT_L2_ADDRESS,
        amount
      }
    ], adminAddress))
      .to
      .be
      .revertedWith("No message to be consumed")
  });

  it("Revert on invalid amount", async function () {
    // Invalid amount
    await expect(adminStarkway.processFailedWithdrawals([
      {
        token: tokenAddress,
        recipientAddressL1: aliceAddress,
        senderAddressL2: Const.ALICE_L2_ADDRESS,
        amount: amount.add(1)
      }
    ], adminAddress))
      .to
      .be
      .revertedWith("No message to be consumed")
  });
})

type DepositInfo = {
  user: Signer,
  depositAmount: BigNumber,
}

type WithdrawalInfo = {
  token: string,
  recipientAddressL1: string,
  senderAddressL2: BigNumber,
  amount: BigNumber
}
