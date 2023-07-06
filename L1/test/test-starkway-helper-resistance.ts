import { expect } from 'chai';
import { TokenInfo, TokenMetadata } from './helpers/models'
import { 
  prepareUsers, 
  deployStarknetCoreMock,
  deployStarkwayAndVault,
  deployTestToken, 
  deployStarkwayHelper,
  prepareUserTokenBalance,
  prepareTokenMetadata,
  validateTokenInfoEqual,
  deployMaliciousToken,
} from './helpers/utils';
import * as Const from './helpers/constants';
import { ENV } from './helpers/env';
import { MaliciousToken, StarkwayHelper } from '../typechain-types';
import { ethers } from 'hardhat';

///////////////////////////////
// StarkwayHelper Resistance //
///////////////////////////////

describe("StarkwayHelper with Malicious Tokens", function () {

  const TOKENS_COUNT = 10;
  let aliceAddress: string;
  let vaultAddress: string;
  let helper: StarkwayHelper;

  beforeEach(async function () {
    // Deploy instrastructure
    await prepareUsers();
    await deployStarknetCoreMock();
    await deployStarkwayAndVault();
    await deployStarkwayHelper();
    aliceAddress = await ENV.alice.getAddress();
    vaultAddress = ENV.vault.address;
    helper = ENV.starkwayHelper;
  });

  it("Resistant to revert of IERC20.balanceOf() call", async function () {
    // Given
    const maliciousToken = await initMaliciousToken(maliciousMeta);
    await maliciousToken.setBalanceActionTo(Action.Revert);
    const ethToken = await initETH();
    const testTokens = await initTestTokens(TOKENS_COUNT);
    const expectedTokens: TokenInfo[] = [ethToken, ...testTokens];

    // When
    const responseTokens = await helper.getSupportedTokensWithBalance(vaultAddress, aliceAddress);
    
    // Then
    expect(responseTokens.length).to.be.eq(expectedTokens.length);
    for (let i = 0; i != responseTokens.length; i++) {
      validateTokenInfoEqual(
        responseTokens[i],
        expectedTokens[i]
      );
    }
  });

  it("Resistant to revert of IERC20.name() call", async function () {
    // Given
    const maliciousToken = await initMaliciousToken(maliciousMeta);
    await maliciousToken.setNameActionTo(Action.Revert);
    const ethToken = await initETH();
    const testTokens = await initTestTokens(TOKENS_COUNT);
    const expectedTokens: TokenInfo[] = [ethToken, ...testTokens];

    // When
    const responseTokens = await helper.getSupportedTokensWithBalance(vaultAddress, aliceAddress);
    
    // Then
    expect(responseTokens.length).to.be.eq(expectedTokens.length);
    for (let i = 0; i != responseTokens.length; i++) {
      validateTokenInfoEqual(
        responseTokens[i],
        expectedTokens[i]
      );
    }
  });

  it("Resistant to revert of IERC20.symbol() call", async function () {
    // Given
    const maliciousToken = await initMaliciousToken(maliciousMeta);
    await maliciousToken.setSymbolActionTo(Action.Revert);
    const ethToken = await initETH();
    const testTokens = await initTestTokens(TOKENS_COUNT);
    const expectedTokens: TokenInfo[] = [ethToken, ...testTokens];

    // When
    const responseTokens = await helper.getSupportedTokensWithBalance(vaultAddress, aliceAddress);
    
    // Then
    expect(responseTokens.length).to.be.eq(expectedTokens.length);
    for (let i = 0; i != responseTokens.length; i++) {
      validateTokenInfoEqual(
        responseTokens[i],
        expectedTokens[i]
      );
    }
  });

  it("Resistant to revert of IERC20.decimals() call", async function () {
    const maliciousToken = await initMaliciousToken(maliciousMeta);
    await maliciousToken.setDecimalsActionTo(Action.Revert);
    const ethToken = await initETH();
    const testTokens = await initTestTokens(TOKENS_COUNT);
    const expectedTokens: TokenInfo[] = [ethToken, ...testTokens];

    // When
    const responseTokens = await helper.getSupportedTokensWithBalance(vaultAddress, aliceAddress);
    
    // Then
    expect(responseTokens.length).to.be.eq(expectedTokens.length);
    for (let i = 0; i != responseTokens.length; i++) {
      validateTokenInfoEqual(
        responseTokens[i],
        expectedTokens[i]
      );
    }
  });

  it("Resistant to revert of all IERC20Metadata calls", async function () {
    const maliciousToken = await initMaliciousToken(maliciousMeta);
    await maliciousToken.setNameActionTo(Action.Revert);
    await maliciousToken.setSymbolActionTo(Action.Revert);
    await maliciousToken.setDecimalsActionTo(Action.Revert);

    const ethToken = await initETH();
    const testTokens = await initTestTokens(TOKENS_COUNT);
    const expectedTokens: TokenInfo[] = [ethToken, ...testTokens];

    // When
    const responseTokens = await helper.getSupportedTokensWithBalance(vaultAddress, aliceAddress);
    
    // Then
    expect(responseTokens.length).to.be.eq(expectedTokens.length);
    for (let i = 0; i != responseTokens.length; i++) {
      validateTokenInfoEqual(
        responseTokens[i],
        expectedTokens[i]
      );
    }
  });

  it("Resistant to 100 infinite loop tokens", async function () {
    // Given
    const MALICIOUS_COUNT = 100;
    const MALICIOUS_HALF_COUNT = MALICIOUS_COUNT / 2;
    for (let i = 0; i != MALICIOUS_HALF_COUNT / 2; i++) {
      const maliciousToken = await initMaliciousToken(maliciousMeta);
      await maliciousToken.setNameActionTo(Action.InfiniteLoop);
      await maliciousToken.setSymbolActionTo(Action.InfiniteLoop);
      await maliciousToken.setDecimalsActionTo(Action.InfiniteLoop);
    }
    const ethToken = await initETH();
    const testTokens = await initTestTokens(TOKENS_COUNT);
    const expectedTokens: TokenInfo[] = [ethToken, ...testTokens];
    for (let i = 0; i != MALICIOUS_HALF_COUNT / 2; i++) {
      const maliciousToken = await initMaliciousToken(maliciousMeta);
      await maliciousToken.setNameActionTo(Action.InfiniteLoop);
      await maliciousToken.setSymbolActionTo(Action.InfiniteLoop);
      await maliciousToken.setDecimalsActionTo(Action.InfiniteLoop);
    }

    // When
    const responseTokens = await helper.getSupportedTokensWithBalance(vaultAddress, aliceAddress);
    
    // Then
    expect(responseTokens.length).to.be.eq(expectedTokens.length);
    for (let i = 0; i != responseTokens.length; i++) {
      validateTokenInfoEqual(
        responseTokens[i],
        expectedTokens[i]
      );
    }
  });
});

