use starknet::{ContractAddress, EthAddress};

#[cfg(test)]
mod test_deposit {
    use array::{Array, ArrayTrait, Span, SpanTrait};
    use core::hash::{LegacyHashFelt252};
    use core::integer::u256;
    use core::result::ResultTrait;
    use debug::{PrintTrait, print_felt252};
    use option::OptionTrait;
    use serde::Serde;
    use starknet::class_hash::ClassHash;
    use starknet::{ContractAddress, contract_address_const, EthAddress};
    use starknet::testing::{set_caller_address, set_contract_address, pop_log_raw};
    use traits::{Default, Into, TryInto};
    use starkway::admin_auth::AdminAuth;
    use starkway::datatypes::{L1TokenDetails, WithdrawalRange, L2TokenDetails, TokenAmount};
    use starkway::erc20::erc20::StarkwayERC20;
    use starkway::interfaces::{
        IAdminAuthDispatcher, IAdminAuthDispatcherTrait, IStarkwayDispatcher,
        IStarkwayDispatcherTrait, IERC20Dispatcher, IERC20DispatcherTrait, IBridgeAdapterDispatcher,
        IBridgeAdapterDispatcherTrait
    };
    use starkway::libraries::reentrancy_guard::ReentrancyGuard;
    use starkway::libraries::fee_library::fee_library;
    use starkway::starkway::Starkway;
    use zeroable::Zeroable;
    use tests::utils::{setup, deploy, mint, init_token, register_bridge_adapter, deploy_non_native_token, whitelist_token};
    use tests::utils::DummyAdapter;
    
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
    #[should_panic(expected: ('SW: Message not from SW L1', 'ENTRYPOINT_FAILED'))]
    fn test_deposit_not_from_starkway() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();

