use starknet::{class_hash::ClassHash, ContractAddress, EthAddress};
use starkway::datatypes::{
    FeeRange, FeeSegment, L1TokenDetails, L2TokenDetails, TokenAmount, TokenDetails, TokenInfo,
    WithdrawalRange
};

#[starknet::interface]
trait IAdminAuth<TContractState> {
    fn set_min_number_admins(ref self: TContractState, num: u8);
    fn add_admin(ref self: TContractState, address: ContractAddress);
    fn remove_admin(ref self: TContractState, address: ContractAddress);
    fn get_is_allowed(self: @TContractState, address: ContractAddress) -> bool;
    fn get_min_number_admins(self: @TContractState) -> u8;
    fn get_current_total_admins(self: @TContractState) -> u8;
}

#[starknet::interface]
trait IStarkway<TContractState> {
    fn get_l1_starkway_address(self: @TContractState) -> EthAddress;
    fn get_l1_starkway_vault_address(self: @TContractState) -> EthAddress;
    fn get_admin_auth_address(self: @TContractState) -> ContractAddress;
    fn get_erc20_class_hash(self: @TContractState) -> ClassHash;
    fn get_fee_lib_class_hash(self: @TContractState) -> ClassHash;
    fn get_reentrancy_guard_class_hash(self: @TContractState) -> ClassHash;
    fn get_native_token_address(
        self: @TContractState, l1_token_address: EthAddress
    ) -> ContractAddress;
    fn get_l1_token_details(self: @TContractState, l1_token_address: EthAddress) -> L1TokenDetails;
    fn get_whitelisted_token_details(
        self: @TContractState, l2_address: ContractAddress
    ) -> L2TokenDetails;
    fn get_supported_tokens(self: @TContractState) -> Array<EthAddress>;
    fn get_supported_tokens_length(self: @TContractState) -> u32;
    fn get_whitelisted_token_addresses(
        self: @TContractState, l1_token_address: EthAddress
    ) -> Array<ContractAddress>;
    fn get_withdrawal_range(self: @TContractState, l1_token_address: EthAddress) -> WithdrawalRange;
    fn can_withdraw_multi(
        self: @TContractState,
        transfer_list: Array<TokenAmount>,
        l1_token_address: EthAddress,
        withdrawal_amount: u256,
        fee: u256,
    ) -> bool;
    fn calculate_fee(
        self: @TContractState, l1_token_address: EthAddress, withdrawal_amount: u256
    ) -> u256;
    fn prepare_withdrawal_lists(
        self: @TContractState,
        l1_address: EthAddress,
        amount: u256,
        user: ContractAddress,
        fee: u256
    ) -> (Array<TokenAmount>, Array<TokenAmount>);
    fn get_cumulative_fees(self: @TContractState, l1_token_address: EthAddress) -> u256;
    fn get_cumulative_fees_withdrawn(self: @TContractState, l1_token_address: EthAddress) -> u256;
    fn get_fee_rate(self: @TContractState, l1_token_address: EthAddress, amount: u256) -> u256;
    fn get_default_fee_rate(self: @TContractState) -> u256;
    fn get_fee_range(self: @TContractState, l1_token_address: EthAddress) -> FeeRange;
    fn set_l1_starkway_address(ref self: TContractState, l1_address: EthAddress);
    fn set_l1_starkway_vault_address(ref self: TContractState, l1_address: EthAddress);
    fn set_admin_auth_address(ref self: TContractState, admin_auth_address: ContractAddress);
    fn set_erc20_class_hash(ref self: TContractState, class_hash: ClassHash);
    fn set_fee_lib_class_hash(ref self: TContractState, class_hash: ClassHash);
    fn set_reentrancy_guard_class_hash(ref self: TContractState, class_hash: ClassHash);
    fn register_bridge_adapter(
        ref self: TContractState,
        bridge_adapter_id: u16,
        bridge_adapter_name: felt252,
        bridge_adapter_address: ContractAddress
    );
    fn withdraw(
        ref self: TContractState,
        l2_token_address: ContractAddress,
        l1_token_address: EthAddress,
        l1_recipient: EthAddress,
        withdrawal_amount: u256,
        fee: u256
    );
    fn set_withdrawal_range(
        ref self: TContractState, l1_token_address: EthAddress, withdrawal_range: WithdrawalRange
    );
    fn withdraw_admin_fees(
        ref self: TContractState,
        l1_token_address: EthAddress,
        l2_token_address: ContractAddress,
        l2_recipient: ContractAddress,
        withdrawal_amount: u256
    );
    fn set_default_fee_rate(ref self: TContractState, default_fee_rate: u256);
    fn set_fee_range(ref self: TContractState, l1_token_address: EthAddress, fee_range: FeeRange);
    fn set_fee_segment(
        ref self: TContractState, l1_token_address: EthAddress, tier: u8, fee_segment: FeeSegment
    );
    fn authorised_init_token(
        ref self: TContractState, l1_token_address: EthAddress, token_details: L1TokenDetails
    );
    fn whitelist_token(
        ref self: TContractState,
        l2_token_address: ContractAddress,
        l2_token_details: L2TokenDetails
    );
    fn withdraw_multi(
        ref self: TContractState,
        transfer_list: Array<TokenAmount>,
        l1_recipient: EthAddress,
        l1_token_address: EthAddress,
        withdrawal_amount: u256,
        fee: u256,
    );

