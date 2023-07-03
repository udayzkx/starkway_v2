use starknet::{ContractAddress, EthAddress};
use starkway::plugins::datatypes::MessageBasicInfo;

#[starknet::interface]
trait IConsumeMessagePlugin<TContractState> {
    fn number_of_messages_by_params(
        self: @TContractState,
        l1_token_address: EthAddress,
        l1_sender_address: EthAddress,
        l2_funds_recipient_address: ContractAddress,
        l2_msg_consumer_address: ContractAddress,
        amount: u256,
        message_payload: Array<felt252>
    ) -> (u128, felt252);
    fn number_of_messages_by_hash(self: @TContractState, msg_hash: felt252) -> u128;
    fn handle_starkway_deposit_message(
        ref self: TContractState,
        l1_token_address: EthAddress,
        l2_token_address: ContractAddress,
        l1_sender_address: EthAddress,
        l2_recipient_address: ContractAddress,
        amount: u256,
        fee: u256,
        message_payload: Array<felt252>
    );
    fn consume_message(
        ref self: TContractState,
        l1_token_address: EthAddress,
        l1_sender_address: EthAddress,
        l2_funds_recipient_address: ContractAddress,
        amount: u256,
        message_payload: Array<felt252>
    );
}

#[starknet::interface]
trait IHistoricalDataPlugin<TContractState> {
    fn get_allow_list_len(self: @TContractState, consumer: ContractAddress) -> u32;
    fn get_allow_list(self: @TContractState, consumer: ContractAddress) -> Array<EthAddress>;
    fn get_message_info_at_index(
        self: @TContractState, consumer: ContractAddress, message_index: u64
    ) -> MessageBasicInfo;
    fn get_message_at_index(
        self: @TContractState, consumer: ContractAddress, message_index: u64
    ) -> (MessageBasicInfo, Array<felt252>);

    fn get_message_pointer(self: @TContractState, consumer: ContractAddress) -> u64;
    fn get_total_messages_count(self: @TContractState, consumer: ContractAddress) -> u64;
    fn get_starkway_address(self: @TContractState) -> ContractAddress;
    fn is_allowed_to_write(
        self: @TContractState, consumer: ContractAddress, writer: EthAddress
    ) -> bool;

    fn handle_starkway_deposit_message(
        ref self: TContractState,
        l1_token_address: EthAddress,
        l2_token_address: ContractAddress,
        l1_sender_address: EthAddress,
        l2_recipient_address: ContractAddress,
        amount: u256,
        fee: u256,
        message_payload: Array<felt252>
    );

    fn fetch_next_message_and_move_pointer(
        ref self: TContractState
    ) -> (MessageBasicInfo, Array<felt252>);
    fn set_permission_required(ref self: TContractState, permission: bool);
    fn add_to_allow_list(ref self: TContractState, eth_address: EthAddress);
    fn remove_from_allow_list(ref self: TContractState, eth_address: EthAddress);
}

#[starknet::interface]
trait IKnownIndexPlugin<TContractState> {
    fn get_last_message_info(
        self: @TContractState,
        sender: EthAddress,
        recipient: ContractAddress,
        index_1: u32,
        index_2: u32,
    ) -> MessageBasicInfo;
    fn get_last_message(
        self: @TContractState,
        sender: EthAddress,
        recipient: ContractAddress,
        index_1: u32,
        index_2: u32
    ) -> (
        EthAddress,
        ContractAddress,
        EthAddress,
        ContractAddress,
        u256,
        u256,
        u64,
        u32,
        Array<felt252>
    );
    fn get_starkway_address(self: @TContractState) -> ContractAddress;
    fn handle_starkway_deposit_message(
        ref self: TContractState,
        l1_token_address: EthAddress,
        l2_token_address: ContractAddress,
        l1_sender_address: EthAddress,
        l2_recipient_address: ContractAddress,
        amount: u256,
        fee: u256,
        message_payload: Array<felt252>
    );
}