/////////////
// Helpers //
/////////////

enum Action {
  Normal = 0,
  Revert = 1,
  InfiniteLoop = 2,
}

const maliciousMeta: TokenMetadata = {
  name: 'Malicious',
  symbol: 'Mal',
  decimals: 18.
}

async function initMaliciousToken(meta: TokenMetadata): Promise<MaliciousToken> {
  const maliciousToken = await deployMaliciousToken(ENV.admin, meta.name, meta.symbol, meta.decimals);
  const initFee = ENV.vault.calculateInitializationFee(maliciousToken.address);
  await ENV.vault.initToken(maliciousToken.address, { value: initFee });
  return maliciousToken;
}

async function initETH(): Promise<TokenInfo> {
  const aliceEthBalance = await ethers.provider.getBalance(ENV.alice.getAddress());
  const initFee = ENV.vault.calculateInitializationFee(Const.ETH_ADDRESS);
  await ENV.vault.initToken(Const.ETH_ADDRESS, { value: initFee });
  return {
    token: Const.ETH_ADDRESS,
    balance: aliceEthBalance,
    name: 'Ethereum',
    symbol: 'ETH',
    decimals: 18,
  };
}

async function initTestTokens(count: number): Promise<TokenInfo[]> {
  let result: TokenInfo[] = [];
  for (let i = 0; i != count; i++) {
    // Prepare parameters
    const meta = prepareTokenMetadata(i);
    const balance = prepareUserTokenBalance(i);
    const aliceAddress = ENV.alice.getAddress();

    // Deploy & Init
    const token = await deployTestToken(ENV.admin, meta.name, meta.symbol, meta.decimals);
    const initFee = ENV.vault.calculateInitializationFee(token.address);
    await ENV.vault.initToken(token.address, { value: initFee });

    if (balance.gt(0)) {
      // Mint tokens to user
      await token.mint(aliceAddress, balance);
      // Store token parameters for validation
      const tokenInfo = {
        token: token.address,
        balance: balance,
        ...meta
      };
      result.push(tokenInfo);
    }
  }
  return result;
}
