import { 
  Starkway, 
  StarkwayHelper, 
  StarknetCoreMock, 
  TestToken, 
  StarkwayVault 
} from "../../typechain-types";
import { Signer } from 'ethers';

export class Env {
  starkwayContract: Starkway;
  vault: StarkwayVault;
  starkwayHelper: StarkwayHelper;
  starknetCoreMock: StarknetCoreMock;
  testToken: TestToken;
  admin: Signer;
  alice: Signer;
  bob: Signer;
  charlie: Signer;
  rogue: Signer;
};

export const ENV = new Env();
