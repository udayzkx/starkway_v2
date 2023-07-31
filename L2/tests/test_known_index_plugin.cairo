#[cfg(test)]
mod test_known_index_plugin {
    use array::{Array, ArrayTrait, Span, SpanTrait};
    use core::integer::u32_to_felt252;
    use serde::Serde;
    use starknet::{ContractAddress, contract_address_const, EthAddress, get_block_timestamp};
    use starknet::testing::{set_caller_address, set_contract_address, pop_log};
    use traits::{Default, Into, TryInto};
    use starkway::interfaces::{
        IStarkwayDispatcher, IStarkwayDispatcherTrait, IERC20Dispatcher, IERC20DispatcherTrait,
    };
    use starkway::starkway::Starkway;
    use starkway::plugins::known_index_plugin::KnownIndexPlugin;
    use starkway::plugins::datatypes::MessageBasicInfo;
    use starkway::plugins::interfaces::{
        IKnownIndexPluginDispatcher, IKnownIndexPluginDispatcherTrait
    };
    use tests::utils::{setup, deploy, init_token};

    fn deploy_known_index_plugin() -> (
        ContractAddress, ContractAddress, ContractAddress, ContractAddress
    ) {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();

        // Deploy known index plugin contract
        let mut calldata = ArrayTrait::<felt252>::new();
        starkway_address.serialize(ref calldata);
        let known_index_plugin_address = deploy(KnownIndexPlugin::TEST_CLASS_HASH, 100, calldata);
        return (starkway_address, known_index_plugin_address, admin_1, admin_2);
    }

    #[test]
    #[available_gas(20000000)]
    #[should_panic(expected: ('KIP:ONLY_STARKWAY_CALLS_ALLOWED', 'ENTRYPOINT_FAILED', ))]
    fn test_unauthorised_call_to_handle_starkway_deposit_message() {
        let (starkway_address, known_index_plugin_address, admin_1, admin_2) =
            deploy_known_index_plugin();
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };
        let known_index_plugin = IKnownIndexPluginDispatcher {
            contract_address: known_index_plugin_address
        };

        let l1_token_address = EthAddress { address: 100_felt252 };
        let l1_sender = EthAddress { address: 300_felt252 };
        let user = contract_address_const::<3000>();
        init_token(starkway_address, admin_1, l1_token_address);

        let native_erc20_address = starkway.get_native_token_address(l1_token_address);
        let amount = u256 { low: 1000, high: 0 };
        let fee = u256 { low: 20, high: 0 };

        let mut message_payload = ArrayTrait::<felt252>::new();
        l1_sender.serialize(ref message_payload);
        1_u32.serialize(ref message_payload);

        known_index_plugin
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
    // Tests correct flow with payload data of length 2
    fn test_simple_custom_data() {
        let (starkway_address, known_index_plugin_address, admin_1, admin_2) =
            deploy_known_index_plugin();
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };
        let known_index_plugin = IKnownIndexPluginDispatcher {
            contract_address: known_index_plugin_address
        };

        let l1_token_address = EthAddress { address: 100_felt252 };
        let l1_starkway = EthAddress { address: 200_felt252 };
        let l1_sender = EthAddress { address: 300_felt252 };
        let user = contract_address_const::<3000>();
        init_token(starkway_address, admin_1, l1_token_address);

        let native_erc20_address = starkway.get_native_token_address(l1_token_address);
        let erc20 = IERC20Dispatcher { contract_address: native_erc20_address };

        set_contract_address(admin_1);
        starkway.set_l1_starkway_address(l1_starkway);

        let balance_user_before = erc20.balance_of(user);
        let balance_starkway_before = erc20.balance_of(starkway_address);
        let total_supply_before = erc20.total_supply();
        let fees_before = starkway.get_cumulative_fees(l1_token_address);
        let amount = u256 { low: 100, high: 0 };
        let fee = u256 { low: 2, high: 0 };
        let index = 0_u32;

