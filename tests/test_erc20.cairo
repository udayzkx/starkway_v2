#[cfg(test)]
mod test_erc20 {
    use starknet::ContractAddress;
    use starknet::contract_address_const;
    use starknet::testing::set_caller_address;
    use starkway::erc20::erc20;
    use integer::u256;
    use integer::u256_from_felt252;
    use traits::Into;

    fn MAX_U256() -> u256 {
        u256 {
            low: 0xffffffffffffffffffffffffffffffff_u128,
            high: 0xffffffffffffffffffffffffffffffff_u128
        }
    }
    //
    // Constants
    //

    const NAME: felt252 = 111;
    const SYMBOL: felt252 = 222;

    fn setup() -> ContractAddress {
        let admin_1: ContractAddress = contract_address_const::<1>();

        let initial_supply: u256 = u256_from_felt252(0);
        let decimals: u8 = 18_u8;
        let owner: ContractAddress = contract_address_const::<1>();
        // Set account as default caller
        set_caller_address(owner);

        erc20::StarkwayERC20::constructor(NAME, SYMBOL, decimals, owner);

        owner
    }


    fn set_caller_as_zero() {
        set_caller_address(contract_address_const::<0>());
    }

    fn mint_funds_to_user(receiver: ContractAddress, amount: u256) {
        erc20::StarkwayERC20::mint(receiver, amount);
    }

    //
    // Tests
    //

    #[test]
    #[available_gas(2000000)]
    fn test_initializer() {
        let owner: ContractAddress = contract_address_const::<1>();
        let decimals: u8 = 18_u8;

        erc20::StarkwayERC20::_initializer(NAME, SYMBOL, decimals, owner);

        assert(erc20::StarkwayERC20::name() == NAME, 'Name should be NAME');
        assert(erc20::StarkwayERC20::symbol() == SYMBOL, 'Symbol should be SYMBOL');
        assert(erc20::StarkwayERC20::decimals() == 18_u8, 'Decimals should be 18');
        assert(erc20::StarkwayERC20::total_supply() == u256_from_felt252(0), 'Supply should eq 0');
    }


    #[test]
    #[available_gas(2000000)]
    fn test_constructor() {
        let owner: ContractAddress = contract_address_const::<0>();
        let decimals: u8 = 18_u8;

        erc20::StarkwayERC20::constructor(NAME, SYMBOL, decimals, owner);

        assert(erc20::StarkwayERC20::name() == NAME, 'Name should be NAME');
        assert(erc20::StarkwayERC20::symbol() == SYMBOL, 'Symbol should be SYMBOL');
        assert(erc20::StarkwayERC20::decimals() == decimals, 'Decimals should be 18');

        assert(
            erc20::StarkwayERC20::get_owner() == contract_address_const::<0>(),
            'Admin not set as owner'
        );

        assert(
            erc20::StarkwayERC20::get_owner() != contract_address_const::<2>(),
            'non-admin set as owner'
        );
    }

    #[test]
    #[available_gas(2000000)]
    fn test_approve() {
        let owner = setup();
        erc20::StarkwayERC20::mint(owner, u256_from_felt252(10000));
        let spender: ContractAddress = contract_address_const::<2>();
        let amount: u256 = u256_from_felt252(100);

        let success: bool = erc20::StarkwayERC20::approve(spender, amount);
        assert(success, 'Should return true');
        assert(
            erc20::StarkwayERC20::allowance(owner, spender) == amount,
            'Spender not approved correctly'
        );
    }

    #[test]
    #[available_gas(2000000)]
    #[should_panic]
    fn test_approve_from_zero() {
        let owner = setup();
        let spender: ContractAddress = contract_address_const::<2>();
        let amount: u256 = u256_from_felt252(100);

        set_caller_as_zero();

        erc20::StarkwayERC20::approve(spender, amount);
    }

    #[test]
    #[available_gas(2000000)]
    #[should_panic]
    fn test_approve_to_zero() {
        let owner = setup();
        let spender: ContractAddress = contract_address_const::<0>();
        let amount: u256 = u256_from_felt252(100);

        erc20::StarkwayERC20::approve(spender, amount);
    }

    #[test]
    #[available_gas(2000000)]
    fn test__approve() {
        let owner = setup();

        let spender: ContractAddress = contract_address_const::<2>();
        let amount: u256 = u256_from_felt252(100);

        erc20::StarkwayERC20::_approve(owner, spender, amount);
        assert(
            erc20::StarkwayERC20::allowance(owner, spender) == amount,
            'Spender not approved correctly'
        );
    }

