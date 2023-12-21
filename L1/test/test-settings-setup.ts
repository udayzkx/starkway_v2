import { expect } from 'chai';
import { 
  prepareUsers, 
  deployStarknetCoreMock, 
  tokenAmount,
  deployStarkwayAndVault,
  deployTestToken,
  calculateInitFee, 
} from './helpers/utils';
import { TokenSettings } from './helpers/models';
import { ENV } from './helpers/env';

//////////////////////////
// Token Settings Setup //
//////////////////////////

describe("Token Settings Setup", function () {

  let tokenAddress: string;

  beforeEach(async function () {
    await prepareUsers();
    await deployStarknetCoreMock();
    await deployStarkwayAndVault();
    await deployTestToken();
    tokenAddress = ENV.testToken.address;
    const initFee = await calculateInitFee(tokenAddress);
    await ENV.vault.initToken(tokenAddress, { value: initFee });
  });

  it("Emits event", async function () {
    const settings = {
      minDeposit: tokenAmount(10),
      maxDeposit: tokenAmount(10_000_000),
      minFee: 0,
      maxFee: 0,
      useCustomFeeRate: false,
      feeSegments: []
    };
    await expect(ENV.starkwayContract.updateTokenSettings(
      tokenAddress,
      settings.minDeposit,
      settings.maxDeposit,
      settings.minFee,
      settings.maxFee,
      settings.useCustomFeeRate,
      settings.feeSegments
    ))
      .to.emit(ENV.starkwayContract, "TokenSettingsUpdate")
      .withArgs(tokenAddress);
  });

  it("Clear settings", async function () {
    // 1. Set settings
    const settings = {
      minDeposit: tokenAmount(10),
      maxDeposit: tokenAmount(10_000_000),
      minFee: tokenAmount(5),
      maxFee: tokenAmount(100),
      useCustomFeeRate: true,
      feeSegments: [
        { feeRate: 300, toAmount: tokenAmount(100) },
        { feeRate: 200, toAmount: tokenAmount(1_000) },
        { feeRate: 120, toAmount: tokenAmount(10_000) },
        { feeRate: 60, toAmount: tokenAmount(100_000) },
        { feeRate: 30, toAmount: tokenAmount(1_000_000) },
        { feeRate: 15, toAmount: tokenAmount(10_000_000) },
      ]
    };
    await testSettingsSuccess(settings);

    // 2. Clear settings
    await expect(ENV.starkwayContract.clearTokenSettings(tokenAddress))
      .to.emit(ENV.starkwayContract, "TokenSettingsUpdate")
      .withArgs(tokenAddress);

    // 3. Check settings were cleared
    const zeroSettings = {
      minDeposit: 0,
      maxDeposit: 0,
      minFee: 0,
      maxFee: 0,
      useCustomFeeRate: false,
      feeSegments: []
    };
    const fetchedSettings = await ENV.starkwayContract.getTokenSettings(tokenAddress);
    ensureSettingsEqual(zeroSettings, fetchedSettings);
  });

  it("Set 0-to-0 fee range", async function () {
    const settings = {
      minDeposit: tokenAmount(10),
      maxDeposit: tokenAmount(10_000_000),
      minFee: 0,
      maxFee: 0,
      useCustomFeeRate: false,
      feeSegments: []
    };
    await testSettingsSuccess(settings);
  });

  it("Set A-to-0 fee range", async function () {
    const settings = {
      minDeposit: tokenAmount(10),
      maxDeposit: tokenAmount(10_000_000),
      minFee: tokenAmount(5),
      maxFee: 0,
      useCustomFeeRate: false,
      feeSegments: []
    };
    await testSettingsSuccess(settings);
  });

  it("Set 0-to-B fee range", async function () {
    const settings = {
      minDeposit: tokenAmount(10),
      maxDeposit: tokenAmount(10_000_000),
      minFee: 0,
      maxFee: tokenAmount(100),
      useCustomFeeRate: false,
      feeSegments: []
    };
    await testSettingsSuccess(settings);
  });

  it("Set A-to-B fee range", async function () {
    const settings = {
      minDeposit: tokenAmount(10),
      maxDeposit: tokenAmount(10_000_000),
      minFee: tokenAmount(5),
      maxFee: tokenAmount(100),
      useCustomFeeRate: false,
      feeSegments: []
    };
    await testSettingsSuccess(settings);
  });

  it("Set 0-to-0 deposit range", async function () {
    const settings = {
      minDeposit: 0,
      maxDeposit: 0,
      minFee: 0,
      maxFee: tokenAmount(100),
      useCustomFeeRate: false,
      feeSegments: []
    };
    await testSettingsSuccess(settings);
  });

  it("Set A-to-0 deposit range", async function () {
    const settings = {
      minDeposit: tokenAmount(10),
      maxDeposit: 0,
      minFee: tokenAmount(5),
      maxFee: 0,
      useCustomFeeRate: false,
      feeSegments: []
    };
    await testSettingsSuccess(settings);
  });

  it("Set 0-to-B deposit range", async function () {
    const settings = {
      minDeposit: 0,
      maxDeposit: tokenAmount(10_000_000),
      minFee: 0,
      maxFee: 0,
      useCustomFeeRate: false,
      feeSegments: []
    };
    await testSettingsSuccess(settings);
  });

  it("Set A-to-B deposit range", async function () {
    const settings = {
      minDeposit: tokenAmount(10),
      maxDeposit: tokenAmount(10_000_000),
      minFee: tokenAmount(5),
      maxFee: tokenAmount(100),
      useCustomFeeRate: false,
      feeSegments: []
    };
    await testSettingsSuccess(settings);
  });

  it("Set single fee segment with 0 (unlimited) to-amount", async function () {
    const settings = {
      minDeposit: tokenAmount(10),
      maxDeposit: tokenAmount(10_000_000),
      minFee: tokenAmount(5),
      maxFee: tokenAmount(100),
      useCustomFeeRate: true,
      feeSegments: [
        { feeRate: 100, toAmount: tokenAmount(0) },
      ]
    };
    await testSettingsSuccess(settings);
  });

  it("Set single fee segment with specific to-amount", async function () {
    const settings = {
      minDeposit: tokenAmount(10),
      maxDeposit: tokenAmount(10_000_000),
      minFee: tokenAmount(5),
      maxFee: tokenAmount(100),
      useCustomFeeRate: true,
      feeSegments: [
        { feeRate: 100, toAmount: tokenAmount(10_000_000) },
      ]
    };
    await testSettingsSuccess(settings);
  });

  it("Set several segments, last one is limited", async function () {
    const settings = {
      minDeposit: tokenAmount(10),
      maxDeposit: tokenAmount(10_000_000),
      minFee: tokenAmount(5),
      maxFee: tokenAmount(100),
      useCustomFeeRate: true,
      feeSegments: [
        { feeRate: 300, toAmount: tokenAmount(100) },
        { feeRate: 200, toAmount: tokenAmount(1_000) },
        { feeRate: 120, toAmount: tokenAmount(10_000) },
        { feeRate: 60, toAmount: tokenAmount(100_000) },
        { feeRate: 30, toAmount: tokenAmount(1_000_000) },
        { feeRate: 15, toAmount: tokenAmount(10_000_000) },
      ]
    };
    await testSettingsSuccess(settings);
  });

  it("Set several segments, last one is unlimited", async function () {
    const settings = {
      minDeposit: tokenAmount(10),
      maxDeposit: tokenAmount(10_000_000),
      minFee: tokenAmount(5),
      maxFee: tokenAmount(100),
      useCustomFeeRate: true,
      feeSegments: [
        { feeRate: 300, toAmount: tokenAmount(100) },
        { feeRate: 200, toAmount: tokenAmount(1_000) },
        { feeRate: 120, toAmount: tokenAmount(10_000) },
        { feeRate: 60, toAmount: tokenAmount(100_000) },
        { feeRate: 30, toAmount: tokenAmount(1_000_000) },
        { feeRate: 15, toAmount: tokenAmount(0) },
      ]
    };
    await testSettingsSuccess(settings);
  });
});

