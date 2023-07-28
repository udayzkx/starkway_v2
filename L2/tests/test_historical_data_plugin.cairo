#[cfg(test)]
mod test_historical_data_plugin {
    use array::{Array, ArrayTrait, Span, SpanTrait};
    use serde::Serde;
    use starknet::{ContractAddress, contract_address_const, EthAddress, get_block_timestamp};
    use starknet::testing::{set_caller_address, set_contract_address, pop_log};
    use traits::{Default, Into, TryInto};
    use starkway::interfaces::{
        IStarkwayDispatcher, IStarkwayDispatcherTrait, IERC20Dispatcher, IERC20DispatcherTrait,
    };
    use starkway::starkway::Starkway;
    use starkway::plugins::historical_data_plugin::HistoricalDataPlugin;
    use starkway::plugins::datatypes::MessageBasicInfo;
    use starkway::plugins::interfaces::{
        IHistoricalDataPluginDispatcher, IHistoricalDataPluginDispatcherTrait
    };
    use tests::utils::{setup, deploy, init_token};

    // Mock L1 users in our system
    fn USER1() -> EthAddress {
        EthAddress { address: 100_felt252 }
    }

    fn USER2() -> EthAddress {
        EthAddress { address: 200_felt252 }
    }

    fn consumer() -> ContractAddress {
        contract_address_const::<123>()
    }

    // function to deploy historical data plugin
    fn deploy_historical_data_plugin() -> (
        ContractAddress, ContractAddress, ContractAddress, ContractAddress
    ) {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();

        // Deploy historical data plugin contract
        let mut calldata = ArrayTrait::<felt252>::new();
        starkway_address.serialize(ref calldata);
        let historical_data_plugin_address = deploy(
            HistoricalDataPlugin::TEST_CLASS_HASH, 100, calldata
        );
        return (starkway_address, historical_data_plugin_address, admin_1, admin_2);
    }

    #[test]
    #[available_gas(20000000)]
    #[should_panic(expected: ('HDP: Caller not SW', 'ENTRYPOINT_FAILED', ))]
    fn test_unauthorised_call_to_handle_starkway_deposit_message() {
        let (starkway_address, historical_data_plugin_address, admin_1, admin_2) =
            deploy_historical_data_plugin();
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };
        let historical_data_plugin = IHistoricalDataPluginDispatcher {
            contract_address: historical_data_plugin_address
        };

        let l1_token_address = EthAddress { address: 100_felt252 };
        let l1_sender = EthAddress { address: 300_felt252 };
        let user = contract_address_const::<3000>();
        init_token(starkway_address, admin_1, l1_token_address);

        let native_erc20_address = starkway.get_native_token_address(l1_token_address);
        let amount = u256 { low: 1000, high: 0 };
        let fee = u256 { low: 20, high: 0 };

        let mut message_payload = ArrayTrait::<felt252>::new();
        consumer().serialize(ref message_payload);

