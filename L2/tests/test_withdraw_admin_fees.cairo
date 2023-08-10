#[cfg(test)]
mod test_withdraw_admin_fees {
    use array::{Array, ArrayTrait, Span, SpanTrait};
    use core::hash::{LegacyHashFelt252};
    use option::OptionTrait;
    use serde::Serde;
    use starknet::{ContractAddress, contract_address_const, EthAddress};
    use starknet::testing::{set_caller_address, set_contract_address, pop_log_raw};
    use traits::{Default, Into, TryInto};
    use starkway::erc20::erc20::StarkwayERC20;
    use starkway::interfaces::{
        IAdminAuthDispatcher, IAdminAuthDispatcherTrait, IStarkwayDispatcher,
        IStarkwayDispatcherTrait, IERC20Dispatcher, IERC20DispatcherTrait, IBridgeAdapterDispatcher,
        IBridgeAdapterDispatcherTrait
    };
    use starkway::starkway::Starkway;
    use zeroable::Zeroable;
    use tests::utils::{
        setup, deploy, mint, init_token, register_bridge_adapter, deploy_non_native_token,
        whitelist_token
    };
    use tests::utils::DummyAdapter;

    // Mock user in our system
    fn USER1() -> ContractAddress {
        contract_address_const::<3>()
    }

    fn compare(expected_data: Array<felt252>, actual_data: Span<felt252>) {
        assert(expected_data.len() == actual_data.len(), 'Data len mismatch');
        let mut index = 0_u32;
        loop {
            if (index == expected_data.len()) {
                break ();
            }
            assert(*expected_data.at(index) == *actual_data.at(index), 'Data mismatch');
            index += 1;
        };
    }

