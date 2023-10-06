#[cfg(test)]
mod test_starkway {
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
    fn test_setting_l1_starkway_address_with_unauthorized_user() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };

        // set USER1 as the caller
        set_contract_address(USER1());

        let l1_starkway_address: EthAddress = EthAddress { address: 100_felt252 };
        starkway.set_l1_starkway_address(l1_starkway_address);
    }

    #[test]
    #[available_gas(2000000)]
    fn test_setting_l1_starkway_address_with_authorized_user() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };

        let l1_starkway_address: EthAddress = EthAddress { address: 100_felt252 };
        starkway.set_l1_starkway_address(l1_starkway_address);
        let l1_starkway_address_res = starkway.get_l1_starkway_address();
        assert(l1_starkway_address == l1_starkway_address_res, 'l1 starkway address mismatch');
    }

    #[test]
    #[available_gas(2000000)]
    #[should_panic(expected: ('SW: Caller not admin', 'ENTRYPOINT_FAILED', ))]
    fn test_setting_l1_starkway_vault_address_with_unauthorized_user() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };

        // set USER1 as the caller
        set_contract_address(USER1());

        let l1_starkway_vault_address: EthAddress = EthAddress { address: 100_felt252 };
        starkway.set_l1_starkway_vault_address(l1_starkway_vault_address);
    }

    #[test]
    #[available_gas(2000000)]
    fn test_setting_l1_starkway_vault_address_with_authorized_user() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };

        let l1_starkway_vault_address: EthAddress = EthAddress { address: 100_felt252 };
        starkway.set_l1_starkway_vault_address(l1_starkway_vault_address);
        let l1_starkway_vault_address_res = starkway.get_l1_starkway_vault_address();
        assert(
            l1_starkway_vault_address == l1_starkway_vault_address_res,
            'l1 starkway vault addr mismatch'
        );
    }

    #[test]
    #[available_gas(2000000)]
    #[should_panic(expected: ('SW: Caller not admin', 'ENTRYPOINT_FAILED', ))]
    fn test_setting_admin_auth_address_with_unauthorized_user() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };

        // set USER1 as the caller
        set_contract_address(USER1());

        let admin_auth_address: ContractAddress = contract_address_const::<10>();
        starkway.set_admin_auth_address(admin_auth_address);
    }

    #[test]
    #[available_gas(2000000)]
    fn test_setting_admin_auth_address_with_authorized_user() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };

        let admin_auth_address: ContractAddress = contract_address_const::<10>();
        starkway.set_admin_auth_address(admin_auth_address);
        let admin_auth_address_res = starkway.get_admin_auth_address();
        assert(admin_auth_address == admin_auth_address_res, 'admin_auth_address mismatch');
    }

    #[test]
    #[available_gas(2000000)]
    #[should_panic(expected: ('SW: Caller not admin', 'ENTRYPOINT_FAILED', ))]
    fn test_setting_erc20_classhash_with_unauthorized_user() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };

        // set USER1 as the caller
        set_contract_address(USER1());

        let erc20_classhash: ClassHash = StarkwayERC20::TEST_CLASS_HASH.try_into().unwrap();
        starkway.set_erc20_class_hash(erc20_classhash);
    }

    #[test]
    #[available_gas(2000000)]
    fn test_setting_erc20_classhash_with_authorized_user() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };

        let erc20_classhash: ClassHash = StarkwayERC20::TEST_CLASS_HASH.try_into().unwrap();
        starkway.set_erc20_class_hash(erc20_classhash);
        let erc20_classhash_res = starkway.get_erc20_class_hash();
        assert(erc20_classhash == erc20_classhash_res, 'erc20 classhash mismatch');
    }

    #[test]
    #[available_gas(2000000)]
    #[should_panic(expected: ('SW: Caller not admin', 'ENTRYPOINT_FAILED', ))]
    fn test_setting_fee_lib_classhash_with_unauthorized_user() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };

        // set USER1 as the caller
        set_contract_address(USER1());

        let fee_library_classhash: ClassHash = fee_library::TEST_CLASS_HASH.try_into().unwrap();
        starkway.set_fee_lib_class_hash(fee_library_classhash);
    }

    #[test]
    #[available_gas(2000000)]
    fn test_setting_fee_lib_classhash_with_authorized_user() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };

        let fee_library_classhash: ClassHash = fee_library::TEST_CLASS_HASH.try_into().unwrap();
        starkway.set_fee_lib_class_hash(fee_library_classhash);
        let fee_library_classhash_res = starkway.get_fee_lib_class_hash();
        assert(
            fee_library_classhash == fee_library_classhash_res, 'fee library classhash mismatch'
        );
    }

    #[test]
    #[available_gas(2000000)]
    #[should_panic(expected: ('SW: Caller not admin', 'ENTRYPOINT_FAILED', ))]
    fn test_setting_reentrancy_guard_classhash_with_unauthorized_user() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };

        // set USER1 as the caller
        set_contract_address(USER1());

        let reentrancy_guard_classhash: ClassHash = ReentrancyGuard::TEST_CLASS_HASH
            .try_into()
            .unwrap();
        starkway.set_reentrancy_guard_class_hash(reentrancy_guard_classhash);
    }

    #[test]
    #[available_gas(2000000)]
    fn test_setting_reentrancy_guard_classhash_with_authorized_user() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };

        let reentrancy_guard_classhash: ClassHash = ReentrancyGuard::TEST_CLASS_HASH
            .try_into()
            .unwrap();
        starkway.set_reentrancy_guard_class_hash(reentrancy_guard_classhash);
        let reentrancy_guard_classhash_res = starkway.get_reentrancy_guard_class_hash();
        assert(
            reentrancy_guard_classhash == reentrancy_guard_classhash_res,
            'reentrancy_guard hash mismatch'
        );
    }

    #[test]
    #[available_gas(2000000)]
    #[should_panic(expected: ('SW: Caller not admin', 'ENTRYPOINT_FAILED', ))]
    fn test_register_bridge_adapter_with_unauthorized_user() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };

        // set USER1 as the caller
        set_contract_address(USER1());
        let mut calldata = ArrayTrait::<felt252>::new();
        let adapter_address = deploy(DummyAdapter::TEST_CLASS_HASH, 100, calldata);
        starkway.register_bridge_adapter(1_u16, 'ADAPTER', adapter_address);
    }

    #[test]
    #[available_gas(2000000)]
    #[should_panic(expected: ('SW: Bridge Adapter id invalid', 'ENTRYPOINT_FAILED', ))]
    fn test_register_bridge_adapter_with_zero_id() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };

        let mut calldata = ArrayTrait::<felt252>::new();
        let adapter_address = deploy(DummyAdapter::TEST_CLASS_HASH, 100, calldata);
        set_contract_address(admin_1);
        // Registering bridge adapter with zero adapter id
        starkway.register_bridge_adapter(0_u16, 'ADAPTER', adapter_address);
    }

    #[test]
    #[available_gas(2000000)]
    #[should_panic(expected: ('SW: Adapter address is 0', 'ENTRYPOINT_FAILED', ))]
    fn test_register_bridge_adapter_with_zero_address() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };
        // Registering bridge adapter with zero adapter address
        starkway.register_bridge_adapter(1_u16, 'ADAPTER', contract_address_const::<0>());
    }

    #[test]
    #[available_gas(2000000)]
    #[should_panic(expected: ('SW: Bridge Adapter name invalid', 'ENTRYPOINT_FAILED', ))]
    fn test_register_bridge_adapter_with_invalid_name() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };

        let mut calldata = ArrayTrait::<felt252>::new();
        let adapter_address = deploy(DummyAdapter::TEST_CLASS_HASH, 100, calldata);
        set_contract_address(admin_1);
        // Registering bridge adapter with invalid name
        starkway.register_bridge_adapter(1_u16, 0, adapter_address);
    }

    #[test]
    #[available_gas(2000000)]
    #[should_panic(expected: ('SW: Bridge Adapter exists', 'ENTRYPOINT_FAILED', ))]
    fn test_registering_already_existing_bridge() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };
        register_bridge_adapter(starkway_address, admin_1);
        // Registering the already registered bridge Adapter
        register_bridge_adapter(starkway_address, admin_1);
    }

    #[test]
    #[available_gas(2000000)]
    #[should_panic(expected: ('SW: Caller not admin', 'ENTRYPOINT_FAILED', ))]
    fn test_setting_withdrawal_range_with_unauthorized_user() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };

        // set USER1 as the caller
        set_contract_address(USER1());

        let l1_token_address: EthAddress = EthAddress { address: 100_felt252 };
        let withdrawal_range: WithdrawalRange = WithdrawalRange {
            min: u256 { low: 100, high: 0 }, max: u256 { low: 1000, high: 0 }
        };

        starkway.set_withdrawal_range(l1_token_address, withdrawal_range);
    }

    #[test]
    #[available_gas(2000000)]
    #[should_panic(expected: ('SW: Token uninitialized', 'ENTRYPOINT_FAILED', ))]
    fn test_setting_withdrawal_range_for_unregistered_token() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };

        let l1_token_address: EthAddress = EthAddress { address: 100_felt252 };
        let withdrawal_range: WithdrawalRange = WithdrawalRange {
            min: u256 { low: 100, high: 0 }, max: u256 { low: 1000, high: 0 }
        };

        starkway.set_withdrawal_range(l1_token_address, withdrawal_range);
    }

    #[test]
    #[available_gas(20000000)]
    fn test_setting_withdrawal_range_for_registered_token() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };

        let l1_token_address: EthAddress = EthAddress { address: 100_felt252 };
        init_token(starkway_address, admin_1, l1_token_address);
        let withdrawal_range: WithdrawalRange = WithdrawalRange {
            min: u256 { low: 100, high: 0 }, max: u256 { low: 1000, high: 0 }
        };

        starkway.set_withdrawal_range(l1_token_address, withdrawal_range);
        let withdrawal_range_res: WithdrawalRange = starkway.get_withdrawal_range(l1_token_address);
        assert(withdrawal_range_res.min == u256 { low: 100, high: 0 }, 'Min value mismatch');
        assert(withdrawal_range_res.max == u256 { low: 1000, high: 0 }, 'Max value mismatch');
    }
}
