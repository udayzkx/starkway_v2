use core::hash::LegacyHash;

#[derive(Copy, Drop)]
enum Action {
    Add: (),
    Remove: (),
}

impl LegacyHashAction of LegacyHash<Action> {
    fn hash(state: felt252, value: Action) -> felt252 {
        let val: felt252 = match value {
            Action::Add(()) => 1,
            Action::Remove(()) => 2,
        };
        LegacyHash::hash(state, val)
    }
}

#[contract]
mod AdminAuth {
    use starknet::ContractAddress;
    use starknet::contract_address::ContractAddressZeroable;
    use starknet::get_caller_address;
    use zeroable::Zeroable;

    use super::Action;

    struct Storage {
        s_admin_lookup: LegacyMap::<ContractAddress, bool>,
        s_min_num_admins: u8,
        s_initiator_lookup: LegacyMap::<(ContractAddress, Action), ContractAddress>,
        s_current_total_admins: u8,
    }

    ////////////
    // Events //
    ////////////

    #[event]
    fn AdminAdded(address: ContractAddress) {}
    fn AdminRemoved(address: ContractAddress) {}
    fn MinNumberAdminsUpdate(new_number: u8) {}

    /////////////////
    // Constructor //
    /////////////////

    #[constructor]
    fn constructor(admin_1: ContractAddress, admin_2: ContractAddress) {
        s_admin_lookup::write(admin_1, true);
        s_admin_lookup::write(admin_2, true);
        s_min_num_admins::write(2_u8);
        s_current_total_admins::write(2_u8);

        AdminAdded(admin_1);
        AdminAdded(admin_2);
    }

    //////////
    // View //
    //////////

    #[view]
    fn get_is_allowed(address: ContractAddress) -> bool {
        s_admin_lookup::read(address)
    }

    #[view]
    fn get_min_number_admins() -> u8 {
        s_min_num_admins::read()
    }

    #[view]
    fn get_current_total_admins() -> u8 {
        s_current_total_admins::read()
    }

    //////////////
    // External //
    //////////////

    #[external]
    fn set_min_number_admins(num: u8) {
        assert_is_admin();
        s_min_num_admins::write(num);
        MinNumberAdminsUpdate(num);
    }

    #[external]
    fn add_admin(address: ContractAddress) {
        update_admin_mapping(address, Action::Add(()));
    }

    #[external]
    fn remove_admin(address: ContractAddress) {
        update_admin_mapping(address, Action::Remove(()));
    }

    /////////////
    // Private //
    /////////////

    #[internal]
    fn update_admin_mapping(address: ContractAddress, action: Action) {
        assert_is_admin();
        assert(address.is_non_zero(), 'Address must be non zero');

        let caller = get_caller_address();
        let is_admin = s_admin_lookup::read(address);
        let desired_admin_state: bool = match action {
            Action::Add(()) => true,
            Action::Remove(()) => false,
        };

        if is_admin == desired_admin_state {
            return ();
        }

        let initiator = s_initiator_lookup::read((address, action));
        assert(caller != initiator, 'Both approvers can not be same');

        if initiator.is_zero() {
            s_initiator_lookup::write((address, action), caller);
        } else {
            s_initiator_lookup::write((address, action), Zeroable::zero());
            s_admin_lookup::write(address, desired_admin_state);

            let current_total_admins = s_current_total_admins::read();
            match action {
                Action::Add(()) => {
                    s_current_total_admins::write(current_total_admins + 1_u8);
                    AdminAdded(address);
                },
                Action::Remove(()) => {
                    let new_total_admins = current_total_admins - 1_u8;
                    assert(new_total_admins >= s_min_num_admins::read(), 'Too few admins');
                    s_current_total_admins::write(new_total_admins);
                    AdminRemoved(address);
                },
            };
        }
    }

    #[internal]
    fn assert_is_admin() {
        let caller = get_caller_address();
        let is_admin = s_admin_lookup::read(caller);
        assert(is_admin, 'Must be admin');
    }
}
