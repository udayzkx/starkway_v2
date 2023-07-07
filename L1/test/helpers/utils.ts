import { ethers } from 'hardhat';
import { expect } from 'chai'
import { Signer, BigNumber, BigNumberish } from 'ethers';
import { 
  IStarkwayGeneral, 
  Starkway, 
  StarkwayHelper, 
  StarknetCoreMock, 
  TestToken, 
  StarknetCoreMock__factory, 
  TestToken__factory, 
  MaliciousToken__factory,
  MaliciousToken,
  StarkwayVault,
  StarkwayVault__factory
} from "../../typechain-types";
import { Starkway__factory, StarkwayHelper__factory  } from "../../typechain-types";
import { TokenInfo, TokenInfoShort } from './models'
import * as Const from './constants';
import { ENV } from './env';

export async function prepareUsers() {
  [ENV.admin, ENV.alice, ENV.bob, ENV.rogue] = await ethers.getSigners();
}

export async function deployStarknetCoreMock(deployer: Signer = ENV.admin): Promise<StarknetCoreMock> {
  const factory = new StarknetCoreMock__factory(deployer);
  const mock = await factory.deploy();
  await mock.deployed();
  ENV.starknetCoreMock = mock;
  return mock;
}

export async function deployStarkwayAndVault(
  deployer: Signer = ENV.admin,
  vaultAddressL2: BigNumber = Const.STARKWAY_L2_ADDRESS,
  vaultConnectionDelay: BigNumberish = Const.TESTING_CONNECTION_DELAY,
  starknetAddress: string = ENV.starknetCoreMock.address,
  starkwayL2Address: BigNumber = Const.STARKWAY_L2_ADDRESS,
  defaultDepositFeeRate: BigNumber = Const.DEFAULT_DEPOSIT_FEE
): Promise<void> {
  const vault = await deployVault(
    deployer,
    starknetAddress,
    vaultAddressL2,
    vaultConnectionDelay
  );
  const starkway = await deployStarkway(
    deployer,
    starknetAddress,
    vault.address,
    starkwayL2Address,
    defaultDepositFeeRate
  );
  await connectStarkwayToVault(
    deployer, 
    vault.address, 
    starkway.address, 
    vaultConnectionDelay
  );
}

export async function deployVault(
  deployer: Signer = ENV.admin,
  starknetAddress: string = ENV.starknetCoreMock.address,
  vaultAddressL2: BigNumber = Const.STARKWAY_L2_ADDRESS,
  vaultConnectionDelay: BigNumberish = Const.TESTING_CONNECTION_DELAY
): Promise<StarkwayVault> {
  const factory = new StarkwayVault__factory(deployer);
  const vault = await factory.deploy(
    starknetAddress,
    vaultAddressL2,
    vaultConnectionDelay
  );
  await vault.deployed();
  ENV.vault = vault;
  return vault;
}

export async function connectStarkwayToVault(
  signer: Signer = ENV.admin,
  vaultAddress: string = ENV.vault.address,
  starkwayAddress: string = ENV.starkwayContract.address,
  vaultConnectionDelay: BigNumberish = Const.TESTING_CONNECTION_DELAY
): Promise<void> {
  const vault = StarkwayVault__factory.connect(vaultAddress, signer);
  await vault.startConnectionProcess(starkwayAddress);
  await fastForwardEVM(vaultConnectionDelay);
  await vault.finalizeConnectionProcess(starkwayAddress);
}

export async function deployStarkway(
  deployer: Signer = ENV.admin,
  starknetAddress: string = ENV.starknetCoreMock.address,
  vaultAddress: string = ENV.vault.address,
  starkwayL2Address: BigNumber = Const.STARKWAY_L2_ADDRESS,
  defaultDepositFeeRate: BigNumber = Const.DEFAULT_DEPOSIT_FEE
): Promise<Starkway> {
  const factory = new Starkway__factory(deployer);
  const contract = await factory.deploy(
    vaultAddress,
    starknetAddress,
    starkwayL2Address,
    defaultDepositFeeRate
  );
  await contract.deployed();
  ENV.starkwayContract = contract;
  return contract;
}

