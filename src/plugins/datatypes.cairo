use core::hash::LegacyHash;
use starknet::{ContractAddress, EthAddress};
use starkway::datatypes::{LegacyHashEthAddress};
#[derive(Copy, Drop, Destruct, Serde, storage_access::StorageAccess)]
struct MessageBasicInfo {
    l1_token_address: EthAddress,
    l2_token_address: ContractAddress,
    l1_sender_address: EthAddress,
    l2_recipient_address: ContractAddress,
    amount: u256,
    fee: u256,
    timestamp: felt252,
    message_payload_len: u32,
}

impl LegacyHashContractAddressEthAddress of LegacyHash<(ContractAddress,EthAddress)> {

    fn hash(state: felt252, value: (ContractAddress,EthAddress)) -> felt252 {
        let (starknet_address, eth_address) = value;
        let state = LegacyHash::<ContractAddress>::hash(state, starknet_address);
        LegacyHash::<EthAddress>::hash(state, eth_address)
    }
}

