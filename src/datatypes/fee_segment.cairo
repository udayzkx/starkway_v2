#[derive(Copy, Drop, Destruct, Serde, storage_access::StorageAccess)]
struct FeeSegment {
    to_amount: u256,
    fee_rate: u256,
}