    #[test]
    #[available_gas(2000000)]
    #[should_panic]
    fn test__approve_from_zero() {
        let owner: ContractAddress = contract_address_const::<0>();
        let spender: ContractAddress = contract_address_const::<1>();
        let amount: u256 = u256_from_felt252(100);
        erc20::StarkwayERC20::_approve(owner, spender, amount);
    }

    #[test]
    #[available_gas(2000000)]
    #[should_panic]
    fn test__approve_to_zero() {
        let owner = setup();

        let spender: ContractAddress = contract_address_const::<0>();
        let amount: u256 = u256_from_felt252(100);
        erc20::StarkwayERC20::_approve(owner, spender, amount);
    }

    #[test]
    #[available_gas(2000000)]
    fn test_transfer() {
        let sender = setup();

        let recipient: ContractAddress = contract_address_const::<2>();
        let amount: u256 = u256_from_felt252(100);
        let user_initial_balance = u256_from_felt252(100000);
        mint_funds_to_user(sender, user_initial_balance);
        let success: bool = erc20::StarkwayERC20::transfer(recipient, amount);

        assert(success, 'Should return true');
        assert(erc20::StarkwayERC20::balance_of(recipient) == amount, 'Balance should eq amount');
        assert(
            erc20::StarkwayERC20::balance_of(sender) == user_initial_balance - amount,
            'Should eq balance - amount'
        );
        assert(
            erc20::StarkwayERC20::total_supply() == user_initial_balance,
            'Total supply should not change'
        );
    }

    #[test]
    #[available_gas(2000000)]
    fn test__transfer() {
        let sender = setup();

        let recipient: ContractAddress = contract_address_const::<2>();
        let amount: u256 = u256_from_felt252(100);
        let user_initial_balance = u256_from_felt252(100000);
        mint_funds_to_user(sender, user_initial_balance);
        erc20::StarkwayERC20::_transfer(sender, recipient, amount);

        assert(erc20::StarkwayERC20::balance_of(recipient) == amount, 'Balance should eq amount');
        assert(
            erc20::StarkwayERC20::balance_of(sender) == user_initial_balance - amount,
            'Should eq supply - amount'
        );
        assert(
            erc20::StarkwayERC20::total_supply() == user_initial_balance,
            'Total supply should not change'
        );
    }

    #[test]
    #[available_gas(2000000)]
    #[should_panic]
    fn test__transfer_not_enough_balance() {
        let sender = setup();

        let recipient: ContractAddress = contract_address_const::<2>();
        let amount: u256 = u256_from_felt252(1);
        erc20::StarkwayERC20::_transfer(sender, recipient, amount);
    }

    #[test]
    #[available_gas(2000000)]
    #[should_panic]
    fn test__transfer_from_zero() {
        let sender: ContractAddress = contract_address_const::<0>();
        let recipient: ContractAddress = contract_address_const::<1>();
        let amount: u256 = u256_from_felt252(100);
        erc20::StarkwayERC20::_transfer(sender, recipient, amount);
    }

    #[test]
    #[available_gas(2000000)]
    #[should_panic]
    fn test__transfer_to_zero() {
        let sender = setup();

        let recipient: ContractAddress = contract_address_const::<0>();
        let amount: u256 = u256_from_felt252(100);

        let user_initial_balance = u256_from_felt252(100000);
        mint_funds_to_user(sender, user_initial_balance);

        erc20::StarkwayERC20::_transfer(sender, recipient, amount);
    }

    #[test]
    #[available_gas(2000000)]
    fn test_transfer_from() {
        let owner = setup();

        let recipient: ContractAddress = contract_address_const::<2>();
        let spender: ContractAddress = contract_address_const::<3>();
        let amount: u256 = u256_from_felt252(100);

        set_caller_address(owner);

        erc20::StarkwayERC20::approve(spender, amount);
        let user_initial_balance = u256_from_felt252(100000);
        mint_funds_to_user(owner, user_initial_balance);

        set_caller_address(spender);

        let success: bool = erc20::StarkwayERC20::transfer_from(owner, recipient, amount);
        assert(success, 'Should return true');

        // Will dangle without setting as a var
        let spender_allowance: u256 = erc20::StarkwayERC20::allowance(owner, spender);
        assert(erc20::StarkwayERC20::balance_of(recipient) == amount, 'Should eq amount');
        assert(
            erc20::StarkwayERC20::balance_of(owner) == user_initial_balance - amount,
            'Should eq suppy - amount'
        );
        assert(spender_allowance == u256_from_felt252(0), 'Should eq 0');
        assert(
            erc20::StarkwayERC20::total_supply() == user_initial_balance,
            'Total supply should not change'
        );
    }

