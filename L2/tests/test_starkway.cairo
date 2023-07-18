#[cfg(test)]
mod test_starkway {
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
    use zeroable::Zeroable;

    // Mock users in our system
    fn ADMIN1() -> ContractAddress {
        contract_address_const::<1>()
    }

    fn ADMIN2() -> ContractAddress {
        contract_address_const::<2>()
    }

    fn USER1() -> ContractAddress {
        contract_address_const::<3>()
    }

    // function to initialise token
    fn init_token(
        starkway_address: ContractAddress, admin_1: ContractAddress, l1_token_address: EthAddress
    ) {
        set_contract_address(admin_1);

        let starkway = IStarkwayDispatcher { contract_address: starkway_address };
        let l1_token_details = L1TokenDetails {
            name: 'TEST_TOKEN', symbol: 'TEST', decimals: 18_u8
        };
        starkway.authorised_init_token(l1_token_address, l1_token_details);
    }

    fn deploy(
        contract_class_hash: felt252, salt: felt252, calldata: Array<felt252>
    ) -> ContractAddress {
        let (address, _) = starknet::deploy_syscall(
            contract_class_hash.try_into().unwrap(), salt, calldata.span(), false
        )
            .unwrap();
        address
    }

    fn setup() -> (ContractAddress, ContractAddress, ContractAddress, ContractAddress) {
        let admin_1: ContractAddress = ADMIN1();
        let admin_2: ContractAddress = ADMIN2();

        // Deploy Admin auth contract
        let mut admin_auth_calldata = ArrayTrait::<felt252>::new();
        admin_1.serialize(ref admin_auth_calldata);
        admin_2.serialize(ref admin_auth_calldata);

        let admin_auth_address = deploy(AdminAuth::TEST_CLASS_HASH, 100, admin_auth_calldata);

        // Deploy Starkway contract
        let mut starkway_calldata = ArrayTrait::<felt252>::new();
        let fee_rate = u256 { low: 10, high: 0 };
        let fee_lib_class_hash = fee_library::TEST_CLASS_HASH;
        let erc20_class_hash = StarkwayERC20::TEST_CLASS_HASH;
        admin_auth_address.serialize(ref starkway_calldata);
        fee_rate.serialize(ref starkway_calldata);
        fee_lib_class_hash.serialize(ref starkway_calldata);
        erc20_class_hash.serialize(ref starkway_calldata);
        let starkway_address = deploy(Starkway::TEST_CLASS_HASH, 100, starkway_calldata);

        // Set admin_1 as default caller
        set_contract_address(admin_1);

        let starkway = IStarkwayDispatcher { contract_address: starkway_address };

        // Set class hash for re-entrancy guard library
        starkway
            .set_reentrancy_guard_class_hash(ReentrancyGuard::TEST_CLASS_HASH.try_into().unwrap());

        // Set class hash for fee library
        starkway.set_fee_lib_class_hash(fee_library::TEST_CLASS_HASH.try_into().unwrap());

        return (starkway_address, admin_auth_address, admin_1, admin_2);
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
        starkway.set_l1_starkway_address(l1_starkway_vault_address);
    }

    #[test]
    #[available_gas(2000000)]
    fn test_setting_l1_starkway_vault_address_with_authorized_user() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };

        let l1_starkway_vault_address: EthAddress = EthAddress { address: 100_felt252 };
        starkway.set_l1_starkway_address(l1_starkway_vault_address);
        let l1_starkway_vault_address_res = starkway.get_l1_starkway_address();
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

    // #[test]
    // #[available_gas(2000000)]
    // #[should_panic(expected: ('SW: Caller not admin', 'ENTRYPOINT_FAILED', ))]
    // fn test_register_bridge_adapter_with_unauthorized_user() {
    //     let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();
    //     let starkway = IStarkwayDispatcher { contract_address: starkway_address };

    //     // set USER1 as the caller
    //     set_contract_address(USER1());
    //     let mut calldata = ArrayTrait::<felt252>::new();
    //     let adapter_address = deploy(DummyAdapter::TEST_CLASS_HASH, 100, calldata);
    //     starkway.register_bridge_adapter(1_u16, 'ADAPTER', adapter_address);
    // }

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
    #[available_gas(2000000)]
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
