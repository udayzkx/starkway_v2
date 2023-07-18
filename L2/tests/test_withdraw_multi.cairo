use starknet::{ContractAddress, EthAddress};

#[cfg(test)]
mod test_withdraw_multi {
    use array::{Array, ArrayTrait, Span, SpanTrait};
    use core::hash::{LegacyHashFelt252};
    use core::integer::u256;
    use core::result::ResultTrait;
    use debug::{PrintTrait, print_felt252};
    use option::OptionTrait;
    use serde::Serde;
    use starknet::class_hash::ClassHash;
    use starknet::{ContractAddress, contract_address_const, EthAddress};
    use starknet::testing::{set_caller_address, set_contract_address, pop_log};
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
    #[should_panic(expected: ('SW: Token uninitialized', 'ENTRYPOINT_FAILED'))]
    fn test_withdraw_uninitialized_token() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();

        let l1_token_address = EthAddress { address: 100_felt252 };
        let l1_recipient = EthAddress { address: 200_felt252 };
        let token_amount = TokenAmount {
                            l1_address: l1_token_address,
                            l2_address: contract_address_const::<100>(),
                            amount: u256{low:0, high:0}
                            };
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };
        let mut transfer_list = ArrayTrait::new();

        transfer_list.append(token_amount);

        starkway.withdraw_multi(
            transfer_list,
            l1_recipient,
            l1_token_address,
            u256{low:0, high:0},
            u256{low:0, high:0}
        );
    }

    #[test]
    #[available_gas(20000000)]
    #[should_panic(expected: ('SW: Amount cannot be zero', 'ENTRYPOINT_FAILED'))]
    fn test_zero_amount() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();

        let l1_token_address = EthAddress { address: 100_felt252 };
        let l1_recipient = EthAddress { address: 200_felt252 };
        init_token(starkway_address, admin_1, l1_token_address);
        let token_amount = TokenAmount {
                            l1_address: l1_token_address,
                            l2_address: contract_address_const::<100>(),
                            amount: u256{low:0, high:0}
                            };
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };
        let mut transfer_list = ArrayTrait::new();

        transfer_list.append(token_amount);

        starkway.withdraw_multi(
            transfer_list,
            l1_recipient,
            l1_token_address,
            u256{low:0, high:0},
            u256{low:0, high:0}
        );
    }

    #[test]
    #[available_gas(20000000)]
    #[should_panic(expected: ('SW: amount > threshold', 'ENTRYPOINT_FAILED'))]
    fn test_out_of_range() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();

        let l1_token_address = EthAddress { address: 100_felt252 };
        let l1_recipient = EthAddress { address: 200_felt252 };
        init_token(starkway_address, admin_1, l1_token_address);
        let token_amount = TokenAmount {
                            l1_address: l1_token_address,
                            l2_address: contract_address_const::<100>(),
                            amount: u256{low:0, high:0}
                            };
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };
        let mut transfer_list = ArrayTrait::new();

        transfer_list.append(token_amount);

        starkway.withdraw_multi(
            transfer_list,
            l1_recipient,
            l1_token_address,
            u256{low:0, high:10000},
            u256{low:0, high:0}
        );
    }

    #[test]
    #[available_gas(20000000)]
    #[should_panic(expected: ('SW: Fee mismatch', 'ENTRYPOINT_FAILED'))]
    fn test_fee_mismatch() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();

        let l1_token_address = EthAddress { address: 100_felt252 };
        let l1_recipient = EthAddress { address: 200_felt252 };
        init_token(starkway_address, admin_1, l1_token_address);
        let token_amount = TokenAmount {
                            l1_address: l1_token_address,
                            l2_address: contract_address_const::<100>(),
                            amount: u256{low:0, high:0}
                            };
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };
        let mut transfer_list = ArrayTrait::new();

        transfer_list.append(token_amount);

        starkway.withdraw_multi(
            transfer_list,
            l1_recipient,
            l1_token_address,
            u256{low:0, high:100},
            u256{low:0, high:0}
        );
    }

    #[test]
    #[available_gas(20000000)]
    #[should_panic(expected: ('SW: L1 address Mismatch', 'ENTRYPOINT_FAILED'))]
    fn test_incompatible_l1_address() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();

        let l1_token_address = EthAddress { address: 100_felt252 };
        let l1_recipient = EthAddress { address: 200_felt252 };
        init_token(starkway_address, admin_1, l1_token_address);
        let token_amount = TokenAmount {
                            l1_address: l1_token_address,
                            l2_address: contract_address_const::<100>(),
                            amount: u256{low:0, high:0}
                            };
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };
        let mut transfer_list = ArrayTrait::new();

        transfer_list.append(token_amount);

        starkway.withdraw_multi(
            transfer_list,
            l1_recipient,
            l1_token_address,
            u256{low:100, high:0},
            u256{low:2, high:0}
        );
    }

    #[test]
    #[available_gas(20000000)]
    #[should_panic(expected: ('SW: L1 address Mismatch', 'ENTRYPOINT_FAILED'))]
    fn test_l1_address_mismatch() {

        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();

        let l1_token_address = EthAddress { address: 100_felt252 };
        let l1_token_address_2 = EthAddress { address: 200_felt252 };
        let l1_recipient = EthAddress { address: 300_felt252 };
        init_token(starkway_address, admin_1, l1_token_address);
        init_token(starkway_address, admin_1, l1_token_address_2);
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };

        let non_native_erc20_address = deploy_non_native_token(starkway_address, 100);

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

        let native_erc20_address = starkway.get_native_token_address(l1_token_address);
        let mut transfer_list = ArrayTrait::new();
        let token_amount = TokenAmount {
                            l1_address: l1_token_address,
                            l2_address: native_erc20_address,
                            amount: u256{low:100, high:0}
                            };
        transfer_list.append(token_amount);
        let token_amount_2 = TokenAmount {
                            l1_address: l1_token_address,
                            l2_address: non_native_erc20_address,
                            amount: u256{low:100, high:0}
                            };
        let non_native_erc20_address_2 = deploy_non_native_token(starkway_address, 200);
        whitelist_token(
            starkway_address,
            admin_1,
            1_u16,
            contract_address_const::<400>(),
            l1_token_address_2,
            non_native_erc20_address_2
        );

        transfer_list.append(token_amount_2);
        let token_amount_3 = TokenAmount {
                            l1_address: l1_token_address_2, // this l1_address is incompatible with others
                            l2_address: non_native_erc20_address_2,
                            amount: u256{low:100, high:0}
                            };
        
        transfer_list.append(token_amount_3);
        starkway.withdraw_multi(
            transfer_list,
            l1_recipient,
            l1_token_address,
            u256{low:100, high:0},
            u256{low:2, high:0}
        );

    }

    #[test]
    #[available_gas(20000000)]
    #[should_panic(expected: ('SW: Withdrawal amount mismatch', 'ENTRYPOINT_FAILED'))]
    fn test_amount_mismatch() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();

        let l1_token_address = EthAddress { address: 100_felt252 };
        let l1_recipient = EthAddress { address: 200_felt252 };
        init_token(starkway_address, admin_1, l1_token_address);
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };
        let native_erc20_address = starkway.get_native_token_address(l1_token_address);
        let token_amount = TokenAmount {
                            l1_address: l1_token_address,
                            l2_address: native_erc20_address,
                            amount: u256{low:100, high:0}
                            };
        
        let mut transfer_list = ArrayTrait::new();

        transfer_list.append(token_amount);

        starkway.withdraw_multi(
            transfer_list,
            l1_recipient,
            l1_token_address,
            u256{low:100, high:0},
            u256{low:2, high:0}
        );
    }

    #[test]
    #[available_gas(20000000)]
    #[should_panic(expected: ('u256_sub Overflow', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED'))]
    fn test_no_approval() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();

        let l1_token_address = EthAddress { address: 100_felt252 };
        let l1_recipient = EthAddress { address: 200_felt252 };
        init_token(starkway_address, admin_1, l1_token_address);
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };
        let native_erc20_address = starkway.get_native_token_address(l1_token_address);
        let amount1 = u256{low:102, high:0};
        let user = contract_address_const::<3000>();
        let token_amount = TokenAmount {
                            l1_address: l1_token_address,
                            l2_address: native_erc20_address,
                            amount: amount1
                            };
        mint(starkway_address, native_erc20_address, user, amount1);
        let mut transfer_list = ArrayTrait::new();

        transfer_list.append(token_amount);
        set_contract_address(user);
        starkway.withdraw_multi(
            transfer_list,
            l1_recipient,
            l1_token_address,
            u256{low:100, high:0},
            u256{low:2, high:0}
        );
    }

    #[test]
    #[available_gas(20000000)]
    #[should_panic(expected: ('u256_sub Overflow', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED'))]
    fn test_insufficient_user_balance() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();

        let l1_token_address = EthAddress { address: 100_felt252 };
        let l1_recipient = EthAddress { address: 200_felt252 };
        init_token(starkway_address, admin_1, l1_token_address);
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };
        let native_erc20_address = starkway.get_native_token_address(l1_token_address);
        let amount1 = u256{low:100, high:0};
        let fee = u256{low:2, high:0};
        let user = contract_address_const::<3000>();
        let token_amount = TokenAmount {
                            l1_address: l1_token_address,
                            l2_address: native_erc20_address,
                            amount: amount1 + fee
                            };
        
        mint(starkway_address, native_erc20_address, user, amount1);
        let erc20 = IERC20Dispatcher { contract_address: native_erc20_address };

        set_contract_address(user);
        erc20.approve(starkway_address, amount1 + fee);
        let mut transfer_list = ArrayTrait::new();

        transfer_list.append(token_amount);
        
        starkway.withdraw_multi(
            transfer_list,
            l1_recipient,
            l1_token_address,
            u256{low:100, high:0},
            u256{low:2, high:0}
        );
    }

    #[test]
    #[available_gas(20000000)]
    fn test_sufficient_single_native() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();

        let l1_token_address = EthAddress { address: 100_felt252 };
        let l1_recipient = EthAddress { address: 200_felt252 };
        init_token(starkway_address, admin_1, l1_token_address);
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };
        let native_erc20_address = starkway.get_native_token_address(l1_token_address);
        let amount1 = u256{low:100, high:0};
        let fee = u256{low:2, high:0};
        let user = contract_address_const::<3000>();
        let token_amount = TokenAmount {
                            l1_address: l1_token_address,
                            l2_address: native_erc20_address,
                            amount: amount1 + fee
                            };
        
        mint(starkway_address, native_erc20_address, user, amount1 + fee);
        let erc20 = IERC20Dispatcher { contract_address: native_erc20_address };
        set_contract_address(user);
        erc20.approve(starkway_address, amount1 + fee);
        let mut transfer_list = ArrayTrait::new();

        transfer_list.append(token_amount);
        
        let balance_user_before = erc20.balance_of(user);
        let balance_starkway_before = erc20.balance_of(starkway_address);
        starkway.withdraw_multi(
            transfer_list,
            l1_recipient,
            l1_token_address,
            u256{low:100, high:0},
            u256{low:2, high:0}
        );

        let balance_user_after = erc20.balance_of(user);
        let balance_starkway_after = erc20.balance_of(starkway_address);
        assert(balance_user_before == balance_user_after + amount1 + fee, 'Incorrect user balance');
        assert(
            balance_starkway_before == balance_starkway_after - fee, 'Incorrect Starkway balance'
        );
    }

    #[test]
    #[available_gas(20000000)]
    fn test_sufficient_single_non_native() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();

        let l1_token_address = EthAddress { address: 100_felt252 };
        let l1_recipient = EthAddress { address: 200_felt252 };
        init_token(starkway_address, admin_1, l1_token_address);
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };
        let native_erc20_address = starkway.get_native_token_address(l1_token_address);
        let amount1 = u256{low:100, high:0};
        let fee = u256{low:2, high:0};
        let user = contract_address_const::<3000>();

        let non_native_erc20_address = deploy_non_native_token(starkway_address, 100);

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


        let token_amount = TokenAmount {
                            l1_address: l1_token_address,
                            l2_address: non_native_erc20_address,
                            amount: amount1 + fee
                            };
        
        mint(starkway_address, non_native_erc20_address, user, amount1 + fee);
        let erc20 = IERC20Dispatcher { contract_address: non_native_erc20_address };
        set_contract_address(user);
        erc20.approve(starkway_address, amount1 + fee);
        let mut transfer_list = ArrayTrait::new();

        transfer_list.append(token_amount);
        
        let balance_user_before = erc20.balance_of(user);
        let balance_starkway_before = erc20.balance_of(starkway_address);
        starkway.withdraw_multi(
            transfer_list,
            l1_recipient,
            l1_token_address,
            u256{low:100, high:0},
            u256{low:2, high:0}
        );

        let balance_user_after = erc20.balance_of(user);
        let balance_starkway_after = erc20.balance_of(starkway_address);
        assert(balance_user_before == balance_user_after + amount1 + fee, 'Incorrect user balance');
        assert(
            balance_starkway_before == balance_starkway_after - fee, 'Incorrect Starkway balance'
        );
    }

    #[test]
    #[available_gas(20000000)]
    #[should_panic(expected: ('SW: No single token liquidity', 'ENTRYPOINT_FAILED'))]
    fn test_insufficient_multi_token() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();

        let l1_token_address = EthAddress { address: 100_felt252 };
        let l1_recipient = EthAddress { address: 200_felt252 };
        init_token(starkway_address, admin_1, l1_token_address);
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };
        let native_erc20_address = starkway.get_native_token_address(l1_token_address);
        let amount1 = u256{low:100, high:0};
        let fee = u256{low:2, high:0};
        let user = contract_address_const::<3000>();
        let token_amount = TokenAmount {
                            l1_address: l1_token_address,
                            l2_address: native_erc20_address,
                            amount: amount1 + 2*fee
                            };
        
        mint(starkway_address, native_erc20_address, user, amount1 + 2*fee);
        let erc20 = IERC20Dispatcher { contract_address: native_erc20_address };
        set_contract_address(user);
        erc20.approve(starkway_address, amount1 + 2*fee);

        let non_native_erc20_address = deploy_non_native_token(starkway_address, 100);

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

        let token_amount_2 = TokenAmount {
                            l1_address: l1_token_address,
                            l2_address: non_native_erc20_address,
                            amount: amount1
                            };
        let non_native_erc20 = IERC20Dispatcher { contract_address: non_native_erc20_address };
        mint(starkway_address, non_native_erc20_address, user, amount1);
        set_contract_address(user);
        non_native_erc20.approve(starkway_address, amount1);


        let mut transfer_list = ArrayTrait::new();

        transfer_list.append(token_amount);
        transfer_list.append(token_amount_2);
        let balance_user_before = erc20.balance_of(user);
        let balance_starkway_before = erc20.balance_of(starkway_address);
        starkway.withdraw_multi(
            transfer_list,
            l1_recipient,
            l1_token_address,
            2*amount1,
            2*fee
        );

        let balance_user_after = erc20.balance_of(user);
        let balance_starkway_after = erc20.balance_of(starkway_address);
        assert(balance_user_before == balance_user_after + amount1 + fee, 'Incorrect user balance');
        assert(
            balance_starkway_before == balance_starkway_after - fee, 'Incorrect Starkway balance'
        );
    }

    #[test]
    #[available_gas(20000000)]
    fn test_sufficient_multi_token_1() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();

        let l1_token_address = EthAddress { address: 100_felt252 };
        let l1_recipient = EthAddress { address: 200_felt252 };
        init_token(starkway_address, admin_1, l1_token_address);
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };
        let native_erc20_address = starkway.get_native_token_address(l1_token_address);
        let amount1 = u256{low:100, high:0};
        let fee = u256{low:2, high:0};
        let user = contract_address_const::<3000>();
        let token_amount = TokenAmount {
                            l1_address: l1_token_address,
                            l2_address: native_erc20_address,
                            amount: amount1 + 2*fee
                            };
        
        mint(starkway_address, native_erc20_address, user, amount1 + 2*fee);
        mint(starkway_address, native_erc20_address, starkway_address, amount1);
        let erc20 = IERC20Dispatcher { contract_address: native_erc20_address };
        set_contract_address(user);
        erc20.approve(starkway_address, amount1 + 2*fee);

        let non_native_erc20_address = deploy_non_native_token(starkway_address, 100);

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

        let token_amount_2 = TokenAmount {
                            l1_address: l1_token_address,
                            l2_address: non_native_erc20_address,
                            amount: amount1
                            };
        let non_native_erc20 = IERC20Dispatcher { contract_address: non_native_erc20_address };
        mint(starkway_address, non_native_erc20_address, user, amount1);
        set_contract_address(user);
        non_native_erc20.approve(starkway_address, amount1);


        let mut transfer_list = ArrayTrait::new();

        transfer_list.append(token_amount);
        transfer_list.append(token_amount_2);
        let balance_user_before = erc20.balance_of(user);
        let balance_starkway_before = erc20.balance_of(starkway_address);
        starkway.withdraw_multi(
            transfer_list,
            l1_recipient,
            l1_token_address,
            2*amount1,
            2*fee
        );

        let balance_user_after = erc20.balance_of(user);
        let balance_starkway_after = erc20.balance_of(starkway_address);
        assert(balance_user_before == balance_user_after + amount1 + 2*fee, 'Incorrect user balance');
        assert(
            balance_starkway_before == balance_starkway_after + amount1 - (2*fee), 'Incorrect Starkway balance'
        );
    }

    #[test]
    #[available_gas(20000000)]
    fn test_sufficient_multi_token_2() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();

        let l1_token_address = EthAddress { address: 100_felt252 };
        let l1_recipient = EthAddress { address: 200_felt252 };
        init_token(starkway_address, admin_1, l1_token_address);
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };
        let native_erc20_address = starkway.get_native_token_address(l1_token_address);
        let amount1 = u256{low:100, high:0};
        let fee = u256{low:2, high:0};
        let user = contract_address_const::<3000>();
        let token_amount = TokenAmount {
                            l1_address: l1_token_address,
                            l2_address: native_erc20_address,
                            amount: amount1 + 2*fee
                            };
        
        mint(starkway_address, native_erc20_address, user, amount1 + 2*fee);
        let erc20 = IERC20Dispatcher { contract_address: native_erc20_address };
        set_contract_address(user);
        erc20.approve(starkway_address, amount1 + 2*fee);

        let non_native_erc20_address = deploy_non_native_token(starkway_address, 100);

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

        let token_amount_2 = TokenAmount {
                            l1_address: l1_token_address,
                            l2_address: non_native_erc20_address,
                            amount: amount1
                            };
        let non_native_erc20 = IERC20Dispatcher { contract_address: non_native_erc20_address };
        mint(starkway_address, non_native_erc20_address, user, amount1);
        mint(starkway_address, non_native_erc20_address, starkway_address, amount1);
        set_contract_address(user);
        non_native_erc20.approve(starkway_address, amount1);


        let mut transfer_list = ArrayTrait::new();

        transfer_list.append(token_amount);
        transfer_list.append(token_amount_2);
        let balance_user_before = erc20.balance_of(user);
        let balance_starkway_before = erc20.balance_of(starkway_address);
        starkway.withdraw_multi(
            transfer_list,
            l1_recipient,
            l1_token_address,
            2*amount1,
            2*fee
        );

        let balance_user_after = erc20.balance_of(user);
        let balance_starkway_after = erc20.balance_of(starkway_address);
        assert(balance_user_before == balance_user_after + amount1 + 2*fee, 'Incorrect user balance');
        assert(
            balance_starkway_before == balance_starkway_after - amount1 - (2*fee), 'Incorrect Starkway balance'
        );
    }

    #[test]
    #[available_gas(20000000)]
    fn test_sufficient_multi_token_3() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();

        let l1_token_address = EthAddress { address: 100_felt252 };
        let l1_recipient = EthAddress { address: 200_felt252 };
        init_token(starkway_address, admin_1, l1_token_address);
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };
        let native_erc20_address = starkway.get_native_token_address(l1_token_address);
        let amount1 = u256{low:100, high:0};
        let fee = u256{low:2, high:0};
        let user = contract_address_const::<3000>();
        let token_amount = TokenAmount {
                            l1_address: l1_token_address,
                            l2_address: native_erc20_address,
                            amount: amount1/2 + fee
                            };
        
        mint(starkway_address, native_erc20_address, user, amount1 + 2*fee);
        let erc20 = IERC20Dispatcher { contract_address: native_erc20_address };
        set_contract_address(user);
        erc20.approve(starkway_address, amount1 + 2*fee);

        let non_native_erc20_address = deploy_non_native_token(starkway_address, 100);

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

        let token_amount_2 = TokenAmount {
                            l1_address: l1_token_address,
                            l2_address: non_native_erc20_address,
                            amount: amount1/2
                            };
        let non_native_erc20 = IERC20Dispatcher { contract_address: non_native_erc20_address };
        mint(starkway_address, non_native_erc20_address, user, amount1);
        mint(starkway_address, non_native_erc20_address, starkway_address, amount1);
        set_contract_address(user);
        non_native_erc20.approve(starkway_address, amount1);


        let mut transfer_list = ArrayTrait::new();

        transfer_list.append(token_amount);
        transfer_list.append(token_amount_2);
        let balance_user_before = erc20.balance_of(user);
        let balance_starkway_before = erc20.balance_of(starkway_address);
        starkway.withdraw_multi(
            transfer_list,
            l1_recipient,
            l1_token_address,
            amount1,
            fee
        );
        let mut transfer_list = ArrayTrait::new();
        transfer_list.append(token_amount);
        transfer_list.append(token_amount_2);
        starkway.withdraw_multi(
            transfer_list,
            l1_recipient,
            l1_token_address,
            amount1,
            fee
        );

        let balance_user_after = erc20.balance_of(user);
        let balance_starkway_after = erc20.balance_of(starkway_address);
        assert(balance_user_before == balance_user_after + amount1 + 2*fee, 'Incorrect user balance');
        assert(
            balance_starkway_before == balance_starkway_after - amount1 - (2*fee), 'Incorrect Starkway balance'
        );
    }

    #[test]
    #[available_gas(20000000)]
    fn test_sufficient_multi_token_4() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();

        let l1_token_address = EthAddress { address: 100_felt252 };
        let l1_recipient = EthAddress { address: 200_felt252 };
        init_token(starkway_address, admin_1, l1_token_address);
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };
        let native_erc20_address = starkway.get_native_token_address(l1_token_address);
        let amount1 = u256{low:100, high:0};
        let fee = u256{low:2, high:0};
        let user = contract_address_const::<3000>();
        let token_amount = TokenAmount {
                            l1_address: l1_token_address,
                            l2_address: native_erc20_address,
                            amount: amount1 + 3*fee
                            };
        
        mint(starkway_address, native_erc20_address, user, amount1 + 3*fee);
        let erc20 = IERC20Dispatcher { contract_address: native_erc20_address };
        set_contract_address(user);
        erc20.approve(starkway_address, amount1 + 3*fee);

        let non_native_erc20_address = deploy_non_native_token(starkway_address, 100);

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

        let token_amount_2 = TokenAmount {
                            l1_address: l1_token_address,
                            l2_address: non_native_erc20_address,
                            amount: amount1
                            };
        let non_native_erc20 = IERC20Dispatcher { contract_address: non_native_erc20_address };
        mint(starkway_address, non_native_erc20_address, user, amount1);
        mint(starkway_address, non_native_erc20_address, starkway_address, 2*amount1);
        set_contract_address(user);
        non_native_erc20.approve(starkway_address, amount1);

        let non_native_erc20_address_2 = deploy_non_native_token(starkway_address, 200);
        whitelist_token(
            starkway_address,
            admin_1,
            1_u16,
            contract_address_const::<400>(),
            l1_token_address,
            non_native_erc20_address_2
        );

        let token_amount_3 = TokenAmount {
                            l1_address: l1_token_address,
                            l2_address: non_native_erc20_address_2,
                            amount: amount1
                            };
        
        let non_native_erc20_2 = IERC20Dispatcher { contract_address: non_native_erc20_address_2 };
        mint(starkway_address, non_native_erc20_address_2, user, amount1);
        set_contract_address(user);
        non_native_erc20_2.approve(starkway_address, amount1);
        let mut transfer_list = ArrayTrait::new();

        transfer_list.append(token_amount);
        transfer_list.append(token_amount_2);
        transfer_list.append(token_amount_3);
        let balance_user_before = erc20.balance_of(user);
        let balance_starkway_before = erc20.balance_of(starkway_address);
        starkway.withdraw_multi(
            transfer_list,
            l1_recipient,
            l1_token_address,
            3*amount1,
            3*fee
        );

        let balance_user_after = erc20.balance_of(user);
        let balance_starkway_after = erc20.balance_of(starkway_address);
        assert(balance_user_before == balance_user_after + amount1 + 3*fee, 'Incorrect user balance');
        assert(
            balance_starkway_before == balance_starkway_after - amount1 - (3*fee), 'Incorrect Starkway balance'
        );
    }
}