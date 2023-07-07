use core::debug::PrintTrait;
#[cfg(test)]
mod test_admin_auth {
    use array::{ArrayTrait};
    use core::result::ResultTrait;
    use debug::PrintTrait;
    use option::OptionTrait;
    use starknet::{
        ContractAddress, contract_address_const, contract_address::contract_address_to_felt252,
        testing::set_caller_address, get_caller_address
    };
    use starkway::admin_auth::AdminAuth;
    use starkway::interfaces::{IAdminAuthDispatcher, IAdminAuthDispatcherTrait};
    use traits::{TryInto};
    use zeroable::Zeroable;

    // Function to deploy contracts
    fn deploy(
        contract_class_hash: felt252, salt: felt252, calldata: Array<felt252>
    ) -> ContractAddress {
        let (address, _) = starknet::deploy_syscall(
            contract_class_hash.try_into().unwrap(), salt, calldata.span(), false
        )
            .unwrap();
        address
    }

    fn setup() -> (ContractAddress, ContractAddress, ContractAddress) {
        let admin_1: ContractAddress = contract_address_const::<1>();
        let admin_2: ContractAddress = contract_address_const::<2>();

        // Deploy Admin auth contract
        let mut admin_auth_calldata = ArrayTrait::<felt252>::new();

        admin_auth_calldata.append(contract_address_to_felt252(admin_1));
        admin_auth_calldata.append(contract_address_to_felt252(admin_2));

        let admin_auth_instance = deploy(AdminAuth::TEST_CLASS_HASH, 100, admin_auth_calldata);

        // Set admin_1 as default caller
        set_caller_address(admin_1);

        return (admin_auth_instance, admin_1, admin_2);
    }

    #[test]
    #[available_gas(2000000)]
    fn test_constructor() {
        let (admin_auth_instance, admin_1, admin_2) = setup();
        let min_number_admins = IAdminAuthDispatcher {
            contract_address: admin_auth_instance
        }.get_min_number_admins();
        let current_total_admins = IAdminAuthDispatcher {
            contract_address: admin_auth_instance
        }.get_current_total_admins();
        let is_admin_1_allowed = IAdminAuthDispatcher {
            contract_address: admin_auth_instance
        }.get_is_allowed(admin_1);
        let is_admin_2_allowed = IAdminAuthDispatcher {
            contract_address: admin_auth_instance
        }.get_is_allowed(admin_2);
        assert(min_number_admins == 2_u8, 'Min no.of admins should be 2');
        assert(current_total_admins == 2_u8, 'Total admins should be 2');
        assert(is_admin_1_allowed == true, 'Admin1 should have access');
        assert(is_admin_2_allowed == true, 'Admin2 should have access');
    }

    #[test]
    #[available_gas(2000000)]
    fn test_set_min_number_admins() {
        let (admin_auth_instance, admin_1, admin_2) = setup();
        get_caller_address().print();
        IAdminAuthDispatcher { contract_address: admin_auth_instance }.set_min_number_admins(4_u8);
        let min_number_admins = IAdminAuthDispatcher {
            contract_address: admin_auth_instance
        }.get_min_number_admins();
        assert(min_number_admins == 4_u8, 'Min no.of admins should be 4');
    }

    #[test]
    #[available_gas(2000000)]
    #[should_panic(expected: ('AA: Address must be non zero', ))]
    fn test_adds_zero_address_as_admin() {
        let (admin_auth_instance, admin_1, admin_2) = setup();
        IAdminAuthDispatcher { contract_address: admin_auth_instance }.add_admin(Zeroable::zero());
    }

    #[test]
    #[available_gas(2000000)]
    fn test_add_admin() {
        let (admin_auth_instance, admin_1, admin_2) = setup();
        let address: ContractAddress = contract_address_const::<3>();

        IAdminAuthDispatcher { contract_address: admin_auth_instance }.add_admin(address);

        let is_address_allowed = IAdminAuthDispatcher {
            contract_address: admin_auth_instance
        }.get_is_allowed(address);
        assert(is_address_allowed == false, 'Admin added with one approval');

        set_caller_address(admin_2);
        IAdminAuthDispatcher { contract_address: admin_auth_instance }.add_admin(address);

        let is_address_allowed = IAdminAuthDispatcher {
            contract_address: admin_auth_instance
        }.get_is_allowed(address);
        assert(is_address_allowed == true, 'Admin should have access');
    }

