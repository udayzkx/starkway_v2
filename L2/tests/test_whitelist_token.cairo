#[cfg(test)]
mod test_whitelist_token {
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
    use zeroable::Zeroable;

    use starkway::admin_auth::AdminAuth;
    use starkway::datatypes::{
        FeeSegment, FeeRange, L1TokenDetails, WithdrawalRange, L2TokenDetails
    };
    use starkway::erc20::erc20::StarkwayERC20;
    use starkway::interfaces::{
        IAdminAuthDispatcher, IAdminAuthDispatcherTrait, IStarkwayDispatcher,
        IStarkwayDispatcherTrait
    };
    use starkway::libraries::reentrancy_guard::ReentrancyGuard;
    use starkway::libraries::fee_library::fee_library;
    use starkway::starkway::Starkway;
    use tests::utils::DummyAdapter;
    use tests::utils::{setup, deploy, mint, init_token, register_bridge_adapter, whitelist_token};

    // Mock user in our system

    fn USER1() -> ContractAddress {
        contract_address_const::<3>()
    }

    #[test]
    #[available_gas(2000000)]
    #[should_panic(expected: ('SW: Caller not admin', 'ENTRYPOINT_FAILED', ))]
    fn test_whitelist_token_with_unauthorized_user() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };

        // set USER1 as the caller
        set_contract_address(USER1());

        let l1_token_address = EthAddress { address: 100_felt252 };
        let l2_token_details = L2TokenDetails {
            l1_address: l1_token_address,
            bridge_adapter_id: 1_u16,
            bridge_address: contract_address_const::<10>(),
            is_erc20_camel_case: false
        };
        let L2_token_address = contract_address_const::<11>();
        starkway.whitelist_token(L2_token_address, l2_token_details);
    }

    #[test]
    #[available_gas(2000000)]
    #[should_panic(expected: ('SW: Bridge Adapter not regd', 'ENTRYPOINT_FAILED', ))]
    fn test_whitelist_non_existing_bridge_adapter() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };

        // Register dummy adapter
        let bridge_adapter_address = register_bridge_adapter(starkway_address, admin_1);

        let l1_token_address = EthAddress { address: 100_felt252 };
        let l2_token_details = L2TokenDetails {
            l1_address: l1_token_address,
            bridge_adapter_id: 2_u16, // This bridge id is not registered
            bridge_address: contract_address_const::<10>(),
            is_erc20_camel_case: false
        };
        let L2_token_address = contract_address_const::<11>();
        starkway.whitelist_token(L2_token_address, l2_token_details);
    }

    #[test]
    #[available_gas(2000000)]
    #[should_panic(expected: ('SW: L2 address cannot be 0', 'ENTRYPOINT_FAILED', ))]
    fn test_whitelist_zero_address_token() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };

        // Register dummy adapter
        let bridge_adapter_address = register_bridge_adapter(starkway_address, admin_1);

        let l1_token_address = EthAddress { address: 100_felt252 };
        let l2_token_details = L2TokenDetails {
            l1_address: l1_token_address,
            bridge_adapter_id: 1_u16,
            bridge_address: contract_address_const::<10>(),
            is_erc20_camel_case: false
        };
        // Setting l2 token address as zero address
        let L2_token_address = contract_address_const::<0>();
        starkway.whitelist_token(L2_token_address, l2_token_details);
    }

    #[test]
    #[available_gas(2000000)]
    #[should_panic(expected: ('SW: Bridge address cannot be 0', 'ENTRYPOINT_FAILED', ))]
    fn test_whitelist_zero_address_bridge_adapter() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };

        // Register dummy adapter
        let bridge_adapter_address = register_bridge_adapter(starkway_address, admin_1);

        let l1_token_address = EthAddress { address: 100_felt252 };
        let l2_token_details = L2TokenDetails {
            l1_address: l1_token_address,
            bridge_adapter_id: 1_u16,
            bridge_address: contract_address_const::<0>(), // zero address as bridge address
            is_erc20_camel_case: false
        };
        let L2_token_address = contract_address_const::<10>();
        starkway.whitelist_token(L2_token_address, l2_token_details);
    }

    #[test]
    #[available_gas(2000000)]
    #[should_panic(expected: ('SW: ERC20 token not initialized', 'ENTRYPOINT_FAILED', ))]
    fn test_whitelist_uninitialized_token() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };

        // Register dummy adapter
        let bridge_adapter_address = register_bridge_adapter(starkway_address, admin_1);

        let l1_token_address = EthAddress { address: 100_felt252 };
        let l2_token_details = L2TokenDetails {
            l1_address: l1_token_address,
            bridge_adapter_id: 1_u16,
            bridge_address: contract_address_const::<10>(),
            is_erc20_camel_case: false
        };
        let L2_token_address = contract_address_const::<11>();
        // Trying to call whitelisting of token without initialising l1 token
        starkway.whitelist_token(L2_token_address, l2_token_details);
    }

    #[test]
    #[available_gas(20000000)]
    fn test_whitelist_token() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };

        // Register dummy adapter
        let bridge_adapter_address = register_bridge_adapter(starkway_address, admin_1);

        let l1_token_address = EthAddress { address: 100_felt252 };
        // initialise token
        init_token(starkway_address, admin_1, l1_token_address);

        let l2_token_details = L2TokenDetails {
            l1_address: l1_token_address,
            bridge_adapter_id: 1_u16,
            bridge_address: contract_address_const::<10>(),
            is_erc20_camel_case: false
        };
        let L2_token_address = contract_address_const::<11>();
        starkway.whitelist_token(L2_token_address, l2_token_details);
        let token_list: Array<ContractAddress> = starkway
            .get_whitelisted_token_addresses(l1_token_address);
        assert(L2_token_address == *token_list.at(0), 'token address mismatch');
    }

    #[test]
    #[available_gas(20000000)]
    fn test_whitelist_multiple_tokens() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };

        // Register dummy adapter
        let bridge_adapter_address = register_bridge_adapter(starkway_address, admin_1);

        let l1_token_address = EthAddress { address: 100_felt252 };
        // initialise token
        init_token(starkway_address, admin_1, l1_token_address);

        // whitelist first token
        let l2_token_details1 = L2TokenDetails {
            l1_address: l1_token_address,
            bridge_adapter_id: 1_u16,
            bridge_address: contract_address_const::<10>(),
            is_erc20_camel_case: false
        };
        let L2_token_address1 = contract_address_const::<5>();
        starkway.whitelist_token(L2_token_address1, l2_token_details1);

        // Register second dummy adapter
        let mut calldata = ArrayTrait::<felt252>::new();

        let adapter_address = deploy(DummyAdapter::TEST_CLASS_HASH, 100, calldata);

        set_contract_address(admin_1);
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };
        starkway.register_bridge_adapter(2_u16, 'ADAPTER', adapter_address);

        // whitelist second token
        let l2_token_details2 = L2TokenDetails {
            l1_address: l1_token_address,
            bridge_adapter_id: 2_u16,
            bridge_address: contract_address_const::<11>(),
            is_erc20_camel_case: false
        };
        let L2_token_address2 = contract_address_const::<6>();
        starkway.whitelist_token(L2_token_address2, l2_token_details2);

        let token_list: Array<ContractAddress> = starkway
            .get_whitelisted_token_addresses(l1_token_address);
        assert(L2_token_address1 == *token_list.at(0), 'token address mismatch');
        assert(L2_token_address2 == *token_list.at(1), 'token address mismatch');
    }
}