    #[test]
    #[available_gas(20000000)]
    #[should_panic(expected: ('SW: Caller not admin', 'ENTRYPOINT_FAILED', ))]
    fn test_withdraw_with_unauthorized_user() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };

        // set USER1 as the caller
        set_contract_address(USER1());

        let l1_token_address = EthAddress { address: 100_felt252 };
        let l2_token_address = contract_address_const::<11>();
        let l2_recipient = contract_address_const::<12>();
        let withdrawal_amount = u256 { low: 100, high: 0 };
        starkway
            .withdraw_admin_fees(
                l1_token_address, l2_token_address, l2_recipient, withdrawal_amount
            );
    }

    #[test]
    #[available_gas(20000000)]
    #[should_panic(expected: ('SW: Token uninitialized', 'ENTRYPOINT_FAILED', ))]
    fn test_withdraw_with_uninitialised_token() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };

        let l1_token_address = EthAddress { address: 100_felt252 };
        let l2_token_address = contract_address_const::<11>();
        let l2_recipient = contract_address_const::<12>();
        let withdrawal_amount = u256 { low: 100, high: 0 };
        // Calling withdraw without initialising the token
        starkway
            .withdraw_admin_fees(
                l1_token_address, l2_token_address, l2_recipient, withdrawal_amount
            );
    }

    #[test]
    #[available_gas(20000000)]
    #[should_panic(expected: ('SW: L2 recipient cannot be zero', 'ENTRYPOINT_FAILED', ))]
    fn test_withdraw_with_zero_address_recipient() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };

        let l1_token_address = EthAddress { address: 100_felt252 };
        let l1_recipient = EthAddress { address: 200_felt252 };
        init_token(starkway_address, admin_1, l1_token_address);

        let l2_token_address = contract_address_const::<11>();
        let l2_recipient = contract_address_const::<0>();
        let withdrawal_amount = u256 { low: 100, high: 0 };
        // Calling withdraw without zero l2_recipient address
        starkway
            .withdraw_admin_fees(
                l1_token_address, l2_token_address, l2_recipient, withdrawal_amount
            );
    }

    #[test]
    #[available_gas(20000000)]
    #[should_panic(expected: ('SW: Amount cannot be zero', 'ENTRYPOINT_FAILED', ))]
    fn test_withdraw_with_zero_withdrawal_amount() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };

        let l1_token_address = EthAddress { address: 100_felt252 };
        let l1_recipient = EthAddress { address: 200_felt252 };
        init_token(starkway_address, admin_1, l1_token_address);

        let l2_token_address = contract_address_const::<11>();
        let l2_recipient = contract_address_const::<12>();
        let withdrawal_amount = u256 { low: 0, high: 0 };
        // Calling withdraw with zero withdrawal amount
        starkway
            .withdraw_admin_fees(
                l1_token_address, l2_token_address, l2_recipient, withdrawal_amount
            );
    }

    #[test]
    #[available_gas(20000000)]
    #[should_panic(expected: ('SW: Token not whitelisted', 'ENTRYPOINT_FAILED', ))]
    fn test_withdraw_with_non_whitelisted_token() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();
        let l1_token_address = EthAddress { address: 100_felt252 };
        let l1_recipient = EthAddress { address: 200_felt252 };
        init_token(starkway_address, admin_1, l1_token_address);

        let starkway = IStarkwayDispatcher { contract_address: starkway_address };

        let l2_token_address = contract_address_const::<11>();
        let l2_recipient = contract_address_const::<12>();
        let withdrawal_amount = u256 { low: 100, high: 0 };
        starkway
            .withdraw_admin_fees(
                l1_token_address, l2_token_address, l2_recipient, withdrawal_amount
            );
    }

    #[test]
    #[available_gas(20000000)]
    #[should_panic(expected: ('SW:Amount exceeds fee collected', 'ENTRYPOINT_FAILED', ))]
    fn test_withdrawal_amount_exceeds_fee() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();

        let l1_token_address = EthAddress { address: 100_felt252 };
        let l1_recipient = EthAddress { address: 200_felt252 };
        init_token(starkway_address, admin_1, l1_token_address);

        let starkway = IStarkwayDispatcher { contract_address: starkway_address };

        let native_erc20_address = starkway.get_native_token_address(l1_token_address);
        let non_native_erc20_address = deploy_non_native_token(starkway_address, 200);

        let starkway = IStarkwayDispatcher { contract_address: starkway_address };

        // Register dummy adapter
        let bridge_adapter_address = register_bridge_adapter(starkway_address, admin_1);

        // Whitelist token
        whitelist_token(
            starkway_address,
            admin_1,
            1_u16,
            contract_address_const::<400>(),
            l1_token_address,
            non_native_erc20_address
        );

        let l2_recipient = contract_address_const::<12>();
        let withdrawal_amount = u256 { low: 100, high: 0 };
        starkway
            .withdraw_admin_fees(
                l1_token_address, non_native_erc20_address, l2_recipient, withdrawal_amount
            );
    }

    #[test]
    #[available_gas(20000000)]
    fn test_withdraw_with_non_native_token() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();

        let l1_token_address = EthAddress { address: 100_felt252 };
        let l1_recipient = EthAddress { address: 200_felt252 };

        let l2_recipient = contract_address_const::<12>();
        let withdrawal_amount = u256 { low: 1000, high: 0 };
        let fee = u256 { low: 20, high: 0 };
        init_token(starkway_address, admin_1, l1_token_address);

        let starkway = IStarkwayDispatcher { contract_address: starkway_address };

        let native_erc20_address = starkway.get_native_token_address(l1_token_address);
        let non_native_erc20_address = deploy_non_native_token(starkway_address, 200);

        let starkway = IStarkwayDispatcher { contract_address: starkway_address };

        mint(starkway_address, non_native_erc20_address, USER1(), u256 { low: 10000, high: 0 });

        // Register dummy adapter
        let bridge_adapter_address = register_bridge_adapter(starkway_address, admin_1);

        // Whitelist token
        whitelist_token(
            starkway_address,
            admin_1,
            1_u16,
            contract_address_const::<400>(),
            l1_token_address,
            non_native_erc20_address
        );

        set_contract_address(USER1());

        let erc20 = IERC20Dispatcher { contract_address: non_native_erc20_address };

        let balance_user_before = erc20.balance_of(USER1());
        let balance_starkway_before = erc20.balance_of(starkway_address);
        let balance_adapter_before = erc20.balance_of(bridge_adapter_address);

        erc20.approve(starkway_address, withdrawal_amount + fee);

        starkway
            .withdraw(
                non_native_erc20_address, l1_token_address, l1_recipient, withdrawal_amount, fee
            );

        let fee_collected = starkway.get_cumulative_fees(l1_token_address);
        assert(fee_collected == fee, 'Mismatch in fee collected');

        // Balances before withdrawal
        let balance_user_before = erc20.balance_of(l2_recipient);
        let balance_starkway_before = erc20.balance_of(starkway_address);

        set_contract_address(admin_1);
        starkway.withdraw_admin_fees(l1_token_address, non_native_erc20_address, l2_recipient, fee);

        // Check for the fees withdrawn
        let fee_withdrawn = starkway.get_cumulative_fees_withdrawn(l1_token_address);
        assert(fee_withdrawn == fee, 'Mismatch in fee withdrawn');

        // Balances after withdrawal
        let balance_user_after = erc20.balance_of(l2_recipient);
        let balance_starkway_after = erc20.balance_of(starkway_address);

        assert(balance_user_before == balance_user_after - fee, 'Incorrect user balance');
        assert(
            balance_starkway_before == balance_starkway_after + fee, 'Incorrect Starkway balance'
        );

        let (keys, data) = pop_log_raw(starkway_address).unwrap();
        let (keys, data) = pop_log_raw(starkway_address).unwrap();
        // Since first event emitted is going to be the init token event, and second is for withdraw,
        // we skip it and pop the next event
        let (keys, data) = pop_log_raw(starkway_address).unwrap();
        let mut expected_keys = ArrayTrait::<felt252>::new();
        expected_keys.append(l1_token_address.into());
        expected_keys.append(non_native_erc20_address.into());
        expected_keys.append('WITHDRAW_FEES');

        // compare expected and actual keys
        compare(expected_keys, keys);

        let mut expected_data = ArrayTrait::<felt252>::new();
        expected_data.append(l2_recipient.into());
        expected_data.append(fee.low.into());
        expected_data.append(fee.high.into());

        // compare expected and actual values
        compare(expected_data, data);
    }

    #[test]
    #[available_gas(20000000)]
    fn test_withdraw_with_native_token() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();

        let l1_token_address = EthAddress { address: 100_felt252 };
        let l1_recipient = EthAddress { address: 200_felt252 };

        let l2_recipient = contract_address_const::<12>();
        let withdrawal_amount = u256 { low: 1000, high: 0 };
        let fee = u256 { low: 20, high: 0 };
        init_token(starkway_address, admin_1, l1_token_address);

        let starkway = IStarkwayDispatcher { contract_address: starkway_address };

        let native_erc20_address = starkway.get_native_token_address(l1_token_address);

        let starkway = IStarkwayDispatcher { contract_address: starkway_address };

        mint(starkway_address, native_erc20_address, USER1(), u256 { low: 10000, high: 0 });

        set_contract_address(USER1());

        let erc20 = IERC20Dispatcher { contract_address: native_erc20_address };

        let balance_user_before = erc20.balance_of(USER1());
        let balance_starkway_before = erc20.balance_of(starkway_address);

        erc20.approve(starkway_address, withdrawal_amount + fee);
        starkway
            .withdraw(native_erc20_address, l1_token_address, l1_recipient, withdrawal_amount, fee);

        let fee_collected = starkway.get_cumulative_fees(l1_token_address);
        assert(fee_collected == fee, 'Mismatch in fee collected');

        // Balances before withdrawal
        let balance_user_before = erc20.balance_of(l2_recipient);
        let balance_starkway_before = erc20.balance_of(starkway_address);

        set_contract_address(admin_1);
        starkway.withdraw_admin_fees(l1_token_address, native_erc20_address, l2_recipient, fee);

        // Check for the fees withdrawn
        let fee_withdrawn = starkway.get_cumulative_fees_withdrawn(l1_token_address);
        assert(fee_withdrawn == fee, 'Mismatch in fee withdrawn');

        // Balances after withdrawal
        let balance_user_after = erc20.balance_of(l2_recipient);
        let balance_starkway_after = erc20.balance_of(starkway_address);

        assert(balance_user_before == balance_user_after - fee, 'Incorrect user balance');
        assert(
            balance_starkway_before == balance_starkway_after + fee, 'Incorrect Starkway balance'
        );

        let (keys, data) = pop_log_raw(starkway_address).unwrap();
        let (keys, data) = pop_log_raw(starkway_address).unwrap();

        // Since first event emitted is going to be the init token event, and second is for withdraw,
        // we skip it and pop the next event
        let (keys, data) = pop_log_raw(starkway_address).unwrap();
        let mut expected_keys = ArrayTrait::<felt252>::new();
        expected_keys.append(l1_token_address.into());
        expected_keys.append(native_erc20_address.into());
        expected_keys.append('WITHDRAW_FEES');

        // compare expected and actual keys
        compare(expected_keys, keys);

        let mut expected_data = ArrayTrait::<felt252>::new();
        expected_data.append(l2_recipient.into());
        expected_data.append(fee.low.into());
        expected_data.append(fee.high.into());

        // compare expected and actual values
        compare(expected_data, data);
    }
}
