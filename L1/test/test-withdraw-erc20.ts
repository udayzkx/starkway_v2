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

///////////////////////
// ERC20 Withdrawals //
///////////////////////

describe("ERC20 Withdrawals", function () {
  const amount = tokenAmount(1_000);
  let aliceStarkway: Starkway;
  let tokenAddress: string;
  let aliceAddress: string;
  let vaultAddress: string;

  beforeEach(async function () {
    await prepareUsers();
    await deployStarknetCoreMock();
    await deployStarkwayAndVault();
    await deployTestToken();
    
    aliceStarkway = ENV.starkwayContract.connect(ENV.alice);
    tokenAddress = ENV.testToken.address;
    aliceAddress = await ENV.alice.getAddress();
    vaultAddress = ENV.vault.address;

    const fees = await aliceStarkway.calculateFees(tokenAddress, amount);
    const depositParams = prepareDeposit(tokenAddress, amount, fees.depositFee, fees.starknetFee);
    await ENV.testToken.mint(aliceAddress, depositParams.totalAmount);
  });

  it("Revert ERC20 withdrawal when token is not yet initialized", async function () {
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
      ENV.starkwayContract.address,
      payload
    );
    // Try to withdraw
    await expect(aliceStarkway.withdrawFunds(
      tokenAddress,
      aliceAddress,
      Const.ALICE_L2_ADDRESS,
      amount
    )).to.be.revertedWithCustomError(ENV.vault, "StarkwayVault__TokenMustBeInitialized");
  });

  it("Revert ERC20 withdrawal when to address is zero", async function () {
    // Approve
    const initFee = calculateInitFee(tokenAddress)
    await ENV.vault.initToken(tokenAddress, { value: initFee })
    const fees = await aliceStarkway.calculateFees(tokenAddress, amount)
    const depositParams = prepareDeposit(tokenAddress, amount, fees.depositFee, fees.starknetFee)
    await ENV.testToken.connect(ENV.alice).approve(vaultAddress, depositParams.totalAmount)

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
      Const.ZERO_ADDRESS,
      Const.ALICE_L2_ADDRESS,
      amount,
      0
    ];
    await ENV.starknetCoreMock.addL2ToL1Message(
      Const.STARKWAY_L2_ADDRESS,
      ENV.starkwayContract.address,
      payload
    );
    // Try to withdraw
    await expect(aliceStarkway.withdrawFunds(
      tokenAddress,
      Const.ZERO_ADDRESS,
      Const.ALICE_L2_ADDRESS,
      amount
    )).to.be.revertedWithCustomError(ENV.vault, "TokenUtils__TransferToZero");
  });

  it("Successful ERC20 withdrawal by user", async function () {
    // Approve
    const initFee = calculateInitFee(tokenAddress);
    await ENV.vault.initToken(tokenAddress, { value: initFee });
    const fees = await aliceStarkway.calculateFees(tokenAddress, amount);
    const depositParams = prepareDeposit(tokenAddress, amount, fees.depositFee, fees.starknetFee);
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
      ENV.starkwayContract.address,
      payload
    );

    // Snapshot balances
    const aliceBalanceBefore = await ENV.testToken.balanceOf(aliceAddress);
    const vaultBalanceBefore = await ENV.testToken.balanceOf(vaultAddress);

    // Withdraw
    await expect(aliceStarkway.withdrawFunds(
      tokenAddress,
      aliceAddress,
      Const.ALICE_L2_ADDRESS,
      amount
    ))
      .to.emit(ENV.testToken, "Transfer")
      .to.emit(ENV.vault, "WithdrawalFromVault")
      .to.emit(ENV.starkwayContract, "Withdrawal");
    
    // Snapshot updated balances
    const aliceBalanceAfter = await ENV.testToken.balanceOf(aliceAddress);
    const vaultBalanceAfter = await ENV.testToken.balanceOf(vaultAddress);

    // Check balances
    expect(aliceBalanceAfter).to.be.eq(
      aliceBalanceBefore.add(amount)
    );
    expect(vaultBalanceAfter).to.be.eq(
      vaultBalanceBefore.sub(amount)
    );
  });

  it("Successful ERC20 withdrawal by admin", async function () {
    // Approve
    const initFee = calculateInitFee(tokenAddress);
    await ENV.vault.initToken(tokenAddress, { value: initFee });
    const fees = await aliceStarkway.calculateFees(tokenAddress, amount);
    const depositParams = prepareDeposit(tokenAddress, amount, fees.depositFee, fees.starknetFee);
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
      ENV.starkwayContract.address,
      payload
    );

    // Snapshot balances
    const aliceBalanceBefore = await ENV.testToken.balanceOf(aliceAddress);
    const vaultBalanceBefore = await ENV.testToken.balanceOf(vaultAddress);

    // Withdraw
    await expect(ENV.starkwayContract.connect(ENV.admin).withdrawFunds(
      tokenAddress,
      aliceAddress,
      Const.ALICE_L2_ADDRESS,
      amount
    ))
      .to.emit(ENV.testToken, "Transfer")
      .to.emit(ENV.starkwayContract, "Withdrawal");
    
    // Snapshot updated balances
    const aliceBalanceAfter = await ENV.testToken.balanceOf(aliceAddress);
    const vaultBalanceAfter = await ENV.testToken.balanceOf(vaultAddress);

    // Check balances
    expect(aliceBalanceAfter).to.be.eq(
      aliceBalanceBefore.add(amount)
    );
    expect(vaultBalanceAfter).to.be.eq(
      vaultBalanceBefore.sub(amount)
    );
  });
});
