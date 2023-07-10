#[cfg(test)]
mod test_starkway_withdraw {
    use array::{Array, ArrayTrait, Span};
    use core::integer::u256;
    use core::result::ResultTrait;
    use debug::PrintTrait;
    use option::OptionTrait;
    use serde::Serde;
    use starknet::class_hash::ClassHash;
    use starknet::{ContractAddress, contract_address_const, EthAddress};
    use starknet::testing::{set_caller_address, set_contract_address};
    use traits::{TryInto};
    use starkway::admin_auth::AdminAuth;
    use starkway::datatypes::{
        L1TokenDetails,
        WithdrawalRange
    };
    use starkway::erc20::erc20::StarkwayERC20;
    use starkway::interfaces::{
        IAdminAuthDispatcher, 
        IAdminAuthDispatcherTrait,
        IStarkwayDispatcher,
        IStarkwayDispatcherTrait,
        IERC20Dispatcher, 
        IERC20DispatcherTrait
    };
    use starkway::libraries::reentrancy_guard::ReentrancyGuard;
    use starkway::libraries::fee_library::fee_library;
    use starkway::starkway::Starkway;
    use zeroable::Zeroable;


    fn deploy(
        contract_class_hash: felt252, salt: felt252, calldata: Array<felt252>
    ) -> ContractAddress {

        set_contract_address(contract_address_const::<100>());
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
        let fee_rate = u256{low:200, high:0};
        let fee_lib_class_hash = fee_library::TEST_CLASS_HASH;
        let erc20_class_hash = StarkwayERC20::TEST_CLASS_HASH;
        admin_auth_address.serialize(ref starkway_calldata);
        fee_rate.serialize(ref starkway_calldata);
        fee_lib_class_hash.serialize(ref starkway_calldata);
        erc20_class_hash.serialize(ref starkway_calldata);
        let starkway_address = deploy(Starkway::TEST_CLASS_HASH, 100, starkway_calldata);
        
        // Set class hash for re-entrancy guard library
        let starkway = IStarkwayDispatcher{contract_address: starkway_address};
        
        // Set admin_1 as default caller
        set_contract_address(admin_1);

        starkway.set_reentrancy_guard_class_hash(ReentrancyGuard::TEST_CLASS_HASH.try_into().unwrap());

        return (starkway_address, admin_auth_address, admin_1, admin_2);
    }

    fn mint(starkway_address: ContractAddress, erc20_address: ContractAddress, to: ContractAddress, amount: u256) {

        set_contract_address(starkway_address);
        let erc20 = IERC20Dispatcher{contract_address: erc20_address};
        erc20.mint(to, amount);
    }

    #[test]
    #[available_gas(20000000)]
    fn test_mint_and_withdraw() {

        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();

        let l1_token_address = EthAddress { address: 100_felt252};
        let l1_recipient = EthAddress {address: 200_felt252};
        let starkway = IStarkwayDispatcher {contract_address: starkway_address};
        let l1_token_details = L1TokenDetails {name: 'TEST_TOKEN', symbol:'TEST', decimals: 18_u8};
        set_contract_address(admin_1);

        starkway.authorised_init_token(l1_token_address, l1_token_details);
        let native_erc20_address = starkway.get_native_token_address(l1_token_address);
        let acc1 = contract_address_const::<30>();
        let amount1 = u256{low: 1000, high: 0};
        let amount2 = u256{low: 100, high: 0};
        let fee = u256{low:2, high:0};
        mint(starkway_address, native_erc20_address, acc1, amount1);
        
        set_contract_address(admin_1);
        let withdrawal_range = WithdrawalRange {
            min: u256 {low:2, high:0},
            max: u256 {low:0, high:1000}
        };
        starkway.set_withdrawal_range(l1_token_address, withdrawal_range);
        set_contract_address(acc1);
        let calculated_fee = starkway.calculate_fee(l1_token_address, amount2);
        calculated_fee.print();
        let erc20 = IERC20Dispatcher{contract_address: native_erc20_address};
        erc20.approve(starkway_address, amount2+fee);
        starkway.withdraw(native_erc20_address, l1_token_address, l1_recipient, amount2, fee);

    }
}