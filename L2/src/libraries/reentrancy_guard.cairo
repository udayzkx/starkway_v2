#[starknet::contract]
mod ReentrancyGuard {
    use starknet::get_caller_address;
    use starkway::interfaces::IReentrancyGuard;

    /////////////
    // Storage //
    /////////////

    #[storage]
    struct Storage {
        entered: bool
    }

    #[external(v0)]
    impl ReentrancyGuardImpl of IReentrancyGuard<ContractState> {
        //////////////
        // External //
        //////////////
        fn start(ref self: ContractState) {
            assert(!self.entered.read(), 'ReentrancyGuard: reentrant call');
            self.entered.write(true);
        }

        fn end(ref self: ContractState) {
            self.entered.write(false);
        }
    }
}