    #[test]
    #[available_gas(2000000)]
    fn test_transfer_from_doesnt_consume_infinite_allowance() {
        let owner = setup();

        let recipient: ContractAddress = contract_address_const::<2>();
        let spender: ContractAddress = contract_address_const::<3>();
        let amount: u256 = u256_from_felt252(100);
        let user_initial_balance = u256_from_felt252(100000);
        mint_funds_to_user(owner, user_initial_balance);

        erc20::StarkwayERC20::approve(spender, MAX_U256());

        set_caller_address(spender);
        erc20::StarkwayERC20::transfer_from(owner, recipient, amount);

        let spender_allowance: u256 = erc20::StarkwayERC20::allowance(owner, spender);
        assert(spender_allowance == MAX_U256(), 'Allowance should not change');
    }

    #[test]
    #[available_gas(2000000)]
    #[should_panic]
    fn test_transfer_from_greater_than_allowance() {
        let owner = setup();

        let recipient: ContractAddress = contract_address_const::<2>();
        let spender: ContractAddress = contract_address_const::<3>();
        let amount: u256 = u256_from_felt252(100);
        let user_initial_balance = u256_from_felt252(100000);
        mint_funds_to_user(owner, user_initial_balance);
        let amount_plus_one: u256 = amount + u256_from_felt252(1);

        erc20::StarkwayERC20::approve(spender, amount);

        set_caller_address(spender);

        erc20::StarkwayERC20::transfer_from(owner, recipient, amount_plus_one);
    }

    #[test]
    #[available_gas(2000000)]
    #[should_panic]
    fn test_transfer_from_to_zero_address() {
        let owner = setup();

        let recipient: ContractAddress = contract_address_const::<0>();
        let spender: ContractAddress = contract_address_const::<3>();
        let amount: u256 = u256_from_felt252(100);

        erc20::StarkwayERC20::approve(spender, amount);

        set_caller_address(spender);

        erc20::StarkwayERC20::transfer_from(owner, recipient, amount);
    }

    #[test]
    #[available_gas(2000000)]
    #[should_panic]
    fn test_transfer_from_from_zero_address() {
        let owner = setup();

        let zero_address: ContractAddress = contract_address_const::<0>();
        let recipient: ContractAddress = contract_address_const::<2>();
        let spender: ContractAddress = contract_address_const::<3>();
        let amount: u256 = u256_from_felt252(100);

        set_caller_address(zero_address);

        erc20::StarkwayERC20::transfer_from(owner, recipient, amount);
    }

    #[test]
    #[available_gas(2000000)]
    fn test_increase_allowance() {
        let owner = setup();

        let spender: ContractAddress = contract_address_const::<2>();
        let amount: u256 = u256_from_felt252(100);

        erc20::StarkwayERC20::approve(spender, amount);
        let success: bool = erc20::StarkwayERC20::increase_allowance(spender, amount);
        assert(success, 'Should return true');

        let spender_allowance: u256 = erc20::StarkwayERC20::allowance(owner, spender);
        assert(spender_allowance == amount + amount, 'Should be amount * 2');
    }

    #[test]
    #[available_gas(2000000)]
    #[should_panic]
    fn test_increase_allowance_to_zero_address() {
        let owner = setup();

        let spender: ContractAddress = contract_address_const::<0>();
        let amount: u256 = u256_from_felt252(100);

        erc20::StarkwayERC20::increase_allowance(spender, amount);
    }

    #[test]
    #[available_gas(2000000)]
    #[should_panic]
    fn test_increase_allowance_from_zero_address() {
        let owner = setup();

        let zero_address: ContractAddress = contract_address_const::<0>();
        let spender: ContractAddress = contract_address_const::<2>();
        let amount: u256 = u256_from_felt252(100);

        set_caller_address(zero_address);

        erc20::StarkwayERC20::increase_allowance(spender, amount);
    }

    #[test]
    #[available_gas(2000000)]
    fn test_decrease_allowance() {
        let owner = setup();

        let spender: ContractAddress = contract_address_const::<2>();
        let amount: u256 = u256_from_felt252(100);

        erc20::StarkwayERC20::approve(spender, amount);
        let success: bool = erc20::StarkwayERC20::decrease_allowance(spender, amount);
        assert(success, 'Should return true');

        let spender_allowance: u256 = erc20::StarkwayERC20::allowance(owner, spender);
        assert(spender_allowance == amount - amount, 'Should be 0');
    }