        let l1_token_address = EthAddress { address: 100_felt252 };
        let l1_starkway = EthAddress { address: 200_felt252 };
        let l1_sender = EthAddress { address: 300_felt252 };
        init_token(starkway_address, admin_1, l1_token_address);

    
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };
        
        set_contract_address(admin_1);
        starkway.set_l1_starkway_address(l1_starkway);

        // Deposit l1_handler should only be called by Starkway L1
        starkway.deposit_test(
            l1_sender.into(),
            l1_token_address,
            l1_sender,
            admin_1,
            u256 {low:0, high:0},
            u256 {low:0, high:0}
        );

    }

    #[test]
    #[available_gas(20000000)]
    #[should_panic(expected: ('SW: Invalid recipient', 'ENTRYPOINT_FAILED'))]
    fn test_invalid_recipient() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();

        let l1_token_address = EthAddress { address: 100_felt252 };
        let l1_starkway = EthAddress { address: 200_felt252 };
        let l1_sender = EthAddress { address: 300_felt252 };
        init_token(starkway_address, admin_1, l1_token_address);

    
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };
        
        set_contract_address(admin_1);
        starkway.set_l1_starkway_address(l1_starkway);
        starkway.deposit_test(
            l1_starkway.into(),
            l1_token_address,
            l1_sender,
            contract_address_const::<0>(), // invalid recipient
            u256 {low:0, high:0},
            u256 {low:0, high:0}
        );

    }

    #[test]
    #[available_gas(20000000)]
    #[should_panic(expected: ('SW: Token uninitialized', 'ENTRYPOINT_FAILED'))]
    fn test_token_uninitialized() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();

        let l1_token_address = EthAddress { address: 100_felt252 };
        let l1_starkway = EthAddress { address: 200_felt252 };
        let l1_sender = EthAddress { address: 300_felt252 };
        //init_token(starkway_address, admin_1, l1_token_address);

    
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };
        
        set_contract_address(admin_1);
        starkway.set_l1_starkway_address(l1_starkway);
        starkway.deposit_test(
            l1_starkway.into(),
            l1_token_address,
            l1_sender,
            admin_1,
            u256 {low:0, high:0},
            u256 {low:0, high:0}
        );
    }

    #[test]
    #[available_gas(20000000)]
    fn test_simple_deposit() {

        // Test the scenario where user makes a simple deposit of an initialized token
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();

        let l1_token_address = EthAddress { address: 100_felt252 };
        let l1_starkway = EthAddress { address: 200_felt252 };
        let l1_sender = EthAddress { address: 300_felt252 };
        let user = contract_address_const::<3000>();

        // Initialise token
        init_token(starkway_address, admin_1, l1_token_address);
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };
        let native_erc20_address = starkway.get_native_token_address(l1_token_address);
        let erc20 = IERC20Dispatcher { contract_address: native_erc20_address };

        set_contract_address(admin_1);
        starkway.set_l1_starkway_address(l1_starkway);

        let balance_user_before = erc20.balance_of(user);
        let balance_starkway_before = erc20.balance_of(starkway_address);
        let total_supply_before = erc20.total_supply();
        let fees_before = starkway.get_cumulative_fees(l1_token_address);
        let amount = u256 {low:100, high:0};
        let fee = u256 {low:2, high:0};

        set_contract_address(user);
        starkway.deposit_test(
            l1_starkway.into(),
            l1_token_address,
            l1_sender,
            user,
            amount,
            fee
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

        let (keys, data) = pop_log_raw(starkway_address).unwrap();
        // Since first event emitted is going to be the init token event, we skip it and pop the next event
        let (keys, data) = pop_log_raw(starkway_address).unwrap();
        let mut expected_keys = ArrayTrait::<felt252>::new();
        expected_keys.append(l1_sender.into());
        expected_keys.append(user.into());
        expected_keys.append(LegacyHashFelt252::hash(l1_sender.into(), user.into()));
        expected_keys.append(l1_token_address.into());
        expected_keys.append('DEPOSIT');
        
        let mut expected_data = ArrayTrait::<felt252>::new();
        expected_data.append(amount.low.into());
        expected_data.append(amount.high.into());
        expected_data.append(fee.low.into());
        expected_data.append(fee.high.into());
        expected_data.append(native_erc20_address.into());

        // compare expected and actual keys
        compare(expected_keys, keys);
        // compare expected and actual values
        compare(expected_data, data);

    }

    #[test]
    #[available_gas(20000000)]
    fn test_multi_deposit() {

        // Multiple deposits made by user
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();

        let l1_token_address = EthAddress { address: 100_felt252 };
        let l1_starkway = EthAddress { address: 200_felt252 };
        let l1_sender = EthAddress { address: 300_felt252 };
        let user = contract_address_const::<3000>();

        // Initialise token
        init_token(starkway_address, admin_1, l1_token_address);
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };
        let native_erc20_address = starkway.get_native_token_address(l1_token_address);
        let erc20 = IERC20Dispatcher { contract_address: native_erc20_address };

        
        set_contract_address(admin_1);
        starkway.set_l1_starkway_address(l1_starkway);

        let balance_user_before = erc20.balance_of(user);
        let balance_starkway_before = erc20.balance_of(starkway_address);
        let total_supply_before = erc20.total_supply();
        let fees_before = starkway.get_cumulative_fees(l1_token_address);
        let amount = u256 {low:100, high:0};
        let fee = u256 {low:2, high:0};

        set_contract_address(user); // This should be sequencer but we are calling test-only ext function
        starkway.deposit_test(
            l1_starkway.into(),
            l1_token_address,
            l1_sender,
            user,
            amount,
            fee
        );

        let balance_user_after = erc20.balance_of(user);
        let balance_starkway_after = erc20.balance_of(starkway_address);
        let total_supply_after = erc20.total_supply();
        let fees_after = starkway.get_cumulative_fees(l1_token_address);

        // Compare token balances
        assert(balance_user_before == balance_user_after - amount, 'Incorrect user balance');
        assert(
            balance_starkway_before == balance_starkway_after - fee, 'Incorrect Starkway balance'
        );
        assert(total_supply_before == total_supply_after - amount - fee, 'Incorrect total supply');
        assert(fees_before == fees_after - fee, 'Incorrect Fee');

        let (keys, data) = pop_log_raw(starkway_address).unwrap();
        // Since first event emitted is going to be the init token event, we skip it and pop the next event
        let (keys, data) = pop_log_raw(starkway_address).unwrap();
        let mut expected_keys = ArrayTrait::<felt252>::new();
        expected_keys.append(l1_sender.into());
        expected_keys.append(user.into());
        expected_keys.append(LegacyHashFelt252::hash(l1_sender.into(), user.into()));
        expected_keys.append(l1_token_address.into());
        expected_keys.append('DEPOSIT');
        
        let mut expected_data = ArrayTrait::<felt252>::new();
        expected_data.append(amount.low.into());
        expected_data.append(amount.high.into());
        expected_data.append(fee.low.into());
        expected_data.append(fee.high.into());
        expected_data.append(native_erc20_address.into());

        // compare expected and actual keys
        compare(expected_keys, keys);
        // compare expected and actual values
        compare(expected_data, data);

        let amount = u256 {low:100, high:0};
        let fee = u256 {low:2, high:0};

        // Deposit again for same token
        set_contract_address(admin_1);
        starkway.deposit_test(
            l1_starkway.into(),
            l1_token_address,
            l1_sender,
            user,
            amount,
            fee
        );

        let balance_user_after = erc20.balance_of(user);
        let balance_starkway_after = erc20.balance_of(starkway_address);
        let total_supply_after = erc20.total_supply();
        let fees_after = starkway.get_cumulative_fees(l1_token_address);

        assert(balance_user_before == balance_user_after - 2*amount, 'Incorrect user balance');
        assert(
            balance_starkway_before == balance_starkway_after - 2*fee, 'Incorrect Starkway balance'
        );
        assert(total_supply_before == total_supply_after - 2*amount - 2*fee, 'Incorrect total supply');
        assert(fees_before == fees_after - 2*fee, 'Incorrect Fee');

        let (keys, data) = pop_log_raw(starkway_address).unwrap();
        let mut expected_keys = ArrayTrait::<felt252>::new();
        expected_keys.append(l1_sender.into());
        expected_keys.append(user.into());
        expected_keys.append(LegacyHashFelt252::hash(l1_sender.into(), user.into()));
        expected_keys.append(l1_token_address.into());
        expected_keys.append('DEPOSIT');
        
        let mut expected_data = ArrayTrait::<felt252>::new();
        expected_data.append(amount.low.into());
        expected_data.append(amount.high.into());
        expected_data.append(fee.low.into());
        expected_data.append(fee.high.into());
        expected_data.append(native_erc20_address.into());

        // compare expected and actual keys
        compare(expected_keys, keys);
        // compare expected and actual values
        compare(expected_data, data);
    }
}
