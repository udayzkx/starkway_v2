use core::traits::{PartialOrd, PartialEq};
use starknet::ContractAddress;
use starkway::datatypes::l1_address::L1Address;

#[derive(Serde, Destruct, Drop, Copy)]
struct TokenInfo {
    l2_address: ContractAddress,
    l1_address: L1Address,
    native_l2_address: ContractAddress,
    balance: u256,
    name: felt252,
    symbol: felt252,
    decimals: u8,
}

#[derive(Copy, Destruct, Drop, Serde)]
struct TokenAmount {
    l1_address: L1Address,
    l2_address: ContractAddress,
    amount: u256,
}

// CAUTION - It only makes sense to compare TokenAmounts which represent same L1 Token
// The code will panic if incompatible tokens are compared i.e. which do not have same l1_address
impl TokenAmountPartialOrd of PartialOrd<TokenAmount> {
    #[inline_always]
    fn le(lhs: TokenAmount, rhs: TokenAmount) -> bool {
        assert(lhs.l1_address == rhs.l1_address, 'TA: Incompatible L1 address');
        lhs.amount <= rhs.amount
    }

    #[inline_always]
    fn ge(lhs: TokenAmount, rhs: TokenAmount) -> bool {
        assert(lhs.l1_address == rhs.l1_address, 'TA: Incompatible L1 address');
        lhs.amount >= rhs.amount
    }

    #[inline_always]
    fn lt(lhs: TokenAmount, rhs: TokenAmount) -> bool {
        assert(lhs.l1_address == rhs.l1_address, 'TA: Incompatible L1 address');
        lhs.amount < rhs.amount
    }

    #[inline_always]
    fn gt(lhs: TokenAmount, rhs: TokenAmount) -> bool {
        assert(lhs.l1_address == rhs.l1_address, 'TA: Incompatible L1 address');
        lhs.amount > rhs.amount
    }
}

// CAUTION - It only makes sense to compare TokenAmounts which represent same L1 Token
// The code will panic if incompatible tokens are compared i.e. which do not have same l1_address
impl TokenAmountPartialEq of PartialEq<TokenAmount> {
    #[inline(always)]
    fn eq(lhs: TokenAmount, rhs: TokenAmount) -> bool {
        assert(lhs.l1_address == rhs.l1_address, 'TA: Incompatible L1 address');
        lhs.amount == rhs.amount
    }
    #[inline(always)]
    fn ne(lhs: TokenAmount, rhs: TokenAmount) -> bool {
        assert(lhs.l1_address == rhs.l1_address, 'TA: Incompatible L1 address');
        lhs.amount != rhs.amount
    }
}
