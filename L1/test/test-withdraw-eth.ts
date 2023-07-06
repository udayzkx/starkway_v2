import { ethers } from 'hardhat';
import { expect } from 'chai';
import { Starkway } from "../typechain-types";
import * as Const from './helpers/constants';
import { 
  prepareUsers,
  deployStarknetCoreMock,
  deployStarkwayAndVault,
  prepareDeposit,
} from './helpers/utils';
import { ENV } from './helpers/env';

/////////////////////
// ETH Withdrawals //
/////////////////////

describe("ETH Withdrawals", function () {
  const amount = Const.ONE_ETH;
  let aliceStarkway: Starkway;

  beforeEach(async function () {
    await prepareUsers();
    await deployStarknetCoreMock();
    await deployStarkwayAndVault();
    aliceStarkway = ENV.starkwayContract.connect(ENV.alice);
  });

  it("Revert ETH withdrawal when token is not yet initialized", async function () {
    // Prepare L2-to-L1 message
    const payload = [
      Const.ETH_ADDRESS,
      ENV.alice.getAddress(),
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
      Const.ETH_ADDRESS,
      ENV.alice.getAddress(),
      Const.ALICE_L2_ADDRESS,
      amount
    )).to.be.revertedWithCustomError(ENV.vault, "StarkwayVault__TokenMustBeInitialized");
  });

  it("Successful ETH withdrawal by user", async function () {
    // Calculate fee
    const fees = await aliceStarkway.calculateFees(Const.ETH_ADDRESS, amount);
    const deposit = prepareDeposit(Const.ETH_ADDRESS, amount, fees.depositFee, fees.starknetFee);

    // Deposit
    await aliceStarkway.depositFunds(
      Const.ETH_ADDRESS,
      Const.ALICE_L2_ADDRESS,
      deposit.depositAmount,
      deposit.feeAmount,
      deposit.starknetFee,
      { value: deposit.msgValue }
    );
    await ENV.starknetCoreMock.resetCounters();

    // Prepare L2-to-L1 message
    const payload = [
      Const.ETH_ADDRESS,
      ENV.alice.getAddress(),
      Const.ALICE_L2_ADDRESS,
      amount,
      0
    ];
    await ENV.starknetCoreMock.addL2ToL1Message(
      Const.STARKWAY_L2_ADDRESS,
      ENV.starkwayContract.address,
      payload
    );

    // Snapshot balance
    const vaultBalanceBefore = await ethers.provider.getBalance(ENV.vault.address);

    // Withdraw
    const tx = await expect(aliceStarkway.withdrawFunds(
      Const.ETH_ADDRESS,
      ENV.alice.getAddress(),
      Const.ALICE_L2_ADDRESS,
      amount
    ))
      .to.emit(ENV.starkwayContract, "Withdrawal");
    
    // Snapshot updated balances
    const vaultBalanceAfter = await ethers.provider.getBalance(ENV.vault.address);

    // Check balance
    expect(vaultBalanceAfter).to.be.eq(
      vaultBalanceBefore.sub(amount)
    );
  });

  it("Successful ETH withdrawal by admin", async function () {
    // Calculate fee
    const fees = await aliceStarkway.calculateFees(Const.ETH_ADDRESS, amount);
    const deposit = prepareDeposit(Const.ETH_ADDRESS, amount, fees.depositFee, fees.starknetFee);

    // Deposit
    await aliceStarkway.depositFunds(
      Const.ETH_ADDRESS,
      Const.ALICE_L2_ADDRESS,
      deposit.depositAmount,
      deposit.feeAmount,
      deposit.starknetFee,
      { value: deposit.msgValue }
    );
    await ENV.starknetCoreMock.resetCounters();

    // Prepare L2-to-L1 message
    const payload = [
      Const.ETH_ADDRESS,
      ENV.alice.getAddress(),
      Const.ALICE_L2_ADDRESS,
      amount,
      0
    ];
    await ENV.starknetCoreMock.addL2ToL1Message(
      Const.STARKWAY_L2_ADDRESS,
      ENV.starkwayContract.address,
      payload
    );

    // Snapshot balance
    const aliceBalanceBefore = await ethers.provider.getBalance(ENV.alice.getAddress());
    const vaultBalanceBefore = await ethers.provider.getBalance(ENV.vault.address);

    // Withdraw
    const tx = await expect(ENV.starkwayContract.connect(ENV.admin).withdrawFunds(
      Const.ETH_ADDRESS,
      ENV.alice.getAddress(),
      Const.ALICE_L2_ADDRESS,
      amount
    ))
      .to.emit(ENV.starkwayContract, "Withdrawal");
    
    // Snapshot updated balances
    const aliceBalanceAfter = await ethers.provider.getBalance(ENV.alice.getAddress());
    const vaultBalanceAfter = await ethers.provider.getBalance(ENV.vault.address);

    // Check balance
    expect(aliceBalanceAfter).to.be.eq(
      aliceBalanceBefore.add(amount)
    );
    expect(vaultBalanceAfter).to.be.eq(
      vaultBalanceBefore.sub(amount)
    );
  });
});
