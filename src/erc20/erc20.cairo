use starknet::ContractAddress;

trait IERC20 {
    fn name() -> felt252;
    fn symbol() -> felt252;
    fn decimals() -> u8;
    fn total_supply() -> u256;
    fn balance_of(account: ContractAddress) -> u256;
    fn allowance(owner: ContractAddress, spender: ContractAddress) -> u256;
    fn transfer(recipient: ContractAddress, amount: u256) -> bool;
    fn transfer_from(sender: ContractAddress, recipient: ContractAddress, amount: u256) -> bool;
    fn approve(spender: ContractAddress, amount: u256) -> bool;
}

#[contract]
mod StarkwayERC20 {
    use starknet::ContractAddress;
    use super::IERC20;
    use starknet::get_caller_address;
    use zeroable::Zeroable;
    use starknet::contract_address::ContractAddressZeroable;

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
    fn Transfer(from: ContractAddress, to: ContractAddress, value: u256) {}

    #[event]
    fn Approval(owner: ContractAddress, spender: ContractAddress, value: u256) {}

    #[event]
    fn OwnershipTransferred(previous_owner: ContractAddress, new_owner: ContractAddress) {}

    impl ERC20 of IERC20 {
        fn name() -> felt252 {
            s_name::read()
        }

        fn symbol() -> felt252 {
            s_symbol::read()
        }

        fn decimals() -> u8 {
            s_decimals::read()
        }

        fn total_supply() -> u256 {
            s_total_supply::read()
        }

        fn balance_of(account: ContractAddress) -> u256 {
            s_balances::read(account)
        }

        fn allowance(owner: ContractAddress, spender: ContractAddress) -> u256 {
            s_allowances::read((owner, spender))
        }

        fn transfer(recipient: ContractAddress, amount: u256) -> bool {
            let sender = get_caller_address();
            _transfer(sender, recipient, amount);
            true
        }

        fn transfer_from(
            sender: ContractAddress, recipient: ContractAddress, amount: u256
        ) -> bool {
            let caller = get_caller_address();
            _spend_allowance(sender, caller, amount);
            _transfer(sender, recipient, amount);
            true
        }

        fn approve(spender: ContractAddress, amount: u256) -> bool {
            let caller = get_caller_address();
            _approve(caller, spender, amount);
            true
        }
    }


    /////////////////
    // Constructor //
    /////////////////

    #[constructor]
    fn constructor(name: felt252, symbol: felt252, decimals: u8, owner: ContractAddress) {
        _initializer(name, symbol, decimals, owner);
    }

    //////////
    // View //
    //////////

    #[view]
    fn name() -> felt252 {
        ERC20::name()
    }

    #[view]
    fn symbol() -> felt252 {
        ERC20::symbol()
    }

    #[view]
    fn decimals() -> u8 {
        ERC20::decimals()
    }

    #[view]
    fn total_supply() -> u256 {
        ERC20::total_supply()
    }

    #[view]
    fn balance_of(account: ContractAddress) -> u256 {
        ERC20::balance_of(account)
    }

    #[view]
    fn allowance(owner: ContractAddress, spender: ContractAddress) -> u256 {
        ERC20::allowance(owner, spender)
    }

    #[view]
    fn get_owner() -> ContractAddress {
        s_owner::read()
    }

    //////////////
    // External //
    //////////////

    #[external]
    fn transfer(recipient: ContractAddress, amount: u256) -> bool {
        ERC20::transfer(recipient, amount)
    }

    #[external]
    fn transfer_from(sender: ContractAddress, recipient: ContractAddress, amount: u256) -> bool {
        ERC20::transfer_from(sender, recipient, amount)
    }

    #[external]
    fn approve(spender: ContractAddress, amount: u256) -> bool {
        ERC20::approve(spender, amount)
    }

    #[external]
    fn increase_allowance(spender: ContractAddress, added_value: u256) -> bool {
        _increase_allowance(spender, added_value)
    }