    fn upgrade_class_hash(ref self: TContractState, new_class_hash: ClassHash);
    fn get_dummy_var(self: @TContractState) -> u32;
    fn set_dummy_var(ref self: TContractState, var: u32);
    // test functions
    //#[cfg(test)]
    //fn initialize_token_test(
    //    ref self: TContractState,
    //    from_address: felt252,
    //    l1_token_address: EthAddress,
    //    token_details: L1TokenDetails
    //);

    //#[cfg(test)]
    //fn deposit_test(
    //    ref self: TContractState,
    //    from_address: felt252,
    //    l1_token_address: EthAddress,
    //    sender_l1_address: EthAddress,
    //    recipient_address: ContractAddress,
    //    amount: u256,
    //    fee: u256
    //);

    //#[cfg(test)]
    //fn deposit_with_message_test(
    //    ref self: TContractState,
    //    from_address: felt252,
    //    l1_token_address: EthAddress,
    //    sender_l1_address: EthAddress,
    //    recipient_address: ContractAddress,
    //    amount: u256,
    //    fee: u256,
    //    message_handler: ContractAddress,
    //    message_payload: Array<felt252>
    //);

}

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

#[starknet::interface]
trait IBridgeAdapter<TContractState> {
    fn withdraw(
        ref self: TContractState,
        token_bridge_address: ContractAddress,
        l2_token_address: ContractAddress,
        l1_recipient: EthAddress,
        withdrawal_amount: u256,
        user: ContractAddress
    );
}

#[starknet::interface]
trait IStarkwayMessageHandler<TContractState> {
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

#[starknet::interface]
trait IFeeLib<TContractState> {
    fn get_default_fee_rate(self: @TContractState) -> u256;
    fn get_max_fee_segment_tier(self: @TContractState, token_l1_address: EthAddress) -> u8;
    fn get_fee_segment(self: @TContractState, token_l1_address: EthAddress, tier: u8) -> FeeSegment;
    fn get_fee_range(self: @TContractState, token_l1_address: EthAddress) -> FeeRange;
    fn get_fee_rate(self: @TContractState, token_l1_address: EthAddress, amount: u256) -> u256;
    fn set_default_fee_rate(ref self: TContractState, default_fee_rate: u256);
    fn set_fee_range(ref self: TContractState, token_l1_address: EthAddress, fee_range: FeeRange);
    fn set_fee_segment(
        ref self: TContractState, token_l1_address: EthAddress, tier: u8, fee_segment: FeeSegment
    );
}

#[starknet::interface]
trait IStarkwayHelper<TContractState> {
    fn get_supported_tokens_with_balance(
        self: @TContractState, user_address: ContractAddress
    ) -> Array<TokenInfo>;
    fn get_non_native_token_balances(
        self: @TContractState, user_address: ContractAddress, l1_token_address: EthAddress
    ) -> Array<TokenInfo>;
    fn get_supported_tokens(self: @TContractState) -> Array<TokenDetails>;
}

#[starknet::interface]
trait IReentrancyGuard<TContractState> {
    fn start(ref self: TContractState);
    fn end(ref self: TContractState);
}
