use starknet::{ContractAddress, EthAddress};

#[cfg(test)]
mod test_can_withdraw_multi {
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
    use tests::utils::{setup, deploy, mint, init_token, 
        register_bridge_adapter, deploy_non_native_token, 
        whitelist_token, whitelist_token_camelCase};

    
    #[test]
    #[available_gas(20000000)]
    #[should_panic(expected: ('SW: Token uninitialized', 'ENTRYPOINT_FAILED'))]
    fn test_uninitialized_token() {

        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();

        let l1_token_address = EthAddress { address: 100_felt252 };

        let starkway = IStarkwayDispatcher { contract_address: starkway_address };
        let transfer_list = ArrayTrait::new();
        starkway.can_withdraw_multi(
            transfer_list,
            l1_token_address,
            u256{low:0, high:0},
            u256{low:0, high:0}
        );
    }

    #[test]
    #[available_gas(20000000)]
    fn test_empty_transfer_list() {

        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();

        let l1_token_address = EthAddress { address: 100_felt252 };
        init_token(starkway_address, admin_1, l1_token_address);
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };
        let transfer_list = ArrayTrait::new();
        let can_withdraw = starkway.can_withdraw_multi(
            transfer_list,
            l1_token_address,
            u256{low:0, high:0},
            u256{low:0, high:0}
        );
        assert(can_withdraw, 'Invalid response');
    }

    #[test]
    #[available_gas(20000000)]
    fn test_amount_zero() {

        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();

        let l1_token_address = EthAddress { address: 100_felt252 };
        init_token(starkway_address, admin_1, l1_token_address);
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };
        let native_erc20_address = starkway.get_native_token_address(l1_token_address);
        let mut transfer_list = ArrayTrait::new();
        let token_amount = TokenAmount {
                            l1_address: l1_token_address,
                            l2_address: native_erc20_address,
                            amount: u256{low:0, high:0}
                            };
        transfer_list.append(token_amount);
        let can_withdraw = starkway.can_withdraw_multi(
            transfer_list,
            l1_token_address,
            u256{low:0, high:0},
            u256{low:0, high:0}
        );
        assert(can_withdraw, 'Invalid response');
    }

    #[test]
    #[available_gas(20000000)]
    #[should_panic(expected: ('SW: Incompatible L1 addr', 'ENTRYPOINT_FAILED'))]
    fn test_incompatible_l1_address() {

        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();

        let l1_token_address = EthAddress { address: 100_felt252 };
        let l1_token_address_incorrect = EthAddress { address: 200_felt252 };
        init_token(starkway_address, admin_1, l1_token_address);
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };
        let native_erc20_address = starkway.get_native_token_address(l1_token_address);
        let mut transfer_list = ArrayTrait::new();
        let token_amount = TokenAmount {
                            l1_address: l1_token_address_incorrect, //incorrect l1_address in TokenAmount
                            l2_address: native_erc20_address,
                            amount: u256{low:0, high:0}
                            };
        transfer_list.append(token_amount);
        let can_withdraw = starkway.can_withdraw_multi(
            transfer_list,
            l1_token_address,
            u256{low:0, high:0},
            u256{low:0, high:0}
        );        
    }

    #[test]
    #[available_gas(20000000)]
    #[should_panic(expected: ('SW: Mismatched amount', 'ENTRYPOINT_FAILED'))]
    fn test_amount_mismatch() {

        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();

        let l1_token_address = EthAddress { address: 100_felt252 };
        init_token(starkway_address, admin_1, l1_token_address);
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };
        let native_erc20_address = starkway.get_native_token_address(l1_token_address);
        let mut transfer_list = ArrayTrait::new();
        let token_amount = TokenAmount {
                            l1_address: l1_token_address,
                            l2_address: native_erc20_address,
                            amount: u256{low:100, high:0}
                            };
        transfer_list.append(token_amount);
        let can_withdraw = starkway.can_withdraw_multi(
            transfer_list,
            l1_token_address,
            u256{low:100, high:0},
            u256{low:2, high:0}
        );
        
    }

    #[test]
    #[available_gas(20000000)]
    #[should_panic(expected: ('SW: min_withdraw > amount', 'ENTRYPOINT_FAILED'))]
    fn test_out_of_range() {

        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();

        let l1_token_address = EthAddress { address: 100_felt252 };
        init_token(starkway_address, admin_1, l1_token_address);
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };
        let native_erc20_address = starkway.get_native_token_address(l1_token_address);
        let mut transfer_list = ArrayTrait::new();
        let token_amount = TokenAmount {
                            l1_address: l1_token_address,
                            l2_address: native_erc20_address,
                            amount: u256{low:1, high:0}
                            };
        transfer_list.append(token_amount);
        let can_withdraw = starkway.can_withdraw_multi(
            transfer_list,
            l1_token_address,
            u256{low:1, high:0},
            u256{low:0, high:0}
        );
        
    }

    #[test]
    #[available_gas(20000000)]
    #[should_panic(expected: ('SW: L1 address Mismatch', 'ENTRYPOINT_FAILED'))]
    fn test_l1_address_mismatch() {

        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();

        let l1_token_address = EthAddress { address: 100_felt252 };
        let l1_token_address_2 = EthAddress { address: 200_felt252 };
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

        let can_withdraw = starkway.can_withdraw_multi(
            transfer_list,
            l1_token_address,
            u256{low:300, high:0},
            u256{low:6, high:0}
        );
        
    }

    #[test]
    #[available_gas(20000000)]
    fn test_insufficient_single_token_liquidity() {

        // test the scenario where user is transferring multiple tokens but bridge doesnt have enough liquidity in any 1 token
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();

        let l1_token_address = EthAddress { address: 100_felt252 };
        let l1_token_address_2 = EthAddress { address: 200_felt252 };
        init_token(starkway_address, admin_1, l1_token_address);
        //init_token(starkway_address, admin_1, l1_token_address_2);
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
            l1_token_address,
            non_native_erc20_address_2
        );

        transfer_list.append(token_amount_2);
        let token_amount_3 = TokenAmount {
                            l1_address: l1_token_address,
                            l2_address: non_native_erc20_address_2,
                            amount: u256{low:106, high:0}
                            };
        
        transfer_list.append(token_amount_3);

        let can_withdraw = starkway.can_withdraw_multi(
            transfer_list,
            l1_token_address,
            u256{low:300, high:0},
            u256{low:6, high:0}
        );

        assert(!can_withdraw, 'Invalid response');
        
    }

    #[test]
    #[available_gas(20000000)]
    fn test_single_native_token_sufficient_liquidity() {

        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();

        let l1_token_address = EthAddress { address: 100_felt252 };
        let l1_token_address_2 = EthAddress { address: 200_felt252 };
        init_token(starkway_address, admin_1, l1_token_address);
        //init_token(starkway_address, admin_1, l1_token_address_2);
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };

        
        let native_erc20_address = starkway.get_native_token_address(l1_token_address);
        let mut transfer_list = ArrayTrait::new();
        let token_amount = TokenAmount {
                            l1_address: l1_token_address,
                            l2_address: native_erc20_address,
                            amount: u256{low:306, high:0}
                            };
        transfer_list.append(token_amount);
        
        let can_withdraw = starkway.can_withdraw_multi(
            transfer_list,
            l1_token_address,
            u256{low:300, high:0},
            u256{low:6, high:0}
        );

        assert(can_withdraw, 'Invalid response');
        
    }

    #[test]
    #[available_gas(20000000)]
    fn test_single_native_token_sufficient_prior_liquidity() {

        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();

        let l1_token_address = EthAddress { address: 100_felt252 };
        let l1_token_address_2 = EthAddress { address: 200_felt252 };
        init_token(starkway_address, admin_1, l1_token_address);
        //init_token(starkway_address, admin_1, l1_token_address_2);
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };

        
        let native_erc20_address = starkway.get_native_token_address(l1_token_address);
        let mut transfer_list = ArrayTrait::new();
        let token_amount = TokenAmount {
                            l1_address: l1_token_address,
                            l2_address: native_erc20_address,
                            amount: u256{low:306, high:0}
                            };
        transfer_list.append(token_amount);

        // Give prior liquidity to bridge
        mint(starkway_address, native_erc20_address, starkway_address, amount: u256{low:306, high:0});
        let can_withdraw = starkway.can_withdraw_multi(
            transfer_list,
            l1_token_address,
            u256{low:300, high:0},
            u256{low:6, high:0}
        );

        assert(can_withdraw, 'Invalid response');    
    }

    #[test]
    #[available_gas(20000000)]
    fn test_single_non_native_token_sufficient_liquidity() {

        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();

        let l1_token_address = EthAddress { address: 100_felt252 };
        let l1_token_address_2 = EthAddress { address: 200_felt252 };
        init_token(starkway_address, admin_1, l1_token_address);
        //init_token(starkway_address, admin_1, l1_token_address_2);
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
                            l2_address: non_native_erc20_address,
                            amount: u256{low:306, high:0}
                            };
        transfer_list.append(token_amount);
        
        let can_withdraw = starkway.can_withdraw_multi(
            transfer_list,
            l1_token_address,
            u256{low:300, high:0},
            u256{low:6, high:0}
        );

        assert(can_withdraw, 'Invalid response');
        
    }

    #[test]
    #[available_gas(20000000)]
    fn test_single_non_native_token_sufficient_liquidity_camel() {

        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();

        let l1_token_address = EthAddress { address: 100_felt252 };
        let l1_token_address_2 = EthAddress { address: 200_felt252 };
        init_token(starkway_address, admin_1, l1_token_address);
        //init_token(starkway_address, admin_1, l1_token_address_2);
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };

        let non_native_erc20_address = deploy_non_native_token(starkway_address, 100);

        // Register dummy adapter
        let bridge_adapter_address = register_bridge_adapter(starkway_address, admin_1);

        // Whitelist token
        whitelist_token_camelCase(
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
                            l2_address: non_native_erc20_address,
                            amount: u256{low:306, high:0}
                            };
        transfer_list.append(token_amount);
        
        let can_withdraw = starkway.can_withdraw_multi(
            transfer_list,
            l1_token_address,
            u256{low:300, high:0},
            u256{low:6, high:0}
        );

        assert(can_withdraw, 'Invalid response');
        
    }

    #[test]
    #[available_gas(20000000)]
    fn test_multi_tokens_sufficient_prior_liquidity() {

        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();

        let l1_token_address = EthAddress { address: 100_felt252 };
        let l1_token_address_2 = EthAddress { address: 200_felt252 };
        init_token(starkway_address, admin_1, l1_token_address);
        //init_token(starkway_address, admin_1, l1_token_address_2);
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
        whitelist_token_camelCase(
            starkway_address,
            admin_1,
            1_u16,
            contract_address_const::<400>(),
            l1_token_address,
            non_native_erc20_address_2
        );

        transfer_list.append(token_amount_2);
        let token_amount_3 = TokenAmount {
                            l1_address: l1_token_address,
                            l2_address: non_native_erc20_address_2,
                            amount: u256{low:106, high:0}
                            };
        
        transfer_list.append(token_amount_3);

        // Bridge will have sufficient liquidity from prior tokens + tokens being transferred by the user
        mint(starkway_address, native_erc20_address, starkway_address, amount: u256{low:200, high:0});
        let can_withdraw = starkway.can_withdraw_multi(
            transfer_list,
            l1_token_address,
            u256{low:300, high:0},
            u256{low:6, high:0}
        );

        assert(can_withdraw, 'Invalid response');
        
    }

    #[test]
    #[available_gas(20000000)]
    fn test_multi_tokens_sufficient_prior_liquidity_2() {

        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();

        let l1_token_address = EthAddress { address: 100_felt252 };
        let l1_token_address_2 = EthAddress { address: 200_felt252 };
        init_token(starkway_address, admin_1, l1_token_address);
        //init_token(starkway_address, admin_1, l1_token_address_2);
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
            l1_token_address,
            non_native_erc20_address_2
        );

        transfer_list.append(token_amount_2);
        let token_amount_3 = TokenAmount {
                            l1_address: l1_token_address,
                            l2_address: non_native_erc20_address_2,
                            amount: u256{low:106, high:0}
                            };
        
        transfer_list.append(token_amount_3);

        // Bridge has sufficient liquidity in prior non-native tokens + tokens transferred by the user
        mint(starkway_address, non_native_erc20_address_2, starkway_address, amount: u256{low:200, high:0});
        let can_withdraw = starkway.can_withdraw_multi(
            transfer_list,
            l1_token_address,
            u256{low:300, high:0},
            u256{low:6, high:0}
        );

        assert(can_withdraw, 'Invalid response');
        
    }

    #[test]
    #[available_gas(20000000)]
    fn test_multi_tokens_sufficient_liquidity() {

        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();

        let l1_token_address = EthAddress { address: 100_felt252 };
        let l1_token_address_2 = EthAddress { address: 200_felt252 };
        init_token(starkway_address, admin_1, l1_token_address);
        //init_token(starkway_address, admin_1, l1_token_address_2);
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
                            amount: u256{low:2, high:0}
                            };
        let non_native_erc20_address_2 = deploy_non_native_token(starkway_address, 200);
        whitelist_token(
            starkway_address,
            admin_1,
            1_u16,
            contract_address_const::<400>(),
            l1_token_address,
            non_native_erc20_address_2
        );

        transfer_list.append(token_amount_2);
        

        //mint(starkway_address, native_erc20_address, starkway_address, amount: u256{low:200, high:0});
        let can_withdraw = starkway.can_withdraw_multi(
            transfer_list,
            l1_token_address,
            u256{low:100, high:0},
            u256{low:2, high:0}
        );

        assert(can_withdraw, 'Invalid response');   
    }
}