    #[external]
    fn decrease_allowance(spender: ContractAddress, subtracted_value: u256) -> bool {
        _decrease_allowance(spender, subtracted_value)
    }

    #[external]
    fn burn(amount: u256) {
        _burn(get_caller_address(), amount);
    }

    #[external]
    fn mint(to: ContractAddress, amount: u256) {
        assert_only_owner();
        _mint(get_caller_address(), amount);
    }

    /////////////
    // Private //
    /////////////

    #[internal]
    fn _initializer(name: felt252, symbol: felt252, decimals: u8, owner: ContractAddress) {
        s_name::write(name);
        s_symbol::write(symbol);
        s_decimals::write(decimals);
        s_owner::write(owner);
    }

    #[internal]
    fn _increase_allowance(spender: ContractAddress, added_value: u256) -> bool {
        let caller = get_caller_address();
        _approve(caller, spender, s_allowances::read((caller, spender)) + added_value);
        true
    }

    #[internal]
    fn _decrease_allowance(spender: ContractAddress, subtracted_value: u256) -> bool {
        let caller = get_caller_address();
        _approve(caller, spender, s_allowances::read((caller, spender)) - subtracted_value);
        true
    }

    #[internal]
    fn _mint(recipient: ContractAddress, amount: u256) {
        assert(!recipient.is_zero(), 'ERC20: mint to 0');
        s_total_supply::write(s_total_supply::read() + amount);
        s_balances::write(recipient, s_balances::read(recipient) + amount);
        Transfer(Zeroable::zero(), recipient, amount);
    }

    #[internal]
    fn _burn(account: ContractAddress, amount: u256) {
        assert(!account.is_zero(), 'ERC20: burn from 0');
        s_total_supply::write(s_total_supply::read() - amount);
        s_balances::write(account, s_balances::read(account) - amount);
        Transfer(account, Zeroable::zero(), amount);
    }

    #[internal]
    fn _approve(owner: ContractAddress, spender: ContractAddress, amount: u256) {
        assert(!owner.is_zero(), 'ERC20: approve from 0');
        assert(!spender.is_zero(), 'ERC20: approve to 0');
        s_allowances::write((owner, spender), amount);
        Approval(owner, spender, amount);
    }

    #[internal]
    fn _transfer(sender: ContractAddress, recipient: ContractAddress, amount: u256) {
        assert(!sender.is_zero(), 'ERC20: transfer from 0');
        assert(!recipient.is_zero(), 'ERC20: transfer to 0');
        s_balances::write(sender, s_balances::read(sender) - amount);
        s_balances::write(recipient, s_balances::read(recipient) + amount);
        Transfer(sender, recipient, amount);
    }

    #[internal]
    fn _spend_allowance(owner: ContractAddress, spender: ContractAddress, amount: u256) {
        let current_allowance = s_allowances::read((owner, spender));
        let ONES_MASK = 0xffffffffffffffffffffffffffffffff_u128;
        let is_unlimited_allowance =
            current_allowance.low == ONES_MASK & current_allowance.high == ONES_MASK;
        if !is_unlimited_allowance {
            _approve(owner, spender, current_allowance - amount);
        }
    }

    #[internal]
    fn assert_only_owner() {
        let owner: ContractAddress = s_owner::read();
        let caller: ContractAddress = get_caller_address();
        assert(!caller.is_zero(), 'Caller is the zero address');
        assert(caller == owner, 'Caller is not the owner');
    }

    #[internal]
    fn transfer_ownership(new_owner: ContractAddress) {
        assert(!new_owner.is_zero(), 'New owner is the zero address');
        assert_only_owner();
        _transfer_ownership(new_owner);
    }

    #[internal]
    fn _transfer_ownership(new_owner: ContractAddress) {
        let previous_owner: ContractAddress = s_owner::read();
        s_owner::write(new_owner);
        OwnershipTransferred(previous_owner, new_owner);
    }
}
