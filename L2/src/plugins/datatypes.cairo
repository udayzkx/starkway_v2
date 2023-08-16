use core::hash::LegacyHash;
use starknet::{ContractAddress, EthAddress};
use starkway::datatypes::{LegacyHashEthAddress};

#[derive(Copy, Drop, Destruct, Serde, starknet::Store)]
struct MessageBasicInfo {
    l1_token_address: EthAddress,
    l2_token_address: ContractAddress,
    l1_sender_address: EthAddress,
    l2_recipient_address: ContractAddress,
    amount: u256,
    fee: u256,
    timestamp: u64,
    message_payload_len: u32,
}

impl LegacyHashContractAddressEthAddress of LegacyHash<(ContractAddress, EthAddress)> {
    fn hash(state: felt252, value: (ContractAddress, EthAddress)) -> felt252 {
        let (starknet_address, eth_address) = value;
        let state = LegacyHash::<ContractAddress>::hash(state, starknet_address);
        LegacyHash::<EthAddress>::hash(state, eth_address)
    }
}

impl LegacyHashEthContractEthU32 of LegacyHash<(EthAddress, ContractAddress, EthAddress, u32)> {
    fn hash(state: felt252, value: (EthAddress, ContractAddress, EthAddress, u32)) -> felt252 {
        let (eth_address, starknet_address, index_1, index_2) = value;
        let state_1 = LegacyHash::<EthAddress>::hash(state, eth_address);
        let state_2 = LegacyHash::<ContractAddress>::hash(state_1, starknet_address);
        let state_3 = LegacyHash::<EthAddress>::hash(state_2, index_1);
        LegacyHash::<u32>::hash(state_3, index_2)
    }
}

impl LegacyHashEthContractEthU32U32 of LegacyHash<(
    EthAddress, ContractAddress, EthAddress, u32, u32
)> {
    fn hash(state: felt252, value: (EthAddress, ContractAddress, EthAddress, u32, u32)) -> felt252 {
        let (eth_address, starknet_address, index_1, index_2, index_3) = value;
        let state_1 = LegacyHash::<EthAddress>::hash(state, eth_address);
        let state_2 = LegacyHash::<ContractAddress>::hash(state_1, starknet_address);
        let state_3 = LegacyHash::<EthAddress>::hash(state_2, index_1);
        let state_4 = LegacyHash::<u32>::hash(state_3, index_2);
        LegacyHash::<u32>::hash(state_4, index_3)
    }
}

impl DropEthAddressContractAddressU32U32U32 of Drop<(
    EthAddress, ContractAddress, EthAddress, u32, u32
)>;
