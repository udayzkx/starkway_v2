#[derive(Destruct, Serde, storage_access::StorageAccess)]
struct WithdrawalRange {
    min: u256,
    max: u256,
}
