use starknet::{ContractAddress, EthAddress};

#[cfg(test)]
mod test_upgradeability {
    use array::{Array, ArrayTrait, Span, SpanTrait};
    use core::hash::{LegacyHashFelt252};
    use core::integer::u256;
    use core::result::ResultTrait;
    use debug::{PrintTrait, print_felt252};
    use option::OptionTrait;
    use serde::Serde;
    use starknet::class_hash:: {ClassHash, class_hash_try_from_felt252};
    use starknet::{ContractAddress, contract_address_const, EthAddress};
    use starknet::testing::{set_caller_address, set_contract_address, pop_log_raw};
    use traits::{Default, Into, TryInto};
    use starkway::admin_auth::AdminAuth;
    use starkway::datatypes::{L1TokenDetails, WithdrawalRange, L2TokenDetails};
    use starkway::erc20::erc20::StarkwayERC20;
    use tests::dummy_interfaces::{
        IAdminAuthDispatcher, IAdminAuthDispatcherTrait, IStarkwayDispatcher,
        IStarkwayDispatcherTrait, IERC20Dispatcher, IERC20DispatcherTrait, IBridgeAdapterDispatcher,
        IBridgeAdapterDispatcherTrait
    };
    use starkway::libraries::reentrancy_guard::ReentrancyGuard;
    use starkway::libraries::fee_library::fee_library;
    //use starkway::starkway::Starkway;
    use zeroable::Zeroable;
    use tests::utils::{setup, deploy, mint, init_token, register_bridge_adapter, deploy_non_native_token, whitelist_token};
    use tests::utils::DummyAdapter;
    use tests::dummy_starkway::Starkway;


    #[test]
    #[available_gas(20000000)]
    #[should_panic(expected: ('ENTRYPOINT_NOT_FOUND', ))]
    fn test_invalid_call_without_upgrade() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();
        let user = contract_address_const::<30>();
        set_contract_address(admin_1);

        let new_class_hash = Starkway::TEST_CLASS_HASH;
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };
        
        // starkway.upgrade_class_hash(new_class_hash.try_into().unwrap());
        
        // Call functions present only in the new contract - this should revert since contract was not upgraded
        starkway.set_dummy_var(1234_u32);
        let dummy_var = starkway.get_dummy_var();
        assert(dummy_var == 1234_u32, 'Invalid dummy var value');
    }

    #[test]
    #[available_gas(20000000)]
    #[should_panic(expected: ('SW: Caller not admin', 'ENTRYPOINT_FAILED', ))]
    fn test_unauthorised_upgrade() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();
         let user = contract_address_const::<30>();
         set_contract_address(user);
         let new_class_hash = class_hash_try_from_felt252(12345).unwrap();
         let starkway = IStarkwayDispatcher { contract_address: starkway_address };
         starkway.upgrade_class_hash(new_class_hash);
    }

    #[test]
    #[available_gas(20000000)]
    #[should_panic(expected: ('SW: Invalid new class hash', 'ENTRYPOINT_FAILED', ))]
    fn test_zero_class_hash() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();
         let user = contract_address_const::<30>();
         set_contract_address(admin_1);
         let new_class_hash = class_hash_try_from_felt252(0).unwrap();
         let starkway = IStarkwayDispatcher { contract_address: starkway_address };
         starkway.upgrade_class_hash(new_class_hash);
    }

    #[test]
    #[available_gas(20000000)]
    fn test_simple_upgrade() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();
        let user = contract_address_const::<30>();
        set_contract_address(admin_1);

        let new_class_hash = Starkway::TEST_CLASS_HASH;
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };
        let erc20_temp_class_hash = class_hash_try_from_felt252(12345).unwrap();
        starkway.set_erc20_class_hash(erc20_temp_class_hash);
        let erc20_hash_before_upgrade = starkway.get_erc20_class_hash();
        starkway.upgrade_class_hash(new_class_hash.try_into().unwrap());
        let erc20_hash_after_upgrade = starkway.get_erc20_class_hash();
        
        // Check erc20 class hash - same value indicates that storage variables maintain state post upgrade
        assert (erc20_hash_before_upgrade == erc20_temp_class_hash, 'Error in contract state');
        assert (erc20_hash_after_upgrade == erc20_temp_class_hash, 'Error in contract state');

        // Call functions present only in the new contract
        starkway.set_dummy_var(1234_u32);
        let dummy_var = starkway.get_dummy_var();
        assert(dummy_var == 1234_u32, 'Invalid dummy var value');
    }
}