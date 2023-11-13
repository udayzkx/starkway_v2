import { ethers } from 'hardhat';
import { expect } from 'chai';
import { BigNumber, Signer } from 'ethers';
import { Starkway } from "../typechain-types";
import * as Const from './helpers/constants';
import { 
  prepareUsers,
  deployStarknetCoreMock,
  deployStarkwayAndVault,
  prepareDeposit,
  calculateInitFee,
} from './helpers/utils';
import { ENV } from './helpers/env';
import { BigNumberish } from 'starknet';

/////////////////////
// ETH Withdrawals //
/////////////////////

describe("ETH Withdrawals", function () {
  const amount = Const.ONE_ETH;
  let aliceStarkway: Starkway;
  let aliceAddress: string;

  beforeEach(async function () {
    await prepareUsers();
    await deployStarknetCoreMock();
    await deployStarkwayAndVault();
    aliceAddress = await ENV.alice.getAddress();
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

  it("Revert ETH withdrawal when to address is zero", async function () {
    // Calculate fee
    const initFee = calculateInitFee(Const.ETH_ADDRESS);
    await ENV.vault.initToken(Const.ETH_ADDRESS, { value: initFee });
    const deposit = await prepareDeposit({
      token: Const.ETH_ADDRESS, 
      amount,
      senderL1: aliceAddress,
      recipientL2: Const.ALICE_L2_ADDRESS
    });

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
      Const.ETH_ADDRESS,
      Const.ZERO_ADDRESS,
      Const.ALICE_L2_ADDRESS,
      amount
    )).to.be.revertedWithCustomError(ENV.vault, "TokenUtils__TransferToZero");
  });

  it("Successful ETH withdrawal by user", async function () {
    // Calculate fee
    const initFee = calculateInitFee(Const.ETH_ADDRESS);
    await ENV.vault.initToken(Const.ETH_ADDRESS, { value: initFee });
    const deposit = await prepareDeposit({
      token: Const.ETH_ADDRESS, 
      amount,
      senderL1: aliceAddress,
      recipientL2: Const.ALICE_L2_ADDRESS
    });

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
    await expect(aliceStarkway.withdrawFunds(
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
    const initFee = calculateInitFee(Const.ETH_ADDRESS);
    await ENV.vault.initToken(Const.ETH_ADDRESS, { value: initFee });
    const deposit = await prepareDeposit({
      token: Const.ETH_ADDRESS, 
      amount,
      senderL1: aliceAddress,
      recipientL2: Const.ALICE_L2_ADDRESS
    });

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

describe("ETH Batch Withdrawal", function () {

  const aliceDeposit = Const.ONE_ETH
  const bobDeposit = Const.ONE_ETH.div(10)
  const charlieDeposit = Const.ONE_ETH.mul(7)

  let vaultAddress: string;
  let aliceAddress: string;
  let bobAddress: string;
  let charlieAddress: string;

  let withdrawalInfos: WithdrawalInfo[] = []

  beforeEach(async function () {
    await prepareUsers()
    await deployStarknetCoreMock()
    await deployStarkwayAndVault()

    vaultAddress = ENV.vault.address
    aliceAddress = await ENV.alice.getAddress()
    bobAddress = await ENV.bob.getAddress()
    charlieAddress = await ENV.charlie.getAddress()

    const initFee = await calculateInitFee(Const.ETH_ADDRESS)
    await ENV.vault.initToken(Const.ETH_ADDRESS, { value: initFee })

    const depositInfos: DepositInfo[] = [
      { user: ENV.alice, depositAmount: aliceDeposit },
      { user: ENV.bob, depositAmount: bobDeposit },
      { user: ENV.charlie, depositAmount: charlieDeposit }
    ]

    withdrawalInfos = []
    for (const info of depositInfos) {
      const { user, depositAmount } = info
      
      // Prepare
      const userAddress = await user.getAddress()
      const userStarkway = ENV.starkwayContract.connect(user)

      // Make deposit for a user
      const depositParams = await prepareDeposit({
        token: Const.ETH_ADDRESS,
        amount: depositAmount,
        senderL1: userAddress,
        recipientL2: Const.ALICE_L2_ADDRESS
      })
      await userStarkway.depositFunds(
        Const.ETH_ADDRESS, 
        Const.ALICE_L2_ADDRESS, 
        depositParams.depositAmount,
        depositParams.feeAmount,
        depositParams.starknetFee,
        { value: depositParams.msgValue }
      )

      // Prepare info for withdrawal
      const withdrawalInfo: WithdrawalInfo = {
        token: Const.ETH_ADDRESS,
        recipientAddressL1: userAddress,
        senderAddressL2: Const.ALICE_L2_ADDRESS,
        amount: depositParams.depositAmount
      }
      withdrawalInfos.push(
        withdrawalInfo
      )
      // Place L2-to-L1 message for the withdrawal
      const payload = [
        Const.ETH_ADDRESS,
        userAddress,
        Const.ALICE_L2_ADDRESS,
        depositParams.depositAmount,
        0
      ]
      await ENV.starknetCoreMock.addL2ToL1Message(
        Const.STARKWAY_L2_ADDRESS,
        ENV.starkwayContract.address,
        payload
      )
    }

    await ENV.starknetCoreMock.resetCounters()
  })

  it("Process ERC20 withdrawals in a batch", async function () {
    // Snapshot balances before
    const aliceBalanceBefore = await ethers.provider.getBalance(aliceAddress)
    const bobBalanceBefore = await ethers.provider.getBalance(bobAddress)
    const charlieBalanceBefore = await ethers.provider.getBalance(charlieAddress)
    const vaultBalanceBefore = await ethers.provider.getBalance(vaultAddress)

    // Execute batch withdrawal
    await ENV.starkwayContract.connect(ENV.admin)
      .processWithdrawalsBatch(withdrawalInfos)

    // Snapshot balances after
    const aliceBalanceAfter = await ethers.provider.getBalance(aliceAddress)
    const bobBalanceAfter = await ethers.provider.getBalance(bobAddress)
    const charlieBalanceAfter = await ethers.provider.getBalance(charlieAddress)
    const vaultBalanceAfter = await ethers.provider.getBalance(vaultAddress)
    
    // Validate balances
    expect(aliceBalanceAfter).to.be.eq(aliceBalanceBefore.add(aliceDeposit))
    expect(bobBalanceAfter).to.be.eq(bobBalanceBefore.add(bobDeposit))
    expect(charlieBalanceAfter).to.be.eq(charlieBalanceBefore.add(charlieDeposit))
    expect(vaultBalanceAfter).to.be.eq(
      vaultBalanceBefore
        .sub(aliceDeposit)
        .sub(bobDeposit)
        .sub(charlieDeposit)
    )
  })

  it("Process ERC20 withdrawals in a reversed batch", async function () {
    // Snapshot balances before
    const aliceBalanceBefore = await ethers.provider.getBalance(aliceAddress)
    const bobBalanceBefore = await ethers.provider.getBalance(bobAddress)
    const charlieBalanceBefore = await ethers.provider.getBalance(charlieAddress)
    const vaultBalanceBefore = await ethers.provider.getBalance(vaultAddress)

    // Execute batch withdrawal
    await ENV.starkwayContract.connect(ENV.admin)
      .processWithdrawalsBatch(withdrawalInfos.reverse())

    // Snapshot balances after
    const aliceBalanceAfter = await ethers.provider.getBalance(aliceAddress)
    const bobBalanceAfter = await ethers.provider.getBalance(bobAddress)
    const charlieBalanceAfter = await ethers.provider.getBalance(charlieAddress)
    const vaultBalanceAfter = await ethers.provider.getBalance(vaultAddress)
    
    // Validate balances
    expect(aliceBalanceAfter).to.be.eq(aliceBalanceBefore.add(aliceDeposit))
    expect(bobBalanceAfter).to.be.eq(bobBalanceBefore.add(bobDeposit))
    expect(charlieBalanceAfter).to.be.eq(charlieBalanceBefore.add(charlieDeposit))
    expect(vaultBalanceAfter).to.be.eq(
      vaultBalanceBefore
        .sub(aliceDeposit)
        .sub(bobDeposit)
        .sub(charlieDeposit)
    )
  })

  it("Only Admin can execute batch withdrawal", async function () {
    await expect(
      ENV.starkwayContract.connect(ENV.rogue).processWithdrawalsBatch(withdrawalInfos)
    )
      .to
      .be
      .revertedWithCustomError(ENV.starkwayContract, 'OwnableUnauthorizedAccount')
  })
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
