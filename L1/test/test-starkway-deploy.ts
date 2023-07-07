import { expect } from 'chai';
import * as Const from './helpers/constants';
import { BigNumber } from 'ethers';
import { 
  prepareUsers, 
  deployStarknetCoreMock, 
  deployStarkway,
  deployVault,
} from './helpers/utils';
import { ENV } from './helpers/env';
import { Starkway__factory } from '../typechain-types';

//////////////////////////////
// When Starkway L2 not set //
//////////////////////////////

const STARKWAY_INTERFACE_PROVIDER = new Starkway__factory();

describe("Starkway deployment", function () {
  beforeEach(async function () {
    await prepareUsers();
    await deployStarknetCoreMock();
    await deployVault();
  });

  it("Revert when Starknet address is ZERO", async function () {
    await expect(
      deployStarkway(
        ENV.admin,
        Const.ZERO_ADDRESS, // invalid
        ENV.vault.address,
        Const.STARKWAY_L2_ADDRESS,
        Const.DEFAULT_DEPOSIT_FEE
      )
    ).to.be.revertedWithoutReason();
  });

  it("Revert when vault address is ZERO", async function () {
    await expect(
      deployStarkway(
        ENV.admin,
        ENV.starknetCoreMock.address,
        Const.ZERO_ADDRESS, // invalid
        Const.STARKWAY_L2_ADDRESS,
        Const.DEFAULT_DEPOSIT_FEE
      )
    ).to.be.revertedWithCustomError(STARKWAY_INTERFACE_PROVIDER, "ZeroAddressError");
  });

  it("Revert when Starkway L2 address is ZERO", async function () {
    await expect(
      deployStarkway(
        ENV.admin,
        ENV.starknetCoreMock.address,
        ENV.vault.address,
        Const.BN_ZERO, // invalid
        Const.DEFAULT_DEPOSIT_FEE
      )
    ).to.be.revertedWithoutReason();
  });

  it("Revert when fee rate too high", async function () {
    await expect(
      deployStarkway(
        ENV.admin,
        ENV.starknetCoreMock.address,
        ENV.vault.address,
        Const.STARKWAY_L2_ADDRESS,
        BigNumber.from("100000000000000") // invalid
      )
    ).to.be.revertedWithCustomError(STARKWAY_INTERFACE_PROVIDER, "DefaultFeeRateTooHigh");
  });

  it("Success deployment", async function () {
    const starkway = await deployStarkway(
      ENV.admin,
      ENV.starknetCoreMock.address,
      ENV.vault.address,
      Const.STARKWAY_L2_ADDRESS,
      Const.DEFAULT_DEPOSIT_FEE
    );
    const state = await starkway.getStarkwayState();
    expect (await starkway.owner()).to.be.eq(await ENV.admin.getAddress());
    expect(state._vault).to.be.eq(ENV.vault.address);
    expect(state._starknet).to.be.eq(ENV.starknetCoreMock.address);
    expect(state._starkwayL2).to.be.eq(Const.STARKWAY_L2_ADDRESS);
    expect(state._defaultFeeRate).to.be.eq(Const.DEFAULT_DEPOSIT_FEE);
    expect(state._maxFeeRate).to.be.eq(300);
  });
});
