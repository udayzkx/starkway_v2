#[derive(Copy, Serde, Destruct, starknet::StorageAccess)]
struct L1TokenDetails {
    name: felt252,
    symbol: felt252,
    decimals: u8,
}
