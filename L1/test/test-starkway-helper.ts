import { expect } from 'chai';
import { TokenInfo } from './helpers/models'
import { 
  prepareUsers, 
  deployStarknetCoreMock, 
  tokenAmount,
  deployStarkwayAndVault,
  deployTestToken, 
  deployStarkwayHelper,
  prepareUserTokenBalance,
  prepareTokenMetadata,
  validateTokenInfoEqual,
  validateTokenInfoEqualShort,
  calculateInitFee,
} from './helpers/utils';
import { ENV } from './helpers/env';
import { StarkwayHelper } from '../typechain-types';

//////////////////////////
// StarkwayHelper Tests //
//////////////////////////

describe("StarkwayHelper with many tokens", function () {

  const TOKENS_COUNT = 20;
  let aliceAddress: string;
  let bobAddress: string;
  let vaultAddress: string;
  let helper: StarkwayHelper;
  let expectedTokens: TokenInfo[] = [];

  beforeEach(async function () {
    expectedTokens = [];
    // Deploy instrastructure
    await prepareUsers();
    await deployStarknetCoreMock();
    await deployStarkwayAndVault();
    await deployStarkwayHelper();

    aliceAddress = await ENV.alice.getAddress();
    bobAddress = await ENV.bob.getAddress();
    vaultAddress = ENV.vault.address;
    helper = ENV.starkwayHelper;

    // Deploy, init and mint tokens
    for (let i = 0; i != TOKENS_COUNT; i++) {
      // Prepare token parameters
      const metadata = prepareTokenMetadata(i);
      const balance = prepareUserTokenBalance(i);
      // Deploy and init token
      const token = await deployTestToken(ENV.admin, metadata.name, metadata.symbol, metadata.decimals);
      const initFee = await calculateInitFee(token.address);
      await ENV.vault.initToken(token.address, { value: initFee });

      if (balance.gt(0)) {
        // Mint tokens to user
        await token.mint(aliceAddress, balance);
        // Store token parameters for validation
        const tokenInfo = {
          token: token.address,
          name: metadata.name,
          symbol: metadata.symbol,
          decimals: metadata.decimals,
          balance: balance
        };
        expectedTokens.push(tokenInfo);
      }
    }
  });

  it("Return many tokens", async function () {
    // Fetch Alice's tokens
    const tokens = await helper.getSupportedTokensWithBalance(vaultAddress, aliceAddress);
    // Validate token list
    expect(tokens.length).to.be.eq(expectedTokens.length);
    for (let i = 0; i != tokens.length; i++) {
      validateTokenInfoEqual(
        tokens[i],
        expectedTokens[i]
      );
    }
  });

  it("Return 0 tokens", async function () {
    // Fetch Bob's tokens (he has none)
    const tokens = await helper.getSupportedTokensWithBalance(vaultAddress, bobAddress);
    // Validate token list is empty
    expect(tokens.length).to.be.eq(0);
  });
});

describe("StarkwayHelper with ONE token", function () {

  let expectedInfo: TokenInfo;
  let aliceAddress: string;
  let vaultAddress: string;
  let helper: StarkwayHelper;

  beforeEach(async function () {
    // Deploy infrastructure
    await prepareUsers();
    await deployStarknetCoreMock();
    await deployStarkwayAndVault();
    await deployStarkwayHelper();

    // Set variables
    aliceAddress = await ENV.alice.getAddress();
    vaultAddress = ENV.vault.address;
    helper = ENV.starkwayHelper;

    // Deploy token and mint
    const metadata = prepareTokenMetadata(0);
    const token = await deployTestToken(ENV.admin, metadata.name, metadata.symbol, metadata.decimals);
    const initFee = await calculateInitFee(token.address);
    await ENV.vault.initToken(token.address, { value: initFee });
    const TOKEN_BALANCE = tokenAmount(1000);
    await token.mint(aliceAddress, TOKEN_BALANCE);
    // Prepare expected token info
    expectedInfo = {
      token: token.address,
      balance: TOKEN_BALANCE,
      decimals: metadata.decimals,
      symbol: metadata.symbol,
      name: metadata.name
    };
  });

  it("Return 1 token", async function () {
    // Fetch tokens
    const tokens = await helper.getSupportedTokensWithBalance(vaultAddress, aliceAddress);
    // Validate result
    expect(tokens.length).to.be.eq(1);
    validateTokenInfoEqual(tokens[0], expectedInfo);
  });
});
