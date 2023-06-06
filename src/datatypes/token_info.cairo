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

#[derive(Destruct, Drop, Serde)]
struct TokenAmount {
    l2_address: ContractAddress,
    amount: u256,
}
