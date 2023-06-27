#[derive(Copy, Drop, Destruct, Serde, storage_access::StorageAccess)]
struct FeeRange {
    is_set: bool,
    min: u256,
    max: u256,
}
