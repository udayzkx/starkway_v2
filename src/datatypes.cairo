use core::hash::LegacyHash;
use core::traits::{PartialOrd, PartialEq};
use starknet::{ContractAddress, EthAddress};


#[derive(Copy, Drop, Destruct, Serde, storage_access::StorageAccess)]
struct FeeRange {
    is_set: bool,
    min: u256,
    max: u256,
}

#[derive(Copy, Drop, Destruct, Serde, storage_access::StorageAccess)]
struct FeeSegment {
    to_amount: u256,
    fee_rate: u256,
}

#[derive(Copy, Serde, Destruct, storage_access::StorageAccess)]
struct L1TokenDetails {
    name: felt252,
    symbol: felt252,
    decimals: u8,
}

#[derive(Copy, Destruct, Drop, Serde, storage_access::StorageAccess)]
struct L2TokenDetails {
    l1_address: EthAddress,
    bridge_id: u16,
    bridge_address: ContractAddress,
}

#[derive(Destruct, Serde, storage_access::StorageAccess)]
struct WithdrawalRange {
    min: u256,
    max: u256,
}

#[derive(Serde, Destruct, Drop, Copy)]
struct TokenInfo {
    l2_address: ContractAddress,
    l1_address: EthAddress,
    native_l2_address: ContractAddress,
    balance: u256,
    name: felt252,
    symbol: felt252,
    decimals: u8,
}

#[derive(Copy, Destruct, Drop, Serde)]
struct TokenAmount {
    l1_address: EthAddress,
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

impl LegacyHashEthAddress of LegacyHash<EthAddress> {
    fn hash(state: felt252, value: EthAddress) -> felt252 {
        LegacyHash::<felt252>::hash(state, value.address)
    }
}
