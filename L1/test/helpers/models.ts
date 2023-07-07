import { BigNumber, BigNumberish } from 'ethers';

export type FeeSegment = {
  feeRate: BigNumberish;
  toAmount: BigNumber;
};

export type TokenSettings = {
  minDeposit: BigNumberish;
  maxDeposit: BigNumberish;
  minFee: BigNumberish;
  maxFee: BigNumberish;
  useCustomFeeRate: boolean;
  feeSegments: FeeSegment[]
};

export type TokenMetadata = {
  decimals: number;
  symbol: string;
  name: string;
};

export type TokenInfo = {
  token: string;
  balance: BigNumber;
} & TokenMetadata;

export type TokenInfoShort = {
  token: string;
  balance: BigNumber;
};