#[cfg(test)]
mod test_consume_message_plugin {
    use array::{Array, ArrayTrait, Span, SpanTrait};
    use core::Clone;
    use serde::Serde;
    use starknet::{ContractAddress, contract_address_const, EthAddress};
    use starknet::testing::set_contract_address;
    use traits::{Default, Into, TryInto};
    use starkway::interfaces::{IStarkwayDispatcher, IStarkwayDispatcherTrait};
    use starkway::starkway::Starkway;
    use starkway::plugins::consume_message_plugin::ConsumeMessagePlugin;
    use starkway::plugins::interfaces::{
        IConsumeMessagePluginDispatcher, IConsumeMessagePluginDispatcherTrait
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

    // function to deploy consume message plugin
    fn deploy_consume_message_plugin() -> (
        ContractAddress, ContractAddress, ContractAddress, ContractAddress
    ) {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();

        // Deploy Consume message plugin contract
        let mut calldata = ArrayTrait::<felt252>::new();
        starkway_address.serialize(ref calldata);
        let consume_message_plugin_address = deploy(
            ConsumeMessagePlugin::TEST_CLASS_HASH, 100, calldata
        );
        return (starkway_address, consume_message_plugin_address, admin_1, admin_2);
    }

    #[test]
    #[available_gas(20000000)]
    #[should_panic(expected: ('CMP:ONLY_STARKWAY_CALLS_ALLOWED', 'ENTRYPOINT_FAILED', ))]
    fn test_unauthorised_call_to_handle_starkway_deposit_message() {
        let (starkway_address, consume_message_plugin_address, admin_1, admin_2) =
            deploy_consume_message_plugin();
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };
        let consume_message_plugin = IConsumeMessagePluginDispatcher {
            contract_address: consume_message_plugin_address
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

        consume_message_plugin
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
    fn test_message_count_updation() {
        let (starkway_address, consume_message_plugin_address, admin_1, admin_2) =
            deploy_consume_message_plugin();
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };
        let consume_message_plugin = IConsumeMessagePluginDispatcher {
            contract_address: consume_message_plugin_address
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

        // Get no.of messages by params
        let (message_count, message_hash) = consume_message_plugin
            .number_of_messages_by_params(
                l1_token_address, l1_sender, user, consumer(), amount, message_payload.clone()
            );
        assert(message_count == 0, 'no_of_messages should be 0');

        // Get no.of messages by hash
        let message_count = consume_message_plugin.number_of_messages_by_hash(message_hash);
        assert(message_count == 0, 'no_of_messages should be 0');

        // Call deposit funds with message 
        starkway
            .deposit_with_message_test(
                l1_starkway.into(),
                l1_token_address,
                l1_sender,
                user,
                amount,
                fee,
                consume_message_plugin_address,
                message_payload.clone()
            );

        // Get no.of messages by params
        let (message_count, message_hash) = consume_message_plugin
            .number_of_messages_by_params(
                l1_token_address, l1_sender, user, consumer(), amount, message_payload.clone()
            );
        assert(message_count == 1, 'no_of_messages should be 1');

        // Get no.of messages by hash
        let message_count = consume_message_plugin.number_of_messages_by_hash(message_hash);
        assert(message_count == 1, 'no_of_messages should be 1');

        // Call deposit funds with message 
        starkway
            .deposit_with_message_test(
                l1_starkway.into(),
                l1_token_address,
                l1_sender,
                user,
                amount,
                fee,
                consume_message_plugin_address,
                message_payload.clone()
            );

        // Get no.of messages by params
        let (message_count, message_hash) = consume_message_plugin
            .number_of_messages_by_params(
                l1_token_address, l1_sender, user, consumer(), amount, message_payload
            );
        assert(message_count == 2, 'no_of_messages should be 2');

        // Get no.of messages by hash
        let message_count = consume_message_plugin.number_of_messages_by_hash(message_hash);
        assert(message_count == 2, 'no_of_messages should be 2');
    }

    #[test]
    #[available_gas(20000000)]
    fn test_consume_message() {
        let (starkway_address, consume_message_plugin_address, admin_1, admin_2) =
            deploy_consume_message_plugin();
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };
        let consume_message_plugin = IConsumeMessagePluginDispatcher {
            contract_address: consume_message_plugin_address
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

        // Get no.of messages by params
        let (message_count, message_hash) = consume_message_plugin
            .number_of_messages_by_params(
                l1_token_address, l1_sender, user, consumer(), amount, message_payload.clone()
            );
        assert(message_count == 0, 'no_of_messages should be 0');

        // Get no.of messages by hash
        let message_count = consume_message_plugin.number_of_messages_by_hash(message_hash);
        assert(message_count == 0, 'no_of_messages should be 0');

        // Call deposit funds with message 
        starkway
            .deposit_with_message_test(
                l1_starkway.into(),
                l1_token_address,
                l1_sender,
                user,
                amount,
                fee,
                consume_message_plugin_address,
                message_payload.clone()
            );

        // Get no.of messages by params
        let (message_count, message_hash) = consume_message_plugin
            .number_of_messages_by_params(
                l1_token_address, l1_sender, user, consumer(), amount, message_payload.clone()
            );
        assert(message_count == 1, 'no_of_messages should be 1');

        // Get no.of messages by hash
        let message_count = consume_message_plugin.number_of_messages_by_hash(message_hash);
        assert(message_count == 1, 'no_of_messages should be 1');

        // Set contract address as the consumer address
        set_contract_address(consumer());

        // Consume message will decrement the message count
        consume_message_plugin
            .consume_message(l1_token_address, l1_sender, user, amount, message_payload.clone());

        // Get no.of messages by params
        let (message_count, message_hash) = consume_message_plugin
            .number_of_messages_by_params(
                l1_token_address, l1_sender, user, consumer(), amount, message_payload.clone()
            );
        assert(message_count == 0, 'no_of_messages should be 0');

        // Get no.of messages by hash
        let message_count = consume_message_plugin.number_of_messages_by_hash(message_hash);
        assert(message_count == 0, 'no_of_messages should be 0');

        // Call deposit funds with message 
        starkway
            .deposit_with_message_test(
                l1_starkway.into(),
                l1_token_address,
                l1_sender,
                user,
                amount,
                fee,
                consume_message_plugin_address,
                message_payload.clone()
            );

        // Get no.of messages by params
        let (message_count, message_hash) = consume_message_plugin
            .number_of_messages_by_params(
                l1_token_address, l1_sender, user, consumer(), amount, message_payload
            );
        assert(message_count == 1, 'no_of_messages should be 1');

        // Get no.of messages by hash
        let message_count = consume_message_plugin.number_of_messages_by_hash(message_hash);
        assert(message_count == 1, 'no_of_messages should be 1');
    }

    #[test]
    #[available_gas(20000000)]
    #[should_panic(expected: ('CMP: INVALID_MESSAGE_TO_CONSUME', 'ENTRYPOINT_FAILED', ))]
    fn test_invalid_message_to_consume() {
        let (starkway_address, consume_message_plugin_address, admin_1, admin_2) =
            deploy_consume_message_plugin();
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };
        let consume_message_plugin = IConsumeMessagePluginDispatcher {
            contract_address: consume_message_plugin_address
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

        // Get no.of messages by params
        let (message_count, message_hash) = consume_message_plugin
            .number_of_messages_by_params(
                l1_token_address, l1_sender, user, consumer(), amount, message_payload.clone()
            );
        assert(message_count == 0, 'no_of_messages should be 0');

        // Get no.of messages by hash
        let message_count = consume_message_plugin.number_of_messages_by_hash(message_hash);
        assert(message_count == 0, 'no_of_messages should be 0');

        // Call deposit funds with message 
        starkway
            .deposit_with_message_test(
                l1_starkway.into(),
                l1_token_address,
                l1_sender,
                user,
                amount,
                fee,
                consume_message_plugin_address,
                message_payload.clone()
            );

        // Get no.of messages by params
        let (message_count, message_hash) = consume_message_plugin
            .number_of_messages_by_params(
                l1_token_address, l1_sender, user, consumer(), amount, message_payload.clone()
            );
        assert(message_count == 1, 'no_of_messages should be 1');

        // Get no.of messages by hash
        let message_count = consume_message_plugin.number_of_messages_by_hash(message_hash);
        assert(message_count == 1, 'no_of_messages should be 1');

        // Consume message will throw an error becuase, caller is not the consumer address
        // So, Computed message hash will be different 
        consume_message_plugin
            .consume_message(l1_token_address, l1_sender, user, amount, message_payload.clone());
    }
}
