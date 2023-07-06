import * as Const from './helpers/constants';
import { expect } from 'chai'
import { 
  prepareUsers, 
  deployStarknetCoreMock, 
  tokenAmount,
  deployStarkwayAndVault,
  deployTestToken,
} from './helpers/utils';
import { TokenSettings } from './helpers/models';
import { ENV } from './helpers/env';

///////////////////////////
// Token Settings Errors //
///////////////////////////

describe("Token Settings Errors", function () {

  beforeEach(async function () {
    await prepareUsers();
    await deployStarknetCoreMock();
    await deployStarkwayAndVault();
    await deployTestToken();
    const initFee = ENV.vault.calculateInitializationFee(ENV.testToken.address);
    await ENV.vault.initToken(ENV.testToken.address, { value: initFee });
  });

  it("Revert if token not initialized", async function () {
    const settings = {
      minDeposit: tokenAmount(10),
      maxDeposit: tokenAmount(10_000_000),
      minFee: tokenAmount(5),
      maxFee: tokenAmount(100),
      useCustomFeeRate: false,
      feeSegments: []
    };
    await testSettingsError(settings, "TokenNotInitialized", Const.DUMMY_ADDRESS);
  });

  it("Revert if useCustomFeeRate == true, but no segments", async function () {
    const settings = {
      minDeposit: tokenAmount(10),
      maxDeposit: tokenAmount(10_000_000),
      minFee: tokenAmount(5),
      maxFee: tokenAmount(100),
      useCustomFeeRate: true,
      feeSegments: []
    };
    await testSettingsError(settings, "SegmentsMustExist");
  });

  it("Revert if useCustomFeeRate == false, but with segments", async function () {
    const settings = {
      minDeposit: tokenAmount(10),
      maxDeposit: tokenAmount(10_000_000),
      minFee: tokenAmount(5),
      maxFee: tokenAmount(100),
      useCustomFeeRate: false,
      feeSegments: [
        { feeRate: 0, toAmount: tokenAmount(10_000_000) }
      ]
    };
    await testSettingsError(settings, "SegmentsMustBeEmpty");
  });

  it("Revert if min fee > max fee", async function () {
    const settings = {
      minDeposit: tokenAmount(10),
      maxDeposit: tokenAmount(10_000_000),
      minFee: tokenAmount(5),
      maxFee: tokenAmount(3),
      useCustomFeeRate: false,
      feeSegments: []
    };
    await testSettingsError(settings, "InvalidMaxFee");
  });

  it("Revert if min deposit > max deposit", async function () {
    const settings = {
      minDeposit: tokenAmount(10),
      maxDeposit: tokenAmount(5),
      minFee: tokenAmount(5),
      maxFee: tokenAmount(100),
      useCustomFeeRate: false,
      feeSegments: []
    };
    await testSettingsError(settings, "InvalidMaxDeposit");
  });

  it("Revert if min fee > min deposit", async function () {
    const settings = {
      minDeposit: tokenAmount(1),
      maxDeposit: tokenAmount(10_000_000),
      minFee: tokenAmount(5),
      maxFee: tokenAmount(100),
      useCustomFeeRate: false,
      feeSegments: []
    };
    await testSettingsError(settings, "InvalidMinFee");
  });

  it("Revert if segments not in increasing order", async function () {
    const settings = {
      minDeposit: tokenAmount(10),
      maxDeposit: tokenAmount(10_000_000),
      minFee: tokenAmount(5),
      maxFee: tokenAmount(100),
      useCustomFeeRate: true,
      feeSegments: [
        { feeRate: 100, toAmount: tokenAmount(10) },
        { feeRate: 80, toAmount: tokenAmount(1_000) },
        { feeRate: 60, toAmount: tokenAmount(8_000) },
        { feeRate: 40, toAmount: tokenAmount(4_000) }, // to-amount is less than previous
        { feeRate: 20, toAmount: tokenAmount(10_000_000) },
      ]
    };
    await testSettingsError(settings, "InvalidFeeSegments");
  });

  it("Revert if any segments fee rate > MAX_FEE_RATE", async function () {
    const settings = {
      minDeposit: tokenAmount(10),
      maxDeposit: tokenAmount(10_000_000),
      minFee: tokenAmount(5),
      maxFee: tokenAmount(100),
      useCustomFeeRate: true,
      feeSegments: [
        { feeRate: 100, toAmount: tokenAmount(10) },
        { feeRate: 200, toAmount: tokenAmount(100) },
        { feeRate: 300, toAmount: tokenAmount(1_000) },
        { feeRate: 350, toAmount: tokenAmount(10_000_000) }, // rate higher than 300 (3%)
      ]
    };
    await testSettingsError(settings, "SegmentRateTooHigh");
  });

  it("Revert if segments don't cover full deposit range", async function () {
    const settings = {
      minDeposit: tokenAmount(10),
      maxDeposit: tokenAmount(10_000_000),
      minFee: tokenAmount(5),
      maxFee: tokenAmount(100),
      useCustomFeeRate: true,
      feeSegments: [
        { feeRate: 100, toAmount: tokenAmount(10) },
        { feeRate: 200, toAmount: tokenAmount(10_000) },
        { feeRate: 300, toAmount: tokenAmount(1_000_000) },
      ]
    };
    await testSettingsError(settings, "InvalidMaxDeposit");
  });

  it("Revert if not-last segment's to-amount == 0", async function () {
    const settings = {
      minDeposit: tokenAmount(10),
      maxDeposit: tokenAmount(10_000_000),
      minFee: tokenAmount(5),
      maxFee: tokenAmount(100),
      useCustomFeeRate: true,
      feeSegments: [
        { feeRate: 100, toAmount: tokenAmount(10) },
        { feeRate: 200, toAmount: tokenAmount(0) },
        { feeRate: 300, toAmount: tokenAmount(10_000_000) },
      ]
    };
    await testSettingsError(settings, "InvalidFeeSegments");
  });
});

export async function testSettingsError(
  settings: TokenSettings, 
  error: string,
  tokenAddress: string = ENV.testToken.address
) {
  // 1. Validate settings
  await expect(ENV.starkwayContract.validateTokenSettings(
    tokenAddress,
    settings.minDeposit,
    settings.maxDeposit,
    settings.minFee,
    settings.maxFee,
    settings.useCustomFeeRate,
    settings.feeSegments
  )).to.be.revertedWithCustomError(ENV.starkwayContract, error);

  // 2. Update settings
  await expect(ENV.starkwayContract.updateTokenSettings(
    tokenAddress,
    settings.minDeposit,
    settings.maxDeposit,
    settings.minFee,
    settings.maxFee,
    settings.useCustomFeeRate,
    settings.feeSegments
  )).to.be.revertedWithCustomError(ENV.starkwayContract, error);
}
