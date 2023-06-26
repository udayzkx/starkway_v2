use starknet::{ContractAddress, EthAddress};

#[derive(Copy, Destruct, Drop, Serde, storage_access::StorageAccess)]
struct L2TokenDetails {
    l1_address: EthAddress,
    bridge_id: u16,
    bridge_address: ContractAddress,
}

