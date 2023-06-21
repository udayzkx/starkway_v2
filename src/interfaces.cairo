use starknet::ContractAddress;
// use starkway::datatypes::{l1_address::L1Address, l1_token_details::L1TokenDetails};

#[starknet::interface]
trait IAdminAuth<TContractState> {
    fn set_min_number_admins(ref self: TContractState, num: u8);
    fn add_admin(ref self: TContractState, address: ContractAddress);
    fn remove_admin(ref self: TContractState, address: ContractAddress);
    fn get_is_allowed(self: @TContractState, address: ContractAddress) -> bool;
    fn get_min_number_admins(self: @TContractState) -> u8;
    fn get_current_total_admins(self: @TContractState) -> u8;
}
// #[abi]
// trait IStarkway {
//     fn get_whitelisted_token_addresses(l1_token_address: L1Address) -> Array<ContractAddress>;
//     fn get_supported_tokens() -> Array<L1Address>;
//     fn get_native_token_address(l1_token_address: L1Address) -> ContractAddress;
//     fn get_l1_token_details(l1_token_address: L1Address) -> L1TokenDetails;
// }

#[starknet::interface]
trait IERC20<TContractState> {
    fn name(self: @TContractState) -> felt252;
    fn symbol(self: @TContractState) -> felt252;
    fn decimals(self: @TContractState) -> u8;
    fn total_supply(self: @TContractState) -> u256;
    fn balance_of(self: @TContractState, account: ContractAddress) -> u256;
    fn allowance(self: @TContractState, owner: ContractAddress, spender: ContractAddress) -> u256;
    fn get_owner(self: @TContractState) -> ContractAddress;
    fn transfer(ref self: TContractState, recipient: ContractAddress, amount: u256) -> bool;
    fn transfer_from(
        ref self: TContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256
    ) -> bool;
    fn approve(ref self: TContractState, spender: ContractAddress, amount: u256) -> bool;
    fn increase_allowance(
        ref self: TContractState, spender: ContractAddress, added_value: u256
    ) -> bool;
    fn decrease_allowance(
        ref self: TContractState, spender: ContractAddress, subtracted_value: u256
    ) -> bool;
    fn burn(ref self: TContractState, amount: u256);
    fn mint(ref self: TContractState, to: ContractAddress, amount: u256);
    fn transfer_ownership(ref self: TContractState, new_owner: ContractAddress);
}
// #[abi]
// trait IBridgeAdapter {
//     #[external]
//     fn withdraw(
//         token_bridge_address: ContractAddress,
//         l2_token_address: ContractAddress,
//         l1_recipient: L1Address,
//         withdrawal_amount: u256,
//         user: ContractAddress
//     );
// }

// #[abi]
// trait IStarkwayMessageHandler {
//     #[external]
//     fn handle_starkway_deposit_message(
//         l1_token_address: L1Address,
//         l2_token_address: ContractAddress,
//         l1_sender_address: L1Address,
//         l2_recipient_address: ContractAddress,
//         amount: u256,
//         fee: u256,
//         message_payload: Array<felt252>
//     );
// }