    #[test]
    #[available_gas(2000000)]
    #[should_panic]
    fn test_decrease_allowance_to_zero_address() {
        let owner = setup();

        let spender: ContractAddress = contract_address_const::<0>();
        let amount: u256 = u256_from_felt252(100);

        erc20::StarkwayERC20::decrease_allowance(spender, amount);
    }

    #[test]
    #[available_gas(2000000)]
    #[should_panic]
    fn test_decrease_allowance_from_zero_address() {
        let owner = setup();

        let zero_address: ContractAddress = contract_address_const::<0>();
        let spender: ContractAddress = contract_address_const::<2>();
        let amount: u256 = u256_from_felt252(100);

        set_caller_address(zero_address);

        erc20::StarkwayERC20::decrease_allowance(spender, amount);
    }

    #[test]
    #[available_gas(2000000)]
    fn test__spend_allowance_not_unlimited() {
        let owner = setup();

        let spender: ContractAddress = contract_address_const::<2>();
        let amount: u256 = u256_from_felt252(100);
        let user_initial_balance = u256_from_felt252(100000);
        mint_funds_to_user(owner, user_initial_balance);

        erc20::StarkwayERC20::_approve(owner, spender, user_initial_balance);
        erc20::StarkwayERC20::_spend_allowance(owner, spender, amount);
        assert(
            erc20::StarkwayERC20::allowance(owner, spender) == user_initial_balance - amount,
            'Should eq supply - amount'
        );
    }

    #[test]
    #[available_gas(2000000)]
    fn test__spend_allowance_unlimited() {
        let owner = setup();

        let spender: ContractAddress = contract_address_const::<2>();
        let max_minus_one: u256 = MAX_U256() - 1.into();

        erc20::StarkwayERC20::_approve(owner, spender, MAX_U256());
        erc20::StarkwayERC20::_spend_allowance(owner, spender, max_minus_one);

        assert(
            erc20::StarkwayERC20::allowance(owner, spender) == MAX_U256(),
            'Allowance should not change'
        );
    }

    #[test]
    #[available_gas(2000000)]
    fn test__mint() {
        let minter: ContractAddress = contract_address_const::<2>();
        let amount: u256 = u256_from_felt252(100);

        erc20::StarkwayERC20::_mint(minter, amount);

        let minter_balance: u256 = erc20::StarkwayERC20::balance_of(minter);
        assert(minter_balance == amount, 'Should eq amount');

        assert(erc20::StarkwayERC20::total_supply() == amount, 'Should eq total supply');
    }

    #[test]
    #[available_gas(2000000)]
    #[should_panic]
    fn test__mint_to_zero() {
        let minter: ContractAddress = contract_address_const::<0>();
        let amount: u256 = u256_from_felt252(100);

        erc20::StarkwayERC20::_mint(minter, amount);
    }

    #[test]
    #[available_gas(2000000)]
    fn test__burn() {
        let owner = setup();

        let amount: u256 = u256_from_felt252(100);
        let user_initial_balance = u256_from_felt252(100000);
        mint_funds_to_user(owner, user_initial_balance);
        erc20::StarkwayERC20::_burn(owner, amount);

        assert(
            erc20::StarkwayERC20::total_supply() == user_initial_balance - amount,
            'Should eq supply - amount'
        );
        assert(
            erc20::StarkwayERC20::balance_of(owner) == user_initial_balance - amount,
            'Should eq supply - amount'
        );
    }

    #[test]
    #[available_gas(2000000)]
    #[should_panic]
    fn test__burn_from_zero() {
        let owner = setup();

        let zero_address: ContractAddress = contract_address_const::<0>();
        let amount: u256 = u256_from_felt252(100);

        erc20::StarkwayERC20::_burn(zero_address, amount);
    }

    #[test]
    #[available_gas(2000000)]
    fn test_transfer_ownership() {
        let owner = setup();

        erc20::StarkwayERC20::transfer_ownership(contract_address_const::<2>());

        assert(
            erc20::StarkwayERC20::get_owner() == contract_address_const::<2>(),
            'Owner should change'
        );
    }

    #[test]
    #[available_gas(2000000)]
    #[should_panic]
    fn test_transfer_ownership_revert() {
        let owner = setup();

        // Set account as default caller
        set_caller_address(contract_address_const::<3>());

        erc20::StarkwayERC20::transfer_ownership(contract_address_const::<2>());
    }
}