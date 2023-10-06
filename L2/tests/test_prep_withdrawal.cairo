use starknet::{ContractAddress, EthAddress};

#[cfg(test)]
mod test_prep_withdrawal {
    use array::{Array, ArrayTrait, Span, SpanTrait};
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
    use tests::utils::DummyAdapter;
    use tests::utils::{setup, deploy, mint, init_token, register_bridge_adapter, deploy_non_native_token, whitelist_token};

    
    fn compare(actual_data: TokenAmount, expected_data: TokenAmount) {

        assert(actual_data.l1_address == expected_data.l1_address, 'L1 addr mismatch');
        assert(actual_data.l2_address == expected_data.l2_address, 'L2 addr mismatch');
        assert(actual_data.amount == expected_data.amount, 'Amount mismatch');
    }

    #[test]
    #[available_gas(20000000)]
    #[should_panic(expected: ('SW: Native token uninitialized', 'ENTRYPOINT_FAILED'))]
    fn test_uninitialized_token() {

        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();

        let l1_token_address = EthAddress { address: 100_felt252 };

        let starkway = IStarkwayDispatcher { contract_address: starkway_address };

        starkway.prepare_withdrawal_lists(l1_token_address, u256{low: 100, high:0}, admin_1, u256{low: 2, high:0});

    }

    #[test]
    #[available_gas(20000000)]
    #[should_panic(expected: ('SW: amount > threshold', 'ENTRYPOINT_FAILED'))]
    fn test_out_of_range() {

        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();

        let l1_token_address = EthAddress { address: 100_felt252 };
        init_token(starkway_address, admin_1, l1_token_address);
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };

        starkway.prepare_withdrawal_lists(l1_token_address, u256{low: 1000, high:10000}, admin_1, u256{low: 2, high:0});

    }

    #[test]
    #[available_gas(20000000)]
    fn test_zero_amount() {

        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();

        let l1_token_address = EthAddress { address: 100_felt252 };
        init_token(starkway_address, admin_1, l1_token_address);
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };

        // Set withdrawal range
        let withdrawal_range = WithdrawalRange {
            min: u256 { low: 0, high: 0 }, max: u256 { low: 100, high: 0 }
        };
        starkway.set_withdrawal_range(l1_token_address, withdrawal_range);


        let (approval_list, transfer_list) = starkway.prepare_withdrawal_lists(
                                            l1_token_address, 
                                            u256{low: 0, high: 0}, 
                                            admin_1, 
                                            u256{low: 2, high:0});
        
        assert(approval_list.len() == 0, 'Incorrect list length');
        assert(transfer_list.len() == 0, 'Incorrect list length');
    }

    #[test]
    #[available_gas(20000000)]
    #[should_panic(expected: ('SW: Insufficient balance', 'ENTRYPOINT_FAILED'))]
    fn test_no_token() {

        // Tests the situation where user does not have any native/non-native token
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();

        let l1_token_address = EthAddress { address: 100_felt252 };
        init_token(starkway_address, admin_1, l1_token_address);
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };

        starkway.prepare_withdrawal_lists(l1_token_address, u256{low: 100, high:0}, admin_1, u256{low: 2, high:0});
    }

    #[test]
    #[available_gas(20000000)]
    #[should_panic(expected: ('SW: Insufficient balance', 'ENTRYPOINT_FAILED'))]
    fn test_native_only_insufficient() {

        // Tests the situation where user has some native token but not enough
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();

        let l1_token_address = EthAddress { address: 100_felt252 };
        init_token(starkway_address, admin_1, l1_token_address);
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };

        let native_erc20_address = starkway.get_native_token_address(l1_token_address);

        let user = contract_address_const::<30>();
        let amount1 = u256 { low: 1000, high: 0 };
        let amount2 = u256 { low: 100, high: 0 };
        let fee = u256 { low: 2, high: 0 };

        // Mint tokens to user
        mint(starkway_address, native_erc20_address, user, amount2);

        starkway.prepare_withdrawal_lists(l1_token_address, u256{low: 100, high:0}, user, u256{low: 2, high:0});
    }

    #[test]
    #[available_gas(20000000)]
    #[should_panic(expected: ('SW: Insufficient balance', 'ENTRYPOINT_FAILED'))]
    fn test_non_native_only_insufficient() {

        // Tests the situation where user has some non-native token but not enough
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();

        let l1_token_address = EthAddress { address: 100_felt252 };
        init_token(starkway_address, admin_1, l1_token_address);
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };

        let native_erc20_address = starkway.get_native_token_address(l1_token_address);

        let user = contract_address_const::<30>();
        let amount1 = u256 { low: 1000, high: 0 };
        let amount2 = u256 { low: 100, high: 0 };
        let fee = u256 { low: 2, high: 0 };

        let non_native_erc20_address = deploy_non_native_token(starkway_address, 200);

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


        // Mint tokens to user
        mint(starkway_address, non_native_erc20_address, user, amount2); // insufficient to cover amount + fee


        starkway.prepare_withdrawal_lists(l1_token_address, u256{low: 100, high:0}, user, u256{low: 2, high:0});


    }

    #[test]
    #[available_gas(20000000)]
    #[should_panic(expected: ('SW: Insufficient balance', 'ENTRYPOINT_FAILED'))]
    fn test_mixed_insufficient() {

        // Tests the situation where user does not have sufficient native + non-native tokens
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();

        let l1_token_address = EthAddress { address: 100_felt252 };
        init_token(starkway_address, admin_1, l1_token_address);
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };

        let native_erc20_address = starkway.get_native_token_address(l1_token_address);

        let user = contract_address_const::<30>();
        let amount1 = u256 { low: 1000, high: 0 };
        let amount2 = u256 { low: 100, high: 0 };
        let fee = u256 { low: 2, high: 0 };

        let non_native_erc20_address = deploy_non_native_token(starkway_address, 200);

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


        // Mint tokens to user
        mint(starkway_address, non_native_erc20_address, user, amount2);
        mint(starkway_address, native_erc20_address, user, amount2);

        // amount > balance
        starkway.prepare_withdrawal_lists(l1_token_address, u256{low: 1000, high:0}, user, u256{low: 2, high:0});


    }


    #[test]
    #[available_gas(20000000)]
    fn test_native_only_sufficient() {

        // User has sufficient native token balance
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();

        let l1_token_address = EthAddress { address: 100_felt252 };
        init_token(starkway_address, admin_1, l1_token_address);
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };

        let native_erc20_address = starkway.get_native_token_address(l1_token_address);

        let user = contract_address_const::<30>();
        let amount1 = u256 { low: 1000, high: 0 };
        let amount2 = u256 { low: 100, high: 0 };
        let fee = u256 { low: 2, high: 0 };

        // Mint tokens to user
        mint(starkway_address, native_erc20_address, user, amount1);

        let (approval_list, transfer_list) = starkway.prepare_withdrawal_lists(l1_token_address, u256{low: 100, high:0}, user, u256{low: 2, high:0});

        // Check approval and transfer lists
        assert(approval_list.len() == 1, 'Incorrect list length');
        assert(transfer_list.len() == 1, 'Incorrect list length');

        let actual_data = *approval_list.at(0);
        let expected_data = TokenAmount {
                            l1_address: l1_token_address,
                            l2_address: native_erc20_address,
                            amount: amount2 + fee
                        };

        compare(actual_data, expected_data);

        compare(*transfer_list.at(0), expected_data);
        

    }

    #[test]
    #[available_gas(20000000)]
    fn test_non_native_only_sufficient() {

        // Tests the situation where user does have sufficient non-native token balance
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();

        let l1_token_address = EthAddress { address: 100_felt252 };
        init_token(starkway_address, admin_1, l1_token_address);
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };

        let native_erc20_address = starkway.get_native_token_address(l1_token_address);

        let user = contract_address_const::<30>();
        let amount1 = u256 { low: 1000, high: 0 };
        let amount2 = u256 { low: 100, high: 0 };
        let fee = u256 { low: 2, high: 0 };

        let non_native_erc20_address = deploy_non_native_token(starkway_address, 200);

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


        // Mint tokens to user
        mint(starkway_address, non_native_erc20_address, user, amount1);


        let (approval_list, transfer_list) = starkway.prepare_withdrawal_lists(l1_token_address, u256{low: 100, high:0}, user, u256{low: 2, high:0});

        assert(approval_list.len() == 1, 'Incorrect list length');
        assert(transfer_list.len() == 1, 'Incorrect list length');

        let actual_data = *approval_list.at(0);
        let expected_data = TokenAmount {
                            l1_address: l1_token_address,
                            l2_address: non_native_erc20_address,
                            amount: amount2 + fee
                        };

        compare(actual_data, expected_data);

        compare(*transfer_list.at(0), expected_data);
    }

    #[test]
    #[available_gas(20000000)]
    fn test_mixed_2_sufficient() {

        // Tests the situation where user has sufficient combined balance
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();

        let l1_token_address = EthAddress { address: 100_felt252 };
        init_token(starkway_address, admin_1, l1_token_address);
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };

        let native_erc20_address = starkway.get_native_token_address(l1_token_address);

        let user = contract_address_const::<30>();
        let amount1 = u256 { low: 1000, high: 0 };
        let amount2 = u256 { low: 100, high: 0 };
        let fee = u256 { low: 2, high: 0 };

        let non_native_erc20_address = deploy_non_native_token(starkway_address, 200);

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


        // Mint tokens to user
        mint(starkway_address, non_native_erc20_address, user, amount2);
        mint(starkway_address, native_erc20_address, user, fee);

        let (approval_list, transfer_list) = starkway.prepare_withdrawal_lists(l1_token_address, u256{low: 100, high:0}, user, u256{low: 2, high:0});

        assert(approval_list.len() == 2, 'Incorrect list length');
        assert(transfer_list.len() == 2, 'Incorrect list length');

        let actual_data = *approval_list.at(0);
        let expected_data_0 = TokenAmount {
                            l1_address: l1_token_address,
                            l2_address: non_native_erc20_address,
                            amount: amount2
                        };

        compare(actual_data, expected_data_0);

        compare(*transfer_list.at(0), expected_data_0);

        let actual_data = *approval_list.at(1);
        let expected_data_1 = TokenAmount {
                            l1_address: l1_token_address,
                            l2_address: native_erc20_address,
                            amount: fee
                        };

        compare(actual_data, expected_data_1);

        compare(*transfer_list.at(1), expected_data_1);



    }

    #[test]
    #[available_gas(20000000)]
    fn test_mixed_2_more_than_sufficient() {

        // Tests the situation where user does have more than sufficient combined balance
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();

        let l1_token_address = EthAddress { address: 100_felt252 };
        init_token(starkway_address, admin_1, l1_token_address);
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };

        let native_erc20_address = starkway.get_native_token_address(l1_token_address);

        let user = contract_address_const::<30>();
        let amount1 = u256 { low: 1000, high: 0 };
        let amount2 = u256 { low: 100, high: 0 };
        let fee = u256 { low: 2, high: 0 };

        let non_native_erc20_address = deploy_non_native_token(starkway_address, 200);

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


        // Mint tokens to user
        mint(starkway_address, non_native_erc20_address, user, amount2);
        mint(starkway_address, native_erc20_address, user, amount2-fee);

        let (approval_list, transfer_list) = starkway.prepare_withdrawal_lists(l1_token_address, u256{low: 100, high:0}, user, u256{low: 2, high:0});

        assert(approval_list.len() == 2, 'Incorrect list length');
        assert(transfer_list.len() == 2, 'Incorrect list length');

        let actual_data = *approval_list.at(0);
        let expected_data_0 = TokenAmount {
                            l1_address: l1_token_address,
                            l2_address: non_native_erc20_address,
                            amount: amount2
                        };

        compare(actual_data, expected_data_0);

        compare(*transfer_list.at(0), expected_data_0);

        let actual_data = *approval_list.at(1);
        let expected_data_1 = TokenAmount {
                            l1_address: l1_token_address,
                            l2_address: native_erc20_address,
                            amount: fee
                        };

        compare(actual_data, expected_data_1);

        compare(*transfer_list.at(1), expected_data_1);
    }

    #[test]
    #[available_gas(20000000)]
    fn test_different_approvals() {

        // Tests the situation where user has non-zero prior approvals
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();

        let l1_token_address = EthAddress { address: 100_felt252 };
        init_token(starkway_address, admin_1, l1_token_address);
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };

        let native_erc20_address = starkway.get_native_token_address(l1_token_address);

        let user = contract_address_const::<30>();
        let amount1 = u256 { low: 1000, high: 0 };
        let amount2 = u256 { low: 100, high: 0 };
        let fee = u256 { low: 2, high: 0 };

        let non_native_erc20_address = deploy_non_native_token(starkway_address, 200);

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


        // Mint tokens to user
        mint(starkway_address, non_native_erc20_address, user, amount2);
        mint(starkway_address, native_erc20_address, user, fee);

        set_contract_address(user);
        let erc20 = IERC20Dispatcher { contract_address: non_native_erc20_address };
        erc20.approve(starkway_address, amount2);

        let (approval_list, transfer_list) = starkway.prepare_withdrawal_lists(l1_token_address, u256{low: 100, high:0}, user, u256{low: 2, high:0});

        assert(approval_list.len() == 1, 'Incorrect list length');
        assert(transfer_list.len() == 2, 'Incorrect list length');

        
        let expected_data_0 = TokenAmount {
                            l1_address: l1_token_address,
                            l2_address: non_native_erc20_address,
                            amount: amount2
                        };

        

        compare(*transfer_list.at(0), expected_data_0);

        let actual_data = *approval_list.at(0);
        let expected_data_1 = TokenAmount {
                            l1_address: l1_token_address,
                            l2_address: native_erc20_address,
                            amount: fee
                        };

        compare(actual_data, expected_data_1);

        compare(*transfer_list.at(1), expected_data_1);
    }

    #[test]
    #[available_gas(20000000)]
    fn test_different_approvals_2() {

        // Tests the situation where user has non-zero prior approvals but requires fresh approvals for both tokens
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();

        let l1_token_address = EthAddress { address: 100_felt252 };
        init_token(starkway_address, admin_1, l1_token_address);
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };

        let native_erc20_address = starkway.get_native_token_address(l1_token_address);

        let user = contract_address_const::<30>();
        let amount1 = u256 { low: 1000, high: 0 };
        let amount2 = u256 { low: 100, high: 0 };
        let fee = u256 { low: 2, high: 0 };

        let non_native_erc20_address = deploy_non_native_token(starkway_address, 200);

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


        // Mint tokens to user
        mint(starkway_address, non_native_erc20_address, user, amount2);
        mint(starkway_address, native_erc20_address, user, fee);

        set_contract_address(user);
        let erc20 = IERC20Dispatcher { contract_address: non_native_erc20_address };
        erc20.approve(starkway_address, fee);

        let (approval_list, transfer_list) = starkway.prepare_withdrawal_lists(l1_token_address, u256{low: 100, high:0}, user, u256{low: 2, high:0});

        assert(approval_list.len() == 2, 'Incorrect list length');
        assert(transfer_list.len() == 2, 'Incorrect list length');

        
        let actual_data = *approval_list.at(0);
        let expected_data_0 = TokenAmount {
                            l1_address: l1_token_address,
                            l2_address: non_native_erc20_address,
                            amount: amount2-fee
                        };

        compare(actual_data, expected_data_0);

        let expected_data_0 = TokenAmount {
                            l1_address: l1_token_address,
                            l2_address: non_native_erc20_address,
                            amount: amount2
                        };

        compare(*transfer_list.at(0), expected_data_0);

        let actual_data = *approval_list.at(1);
        let expected_data_1 = TokenAmount {
                            l1_address: l1_token_address,
                            l2_address: native_erc20_address,
                            amount: fee
                        };

        compare(actual_data, expected_data_1);

        compare(*transfer_list.at(1), expected_data_1);
    }

}