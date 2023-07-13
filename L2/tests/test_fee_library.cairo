#[cfg(test)]
mod test_starkway_withdraw {
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
        let admin_1: ContractAddress = contract_address_const::<10>();
        let admin_2: ContractAddress = contract_address_const::<20>();

        // Deploy Admin auth contract
        let mut admin_auth_calldata = ArrayTrait::<felt252>::new();
        admin_1.serialize(ref admin_auth_calldata);
        admin_2.serialize(ref admin_auth_calldata);

        let admin_auth_address = deploy(AdminAuth::TEST_CLASS_HASH, 100, admin_auth_calldata);

        // Deploy Starkway contract
        let mut starkway_calldata = ArrayTrait::<felt252>::new();
        let fee_rate = u256 { low: 200, high: 0 };
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
    #[available_gas(20000000)]
    #[should_panic(expected: ('SW: Caller not admin', 'ENTRYPOINT_FAILED', ))]
    fn test_set_fee_lib_class_hash_unauthorized() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };
        // set some random address as the caller
        set_contract_address(contract_address_const::<1>());
        starkway.set_fee_lib_class_hash(StarkwayERC20::TEST_CLASS_HASH.try_into().unwrap());
    }

    #[test]
    #[available_gas(20000000)]
    #[should_panic(expected: ('SW: Caller not admin', 'ENTRYPOINT_FAILED', ))]
    fn test_set_default_fee_rate_unauthorized() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };
        // set some random address as the caller
        set_contract_address(contract_address_const::<1>());
        starkway.set_default_fee_rate(u256 { low: 2, high: 0 });
    }

    #[test]
    #[available_gas(20000000)]
    fn test_set_and_get_default_fee_rate() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };
        starkway.set_default_fee_rate(u256 { low: 2, high: 0 });
        let fee_rate = starkway.get_default_fee_rate();
        assert(fee_rate == u256 { low: 2, high: 0 }, 'Default fee rate is wrong');
    }

    #[test]
    #[available_gas(20000000)]
    #[should_panic(expected: ('SW: Caller not admin', 'ENTRYPOINT_FAILED', ))]
    fn test_set_fee_range_unauthorized() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };

        let l1_token_address = EthAddress { address: 100_felt252 };
        let fee_range = FeeRange {
            is_set: true, min: u256 { low: 100, high: 0 }, max: u256 { low: 200, high: 0 }
        };
        // set some random address as the caller
        set_contract_address(contract_address_const::<1>());
        starkway.set_fee_range(l1_token_address, fee_range);
    }

    #[test]
    #[available_gas(20000000)]
    fn test_set_and_get_fee_range() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };

        let l1_token_address = EthAddress { address: 100_felt252 };
        let fee_range = FeeRange {
            is_set: true, min: u256 { low: 100, high: 0 }, max: u256 { low: 200, high: 0 }
        };
        starkway.set_fee_range(l1_token_address, fee_range);
        let expected_fee_range = starkway.get_fee_range(l1_token_address);
        assert(expected_fee_range.is_set == fee_range.is_set, 'is_set value mismatch');
        assert(expected_fee_range.min == fee_range.min, 'Min value mismatch');
        assert(expected_fee_range.max == fee_range.max, 'Max value mismatch');
    }

    #[test]
    #[available_gas(20000000)]
    #[should_panic(expected: ('Min value > Max value', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED', ))]
    fn test_set_fee_range_with_min_greater_than_max() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };

        let l1_token_address = EthAddress { address: 100_felt252 };
        // Declaring the min value greater than max value 
        let fee_range = FeeRange {
            is_set: true, min: u256 { low: 100, high: 0 }, max: u256 { low: 10, high: 0 }
        };
        starkway.set_fee_range(l1_token_address, fee_range);
    }

    #[test]
    #[available_gas(20000000)]
    #[should_panic(expected: ('SW: Caller not admin', 'ENTRYPOINT_FAILED', ))]
    fn test_set_fee_segment_unauthorized() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };
        let l1_token_address = EthAddress { address: 100_felt252 };
        let fee_segment = FeeSegment {
            from_amount: u256 { low: 0, high: 0 }, fee_rate: u256 { low: 2, high: 0 }
        };
        // set some random address as the caller
        set_contract_address(contract_address_const::<1>());
        starkway.set_fee_segment(l1_token_address, 1_u8, fee_segment);
    }

    #[test]
    #[available_gas(20000000)]
    #[should_panic(expected: ('Tier should be >= 1', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED', ))]
    fn test_set_fee_segment_with_invalid_tier() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };
        let l1_token_address = EthAddress { address: 100_felt252 };
        let fee_segment = FeeSegment {
            from_amount: u256 { low: 0, high: 0 }, fee_rate: u256 { low: 2, high: 0 }
        };
        // Setting fee segment for 0th tier
        starkway.set_fee_segment(l1_token_address, 0_u8, fee_segment);
    }

    #[test]
    #[available_gas(20000000)]
    #[should_panic(
        expected: ('tier1 from_amount should be 0', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED', )
    )]
    fn test_set_fee_segment_with_invalid_tier1_amount() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };
        let l1_token_address = EthAddress { address: 100_felt252 };
        // from_amount of tier 1 should be zero
        let fee_segment = FeeSegment {
            from_amount: u256 { low: 10, high: 0 }, fee_rate: u256 { low: 2, high: 0 }
        };
        starkway.set_fee_segment(l1_token_address, 1_u8, fee_segment);
    }

    #[test]
    #[available_gas(20000000)]
    #[should_panic(
        expected: ('Fee invalid wrt lower tier', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED', )
    )]
    fn test_set_fee_segment_with_invalid_higher_fee() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };
        let l1_token_address = EthAddress { address: 100_felt252 };
        let fee_segment1 = FeeSegment {
            from_amount: u256 { low: 0, high: 0 }, fee_rate: u256 { low: 2, high: 0 }
        };
        starkway.set_fee_segment(l1_token_address, 1_u8, fee_segment1);
        // second tier's fee should be less than first tier
        let fee_segment2 = FeeSegment {
            from_amount: u256 { low: 1000, high: 0 }, fee_rate: u256 { low: 20, high: 0 }
        };
        starkway.set_fee_segment(l1_token_address, 2_u8, fee_segment2);
    }

    #[test]
    #[available_gas(20000000)]
    #[should_panic(
        expected: ('Amount invalid wrt lower tier', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED', )
    )]
    fn test_set_fee_segment_with_invalid_higher_amount() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };
        let l1_token_address = EthAddress { address: 100_felt252 };
        let fee_segment1 = FeeSegment {
            from_amount: u256 { low: 0, high: 0 }, fee_rate: u256 { low: 20, high: 0 }
        };
        starkway.set_fee_segment(l1_token_address, 1_u8, fee_segment1);
        let fee_segment2 = FeeSegment {
            from_amount: u256 { low: 1000, high: 0 }, fee_rate: u256 { low: 10, high: 0 }
        };
        starkway.set_fee_segment(l1_token_address, 2_u8, fee_segment2);
        // Third tier's amount should be more than second tier
        let fee_segment3 = FeeSegment {
            from_amount: u256 { low: 100, high: 0 }, fee_rate: u256 { low: 5, high: 0 }
        };
        starkway.set_fee_segment(l1_token_address, 3_u8, fee_segment3);
    }

    #[test]
    #[available_gas(20000000)]
    #[should_panic(
        expected: ('Fee invalid wrt upper tier', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED', )
    )]
    fn test_set_fee_segment_with_invalid_lower_fee() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };
        let l1_token_address = EthAddress { address: 100_felt252 };
        let fee_segment1 = FeeSegment {
            from_amount: u256 { low: 0, high: 0 }, fee_rate: u256 { low: 20, high: 0 }
        };
        starkway.set_fee_segment(l1_token_address, 1_u8, fee_segment1);
        let fee_segment2 = FeeSegment {
            from_amount: u256 { low: 1000, high: 0 }, fee_rate: u256 { low: 10, high: 0 }
        };
        starkway.set_fee_segment(l1_token_address, 2_u8, fee_segment2);
        let fee_segment3 = FeeSegment {
            from_amount: u256 { low: 2000, high: 0 }, fee_rate: u256 { low: 5, high: 0 }
        };
        starkway.set_fee_segment(l1_token_address, 3_u8, fee_segment3);
        // Second tier's fee should be more than third tier
        let fee_segment4 = FeeSegment {
            from_amount: u256 { low: 1000, high: 0 }, fee_rate: u256 { low: 2, high: 0 }
        };
        starkway.set_fee_segment(l1_token_address, 2_u8, fee_segment4);
    }

    #[test]
    #[available_gas(20000000)]
    #[should_panic(
        expected: ('Amount invalid wrt upper tier', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED', )
    )]
    fn test_set_fee_segment_with_invalid_lower_amount() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };
        let l1_token_address = EthAddress { address: 100_felt252 };
        let fee_segment1 = FeeSegment {
            from_amount: u256 { low: 0, high: 0 }, fee_rate: u256 { low: 20, high: 0 }
        };
        starkway.set_fee_segment(l1_token_address, 1_u8, fee_segment1);
        let fee_segment2 = FeeSegment {
            from_amount: u256 { low: 1000, high: 0 }, fee_rate: u256 { low: 10, high: 0 }
        };
        starkway.set_fee_segment(l1_token_address, 2_u8, fee_segment2);
        let fee_segment3 = FeeSegment {
            from_amount: u256 { low: 2000, high: 0 }, fee_rate: u256 { low: 5, high: 0 }
        };
        starkway.set_fee_segment(l1_token_address, 3_u8, fee_segment3);
        // Second tier's amount should be less than third tier
        let fee_segment4 = FeeSegment {
            from_amount: u256 { low: 3000, high: 0 }, fee_rate: u256 { low: 10, high: 0 }
        };
        starkway.set_fee_segment(l1_token_address, 2_u8, fee_segment4);
    }

    #[test]
    #[available_gas(20000000)]
    #[should_panic(
        expected: ('Tier > max_fee_segment_tier + 1', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED', )
    )]
    fn test_set_fee_segment_with_invalid_tier_number() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };
        let l1_token_address = EthAddress { address: 100_felt252 };
        let fee_segment = FeeSegment {
            from_amount: u256 { low: 0, high: 0 }, fee_rate: u256 { low: 20, high: 0 }
        };
        starkway.set_fee_segment(l1_token_address, 1_u8, fee_segment);
        let fee_segment = FeeSegment {
            from_amount: u256 { low: 1000, high: 0 }, fee_rate: u256 { low: 10, high: 0 }
        };
        // Setting third tier without setting second tier
        starkway.set_fee_segment(l1_token_address, 3_u8, fee_segment);
    }
}
