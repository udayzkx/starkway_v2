#[cfg(test)]
mod test_admin_auth {
    use starknet::ContractAddress;
    use starknet::contract_address_const;
    use starknet::testing::set_caller_address;
    use starkway::admin_auth::AdminAuth;
    use zeroable::Zeroable;

    fn setup() -> (ContractAddress, ContractAddress) {
        let admin_1: ContractAddress = contract_address_const::<1>();
        let admin_2: ContractAddress = contract_address_const::<2>();

        AdminAuth::constructor(admin_1, admin_2);

        // Set admin_1 as default caller
        set_caller_address(admin_1);

        (admin_1, admin_2)
    }

    #[test]
    #[available_gas(2000000)]
    fn test_constructor() {
        let (admin_1, admin_2) = setup();
        assert(AdminAuth::get_min_number_admins() == 2_u8, 'Min no.of admins should be 2');
        assert(AdminAuth::get_current_total_admins() == 2_u8, 'Total admins should be 2');
        assert(AdminAuth::get_is_allowed(admin_1) == true, 'Admin1 should have access');
        assert(AdminAuth::get_is_allowed(admin_2) == true, 'Admin2 should have access');
    }

    #[test]
    #[available_gas(2000000)]
    fn test_set_min_number_admins() {
        let (admin_1, admin_2) = setup();

        AdminAuth::set_min_number_admins(4_u8);
        assert(AdminAuth::get_min_number_admins() == 4_u8, 'Min no.of admins should be 4');
    }

    #[test]
    #[available_gas(2000000)]
    #[should_panic(expected: ('Address must be non zero', ))]
    fn test_adds_zero_address_as_admin() {
        let (admin_1, admin_2) = setup();

        AdminAuth::add_admin(Zeroable::zero());
    }

    #[test]
    #[available_gas(2000000)]
    fn test_add_admin() {
        let (admin_1, admin_2) = setup();

        let address: ContractAddress = contract_address_const::<3>();

        AdminAuth::add_admin(address);
        assert(AdminAuth::get_is_allowed(address) == false, 'Admin added with one approval');

        set_caller_address(admin_2);
        AdminAuth::add_admin(address);
        assert(AdminAuth::get_is_allowed(address) == true, 'Admin should have access');
    }

    #[test]
    #[available_gas(2000000)]
    #[should_panic(expected: ('Both approvers can not be same', ))]
    fn test_add_admin_with_same_approvers() {
        let (admin_1, admin_2) = setup();

        let address: ContractAddress = contract_address_const::<3>();

        AdminAuth::add_admin(address);
        assert(AdminAuth::get_is_allowed(address) == false, 'Admin added with one approval');

        AdminAuth::add_admin(address);
        assert(AdminAuth::get_is_allowed(address) == false, 'Both approvers can not be same');
    }

    #[test]
    #[available_gas(2000000)]
    fn test_remove_admin() {
        let (admin_1, admin_2) = setup();
        assert(AdminAuth::get_min_number_admins() == 2_u8, 'abc');

        let address: ContractAddress = contract_address_const::<3>();

        // Add Admin
        AdminAuth::add_admin(address);
        assert(AdminAuth::get_is_allowed(address) == false, 'Admin added with one approval');

        set_caller_address(admin_2);
        AdminAuth::add_admin(address);
        assert(AdminAuth::get_is_allowed(address) == true, 'Admin should have access');

        // Remove Admin
        set_caller_address(admin_1);
        AdminAuth::remove_admin(address);
        assert(AdminAuth::get_is_allowed(address) == true, 'Admin removed with one approval');

        set_caller_address(admin_2);
        AdminAuth::remove_admin(address);
        assert(AdminAuth::get_is_allowed(address) == false, 'Admin should not have access');
    }

    #[test]
    #[available_gas(2000000)]
    fn test_remove_admin_who_is_not_admin() {
        let (admin_1, admin_2) = setup();

        let address: ContractAddress = contract_address_const::<3>();

        AdminAuth::remove_admin(address);
        assert(AdminAuth::get_is_allowed(address) == false, 'Address should not be Admin');
    }

    #[test]
    #[available_gas(2000000)]
    #[should_panic(expected: ('Must be admin', ))]
    fn test_non_admin_removes_or_adds_admin() {
        let (admin_1, admin_2) = setup();

        let address: ContractAddress = contract_address_const::<3>();
        set_caller_address(address);

        AdminAuth::remove_admin(admin_1);
        AdminAuth::add_admin(admin_1);
        assert(AdminAuth::get_is_allowed(address) == false, 'Caller should not be Admin');
    }
}