export async function testSettingsSuccess(
  settings: TokenSettings,
  tokenAddress: string = ENV.testToken.address
) {
  // 1. Validate settings
  await ENV.starkwayContract.validateTokenSettings(
    tokenAddress,
    settings.minDeposit,
    settings.maxDeposit,
    settings.minFee,
    settings.maxFee,
    settings.useCustomFeeRate,
    settings.feeSegments
  );
  
  // 2. Update settings
  await ENV.starkwayContract.updateTokenSettings(
    tokenAddress,
    settings.minDeposit,
    settings.maxDeposit,
    settings.minFee,
    settings.maxFee,
    settings.useCustomFeeRate,
    settings.feeSegments
  );

  // 3. Fetch updated settings
  const fetchedSettings = await ENV.starkwayContract.getTokenSettings(tokenAddress);
  ensureSettingsEqual(settings, fetchedSettings);
}

export function ensureSettingsEqual(settings: TokenSettings, fetchedSettings: TokenSettings) {
  expect(settings.minDeposit).to.be.eq(fetchedSettings.minDeposit);
  expect(settings.maxDeposit).to.be.eq(fetchedSettings.maxDeposit);
  expect(settings.minFee).to.be.eq(fetchedSettings.minFee);
  expect(settings.maxFee).to.be.eq(fetchedSettings.maxFee);
  expect(settings.useCustomFeeRate).to.be.eq(fetchedSettings.useCustomFeeRate);

  const settingsSegments = settings.feeSegments;
  const fetchedSegments = fetchedSettings.feeSegments;
  expect(settingsSegments.length).to.be.eq(fetchedSegments.length);
  for (let i = 0; i < settingsSegments.length; i++) {
    const segmentA = settingsSegments[i];
    const segmentB = fetchedSegments[i];
    expect(segmentA.feeRate).to.be.eq(segmentB.feeRate);
    expect(segmentA.toAmount).to.be.eq(segmentB.toAmount);
  }
}