export async function deployStarkwayHelper(deployer: Signer = ENV.admin): Promise<StarkwayHelper> {  
  const factory = new StarkwayHelper__factory(deployer);
  const contract = await factory.deploy();
  await contract.deployed();
  ENV.starkwayHelper = contract;
  return contract;
}

export async function deployTestToken(
  deployer: Signer = ENV.admin,
  name: string = "USDTT Token",
  symbol: string = "USDTT",
  decimals: number = 6
): Promise<TestToken> {
  const factory = new TestToken__factory(deployer);
  const token = await factory.deploy(name, symbol, decimals);
  await token.deployed();
  ENV.testToken = token;
  return token;
}

export async function deployMaliciousToken(
  deployer: Signer,
  name: string,
  symbol: string,
  decimals: number
): Promise<MaliciousToken> {
  const factory = new MaliciousToken__factory(deployer);
  const token = await factory.deploy(name, symbol, decimals);
  await token.deployed();
  return token;
}

export function feeSegment(
  toAmount: BigNumberish, 
  feeRate: BigNumberish
): IStarkwayGeneral.FeeSegmentStruct {
  return { 
    toAmount, 
    feeRate 
  };
}

export type DepositParams = {
  depositAmount: BigNumber;
  feeAmount: BigNumber;
  totalAmount: BigNumber;
  starknetFee: BigNumber;
  msgValue: BigNumber;
};

export function prepareDeposit(
  token_: string,
  depositAmount_: BigNumberish, 
  feeAmount_: BigNumberish,
  starknetFee_: BigNumberish
): DepositParams {
  const depositAmount = BigNumber.from(depositAmount_);
  const feeAmount = BigNumber.from(feeAmount_);
  const totalAmount = depositAmount.add(feeAmount);
  const starknetFee = BigNumber.from(starknetFee_);
  const msgValue = token_ == Const.ETH_ADDRESS ? totalAmount.add(starknetFee) : starknetFee;
  return {
    depositAmount,
    feeAmount,
    totalAmount,
    starknetFee,
    msgValue
  };
}

export function tokenAmount(amount: number, decimals = 6): BigNumber {
  const unitAmount = BigNumber.from(Math.pow(10, decimals));
  return BigNumber.from(amount).mul(unitAmount);
}

export function prepareTokenMetadata(index: number) {
  return {
    name: "USDTT name " + index,
    symbol: "USDTT_" + index,
    decimals: 18
  }
}

export function prepareUserTokenBalance(index: number): BigNumber {
  if (index % 3 == 0) {
    return tokenAmount(1000);
  } else {
    return Const.BN_ZERO;
  }
}

export function validateTokenInfoEqual(tokenInfo: TokenInfo, expectedInfo: TokenInfo) {
  expect(tokenInfo.token).to.be.eq(expectedInfo.token);
  expect(tokenInfo.balance).to.be.eq(expectedInfo.balance);
  expect(tokenInfo.decimals).to.be.eq(expectedInfo.decimals);
  expect(tokenInfo.symbol).to.be.eq(expectedInfo.symbol);
  expect(tokenInfo.name).to.be.eq(expectedInfo.name);
}

export function validateTokenInfoEqualShort(tokenInfo: TokenInfoShort, expectedInfo: TokenInfoShort) {
  expect(tokenInfo.token).to.be.eq(expectedInfo.token);
  expect(tokenInfo.balance).to.be.eq(expectedInfo.balance);
}

export async function fastForwardEVM(seconds: BigNumberish) {
  await ethers.provider.send("evm_increaseTime", [seconds]);
  await ethers.provider.send("evm_mine", []);
}
