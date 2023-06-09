use core::traits::{ PartialOrd, PartialEq};
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
    l2_address: ContractAddress,
    amount: u256,
}

// CAUTION - It only makes sense to compare TokenAmounts which represent same L1 Token
// This means the l2_address should either be same or represent same L1 token (whitelisted or native)
// No check for this is done in the trait implementation
// This trait implementation is only to be used in the context of sorting
impl TokenAmountPartialOrd of PartialOrd<TokenAmount> {

    #[inline_always]
    fn le(lhs: TokenAmount, rhs: TokenAmount) -> bool {
        
        lhs.amount <= rhs.amount
    }

    #[inline_always]
    fn ge(lhs: TokenAmount, rhs: TokenAmount) -> bool {
        lhs.amount >= rhs.amount
    }

    #[inline_always]
    fn lt(lhs: TokenAmount, rhs: TokenAmount) -> bool {
        lhs.amount < rhs.amount
    }

    #[inline_always]
    fn gt(lhs: TokenAmount, rhs: TokenAmount) -> bool {
        lhs.amount > rhs.amount
    }
}

// CAUTION - It only makes sense to compare TokenAmounts which represent same L1 Token
// This means the l2_address should either be same or represent same L1 token (whitelisted or native)
// No check for this is done in the trait implementation
// This trait implementation is only to be used in the context of sorting
impl TokenAmountPartialEq of PartialEq<TokenAmount> {

    #[inline(always)]
    fn eq(lhs: TokenAmount, rhs: TokenAmount) -> bool {
        lhs.amount == rhs.amount
    }
    #[inline(always)]
    fn ne(lhs: TokenAmount, rhs: TokenAmount) -> bool {
        lhs.amount != rhs.amount
    }
}