        let mut message_payload = ArrayTrait::<felt252>::new();
        l1_sender.serialize(ref message_payload);
        index.serialize(ref message_payload);

        // Call deposit funds with message 
        starkway
            .deposit_with_message_test(
                l1_starkway.into(),
                l1_token_address,
                l1_sender,
                user,
                amount,
                fee,
                known_index_plugin_address,
                message_payload
            );

        let balance_user_after = erc20.balance_of(user);
        let balance_starkway_after = erc20.balance_of(starkway_address);
        let total_supply_after = erc20.total_supply();
        let fees_after = starkway.get_cumulative_fees(l1_token_address);

        assert(balance_user_before == balance_user_after - amount, 'Incorrect user balance');
        assert(
            balance_starkway_before == balance_starkway_after - fee, 'Incorrect Starkway balance'
        );
        assert(total_supply_before == total_supply_after - amount - fee, 'Incorrect total supply');
        assert(fees_before == fees_after - fee, 'Incorrect Fee');

        // get last message info
        let message_basic_info: MessageBasicInfo = known_index_plugin
            .get_last_message_info(l1_sender, user, l1_sender, index);
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

        // Get last message
        let (message_basic_info, message_payload) = known_index_plugin
            .get_last_message(l1_sender, user, l1_sender, index);
        assert(message_payload.len() == 2_u32, 'Mismatch in payload length');
        assert(*message_payload.at(0) == l1_sender.into(), 'Mismatch in l1 sender address');
        assert(*message_payload.at(1) == u32_to_felt252(0_u32), 'Mismatch in index');
    }

    #[test]
    #[available_gas(20000000)]
    // Tests message update for the same key
    fn test_data_update() {
        let (starkway_address, known_index_plugin_address, admin_1, admin_2) =
            deploy_known_index_plugin();
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };
        let known_index_plugin = IKnownIndexPluginDispatcher {
            contract_address: known_index_plugin_address
        };

        let l1_token_address = EthAddress { address: 100_felt252 };
        let l1_starkway = EthAddress { address: 200_felt252 };
        let l1_sender = EthAddress { address: 300_felt252 };
        let user = contract_address_const::<3000>();
        init_token(starkway_address, admin_1, l1_token_address);

        let native_erc20_address = starkway.get_native_token_address(l1_token_address);
        let erc20 = IERC20Dispatcher { contract_address: native_erc20_address };

        set_contract_address(admin_1);
        starkway.set_l1_starkway_address(l1_starkway);

        let balance_user_before = erc20.balance_of(user);
        let balance_starkway_before = erc20.balance_of(starkway_address);
        let total_supply_before = erc20.total_supply();
        let fees_before = starkway.get_cumulative_fees(l1_token_address);
        let amount = u256 { low: 100, high: 0 };
        let fee = u256 { low: 2, high: 0 };
        let index = 0_u32;

        let mut message_payload1 = ArrayTrait::<felt252>::new();
        l1_sender.serialize(ref message_payload1);
        index.serialize(ref message_payload1);
        10_u32.serialize(ref message_payload1);
        20_u32.serialize(ref message_payload1);

        // 1st message 
        starkway
            .deposit_with_message_test(
                l1_starkway.into(),
                l1_token_address,
                l1_sender,
                user,
                amount,
                fee,
                known_index_plugin_address,
                message_payload1
            );

        let balance_user_after = erc20.balance_of(user);
        let balance_starkway_after = erc20.balance_of(starkway_address);
        let total_supply_after = erc20.total_supply();
        let fees_after = starkway.get_cumulative_fees(l1_token_address);

        assert(balance_user_before == balance_user_after - amount, 'Incorrect user balance');
        assert(
            balance_starkway_before == balance_starkway_after - fee, 'Incorrect Starkway balance'
        );
        assert(total_supply_before == total_supply_after - amount - fee, 'Incorrect total supply');
        assert(fees_before == fees_after - fee, 'Incorrect Fee');

        // get last message info
        let message_basic_info: MessageBasicInfo = known_index_plugin
            .get_last_message_info(l1_sender, user, l1_sender, index);
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
        assert(message_basic_info.message_payload_len == 4_u32, 'Mismatch in payload length');

        // Get last message
        let (message_basic_info, message_payload) = known_index_plugin
            .get_last_message(l1_sender, user, l1_sender, index);
        assert(message_payload.len() == 4_u32, 'Mismatch in payload length');
        assert(*message_payload.at(0) == l1_sender.into(), 'Mismatch in l1 sender address');
        assert(*message_payload.at(1) == u32_to_felt252(0_u32), 'Mismatch in index');
        assert(*message_payload.at(2) == u32_to_felt252(10_u32), 'Mismatch in data');
        assert(*message_payload.at(3) == u32_to_felt252(20_u32), 'Mismatch in data');

        // 2nd message 
        let balance_user_before = erc20.balance_of(user);
        let balance_starkway_before = erc20.balance_of(starkway_address);
        let total_supply_before = erc20.total_supply();
        let fees_before = starkway.get_cumulative_fees(l1_token_address);
        let amount2 = u256 { low: 1000, high: 0 };
        let fee2 = u256 { low: 20, high: 0 };

        let mut message_payload2 = ArrayTrait::<felt252>::new();
        l1_sender.serialize(ref message_payload2);
        index.serialize(ref message_payload2);
        100_u32.serialize(ref message_payload2);
        200_u32.serialize(ref message_payload2);

        starkway
            .deposit_with_message_test(
                l1_starkway.into(),
                l1_token_address,
                l1_sender,
                user,
                amount2,
                fee2,
                known_index_plugin_address,
                message_payload2
            );

        let balance_user_after = erc20.balance_of(user);
        let balance_starkway_after = erc20.balance_of(starkway_address);
        let total_supply_after = erc20.total_supply();
        let fees_after = starkway.get_cumulative_fees(l1_token_address);

        assert(balance_user_before == balance_user_after - amount2, 'Incorrect user balance');
        assert(
            balance_starkway_before == balance_starkway_after - fee2, 'Incorrect Starkway balance'
        );
        assert(
            total_supply_before == total_supply_after - amount2 - fee2, 'Incorrect total supply'
        );
        assert(fees_before == fees_after - fee2, 'Incorrect Fee');

        // get last message info
        let message_basic_info: MessageBasicInfo = known_index_plugin
            .get_last_message_info(l1_sender, user, l1_sender, index);
        assert(
            message_basic_info.l1_token_address == l1_token_address, 'Mismatch in l1 token address'
        );
        assert(
            message_basic_info.l2_token_address == native_erc20_address,
            'Mismatch in l2 token address'
        );
        assert(message_basic_info.l1_sender_address == l1_sender, 'Mismatch in l1 sender');
        assert(message_basic_info.l2_recipient_address == user, 'Mismatch in l2 recipient');
        assert(message_basic_info.amount == amount2, 'Mismatch in amount');
        assert(message_basic_info.fee == fee2, 'Mismatch in fee');
        assert(message_basic_info.timestamp == get_block_timestamp(), 'Mismatch inblock timestamp');
        assert(message_basic_info.message_payload_len == 4_u32, 'Mismatch in payload length');

        // Get last message
        let (message_basic_info, message_payload) = known_index_plugin
            .get_last_message(l1_sender, user, l1_sender, index);
        assert(message_payload.len() == 4_u32, 'Mismatch in payload length');
        assert(*message_payload.at(0) == l1_sender.into(), 'Mismatch in l1 sender address');
        assert(*message_payload.at(1) == u32_to_felt252(0_u32), 'Mismatch in index');
        assert(*message_payload.at(2) == u32_to_felt252(100_u32), 'Mismatch in data');
        assert(*message_payload.at(3) == u32_to_felt252(200_u32), 'Mismatch in data');
    }
}
