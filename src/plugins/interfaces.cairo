use starknet::{ContractAddress, EthAddress};
use starkway::plugins::datatypes::MessageBasicInfo;

#[starknet::interface]
trait IHistoricalDataPlugin<ContractState> {

    fn get_allow_list_len(self: @ContractState, consumer: ContractAddress) -> u32;
    fn get_allow_list(self: @ContractState, consumer: ContractAddress) -> Array<EthAddress>;
    fn get_message_info_at_index(
            self: @ContractState, 
            consumer: ContractAddress, 
            message_index: u64) -> MessageBasicInfo;
    fn get_message_at_index(
            self: @ContractState,
            consumer: ContractAddress,
            message_index: u64) -> (MessageBasicInfo, Array<felt252>);

    fn get_message_pointer(self: @ContractState, consumer: ContractAddress) -> u64;
    fn get_total_messages_count(self: @ContractState, consumer: ContractAddress) -> u64;
    fn get_starkway_address(self: @ContractState) -> ContractAddress;
    fn is_allowed_to_write(
            self: @ContractState, 
            consumer: ContractAddress, 
            writer: EthAddress) -> bool;

    fn handle_starkway_deposit_message(
            ref self: ContractState,
            l1_token_address: EthAddress,
            l2_token_address: ContractAddress,
            l1_sender_address: EthAddress,
            l2_recipient_address: ContractAddress,
            amount: u256,
            fee: u256,
            message_payload: Array<felt252>
        );

    fn fetch_next_message_and_move_pointer(ref self: ContractState) -> (MessageBasicInfo, Array<felt252>);
    fn set_permission_required(ref self: ContractState, permission: bool);
    fn add_to_allow_list(ref self: ContractState, eth_address: EthAddress);
    fn remove_from_allow_list(ref self: ContractState, eth_address: EthAddress);
}