        historical_data_plugin
            .handle_starkway_deposit_message(
                l1_token_address,
                native_erc20_address,
                l1_sender,
                user,
                amount,
                fee,
                message_payload
            );
    }

    #[test]
    #[available_gas(20000000)]
    #[should_panic(expected: ('HDP: Invalid payload length', 'ENTRYPOINT_FAILED', ))]
    fn test_invalid_payload_size() {
        let (starkway_address, historical_data_plugin_address, admin_1, admin_2) =
            deploy_historical_data_plugin();
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };
        let historical_data_plugin = IHistoricalDataPluginDispatcher {
            contract_address: historical_data_plugin_address
        };

        let l1_token_address = EthAddress { address: 100_felt252 };
        let l1_sender = EthAddress { address: 300_felt252 };
        let user = contract_address_const::<3000>();
        init_token(starkway_address, admin_1, l1_token_address);

        let native_erc20_address = starkway.get_native_token_address(l1_token_address);
        let amount = u256 { low: 1000, high: 0 };
        let fee = u256 { low: 20, high: 0 };

        let mut message_payload = ArrayTrait::<felt252>::new();

        // Making starkway as the caller
        set_contract_address(starkway_address);

        // Calling handle_starkway_deposit_message with zero payload size
        historical_data_plugin
            .handle_starkway_deposit_message(
                l1_token_address,
                native_erc20_address,
                l1_sender,
                user,
                amount,
                fee,
                message_payload
            );
    }

    #[test]
    #[available_gas(20000000)]
    fn test_set_permission() {
        let (starkway_address, historical_data_plugin_address, admin_1, admin_2) =
            deploy_historical_data_plugin();
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };
        let historical_data_plugin = IHistoricalDataPluginDispatcher {
            contract_address: historical_data_plugin_address
        };

        let is_allowed = historical_data_plugin.is_allowed_to_write(starkway_address, USER1());
        assert(is_allowed == true, 'USER1 should be allowed towrite');

        // Making starkway as the caller
        set_contract_address(starkway_address);

        // allow list not applicable since globally allow list based permission not yet enabled
        let is_allowed = historical_data_plugin.is_allowed_to_write(starkway_address, USER2());
        assert(is_allowed == true, 'USER2 should be allowed towrite');

        // allow list now enabled but empty - meaning no address can write to message list
        historical_data_plugin.set_permission_required(true);

        //address has to be added explicitly to allow list to get permission to write to message list via deposit
        let is_allowed = historical_data_plugin.is_allowed_to_write(starkway_address, USER1());
        assert(is_allowed == false, 'USER1 should not be allowed');
    }

    #[test]
    #[available_gas(20000000)]
    #[should_panic(
        expected: ('HDP: Unauthorised write', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED', )
    )]
    fn test_unauthorised_write() {
        let (starkway_address, historical_data_plugin_address, admin_1, admin_2) =
            deploy_historical_data_plugin();
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };
        let historical_data_plugin = IHistoricalDataPluginDispatcher {
            contract_address: historical_data_plugin_address
        };

        let l1_token_address = EthAddress { address: 100_felt252 };
        let l1_starkway = EthAddress { address: 200_felt252 };
        let l1_sender = EthAddress { address: 300_felt252 };
        let user = contract_address_const::<3000>();
        let amount = u256 { low: 100, high: 0 };
        let fee = u256 { low: 2, high: 0 };
        let index = 0_u32;

        // Iniatialise token
        init_token(starkway_address, admin_1, l1_token_address);

        // get native erc20 address
        let native_erc20_address = starkway.get_native_token_address(l1_token_address);

        // set l1 starkway contract address
        starkway.set_l1_starkway_address(l1_starkway);

        // Frame message payload
        let mut message_payload = ArrayTrait::<felt252>::new();
        consumer().serialize(ref message_payload);

        set_contract_address(consumer());
        historical_data_plugin.set_permission_required(true);

        // Call deposit funds with message 
        starkway
            .deposit_with_message_test(
                l1_starkway.into(),
                l1_token_address,
                l1_sender,
                user,
                amount,
                fee,
                historical_data_plugin_address,
                message_payload
            );
    }

    #[test]
    #[available_gas(20000000)]
    fn test_add_to_allow_list() {
        let (starkway_address, historical_data_plugin_address, admin_1, admin_2) =
            deploy_historical_data_plugin();
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };
        let historical_data_plugin = IHistoricalDataPluginDispatcher {
            contract_address: historical_data_plugin_address
        };

        // Get length of allow list
        let len = historical_data_plugin.get_allow_list_len(consumer());
        assert(len == 0_u32, 'allow list len should be 0');

        // Get allow list
        let list = historical_data_plugin.get_allow_list(consumer());
        assert(list.len() == 0_u32, 'allow list len should be 0');

        let l1_token_address = EthAddress { address: 100_felt252 };
        let l1_starkway = EthAddress { address: 200_felt252 };
        let l1_sender = EthAddress { address: 300_felt252 };
        let user = contract_address_const::<3000>();
        let amount = u256 { low: 100, high: 0 };
        let fee = u256 { low: 2, high: 0 };
        let index = 0_u32;

        // Iniatialise token
        init_token(starkway_address, admin_1, l1_token_address);

        // get native erc20 address
        let native_erc20_address = starkway.get_native_token_address(l1_token_address);

        // set l1 starkway contract address
        starkway.set_l1_starkway_address(l1_starkway);

        // Frame message payload
        let mut message_payload = ArrayTrait::<felt252>::new();
        consumer().serialize(ref message_payload);

        set_contract_address(consumer());

        // Enable permission to write for the consumer
        historical_data_plugin.set_permission_required(true);

        // Add l1_sender to be allowed to write
        historical_data_plugin.add_to_allow_list(l1_sender);

        // Call deposit funds with message 
        starkway
            .deposit_with_message_test(
                l1_starkway.into(),
                l1_token_address,
                l1_sender,
                user,
                amount,
                fee,
                historical_data_plugin_address,
                message_payload
            );

        // Get length of allow list
        let len = historical_data_plugin.get_allow_list_len(consumer());
        assert(len == 1_u32, 'allow list len should be 1');

        // Get allow list
        let list = historical_data_plugin.get_allow_list(consumer());
        assert(list.len() == 1_u32, 'allow list len should be 1');
        assert(*list.at(0) == l1_sender, 'Mismatch in the l1 sender');

        // l1_sender address is allowed as it is added to allow_list
        let is_allowed = historical_data_plugin.is_allowed_to_write(consumer(), l1_sender);
        assert(is_allowed == true, 'l1_sender should allow towrite');

        // any other address is not allowed unless added to allow_list
        let is_allowed = historical_data_plugin.is_allowed_to_write(consumer(), USER1());
        assert(is_allowed == false, 'USER1 should not be allowed');

        // get message pointer
        let message_pointer = historical_data_plugin.get_message_pointer(consumer());
        assert(message_pointer == 0, 'message pointer should be 0');

        // get total messages count
        let total_messages_count = historical_data_plugin.get_total_messages_count(consumer());
        assert(total_messages_count == 1, 'total message count should be ');

        // get message at a particular index for a consumer
        let (message_basic_info, message_payload) = historical_data_plugin
            .get_message_at_index(consumer(), 0);
        assert(
            message_basic_info.l1_token_address == l1_token_address, 'Mismatch in l1 token address'
        );
        assert(
            message_basic_info.l2_token_address == native_erc20_address,
            'Mismatch in l2 token address'
        );
        assert(message_basic_info.l1_sender_address == l1_sender, 'Mismatch in l1 sender');
        assert(message_basic_info.l2_recipient_address == user, 'Mismatch in l2 recipient');
        assert(message_basic_info.amount == amount, 'Mismatch in amount');
        assert(message_basic_info.fee == fee, 'Mismatch in fee');
        assert(message_basic_info.timestamp == get_block_timestamp(), 'Mismatch inblock timestamp');
        assert(message_basic_info.message_payload_len == 1_u32, 'Mismatch in payload length');
        assert(message_payload.len() == 1_u32, 'Mismatch in payload length');
        assert(*message_payload.at(0) == consumer().into(), 'Mismatch in consumer address');

        // get message basic info for a consumer
        let message_basic_info = historical_data_plugin.get_message_info_at_index(consumer(), 0);
        assert(
            message_basic_info.l1_token_address == l1_token_address, 'Mismatch in l1 token address'
        );
        assert(
            message_basic_info.l2_token_address == native_erc20_address,
            'Mismatch in l2 token address'
        );
        assert(message_basic_info.l1_sender_address == l1_sender, 'Mismatch in l1 sender');
        assert(message_basic_info.l2_recipient_address == user, 'Mismatch in l2 recipient');
        assert(message_basic_info.amount == amount, 'Mismatch in amount');
        assert(message_basic_info.fee == fee, 'Mismatch in fee');
        assert(message_basic_info.timestamp == get_block_timestamp(), 'Mismatch inblock timestamp');
        assert(message_basic_info.message_payload_len == 1_u32, 'Mismatch in payload length');
    }

    #[test]
    #[available_gas(20000000)]
    #[should_panic(expected: ('HDP: Already whitelisted', 'ENTRYPOINT_FAILED'))]
    fn test_adding_already_added_address_to_allow_list() {
        let (starkway_address, historical_data_plugin_address, admin_1, admin_2) =
            deploy_historical_data_plugin();
        let historical_data_plugin = IHistoricalDataPluginDispatcher {
            contract_address: historical_data_plugin_address
        };

        // Add USER1 to be allow list
        historical_data_plugin.add_to_allow_list(USER1());

        // Add USER1 to the allow list again
        historical_data_plugin.add_to_allow_list(USER1());
    }

    #[test]
    #[available_gas(20000000)]
    fn test_remove_from_allow_list() {
        let (starkway_address, historical_data_plugin_address, admin_1, admin_2) =
            deploy_historical_data_plugin();
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };
        let historical_data_plugin = IHistoricalDataPluginDispatcher {
            contract_address: historical_data_plugin_address
        };

        // Get length of allow list
        let len = historical_data_plugin.get_allow_list_len(consumer());
        assert(len == 0_u32, 'allow list len should be 0');

        // Get allow list
        let list = historical_data_plugin.get_allow_list(consumer());
        assert(list.len() == 0_u32, 'allow list len should be 0');

        let l1_token_address = EthAddress { address: 100_felt252 };
        let l1_starkway = EthAddress { address: 200_felt252 };
        let l1_sender = EthAddress { address: 300_felt252 };
        let user = contract_address_const::<3000>();
        let amount = u256 { low: 100, high: 0 };
        let fee = u256 { low: 2, high: 0 };
        let index = 0_u32;

        // Iniatialise token
        init_token(starkway_address, admin_1, l1_token_address);

        // get native erc20 address
        let native_erc20_address = starkway.get_native_token_address(l1_token_address);

        // set l1 starkway contract address
        starkway.set_l1_starkway_address(l1_starkway);

        // Frame message payload
        let mut message_payload = ArrayTrait::<felt252>::new();
        consumer().serialize(ref message_payload);

        set_contract_address(consumer());

        // Enable permission to write for the consumer
        historical_data_plugin.set_permission_required(true);

        // Add l1_sender, USER1 and USER2 to be allowed to write
        historical_data_plugin.add_to_allow_list(l1_sender);
        historical_data_plugin.add_to_allow_list(USER1());
        historical_data_plugin.add_to_allow_list(USER2());

        // Send 1st message with l1_sender as the recipient 
        starkway
            .deposit_with_message_test(
                l1_starkway.into(),
                l1_token_address,
                l1_sender,
                user,
                amount,
                fee,
                historical_data_plugin_address,
                message_payload
            );

        // Get length of allow list
        let len = historical_data_plugin.get_allow_list_len(consumer());
        assert(len == 3_u32, 'allow list len should be 3');

        // Get allow list
        let list = historical_data_plugin.get_allow_list(consumer());
        assert(list.len() == 3_u32, 'allow list len should be 3');
        assert(*list.at(0) == l1_sender, 'Mismatch in the l1 address');
        assert(*list.at(1) == USER1(), 'Mismatch in the l1 address');
        assert(*list.at(2) == USER2(), 'Mismatch in the l1 address');

        // l1_sender address is allowed as it is added to allow_list
        let is_allowed = historical_data_plugin.is_allowed_to_write(consumer(), l1_sender);
        assert(is_allowed == true, 'l1_sender should allow towrite');

        // Remove USER1 from allowed list
        historical_data_plugin.remove_from_allow_list(USER1());

        // USER1 is removed from allow list, so is_allwed will return false
        let is_allowed = historical_data_plugin.is_allowed_to_write(consumer(), USER1());
        assert(is_allowed == false, 'USER1 should not be allowed');

        // get message pointer
        let message_pointer = historical_data_plugin.get_message_pointer(consumer());
        assert(message_pointer == 0, 'message pointer should be 0');

        // get total messages count
        let total_messages_count = historical_data_plugin.get_total_messages_count(consumer());
        assert(total_messages_count == 1, 'total message count should be 1');

        // get message at a particular index for a consumer
        let (message_basic_info, message_payload) = historical_data_plugin
            .get_message_at_index(consumer(), 0);
        assert(
            message_basic_info.l1_token_address == l1_token_address, 'Mismatch in l1 token address'
        );
        assert(
            message_basic_info.l2_token_address == native_erc20_address,
            'Mismatch in l2 token address'
        );
        assert(message_basic_info.l1_sender_address == l1_sender, 'Mismatch in l1 sender');
        assert(message_basic_info.l2_recipient_address == user, 'Mismatch in l2 recipient');
        assert(message_basic_info.amount == amount, 'Mismatch in amount');
        assert(message_basic_info.fee == fee, 'Mismatch in fee');
        assert(message_basic_info.timestamp == get_block_timestamp(), 'Mismatch inblock timestamp');
        assert(message_basic_info.message_payload_len == 1_u32, 'Mismatch in payload length');
        assert(message_payload.len() == 1_u32, 'Mismatch in payload length');
        assert(*message_payload.at(0) == consumer().into(), 'Mismatch in consumer address');

        // Send 2nd message with USER2 as the recipient
        starkway
            .deposit_with_message_test(
                l1_starkway.into(),
                l1_token_address,
                USER2(),
                user,
                amount,
                fee,
                historical_data_plugin_address,
                message_payload
            );

        // USER2 is removed from allow list, so is_allwed will return false
        let is_allowed = historical_data_plugin.is_allowed_to_write(consumer(), USER2());
        assert(is_allowed == true, 'USER2 should be allowed');

        // get message pointer
        let message_pointer = historical_data_plugin.get_message_pointer(consumer());
        assert(message_pointer == 0, 'message pointer should be 0');

        // get total messages count
        let total_messages_count = historical_data_plugin.get_total_messages_count(consumer());
        assert(total_messages_count == 2, 'total message count should be 2');

        // Get length of allow list
        let len = historical_data_plugin.get_allow_list_len(consumer());
        assert(len == 2_u32, 'allow list len should be 2');

        // Get allow list
        let list = historical_data_plugin.get_allow_list(consumer());
        assert(list.len() == 2_u32, 'allow list len should be 2');
        assert(*list.at(0) == l1_sender, 'Mismatch in the l1 address');
        assert(*list.at(1) == USER2(), 'Mismatch in the l1 address');
    }

    #[test]
    #[available_gas(20000000)]
    #[should_panic(expected: ('HDP: Already de-whitelisted', 'ENTRYPOINT_FAILED', ))]
    fn test_removing_already_removed_address_from_allow_list() {
        let (starkway_address, historical_data_plugin_address, admin_1, admin_2) =
            deploy_historical_data_plugin();
        let historical_data_plugin = IHistoricalDataPluginDispatcher {
            contract_address: historical_data_plugin_address
        };

        // Add USER1 to be allow list
        historical_data_plugin.add_to_allow_list(USER1());

        // remove USER1 from the allow list 
        historical_data_plugin.remove_from_allow_list(USER1());

        // remove USER1 from the allow list again
        historical_data_plugin.remove_from_allow_list(USER1());
    }

    #[test]
    #[available_gas(20000000)]
    fn test_message_pointer_updation() {
        let (starkway_address, historical_data_plugin_address, admin_1, admin_2) =
            deploy_historical_data_plugin();
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };
        let historical_data_plugin = IHistoricalDataPluginDispatcher {
            contract_address: historical_data_plugin_address
        };

        // Get length of allow list
        let len = historical_data_plugin.get_allow_list_len(consumer());
        assert(len == 0_u32, 'allow list len should be 0');

        // Get allow list
        let list = historical_data_plugin.get_allow_list(consumer());
        assert(list.len() == 0_u32, 'allow list len should be 0');

        let l1_token_address = EthAddress { address: 100_felt252 };
        let l1_starkway = EthAddress { address: 200_felt252 };
        let l1_sender = EthAddress { address: 300_felt252 };
        let user = contract_address_const::<3000>();
        let amount = u256 { low: 100, high: 0 };
        let fee = u256 { low: 2, high: 0 };
        let index = 0_u32;

        // Iniatialise token
        init_token(starkway_address, admin_1, l1_token_address);

        // get native erc20 address
        let native_erc20_address = starkway.get_native_token_address(l1_token_address);

        // set l1 starkway contract address
        starkway.set_l1_starkway_address(l1_starkway);

        // Frame message payload
        let mut message_payload = ArrayTrait::<felt252>::new();
        consumer().serialize(ref message_payload);

        set_contract_address(consumer());

        // Enable permission to write for the consumer
        historical_data_plugin.set_permission_required(true);

        // Add l1_sender to be allowed to write
        historical_data_plugin.add_to_allow_list(l1_sender);

        // Call deposit funds with message 
        starkway
            .deposit_with_message_test(
                l1_starkway.into(),
                l1_token_address,
                l1_sender,
                user,
                amount,
                fee,
                historical_data_plugin_address,
                message_payload
            );

        // Get length of allow list
        let len = historical_data_plugin.get_allow_list_len(consumer());
        assert(len == 1_u32, 'allow list len should be 1');

        // Get allow list
        let list = historical_data_plugin.get_allow_list(consumer());
        assert(list.len() == 1_u32, 'allow list len should be 1');
        assert(*list.at(0) == l1_sender, 'Mismatch in the l1 sender');

        // get message pointer
        let message_pointer = historical_data_plugin.get_message_pointer(consumer());
        assert(message_pointer == 0, 'message pointer should be 0');

        // get total messages count
        let total_messages_count = historical_data_plugin.get_total_messages_count(consumer());
        assert(total_messages_count == 1, 'total message count should be ');

        // get message at the pointer pointed by message pointer and advance the pointer
        let (message_basic_info, message_payload) = historical_data_plugin
            .fetch_next_message_and_move_pointer();
        assert(
            message_basic_info.l1_token_address == l1_token_address, 'Mismatch in l1 token address'
        );
        assert(
            message_basic_info.l2_token_address == native_erc20_address,
            'Mismatch in l2 token address'
        );
        assert(message_basic_info.l1_sender_address == l1_sender, 'Mismatch in l1 sender');
        assert(message_basic_info.l2_recipient_address == user, 'Mismatch in l2 recipient');
        assert(message_basic_info.amount == amount, 'Mismatch in amount');
        assert(message_basic_info.fee == fee, 'Mismatch in fee');
        assert(message_basic_info.timestamp == get_block_timestamp(), 'Mismatch inblock timestamp');
        assert(message_basic_info.message_payload_len == 1_u32, 'Mismatch in payload length');
        assert(message_payload.len() == 1_u32, 'Mismatch in payload length');
        assert(*message_payload.at(0) == consumer().into(), 'Mismatch in consumer address');

        // get message pointer
        let message_pointer = historical_data_plugin.get_message_pointer(consumer());
        assert(message_pointer == 1, 'message pointer should be 1');

        let mut message_payload2 = ArrayTrait::<felt252>::new();
        consumer().serialize(ref message_payload2);
        100_u32.serialize(ref message_payload2);

        // Sending 2nd deposit with message
        starkway
            .deposit_with_message_test(
                l1_starkway.into(),
                l1_token_address,
                l1_sender,
                user,
                amount,
                fee,
                historical_data_plugin_address,
                message_payload2
            );

        // message pointer still unchanged since fetch_and_update has not been called
        let message_pointer = historical_data_plugin.get_message_pointer(consumer());
        assert(message_pointer == 1, 'message pointer should be 1');

        let mut message_payload3 = ArrayTrait::<felt252>::new();
        consumer().serialize(ref message_payload3);
        100_u32.serialize(ref message_payload3);
        200_u32.serialize(ref message_payload3);

        // Sending 3rd deposit with message
        starkway
            .deposit_with_message_test(
                l1_starkway.into(),
                l1_token_address,
                l1_sender,
                user,
                amount,
                fee,
                historical_data_plugin_address,
                message_payload3
            );

        // message pointer still unchanged since fetch_and_update has not been called
        let message_pointer = historical_data_plugin.get_message_pointer(consumer());
        assert(message_pointer == 1, 'message pointer should be 1');

        // fetch the message (it fetches 2nd message) and increments the pointer
        let (message_basic_info, message_payload) = historical_data_plugin
            .fetch_next_message_and_move_pointer();
        assert(
            message_basic_info.l1_token_address == l1_token_address, 'Mismatch in l1 token address'
        );
        assert(
            message_basic_info.l2_token_address == native_erc20_address,
            'Mismatch in l2 token address'
        );
        assert(message_basic_info.l1_sender_address == l1_sender, 'Mismatch in l1 sender');
        assert(message_basic_info.l2_recipient_address == user, 'Mismatch in l2 recipient');
        assert(message_basic_info.amount == amount, 'Mismatch in amount');
        assert(message_basic_info.fee == fee, 'Mismatch in fee');
        assert(message_basic_info.timestamp == get_block_timestamp(), 'Mismatch inblock timestamp');
        assert(message_basic_info.message_payload_len == 2_u32, 'Mismatch in payload length');
        assert(message_payload.len() == 2_u32, 'Mismatch in payload length');
        assert(*message_payload.at(0) == consumer().into(), 'Mismatch in consumer address');
        assert(*message_payload.at(1) == 100, 'Mismatch in data');

        // message pointer changed now as we called fetch_and_update
        let message_pointer = historical_data_plugin.get_message_pointer(consumer());
        assert(message_pointer == 2, 'message pointer should be 2');

        // fetch the message (it fetches 3rd message) and increments the pointer
        let (message_basic_info, message_payload) = historical_data_plugin
            .fetch_next_message_and_move_pointer();
        assert(
            message_basic_info.l1_token_address == l1_token_address, 'Mismatch in l1 token address'
        );
        assert(
            message_basic_info.l2_token_address == native_erc20_address,
            'Mismatch in l2 token address'
        );
        assert(message_basic_info.l1_sender_address == l1_sender, 'Mismatch in l1 sender');
        assert(message_basic_info.l2_recipient_address == user, 'Mismatch in l2 recipient');
        assert(message_basic_info.amount == amount, 'Mismatch in amount');
        assert(message_basic_info.fee == fee, 'Mismatch in fee');
        assert(message_basic_info.timestamp == get_block_timestamp(), 'Mismatch inblock timestamp');
        assert(message_basic_info.message_payload_len == 3_u32, 'Mismatch in payload length');
        assert(message_payload.len() == 3_u32, 'Mismatch in payload length');
        assert(*message_payload.at(0) == consumer().into(), 'Mismatch in consumer address');
        assert(*message_payload.at(1) == 100, 'Mismatch in data');
        assert(*message_payload.at(2) == 200, 'Mismatch in data');

        // message pointer changed now as we called fetch_and_update
        let message_pointer = historical_data_plugin.get_message_pointer(consumer());
        assert(message_pointer == 3, 'message pointer should be 3');
    }
}
