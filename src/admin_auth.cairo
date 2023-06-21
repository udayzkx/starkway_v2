use core::hash::LegacyHash;

use starkway::interfaces::IAdminAuth;

#[derive(Copy, Drop, Serde)]
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

#[starknet::contract]
mod AdminAuth {
    use starknet::contract_address::ContractAddressZeroable;
    use starknet::{ContractAddress, get_caller_address};
    use zeroable::Zeroable;

    use super::Action;

    /////////////
    // Storage //
    /////////////

    #[storage]
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
    #[derive(Drop, starknet::Event)]
    enum Event {
        AdminAdded: AdminAdded,
        AdminRemoved: AdminRemoved,
        MinNumberAdminsUpdate: MinNumberAdminsUpdate,
    }

    #[derive(Drop, starknet::Event)]
    struct AdminAdded {
        address: ContractAddress
    }

    #[derive(Drop, starknet::Event)]
    struct AdminRemoved {
        address: ContractAddress
    }

    #[derive(Drop, starknet::Event)]
    struct MinNumberAdminsUpdate {
        new_number: u8
    }

    /////////////////
    // Constructor //
    /////////////////

    #[constructor]
    fn constructor(ref self: ContractState, admin_1: ContractAddress, admin_2: ContractAddress) {
        self.s_admin_lookup.write(admin_1, true);
        self.s_admin_lookup.write(admin_2, true);
        self.s_min_num_admins.write(2_u8);
        self.s_current_total_admins.write(2_u8);

        self.emit(Event::AdminAdded(AdminAdded { address: admin_1 }));
        self.emit(Event::AdminAdded(AdminAdded { address: admin_2 }));
    }

    #[external(v0)]
    impl AdminAuth of super::IAdminAuth<ContractState> {
        //////////
        // View //
        //////////

        fn get_is_allowed(self: @ContractState, address: ContractAddress) -> bool {
            self.s_admin_lookup.read(address)
        }

        fn get_min_number_admins(self: @ContractState) -> u8 {
            self.s_min_num_admins.read()
        }

        fn get_current_total_admins(self: @ContractState) -> u8 {
            self.s_current_total_admins.read()
        }

        //////////////
        // External //
        //////////////

        fn set_min_number_admins(ref self: ContractState, num: u8) {
            self._assert_is_admin();
            self.s_min_num_admins.write(num);
            self.emit(Event::MinNumberAdminsUpdate(MinNumberAdminsUpdate { new_number: num }));
        }

        fn add_admin(ref self: ContractState, address: ContractAddress) {
            self._update_admin_mapping(address, Action::Add(()));
        }

        fn remove_admin(ref self: ContractState, address: ContractAddress) {
            self._update_admin_mapping(address, Action::Remove(()));
        }
    }

    #[generate_trait]
    impl AdminAuthPrivateFunctions of IAdminAuthPrivateFunctions {
        /////////////
        // Private //
        /////////////

        fn _update_admin_mapping(
            ref self: ContractState, address: ContractAddress, action: Action
        ) {
            self._assert_is_admin();
            assert(address.is_non_zero(), 'Address must be non zero');

            let caller = get_caller_address();
            let is_admin = self.s_admin_lookup.read(address);
            let desired_admin_state: bool = match action {
                Action::Add(()) => true,
                Action::Remove(()) => false,
            };

            if is_admin == desired_admin_state {
                return ();
            }

            let initiator = self.s_initiator_lookup.read((address, action));
            assert(caller != initiator, 'Both approvers can not be same');

            if initiator.is_zero() {
                self.s_initiator_lookup.write((address, action), caller);
            } else {
                self.s_initiator_lookup.write((address, action), Zeroable::zero());
                self.s_admin_lookup.write(address, desired_admin_state);

                let current_total_admins = self.s_current_total_admins.read();
                match action {
                    Action::Add(()) => {
                        self.s_current_total_admins.write(current_total_admins + 1_u8);
                        self.emit(Event::AdminAdded(AdminAdded { address: address }));
                    },
                    Action::Remove(()) => {
                        let new_total_admins = current_total_admins - 1_u8;
                        assert(new_total_admins >= self.s_min_num_admins.read(), 'Too few admins');
                        self.s_current_total_admins.write(new_total_admins);
                        self.emit(Event::AdminRemoved(AdminRemoved { address: address }));
                    },
                };
            }
        }

        fn _assert_is_admin(self: @ContractState) {
            let caller = get_caller_address();
            let is_admin = self.s_admin_lookup.read(caller);
            assert(is_admin, 'Must be admin');
        }
    }
}
