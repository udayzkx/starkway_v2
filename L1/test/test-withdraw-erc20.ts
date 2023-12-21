import { expect } from 'chai';
import { IStarkwayAuthorized, Starkway } from "../typechain-types";
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

    await ENV.testToken.mint(aliceAddress, amount.mul(2));
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
    const depositParams = await prepareDeposit({
      token: tokenAddress, 
      amount,
      senderL1: aliceAddress,
      recipientL2: Const.ALICE_L2_ADDRESS
    });
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

  it("Successful ERC20 batch withdrawal by admin", async function () {
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

describe("ERC20 Batch Withdrawal", function () {

  const aliceDeposit = tokenAmount(10_000)
  const bobDeposit = tokenAmount(3_333)
  const charlieDeposit = tokenAmount(1_795_000)

  let tokenAddress: string;
  let vaultAddress: string;
  let aliceAddress: string;
  let bobAddress: string;
  let charlieAddress: string;

  let withdrawalInfos: WithdrawalInfo[] = []

  beforeEach(async function () {
    await prepareUsers()
    await deployStarknetCoreMock()
    await deployStarkwayAndVault()
    await deployTestToken()

    tokenAddress = ENV.testToken.address
    vaultAddress = ENV.vault.address
    aliceAddress = await ENV.alice.getAddress()
    bobAddress = await ENV.bob.getAddress()
    charlieAddress = await ENV.charlie.getAddress()

    const initFee = await calculateInitFee(tokenAddress)
    await ENV.vault.initToken(tokenAddress, { value: initFee })

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
      const mintAmount = depositAmount.mul(2)
      const userStarkway = ENV.starkwayContract.connect(user)
      await ENV.testToken.mint(userAddress, mintAmount)
      await ENV.testToken.connect(user).approve(ENV.vault.address, mintAmount)

      // Make deposit for a user
      const depositParams = await prepareDeposit({
        token: tokenAddress,
        amount: depositAmount,
        senderL1: userAddress,
        recipientL2: Const.ALICE_L2_ADDRESS
      })
      await userStarkway.depositFunds(
        tokenAddress, 
        Const.ALICE_L2_ADDRESS, 
        depositParams.depositAmount,
        depositParams.feeAmount,
        depositParams.starknetFee,
        { value: depositParams.msgValue }
      )

      // Prepare info for withdrawal
      const withdrawalInfo: WithdrawalInfo = {
        token: tokenAddress,
        recipientAddressL1: userAddress,
        senderAddressL2: Const.ALICE_L2_ADDRESS,
        amount: depositParams.depositAmount
      }
      withdrawalInfos.push(
        withdrawalInfo
      )
      // Place L2-to-L1 message for the withdrawal
      const payload = [
        tokenAddress,
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
    const aliceBalanceBefore = await ENV.testToken.balanceOf(aliceAddress)
    const bobBalanceBefore = await ENV.testToken.balanceOf(bobAddress)
    const charlieBalanceBefore = await ENV.testToken.balanceOf(charlieAddress)
    const vaultBalanceBefore = await ENV.testToken.balanceOf(vaultAddress)

    // Execute batch withdrawal
    await ENV.starkwayContract.connect(ENV.admin)
      .processWithdrawalsBatch(withdrawalInfos)

    // Snapshot balances after
    const aliceBalanceAfter = await ENV.testToken.balanceOf(aliceAddress)
    const bobBalanceAfter = await ENV.testToken.balanceOf(bobAddress)
    const charlieBalanceAfter = await ENV.testToken.balanceOf(charlieAddress)
    const vaultBalanceAfter = await ENV.testToken.balanceOf(vaultAddress)
    
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
    const aliceBalanceBefore = await ENV.testToken.balanceOf(aliceAddress)
    const bobBalanceBefore = await ENV.testToken.balanceOf(bobAddress)
    const charlieBalanceBefore = await ENV.testToken.balanceOf(charlieAddress)
    const vaultBalanceBefore = await ENV.testToken.balanceOf(vaultAddress)

    // Execute batch withdrawal
    await ENV.starkwayContract.connect(ENV.admin)
      .processWithdrawalsBatch(withdrawalInfos.reverse())

    // Snapshot balances after
    const aliceBalanceAfter = await ENV.testToken.balanceOf(aliceAddress)
    const bobBalanceAfter = await ENV.testToken.balanceOf(bobAddress)
    const charlieBalanceAfter = await ENV.testToken.balanceOf(charlieAddress)
    const vaultBalanceAfter = await ENV.testToken.balanceOf(vaultAddress)
    
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
