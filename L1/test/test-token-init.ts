import { ethers } from 'hardhat';
import { expect } from 'chai';
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
import { StarkwayVault } from '../typechain-types';

//////////////////////////
// Initialization Tests //
//////////////////////////

describe("Token/ETH initialization", function () {
  const depositAmount = tokenAmount(1_000);
  let vault: StarkwayVault;
  let tokenAddress: string;
  let aliceAddress: string;

  beforeEach(async function () {
    // Deploy
    await prepareUsers();
    await deployStarknetCoreMock();
    await deployStarkwayAndVault();
    await deployTestToken();
    // Set variables
    vault = ENV.vault;
    tokenAddress = ENV.testToken.address;
    aliceAddress = await ENV.alice.getAddress();
    // Mint tokens
    await ENV.testToken.mint(aliceAddress, depositAmount.mul(2));
  });

  it("Standalone token init (by admin)", async function () {
    // Check initial Starkway state
    expect(await vault.numberOfSupportedTokens()).to.be.eq(0);
    expect(await vault.isTokenInitialized(ENV.testToken.address)).to.be.eq(false);

    // Initialize token by ENV.admin
    const initFee = await calculateInitFee(ENV.testToken.address);
    await expect(vault.connect(ENV.admin).initToken(ENV.testToken.address, { value: initFee }))
      .to.emit(vault, "TokenInitialized")

    // Check updated Starkway state
    expect(await vault.numberOfSupportedTokens()).to.be.eq(1);
    expect(await vault.isTokenInitialized(ENV.testToken.address)).to.be.eq(true);

    // Check StarknetCoreMock state
    expect(await ENV.starknetCoreMock.invokedSendMessageToL2Count()).to.be.eq(1);
  });

  it("Standalone token init (by any user)", async function () {
    // Check initial Starkway state
    expect(await vault.numberOfSupportedTokens()).to.be.eq(0);
    expect(await vault.isTokenInitialized(ENV.testToken.address)).to.be.eq(false);

    // Initialize token by ENV.alice
    const initFee = await calculateInitFee(ENV.testToken.address);
    await expect(vault.connect(ENV.alice).initToken(ENV.testToken.address, { value: initFee }))
      .to.emit(vault, "TokenInitialized")

    // Check updated Starkway state
    expect(await vault.numberOfSupportedTokens()).to.be.eq(1);
    expect(await vault.isTokenInitialized(ENV.testToken.address)).to.be.eq(true);

    // Check StarknetCoreMock state
    expect(await ENV.starknetCoreMock.invokedSendMessageToL2Count()).to.be.eq(1);
  });

  it("Standalone ETH init (by admin)", async function () {
    // Check initial Starkway state
    expect(await vault.numberOfSupportedTokens()).to.be.eq(0);
    expect(await vault.isTokenInitialized(Const.ETH_ADDRESS)).to.be.eq(false);

    // Initialize token by ENV.admin
    const initFee = await calculateInitFee(ENV.testToken.address);
    await expect(vault.connect(ENV.admin).initToken(Const.ETH_ADDRESS, { value: initFee }))
      .to.emit(vault, "TokenInitialized")

    // Check updated Starkway state
    expect(await vault.numberOfSupportedTokens()).to.be.eq(1);
    expect(await vault.isTokenInitialized(Const.ETH_ADDRESS)).to.be.eq(true);

    // Check StarknetCoreMock state
    expect(await ENV.starknetCoreMock.invokedSendMessageToL2Count()).to.be.eq(1);
  });

  it("Standalone ETH init by some user", async function () {
    // Check initial Starkway state
    expect(await vault.numberOfSupportedTokens()).to.be.eq(0);
    expect(await vault.isTokenInitialized(Const.ETH_ADDRESS)).to.be.eq(false);

    // Initialize token by ENV.admin
    const initFee = await calculateInitFee(ENV.testToken.address);
    await expect(vault.connect(ENV.alice).initToken(Const.ETH_ADDRESS, { value: initFee }))
      .to.emit(vault, "TokenInitialized")

    // Check updated Starkway state
    expect(await vault.numberOfSupportedTokens()).to.be.eq(1);
    expect(await vault.isTokenInitialized(Const.ETH_ADDRESS)).to.be.eq(true);

    // Check StarknetCoreMock state
    expect(await ENV.starknetCoreMock.invokedSendMessageToL2Count()).to.be.eq(1);
  });

  it("NOT possible to init Token twice", async function () {
    // Init TestToken
    const initFee = await calculateInitFee(ENV.testToken.address);
    await vault.initToken(ENV.testToken.address, { value: initFee });

    // Check token is initialized
    expect(await vault.isTokenInitialized(ENV.testToken.address)).to.be.eq(true);

    await expect(vault.initToken(ENV.testToken.address, { value: initFee }))
      .to.be.revertedWithCustomError(vault, "StarkwayVault__TokenAlreadyInitialized");
  });

  it("NOT possible to init ETH twice", async function () {
    // Init TestToken
    const initFee = await calculateInitFee(ENV.testToken.address);
    await vault.initToken(Const.ETH_ADDRESS, { value: initFee });

    // Check token is initialized
    expect(await vault.isTokenInitialized(Const.ETH_ADDRESS)).to.be.eq(true);

    await expect(vault.initToken(Const.ETH_ADDRESS, { value: initFee }))
      .to.be.revertedWithCustomError(vault, "StarkwayVault__TokenAlreadyInitialized");
  });
});
