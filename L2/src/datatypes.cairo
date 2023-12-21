use core::hash::{Hash,HashStateTrait};
use core::traits::{PartialOrd, PartialEq};
use starknet::{ContractAddress, EthAddress};


#[derive(Copy, Drop, Serde, starknet::Store)]
struct FeeRange {
    is_set: bool,
    min: u256,
    max: u256,
}

#[derive(Copy, Drop, Serde, starknet::Store)]
struct FeeSegment {
    from_amount: u256,
    fee_rate: u16,
}

#[derive(Copy, Serde, Drop, starknet::Store)]
struct L1TokenDetails {
    name: felt252,
    symbol: felt252,
    decimals: u8,
}

#[derive(Copy, Drop, Serde, starknet::Store)]
struct L2TokenDetails {
    l1_address: EthAddress,
    bridge_adapter_id: u16,
    bridge_address: ContractAddress,
    is_erc20_camel_case: bool
}

#[derive(Drop, Serde, starknet::Store)]
struct WithdrawalRange {
    min: u256,
    max: u256,
}

#[derive(Serde, Drop, Copy)]
struct TokenInfo {
    l2_address: ContractAddress,
    l1_address: EthAddress,
    native_l2_address: ContractAddress,
    balance: u256,
    name: felt252,
    symbol: felt252,
    decimals: u8,
}

#[derive(Copy, Drop, Serde)]
struct TokenAmount {
    l1_address: EthAddress,
    l2_address: ContractAddress,
    amount: u256,
}

#[derive(Copy, Drop, Serde)]
struct TokenDetails {
    name: felt252,
    symbol: felt252,
    decimals: u8,
    l1_address: EthAddress,
    native_l2_address: ContractAddress,
}

// CAUTION - It only makes sense to compare TokenAmounts which represent same L1 Token
// The code will panic if incompatible tokens are compared i.e. which do not have same l1_address
impl TokenAmountPartialOrd of PartialOrd<TokenAmount> {
    #[inline(always)]
    fn le(lhs: TokenAmount, rhs: TokenAmount) -> bool {
        assert(lhs.l1_address == rhs.l1_address, 'TA: Incompatible L1 address');
        lhs.amount <= rhs.amount
    }

    #[inline(always)]
    fn ge(lhs: TokenAmount, rhs: TokenAmount) -> bool {
        assert(lhs.l1_address == rhs.l1_address, 'TA: Incompatible L1 address');
        lhs.amount >= rhs.amount
    }

    #[inline(always)]
    fn lt(lhs: TokenAmount, rhs: TokenAmount) -> bool {
        assert(lhs.l1_address == rhs.l1_address, 'TA: Incompatible L1 address');
        lhs.amount < rhs.amount
    }

    #[inline(always)]
    fn gt(lhs: TokenAmount, rhs: TokenAmount) -> bool {
        assert(lhs.l1_address == rhs.l1_address, 'TA: Incompatible L1 address');
        lhs.amount > rhs.amount
    }
}

// CAUTION - It only makes sense to compare TokenAmounts which represent same L1 Token
// The code will panic if incompatible tokens are compared i.e. which do not have same l1_address
impl TokenAmountPartialEq of PartialEq<TokenAmount> {
    #[inline(always)]
    fn eq(lhs: @TokenAmount, rhs: @TokenAmount) -> bool {
        assert(lhs.l1_address == rhs.l1_address, 'TA: Incompatible L1 address');
        lhs.amount == rhs.amount
    }
    #[inline(always)]
    fn ne(lhs: @TokenAmount, rhs: @TokenAmount) -> bool {
        assert(lhs.l1_address == rhs.l1_address, 'TA: Incompatible L1 address');
        lhs.amount != rhs.amount
    }
}

impl HashEthAddress<S, impl SHashState: HashStateTrait<S>> of Hash<EthAddress, S, SHashState> {
    #[inline(always)]
    fn update_state(state: S, value: EthAddress) -> S {
        state.update(value.address)
    }
}
