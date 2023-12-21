import { ethers } from 'hardhat'
import { expect } from 'chai'
import { Starkway } from "../typechain-types"
import { BigNumber, BigNumberish } from 'ethers'
import * as Const from './helpers/constants'
import { 
  prepareUsers,
  deployStarknetCoreMock,
  deployStarkwayAndVault,
  prepareDeposit,
  calculateInitFee,
  splitUint256,
  DepositMessage,
  deployTestToken,
  tokenAmount,
} from './helpers/utils'
import { ENV } from './helpers/env'
import { 
  expectStarknetCalls, 
  expectL1ToL2Message, 
  expectDepositMessage, 
  expectPayloadToBeEqual
} from './helpers/expectations'

//////////////////
// ETH Deposits //
//////////////////

describe("Disabling Deposits", function () {
  const depositAmount = tokenAmount(10_000)
  let aliceStarkway: Starkway
  let adminStarkway: Starkway
  let aliceAddress: string
  let tokenAddress: string

  beforeEach(async function () {
    await prepareUsers()
    await deployStarknetCoreMock()
    await deployStarkwayAndVault()
    await deployTestToken()
    
    // Set variables
    tokenAddress = ENV.testToken.address
    aliceAddress = await ENV.alice.getAddress()
    aliceStarkway = ENV.starkwayContract.connect(ENV.alice)
    adminStarkway = ENV.starkwayContract.connect(ENV.admin)

    // Init ETH & test token in Vault
    const ethInitFee = await calculateInitFee(Const.ETH_ADDRESS)
    await ENV.vault.initToken(Const.ETH_ADDRESS, { value: ethInitFee })
    const initFee = await calculateInitFee(tokenAddress)
    await ENV.vault.initToken(tokenAddress, { value: initFee })

    // Mint tokens to Alice
    const mintAmount = depositAmount.mul(10)
    await ENV.testToken.mint(aliceAddress, mintAmount)
    await ENV.testToken.connect(ENV.alice).approve(ENV.vault.address, mintAmount)
    
    await ENV.starknetCoreMock.resetCounters()
  })

  it("Disable token deposits by Admin", async function () {
    // This deposit should succeed
    const depositParams = await prepareDeposit({
      token: tokenAddress, 
      amount: depositAmount,
      senderL1: aliceAddress,
      recipientL2: Const.ALICE_L2_ADDRESS
    })
    await aliceStarkway.depositFunds(
      tokenAddress,
      Const.ALICE_L2_ADDRESS,
      depositParams.depositAmount,
      depositParams.feeAmount,
      depositParams.starknetFee,
      { value: depositParams.msgValue }
    )

    // Admin disables deposits for the token
    await expect(adminStarkway.disableDepositsForToken(tokenAddress))
      .to.emit(ENV.starkwayContract, 'DepositsForTokenDisabled').withArgs(tokenAddress)
    
    // This deposit should fail
    await expect(aliceStarkway.depositFunds(
      tokenAddress,
      Const.ALICE_L2_ADDRESS,
      depositParams.depositAmount,
      depositParams.feeAmount,
      depositParams.starknetFee,
      { value: depositParams.msgValue }
    )).to.be.revertedWithCustomError(ENV.starkwayContract, 'TokenDepositsDisabled')

    // Admin enabled deposits back
    await expect(adminStarkway.enableDepositsForToken(tokenAddress))
      .to.emit(ENV.starkwayContract, 'DepositsForTokenEnabled').withArgs(tokenAddress)

    // Now this deposit should succeed
    await aliceStarkway.depositFunds(
      tokenAddress,
      Const.ALICE_L2_ADDRESS,
      depositParams.depositAmount,
      depositParams.feeAmount,
      depositParams.starknetFee,
      { value: depositParams.msgValue }
    )

    // Admin disabled deposits again
    await expect(adminStarkway.disableDepositsForToken(tokenAddress))
      .to.emit(ENV.starkwayContract, 'DepositsForTokenDisabled').withArgs(tokenAddress)

    // This deposit should fail
    await expect(aliceStarkway.depositFunds(
      tokenAddress,
      Const.ALICE_L2_ADDRESS,
      depositParams.depositAmount,
      depositParams.feeAmount,
      depositParams.starknetFee,
      { value: depositParams.msgValue }
    )).to.be.revertedWithCustomError(ENV.starkwayContract, 'TokenDepositsDisabled')
  })

  it("Disable ETH deposits by Admin", async function () {
    // This deposit should succeed
    const depositParams = await prepareDeposit({
      token: Const.ETH_ADDRESS, 
      amount: Const.ONE_ETH,
      senderL1: aliceAddress,
      recipientL2: Const.ALICE_L2_ADDRESS
    })
    await aliceStarkway.depositFunds(
      Const.ETH_ADDRESS,
      Const.ALICE_L2_ADDRESS,
      depositParams.depositAmount,
      depositParams.feeAmount,
      depositParams.starknetFee,
      { value: depositParams.msgValue }
    )

    // Admin disables deposits for the token
    await expect(adminStarkway.disableDepositsForToken(Const.ETH_ADDRESS))
      .to.emit(ENV.starkwayContract, 'DepositsForTokenDisabled').withArgs(Const.ETH_ADDRESS)
    
    // This deposit should fail
    await expect(aliceStarkway.depositFunds(
      Const.ETH_ADDRESS,
      Const.ALICE_L2_ADDRESS,
      depositParams.depositAmount,
      depositParams.feeAmount,
      depositParams.starknetFee,
      { value: depositParams.msgValue }
    )).to.be.revertedWithCustomError(ENV.starkwayContract, 'TokenDepositsDisabled')

    // Admin enabled deposits back
    await expect(adminStarkway.enableDepositsForToken(Const.ETH_ADDRESS))
      .to.emit(ENV.starkwayContract, 'DepositsForTokenEnabled').withArgs(Const.ETH_ADDRESS)

    // Now this deposit should succeed
    await aliceStarkway.depositFunds(
      Const.ETH_ADDRESS,
      Const.ALICE_L2_ADDRESS,
      depositParams.depositAmount,
      depositParams.feeAmount,
      depositParams.starknetFee,
      { value: depositParams.msgValue }
    )

    // Admin disabled deposits again
    await expect(adminStarkway.disableDepositsForToken(Const.ETH_ADDRESS))
      .to.emit(ENV.starkwayContract, 'DepositsForTokenDisabled').withArgs(Const.ETH_ADDRESS)

    // This deposit should fail
    await expect(aliceStarkway.depositFunds(
      Const.ETH_ADDRESS,
      Const.ALICE_L2_ADDRESS,
      depositParams.depositAmount,
      depositParams.feeAmount,
      depositParams.starknetFee,
      { value: depositParams.msgValue }
    )).to.be.revertedWithCustomError(ENV.starkwayContract, 'TokenDepositsDisabled')
  })

  it("Only admin can disable deposits", async function () {
    const rogueStarkway = ENV.starkwayContract.connect(ENV.rogue)

    await expect(rogueStarkway.disableDepositsForToken(tokenAddress))
      .to
      .be
      .revertedWithCustomError(ENV.starkwayContract, 'OwnableUnauthorizedAccount')

    await expect(rogueStarkway.disableDepositsForToken(Const.ETH_ADDRESS))
      .to
      .be
      .revertedWithCustomError(ENV.starkwayContract, 'OwnableUnauthorizedAccount')
  })

  it("Only admin can enable deposits", async function () {
    const rogueStarkway = ENV.starkwayContract.connect(ENV.rogue)

    await expect(rogueStarkway.enableDepositsForToken(tokenAddress))
      .to
      .be
      .revertedWithCustomError(ENV.starkwayContract, 'OwnableUnauthorizedAccount')

    await expect(rogueStarkway.enableDepositsForToken(Const.ETH_ADDRESS))
      .to
      .be
      .revertedWithCustomError(ENV.starkwayContract, 'OwnableUnauthorizedAccount')
  })
})
