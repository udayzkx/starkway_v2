import { ethers } from 'hardhat'
import { expect } from 'chai'
import * as Const from './helpers/constants'
import { 
  prepareUsers, 
  deployStarknetCoreMock, 
  deployTestToken, 
  deployVault,
  deployStarkway,
  connectStarkwayToVault,
  fastForwardEVM
} from './helpers/utils'
import { ENV } from './helpers/env'
import { StarkwayVault, StarkwayVault__factory } from '../typechain-types'

/////////////////////////
// StarkwayVault Tests //
/////////////////////////

describe("Test Vault", function () {
  let vault: StarkwayVault;

  beforeEach(async function () {
    // Deploy
    await prepareUsers()
    await deployStarknetCoreMock()
    await deployTestToken()
    await deployVault()
    // Set variables
    vault = ENV.vault
  })

  it("Revert on starting connection unauthorized", async function () {
    const starkway = await deployStarkway()
    
    await expect(vault.connect(ENV.rogue).startConnectionProcess(starkway.address))
      .to.be.revertedWithCustomError(vault, 'OwnableUnauthorizedAccount');
  })

  it("Revert on finalizing connection unauthorized", async function () {
    const starkway = await deployStarkway()
    
    await vault.startConnectionProcess(starkway.address)
    await fastForwardEVM(Const.TESTING_CONNECTION_DELAY)

    await expect(vault.connect(ENV.rogue).startConnectionProcess(starkway.address))
      .to.be.revertedWithCustomError(vault, 'OwnableUnauthorizedAccount');
  })

  it("Revert on unauthorized disconnect", async function () {
    const starkway = await deployStarkway()
    await connectStarkwayToVault(ENV.admin, vault.address, starkway.address)

    await expect(vault.connect(ENV.rogue).disconnectStarkway(starkway.address))
      .to.be.revertedWithCustomError(vault, 'OwnableUnauthorizedAccount');
  })

  it("Revert on connecting zero address", async function () {
    await expect(connectStarkwayToVault(ENV.admin, vault.address, Const.ZERO_ADDRESS))
      .to.be.revertedWithCustomError(vault, "MultiConnectable__ZeroAddress")
  })

  it("Revert on finalizing connection too early", async function () {
    const starkway = await deployStarkway()

    await expectStatusFor(starkway.address, ConnectionStatus.NotConnected)
    await vault.startConnectionProcess(starkway.address)
    await expectStatusFor(starkway.address, ConnectionStatus.ToBeConnected)

    await fastForwardEVM(Const.TESTING_CONNECTION_DELAY - 10)
    await expect(vault.finalizeConnectionProcess(starkway.address))
      .to.be.revertedWithCustomError(vault, "MultiConnectable__TooEarlyToConnect")
  })

  it("Connect a single Starkway", async function () {
    const starkway = await deployStarkway()

    await expectStatusFor(starkway.address, ConnectionStatus.NotConnected)
    await vault.startConnectionProcess(starkway.address)
    await expectStatusFor(starkway.address, ConnectionStatus.ToBeConnected)

    await fastForwardEVM(Const.TESTING_CONNECTION_DELAY)
    await vault.finalizeConnectionProcess(starkway.address)
    await expectStatusFor(starkway.address, ConnectionStatus.Connected)
  })

  it("Connect several Starkways", async function () {
    await expectTotalConnections(0)

    const starkwayV1 = await deployStarkway()
    const starkwayV2 = await deployStarkway()

    await connectStarkwayToVault(ENV.admin, vault.address, starkwayV1.address)
    await expectTotalConnections(1)
    await expectStatusFor(starkwayV1.address, ConnectionStatus.Connected)
    await expectStatusFor(starkwayV2.address, ConnectionStatus.NotConnected)
    
    await connectStarkwayToVault(ENV.admin, vault.address, starkwayV2.address)
    await expectTotalConnections(2)
    await expectStatusFor(starkwayV1.address, ConnectionStatus.Connected)
    await expectStatusFor(starkwayV2.address, ConnectionStatus.Connected)
  })

  it("Disconnect Starkway", async function () {
    await expectTotalConnections(0)

    const starkwayV1 = await deployStarkway()
    const starkwayV2 = await deployStarkway()

    await connectStarkwayToVault(ENV.admin, vault.address, starkwayV1.address)
    await expectTotalConnections(1)
    await expectStatusFor(starkwayV1.address, ConnectionStatus.Connected)
    await expectStatusFor(starkwayV2.address, ConnectionStatus.NotConnected)
    
    await connectStarkwayToVault(ENV.admin, vault.address, starkwayV2.address)
    await expectTotalConnections(2)
    await expectStatusFor(starkwayV1.address, ConnectionStatus.Connected)
    await expectStatusFor(starkwayV2.address, ConnectionStatus.Connected)

    await vault.disconnectStarkway(starkwayV1.address)
    await expectTotalConnections(2)
    await expectStatusFor(starkwayV1.address, ConnectionStatus.Disconnected)
    await expectStatusFor(starkwayV2.address, ConnectionStatus.Connected)
  })

  it("Transfer Ownership", async function () {
    const adminAddress = await ENV.admin.getAddress()
    const aliceAddress = await ENV.alice.getAddress()

    // Admin starts ownership transfer to Alice
    await vault.connect(ENV.admin).transferOwnership(aliceAddress)
    expect(await vault.owner()).to.be.eq(adminAddress)

    // Rogue can't accept ownership
    await expect(vault.connect(ENV.rogue).acceptOwnership())
      .to.be.revertedWithCustomError(vault, 'OwnableUnauthorizedAccount')

    // Alice accepts ownership
    await vault.connect(ENV.alice).acceptOwnership()
    expect(await vault.owner()).to.be.eq(aliceAddress)
  })

  it("Revert on disconnecting the last Starkway", async function () {
    await expectTotalConnections(0)

    const starkwayV1 = await deployStarkway()
    const starkwayV2 = await deployStarkway()

    await connectStarkwayToVault(ENV.admin, vault.address, starkwayV1.address)
    await expectTotalConnections(1)
    await expectStatusFor(starkwayV1.address, ConnectionStatus.Connected)
    await expectStatusFor(starkwayV2.address, ConnectionStatus.NotConnected)
    
    await connectStarkwayToVault(ENV.admin, vault.address, starkwayV2.address)
    await expectTotalConnections(2)
    await expectStatusFor(starkwayV1.address, ConnectionStatus.Connected)
    await expectStatusFor(starkwayV2.address, ConnectionStatus.Connected)

    await vault.disconnectStarkway(starkwayV1.address)
    await expectTotalConnections(2)
    await expectStatusFor(starkwayV1.address, ConnectionStatus.Disconnected)
    await expectStatusFor(starkwayV2.address, ConnectionStatus.Connected)

    await expect(vault.disconnectStarkway(starkwayV2.address))
      .to.be.revertedWithCustomError(vault, "MultiConnectable__MustRemainConnectedVersion")
  })
})

/////////////
// Helpers //
/////////////

enum ConnectionStatus {
  NotConnected = 0,
  ToBeConnected = 1,
  Connected = 2,
  Disconnected = 3
}

async function expectTotalConnections(count: number) {
  const allConnections = await ENV.vault.getAllConnections()
  expect(allConnections.length).to.be.eq(count)
}

async function expectStatusFor(target: string, status: ConnectionStatus) {
  const state = await ENV.vault.getConnectionState(target)
  expect(state.status).to.be.eq(status)
}