    #[test]
    #[available_gas(2000000)]
    #[should_panic(expected: ('AA: Both approvers cant be same', ))]
    fn test_add_admin_with_same_approvers() {
        let (admin_auth_instance, admin_1, admin_2) = setup();

        let address: ContractAddress = contract_address_const::<3>();

        IAdminAuthDispatcher { contract_address: admin_auth_instance }.add_admin(address);

        let is_address_allowed = IAdminAuthDispatcher {
            contract_address: admin_auth_instance
        }.get_is_allowed(address);
        assert(is_address_allowed == false, 'Admin added with one approval');

        IAdminAuthDispatcher { contract_address: admin_auth_instance }.add_admin(address);

        let is_address_allowed = IAdminAuthDispatcher {
            contract_address: admin_auth_instance
        }.get_is_allowed(address);
        assert(is_address_allowed == false, 'AA: Both approvers cant be same');
    }
    #[test]
    #[available_gas(2000000)]
    fn test_remove_admin() {
        let (admin_auth_instance, admin_1, admin_2) = setup();
        let min_number_admins = IAdminAuthDispatcher {
            contract_address: admin_auth_instance
        }.get_min_number_admins();
        assert(min_number_admins == 2_u8, 'Min no.of admins should be 2');

        let address: ContractAddress = contract_address_const::<3>();

        // Add Admin
        IAdminAuthDispatcher { contract_address: admin_auth_instance }.add_admin(address);
        let is_address_allowed = IAdminAuthDispatcher {
            contract_address: admin_auth_instance
        }.get_is_allowed(address);
        assert(is_address_allowed == false, 'Admin added with one approval');

        set_caller_address(admin_2);
        IAdminAuthDispatcher { contract_address: admin_auth_instance }.add_admin(address);
        let is_address_allowed = IAdminAuthDispatcher {
            contract_address: admin_auth_instance
        }.get_is_allowed(address);
        assert(is_address_allowed == true, 'Admin should have access');

        // Remove Admin
        set_caller_address(admin_1);
        IAdminAuthDispatcher { contract_address: admin_auth_instance }.remove_admin(address);
        let is_address_allowed = IAdminAuthDispatcher {
            contract_address: admin_auth_instance
        }.get_is_allowed(address);
        assert(is_address_allowed == true, 'Admin removed with one approval');

        set_caller_address(admin_2);
        IAdminAuthDispatcher { contract_address: admin_auth_instance }.remove_admin(address);
        let is_address_allowed = IAdminAuthDispatcher {
            contract_address: admin_auth_instance
        }.get_is_allowed(address);
        assert(is_address_allowed == false, 'Admin should not have access');
    }

    #[test]
    #[available_gas(2000000)]
    fn test_remove_admin_who_is_not_admin() {
        let (admin_auth_instance, admin_1, admin_2) = setup();
        let address: ContractAddress = contract_address_const::<3>();

        IAdminAuthDispatcher { contract_address: admin_auth_instance }.remove_admin(address);
        let is_address_allowed = IAdminAuthDispatcher {
            contract_address: admin_auth_instance
        }.get_is_allowed(address);
        assert(is_address_allowed == false, 'Address should not be Admin');
    }

    #[test]
    #[available_gas(2000000)]
    #[should_panic(expected: ('AA: Must be admin', ))]
    fn test_non_admin_removes_or_adds_admin() {
        let (admin_auth_instance, admin_1, admin_2) = setup();

        let address: ContractAddress = contract_address_const::<3>();
        set_caller_address(address);

        IAdminAuthDispatcher { contract_address: admin_auth_instance }.remove_admin(admin_1);
        IAdminAuthDispatcher { contract_address: admin_auth_instance }.add_admin(admin_1);
        let is_address_allowed = IAdminAuthDispatcher {
            contract_address: admin_auth_instance
        }.get_is_allowed(address);
        assert(is_address_allowed == false, 'Caller should not be Admin');
    }
}
