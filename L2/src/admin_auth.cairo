use core::hash::{Hash,HashStateTrait};

#[derive(Copy, Drop, Serde)]
enum Action {
    Add,
    Remove,
}

impl HashAction<S, impl SHashState: HashStateTrait<S>> of Hash<Action, S, SHashState> {
    #[inline(always)]
    fn update_state(state: S, value: Action) -> S {

        let val: felt252 = match value {
            Action::Add => 1,
            Action::Remove => 2,
        };
        state.update(val)
    }
}

#[starknet::contract]
mod AdminAuth {
    use starknet::contract_address::ContractAddressZeroable;
    use starknet::{ContractAddress, get_caller_address, get_contract_address};
    use zeroable::Zeroable;

    use starkway::interfaces::{ IAdminAuth, IStarkwayDispatcher, IStarkwayDispatcherTrait};
    use super::Action;


    /////////////
    // Storage //
    /////////////

    #[storage]
    struct Storage {
        // stores whether an address is admin or not
        admin_lookup: LegacyMap::<ContractAddress, bool>,
        // stores the minimum number of admins required to be in the system
        // this number can be > current total admins in the system since this number is only used to check whether
        // admin removal is possible
        min_num_admins: u8,
        // stores address of the admin who initiated the approval/removal action
        initiator_lookup: LegacyMap::<(ContractAddress, Action), ContractAddress>,
        // stores the number of admins currently in the system
        current_total_admins: u8,
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

    // @notice Constructor for the contract
    // @param address1 - Address for first initial admin
    // @param address2 - Address for second initial admin
    #[constructor]
    fn constructor(ref self: ContractState, admin_1: ContractAddress, admin_2: ContractAddress) {

        assert(admin_1.is_non_zero(), 'AA: Admin cannot be 0');
        assert(admin_2.is_non_zero(), 'AA: Admin cannot be 0');
        assert(admin_1 != admin_2, 'AA: Admins cannot be same');

        self.admin_lookup.write(admin_1, true);
        self.admin_lookup.write(admin_2, true);
        self.min_num_admins.write(2_u8);
        self.current_total_admins.write(2_u8);

        self.emit(Event::AdminAdded(AdminAdded { address: admin_1 }));
        self.emit(Event::AdminAdded(AdminAdded { address: admin_2 }));
    }

    #[external(v0)]
    impl AdminAuth of IAdminAuth<ContractState> {
        //////////
        // View //
        //////////

        // @notice Function to find whether an address has permission to perform a specific role
        // @param address - Address for which permission has to be determined
        // @return allowed - false if no access, true if access allowed
        fn get_is_allowed(self: @ContractState, address: ContractAddress) -> bool {
            self.admin_lookup.read(address)
        }

        // @notice Function to return minimum number of admins required in the system
        // @return min_num - minimum number of admins required in the system
        fn get_min_number_admins(self: @ContractState) -> u8 {
            self.min_num_admins.read()
        }

        // @notice Function to return the total number of admins currently in the system
        // @return total_admins - total number of admins currently in the system
        fn get_current_total_admins(self: @ContractState) -> u8 {
            self.current_total_admins.read()
        }

        //////////////
        // External //
        //////////////

        // @notice - Callable only by admin, this function sets the minimum number of admins that should be present in the system
        // @param num - number of min admins to set (must be >= 2)
        fn set_min_number_admins(ref self: ContractState, num: u8) {
            self._assert_is_admin();
            assert(num >= 2, 'AA: Min no.of admins >= 2');
            self.min_num_admins.write(num);
            self.emit(Event::MinNumberAdminsUpdate(MinNumberAdminsUpdate { new_number: num }));
        }

        fn add_admin(ref self: ContractState, address: ContractAddress) {
            self._update_admin_mapping(address, Action::Add(()));
        }

        fn remove_admin(ref self: ContractState, address: ContractAddress) {
            self._update_admin_mapping(address, Action::Remove(()));
        }

        // @notice - Callable only by admin
        // This function claims ownership of starkway provided address was previously proposed by an admin
        fn claim_starkway_ownership(ref self: ContractState, starkway_address: ContractAddress) {
            self._assert_is_admin();
            let starkway = IStarkwayDispatcher {contract_address:starkway_address};
            starkway.claim_admin_auth_address();
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
            // Verify that caller has admin role
            self._assert_is_admin();
            assert(address.is_non_zero(), 'AA: Address must be non zero');

            let caller = get_caller_address();
            assert(caller!=address, 'AA: Cannot add/remove self');
            
            let is_admin = self.admin_lookup.read(address);
            let desired_admin_state: bool = match action {
                Action::Add(()) => true,
                Action::Remove(()) => false,
            };

            // if desired admin state is same as current admin state then return without any processing
            if is_admin == desired_admin_state {
                return ();
            }

            // check that approver is not same as caller

            let initiator = self.initiator_lookup.read((address, action));
            assert(caller != initiator, 'AA: Both approvers cant be same');

            // if initial proposer is 0 then caller is initial proposer
            // save caller address as initial proposer & return
            if initiator.is_zero() {
                self.initiator_lookup.write((address, action), caller);
            } else {
                // if initial proposer != 0, then this is 2nd approval
                // give admin permission to address and mark initiator address as 0 for future approvals
                self.initiator_lookup.write((address, action), Zeroable::zero());
                self.admin_lookup.write(address, desired_admin_state);

                let current_total_admins = self.current_total_admins.read();
                match action {
                    Action::Add(()) => {
                        self.current_total_admins.write(current_total_admins + 1_u8);
                        self.emit(Event::AdminAdded(AdminAdded { address: address }));
                    },
                    Action::Remove(()) => {
                        let new_total_admins = current_total_admins - 1_u8;
                        assert(
                            new_total_admins >= self.min_num_admins.read(), 'AA: Too few admins'
                        );
                        self.current_total_admins.write(new_total_admins);
                        self.emit(Event::AdminRemoved(AdminRemoved { address: address }));
                    },
                };
            }
        }

        fn _assert_is_admin(self: @ContractState) {
            let caller = get_caller_address();
            let is_admin = self.admin_lookup.read(caller);
            assert(is_admin, 'AA: Must be admin');
        }
    }
}
