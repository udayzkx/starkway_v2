#[derive(Copy, Serde, Destruct, storage_access::StorageAccess)]
struct L1TokenDetails {
    name: felt252,
    symbol: felt252,
    decimals: u8,
}
