// Following contract is mostly based on open-zeppelin cairo-contracts for erc20 tokens
// https://github.com/OpenZeppelin/cairo-contracts/blob/cairo-2/src/token/erc20/erc20.cairo
#[starknet::contract]
mod StarkwayERC20 {
    use starknet::ContractAddress;
    use starkway::interfaces::IERC20;
    use starknet::get_caller_address;
    use zeroable::Zeroable;
    use starknet::contract_address::ContractAddressZeroable;


    /////////////
    // Storage //
    /////////////

    #[storage]
    struct Storage {
        s_name: felt252,
        s_symbol: felt252,
        s_total_supply: u256,
        s_balances: LegacyMap<ContractAddress, u256>,
        s_allowances: LegacyMap<(ContractAddress, ContractAddress), u256>,
        s_decimals: u8,
        s_owner: ContractAddress
    }

    ////////////
    // Events //
    ////////////

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Transfer: Transfer,
        Approval: Approval,
        OwnershipTransferred: OwnershipTransferred,
    }


    #[derive(Drop, starknet::Event)]
    struct Transfer {
        from: ContractAddress,
        to: ContractAddress,
        value: u256
    }


    #[derive(Drop, starknet::Event)]
    struct Approval {
        owner: ContractAddress,
        spender: ContractAddress,
        value: u256
    }

    #[derive(Drop, starknet::Event)]
    struct OwnershipTransferred {
        previous_owner: ContractAddress,
        new_owner: ContractAddress
    }

    /////////////////
    // Constructor //
    /////////////////

    #[constructor]
    fn constructor(
        ref self: ContractState,
        name: felt252,
        symbol: felt252,
        decimals: u8,
        owner: ContractAddress
    ) {
        self._initializer(name, symbol, decimals, owner);
    }

    #[external(v0)]
    impl StarkwayERC20Impl of IERC20<ContractState> {
        //////////
        // View //
        //////////
        fn name(self: @ContractState) -> felt252 {
            self.s_name.read()
        }

        fn symbol(self: @ContractState) -> felt252 {
            self.s_symbol.read()
        }

        fn decimals(self: @ContractState) -> u8 {
            self.s_decimals.read()
        }

        fn total_supply(self: @ContractState) -> u256 {
            self.s_total_supply.read()
        }

        fn balance_of(self: @ContractState, account: ContractAddress) -> u256 {
            self.s_balances.read(account)
        }

        fn allowance(
            self: @ContractState, owner: ContractAddress, spender: ContractAddress
        ) -> u256 {
            self.s_allowances.read((owner, spender))
        }

        fn get_owner(self: @ContractState) -> ContractAddress {
            self.s_owner.read()
        }

        //////////////
        // External //
        //////////////

        fn transfer(ref self: ContractState, recipient: ContractAddress, amount: u256) -> bool {
            let sender = get_caller_address();
            self._transfer(sender, recipient, amount);
            true
        }

        fn transfer_from(
            ref self: ContractState,
            sender: ContractAddress,
            recipient: ContractAddress,
            amount: u256
        ) -> bool {
            let caller = get_caller_address();
            self._spend_allowance(sender, caller, amount);
            self._transfer(sender, recipient, amount);
            true
        }

        fn approve(ref self: ContractState, spender: ContractAddress, amount: u256) -> bool {
            let caller = get_caller_address();
            self._approve(caller, spender, amount);
            true
        }

        fn increase_allowance(
            ref self: ContractState, spender: ContractAddress, added_value: u256
        ) -> bool {
            self._increase_allowance(spender, added_value)
        }

        fn decrease_allowance(
            ref self: ContractState, spender: ContractAddress, subtracted_value: u256
        ) -> bool {
            self._decrease_allowance(spender, subtracted_value)
        }

        fn burn(ref self: ContractState, amount: u256) {
            self._burn(get_caller_address(), amount);
        }

        fn mint(ref self: ContractState, to: ContractAddress, amount: u256) {
            self._assert_only_owner();
            self._mint(to, amount);
        }

        fn transfer_ownership(ref self: ContractState, new_owner: ContractAddress) {
            assert(!new_owner.is_zero(), 'New owner is the zero address');
            self._assert_only_owner();
            self._transfer_ownership(new_owner);
        }

        // Camel Case function implementations
        // These just forward the calls to the snake_case implementation

        fn totalSupply(self: @ContractState) -> u256 {
            self.total_supply()
        }

        fn balanceOf(self: @ContractState, account: ContractAddress) -> u256 {
            self.balance_of(account)
        }

        fn transferFrom(
            ref self: ContractState,
            sender: ContractAddress,
            recipient: ContractAddress,
            amount: u256
        ) -> bool {
            
            self.transfer_from(sender, recipient, amount)
        }

        fn increaseAllowance(
            ref self: ContractState, spender: ContractAddress, added_value: u256
        ) -> bool {
            self.increase_allowance(spender, added_value)
        }

        fn decreaseAllowance(
            ref self: ContractState, spender: ContractAddress, subtracted_value: u256
        ) -> bool {
            self.decrease_allowance(spender, subtracted_value)
        }

    }

    #[generate_trait]
    impl ERC20PrivateFunctions of IERC20PrivateFunctions {
        /////////////
        // Private //
        /////////////

        fn _initializer(
            ref self: ContractState,
            name: felt252,
            symbol: felt252,
            decimals: u8,
            owner: ContractAddress
        ) {
            self.s_name.write(name);
            self.s_symbol.write(symbol);
            self.s_decimals.write(decimals);
            self.s_owner.write(owner);
        }

        fn _increase_allowance(
            ref self: ContractState, spender: ContractAddress, added_value: u256
        ) -> bool {
            let caller = get_caller_address();
            self._approve(caller, spender, self.s_allowances.read((caller, spender)) + added_value);
            true
        }

        fn _decrease_allowance(
            ref self: ContractState, spender: ContractAddress, subtracted_value: u256
        ) -> bool {
            let caller = get_caller_address();
            self
                ._approve(
                    caller, spender, self.s_allowances.read((caller, spender)) - subtracted_value
                );
            true
        }

        fn _mint(ref self: ContractState, recipient: ContractAddress, amount: u256) {
            assert(!recipient.is_zero(), 'ERC20: mint to 0');
            self.s_total_supply.write(self.s_total_supply.read() + amount);
            self.s_balances.write(recipient, self.s_balances.read(recipient) + amount);
            self
                .emit(
                    Event::Transfer(
                        Transfer { from: Zeroable::zero(), to: recipient, value: amount }
                    )
                );
        }

        fn _burn(ref self: ContractState, account: ContractAddress, amount: u256) {
            assert(!account.is_zero(), 'ERC20: burn from 0');
            self.s_total_supply.write(self.s_total_supply.read() - amount);
            self.s_balances.write(account, self.s_balances.read(account) - amount);
            self
                .emit(
                    Event::Transfer(Transfer { from: account, to: Zeroable::zero(), value: amount })
                );
        }

        fn _approve(
            ref self: ContractState, owner: ContractAddress, spender: ContractAddress, amount: u256
        ) {
            assert(!owner.is_zero(), 'ERC20: approve from 0');
            assert(!spender.is_zero(), 'ERC20: approve to 0');
            self.s_allowances.write((owner, spender), amount);
            self.emit(Event::Approval(Approval { owner: owner, spender: spender, value: amount }));
        }

        fn _transfer(
            ref self: ContractState,
            sender: ContractAddress,
            recipient: ContractAddress,
            amount: u256
        ) {
            assert(!sender.is_zero(), 'ERC20: transfer from 0');
            assert(!recipient.is_zero(), 'ERC20: transfer to 0');
            self.s_balances.write(sender, self.s_balances.read(sender) - amount);
            self.s_balances.write(recipient, self.s_balances.read(recipient) + amount);
            self.emit(Event::Transfer(Transfer { from: sender, to: recipient, value: amount }));
        }

        fn _spend_allowance(
            ref self: ContractState, owner: ContractAddress, spender: ContractAddress, amount: u256
        ) {
            let current_allowance = self.s_allowances.read((owner, spender));
            let is_unlimited_allowance = (current_allowance == integer::BoundedInt::max());
               
            if !is_unlimited_allowance {
                self._approve(owner, spender, current_allowance - amount);
            }
        }

        fn _assert_only_owner(self: @ContractState) {
            let owner: ContractAddress = self.s_owner.read();
            let caller: ContractAddress = get_caller_address();
            assert(!caller.is_zero(), 'Caller is the zero address');
            assert(caller == owner, 'Caller is not the owner');
        }

        fn _transfer_ownership(ref self: ContractState, new_owner: ContractAddress) {
            let previous_owner: ContractAddress = self.s_owner.read();
            self.s_owner.write(new_owner);
            self
                .emit(
                    Event::OwnershipTransferred(
                        OwnershipTransferred {
                            previous_owner: previous_owner, new_owner: new_owner
                        }
                    )
                );
        }
    }
}
