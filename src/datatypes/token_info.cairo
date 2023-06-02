use starknet::ContractAddress;
use starkway::datatypes::l1_address::L1Address;

#[derive(Serde, Destruct, Drop)]
struct TokenInfo {
    l2_address: ContractAddress,
    l1_address: L1Address,
    native_l2_address: ContractAddress,
    balance: u256,
    name: felt252,
    symbol: felt252,
    decimals: u8,
}
