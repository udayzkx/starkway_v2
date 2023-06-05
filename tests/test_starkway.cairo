#[cfg(test)]
mod test_starkway {
    use array::{Array, ArrayTrait, Span};
    use core::result::ResultTrait;
    use option::OptionTrait;
    use starknet::{
        ContractAddress, contract_address_const, ClassHash, class_hash_const,
        testing::set_caller_address, class_hash::{
        Felt252TryIntoClassHash, ClassHashIntoFelt252
        }
    };
    use starkway::{
        starkway::Starkway, admin_auth::AdminAuth, datatypes::l1_address::L1Address,
        datatypes::withdrawal_range::WithdrawalRange, erc20::erc20::StarkwayERC20,
        traits::IStarkwayDispatcher, traits::IStarkwayDispatcherTrait, traits::IAdminAuthDispatcher,
        traits::IAdminAuthDispatcherTrait,
    };
    use traits::{Into, TryInto};
    use zeroable::Zeroable;
    use debug::PrintTrait;

    impl U256TryIntoFelt252 of TryInto<u256, felt252> {
        fn try_into(self: u256) -> Option<felt252> {
            let FELT252_PRIME_HIGH = 0x8000000000000110000000000000000_u128;
            if self.high > FELT252_PRIME_HIGH {
                return Option::None(());
            }
            if self.high == FELT252_PRIME_HIGH {
                // since FELT252_PRIME_LOW is 1.
                if self.low != 0 {
                    return Option::None(());
                }
            }
            Option::Some(
                self.high.into() * 0x100000000000000000000000000000000_felt252 + self.low.into()
            )
        }
    }

    // Mock users in our system
    fn ADMIN1() -> ContractAddress { // let mut calldata = ArrayTrait::<felt252>::new();
        // calldata.append(0x111111);
        // let account_address = deploy(Account::TEST_CLASS_HASH, 100, calldata);
        // return account_address;
        contract_address_const::<1>()
    }

    fn ADMIN2() -> ContractAddress { // let mut calldata = ArrayTrait::<felt252>::new();
        // calldata.append(0x222222);
        // let account_address = deploy(Account::TEST_CLASS_HASH, 200, calldata);
        // return account_address;
        contract_address_const::<2>()
    }

    fn USER1() -> ContractAddress { // let mut calldata = ArrayTrait::<felt252>::new();
        // calldata.append(0x333333);
        // let account_address = deploy(Account::TEST_CLASS_HASH, 300, calldata);
        // return account_address;
        contract_address_const::<3>()
    }

    // Function to deploy contracts
    fn deploy(
        contract_class_hash: felt252, salt: felt252, calldata: Array<felt252>
    ) -> ContractAddress {
        let (address, _) = starknet::deploy_syscall(
            contract_class_hash.try_into().unwrap(), salt, calldata.span(), false
        ).unwrap();
        address
    }

    fn setup() -> (ContractAddress, ContractAddress) {
        let fee_rate_default = u256 { low: 10, high: 0 };

        // Deploy admin_auth contract
        let mut admin_auth_deployment_calldata = ArrayTrait::<felt252>::new();
        admin_auth_deployment_calldata.append(ADMIN1().into());
        admin_auth_deployment_calldata.append(ADMIN2().into());

        let admin_auth_address = deploy(
            AdminAuth::TEST_CLASS_HASH, 100, admin_auth_deployment_calldata
        );

        // Deploy starkway contract
        let mut starkway_deployment_calldata = ArrayTrait::<felt252>::new();
        starkway_deployment_calldata.append(admin_auth_address.into());
        starkway_deployment_calldata.append(fee_rate_default.low.into());
        starkway_deployment_calldata.append(fee_rate_default.high.into());
        starkway_deployment_calldata.append(StarkwayERC20::TEST_CLASS_HASH);

        let starkway_address = deploy(Starkway::TEST_CLASS_HASH, 101, starkway_deployment_calldata);

        (admin_auth_address, starkway_address)
    }

    #[test]
    #[available_gas(2000000)]
    #[should_panic(expected: ('Starkway: Caller not admin', ))]
    fn test_setting_withdrawal_range_with_unauthorized_user() {
        let (admin_auth_address, starkway_address) = setup();

        set_caller_address(USER1());
        let l1_token_address: L1Address = L1Address { value: 1234 };
        let l2_token_address: ContractAddress = contract_address_const::<2>();
        Starkway::s_native_token_l2_address::write(l1_token_address, l2_token_address);
        let withdrawal_range: WithdrawalRange = WithdrawalRange {
            min: u256 { low: 100, high: 0 }, max: u256 { low: 1000, high: 0 }
        };

        IStarkwayDispatcher {
            contract_address: starkway_address
        }.set_withdrawal_range(l1_token_address, withdrawal_range);
    }

    #[test]
    #[available_gas(2000000)]
    #[should_panic(expected: ('Token is not registered', ))]
    fn test_setting_withdrawal_range_for_unregistered_token() {
        let (admin_auth_address, starkway_address) = setup();

        set_caller_address(ADMIN1());
        let l1_token_address: L1Address = L1Address { value: 1234 };
        let withdrawal_range: WithdrawalRange = WithdrawalRange {
            min: u256 { low: 100, high: 0 }, max: u256 { low: 1000, high: 0 }
        };
        IStarkwayDispatcher {
            contract_address: starkway_address
        }.set_withdrawal_range(l1_token_address, withdrawal_range);
    }

    #[test]
    #[available_gas(2000000)]
    fn test_setting_withdrawal_range_for_registered_token() {
        let (admin_auth_address, starkway_address) = setup();

        set_caller_address(ADMIN1());
        let l1_token_address: L1Address = L1Address { value: 1234 };
        let l2_token_address: ContractAddress = contract_address_const::<2>();
        Starkway::s_native_token_l2_address::write(l1_token_address, l2_token_address);
        let withdrawal_range: WithdrawalRange = WithdrawalRange {
            min: u256 { low: 100, high: 0 }, max: u256 { low: 1000, high: 0 }
        };
        IStarkwayDispatcher {
            contract_address: starkway_address
        }.set_withdrawal_range(l1_token_address, withdrawal_range);
        let withdrawal_range_res: WithdrawalRange = IStarkwayDispatcher {
            contract_address: starkway_address
        }.get_withdrawal_range(l1_token_address);
    }
}
