use starknet::ContractAddress;
use starkway::datatypes::l1_address::L1Address;

#[derive(Copy, Destruc, Drop, Serde, storage_access::StorageAccess)]
struct L2TokenDetails {
    l1_address: L1Address,
    bridge_id: u16,
    bridge_address: ContractAddress,
}

