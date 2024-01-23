#[cfg(test)]
mod test_erc20 {
    use array::{ArrayTrait};
    use core::result::ResultTrait;
    use debug::PrintTrait;
    use option::OptionTrait;
    use serde::Serde;
    use starknet::{ContractAddress, contract_address_const, 
        testing::{set_contract_address, pop_log_raw},
    };
    use starkway::erc20::erc20::StarkwayERC20;
    use starkway::interfaces::{IERC20Dispatcher, IERC20DispatcherTrait};
    use traits::{Into, TryInto};
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

    // helper function to compare arrays
    fn compare(expected_data: Array<felt252>, actual_data: Span<felt252>) {
        assert(expected_data.len() == actual_data.len(), 'Data len mismatch');
        let mut index = 0_u32;
        loop {
            if (index == expected_data.len()) {
                break ();
            }
            assert(*expected_data.at(index) == *actual_data.at(index), 'Data mismatch');
            index += 1;
        };
    }

    fn setup() -> (ContractAddress, ContractAddress) {
        let decimals: u8 = 18_u8;
        let owner: ContractAddress = contract_address_const::<1>();

        // Deploy ERC20 contract
        let mut erc20_calldata = ArrayTrait::<felt252>::new();
        NAME.serialize(ref erc20_calldata);
        SYMBOL.serialize(ref erc20_calldata);
        decimals.serialize(ref erc20_calldata);
        owner.serialize(ref erc20_calldata);

        let erc20_address = deploy(StarkwayERC20::TEST_CLASS_HASH, 100, erc20_calldata);

        // Set owner as default caller
        set_contract_address(owner);

        return (erc20_address, owner);
    }

    //
    // Tests
    //

    #[test]
    #[available_gas(2000000)]
    fn test_constructor() {
        let (erc20_address, owner) = setup();
        let mut erc20 = IERC20Dispatcher { contract_address: erc20_address };
        let decimals: u8 = 18_u8;

        assert(erc20.name() == NAME, 'Name should be NAME');
        assert(erc20.symbol() == SYMBOL, 'Symbol should be SYMBOL');
        assert(erc20.decimals() == decimals, 'Decimals should be 18');

        assert(erc20.get_owner() == contract_address_const::<1>(), 'Admin not set as owner');
        assert(erc20.get_owner() != contract_address_const::<2>(), 'non-admin set as owner');
    }

    #[test]
    #[available_gas(2000000)]
    fn test_approve() {
        let (erc20_address, owner) = setup();
        let mut erc20 = IERC20Dispatcher { contract_address: erc20_address };
        erc20.mint(owner, 10000);
        let spender: ContractAddress = contract_address_const::<2>();
        let amount: u256 = 100;

        let success: bool = erc20.approve(spender, amount);
        assert(success, 'Should return true');
        assert(erc20.allowance(owner, spender) == amount, 'Spender not approved correctly');

        let (_, _) = pop_log_raw(erc20_address).unwrap(); //1st event is for transfer based on mint
        let (keys, data) = pop_log_raw(erc20_address).unwrap();
        let mut expected_keys = ArrayTrait::<felt252>::new();
        // 1st key is the sn_keccak(event_name)
        let event_name = 544914742286571513055574265148471203182105283038408585630116262969508767999;
        expected_keys.append(event_name);
        expected_keys.append(owner.into());
        expected_keys.append(spender.into());
      
        // compare expected and actual keys
        compare(expected_keys, keys);

        let mut expected_data = ArrayTrait::<felt252>::new();
        expected_data.append(amount.low.into());
        expected_data.append(amount.high.into());

        // compare expected and actual data values
        compare(expected_data, data);
    }

    #[test]
    #[available_gas(2000000)]
    #[should_panic]
    fn test_approve_from_zero() {
        let (erc20_address, owner) = setup();
        let mut erc20 = IERC20Dispatcher { contract_address: erc20_address };
        let spender: ContractAddress = contract_address_const::<2>();
        let amount: u256 = 100;

        set_contract_address(contract_address_const::<0>());

        erc20.approve(spender, amount);
    }

    #[test]
    #[available_gas(2000000)]
    #[should_panic]
    fn test_approve_to_zero() {
        let (erc20_address, owner) = setup();
        let mut erc20 = IERC20Dispatcher { contract_address: erc20_address };
        let spender: ContractAddress = contract_address_const::<0>();
        let amount: u256 = 100;

        erc20.approve(spender, amount);
    }

    #[test]
    #[available_gas(2000000)]
    fn test_transfer() {
        let (erc20_address, sender) = setup();
        let mut erc20 = IERC20Dispatcher { contract_address: erc20_address };

        let recipient: ContractAddress = contract_address_const::<2>();
        let amount: u256 = 100;
        let user_initial_balance = 100000;
        erc20.mint(sender, user_initial_balance);
        let success: bool = erc20.transfer(recipient, amount);

        assert(success, 'Should return true');
        assert(erc20.balance_of(recipient) == amount, 'Balance should eq amount');
        assert(erc20.balanceOf(recipient) == amount, 'Balance should eq amount');
        assert(
            erc20.balance_of(sender) == user_initial_balance - amount, 'Should eq balance - amount'
        );
        assert(erc20.total_supply() == user_initial_balance, 'Total supply should not change');
        assert(erc20.totalSupply() == user_initial_balance, 'Total supply should not change');

        let (_, _) = pop_log_raw(erc20_address).unwrap(); //1st event is for transfer based on mint
        let (keys, data) = pop_log_raw(erc20_address).unwrap();
        let mut expected_keys = ArrayTrait::<felt252>::new();
        // 1st key is the sn_keccak(event_name)
        let event_name = 271746229759260285552388728919865295615886751538523744128730118297934206697;
        expected_keys.append(event_name);
        expected_keys.append(sender.into());
        expected_keys.append(recipient.into());
      
        // compare expected and actual keys
        compare(expected_keys, keys);

        let mut expected_data = ArrayTrait::<felt252>::new();
        expected_data.append(amount.low.into());
        expected_data.append(amount.high.into());

        // compare expected and actual data values
        compare(expected_data, data);
    }

    #[test]
    #[available_gas(2000000)]
    #[should_panic]
    fn test_transfer_not_enough_balance() {
        let (erc20_address, sender) = setup();
        let mut erc20 = IERC20Dispatcher { contract_address: erc20_address };

        let recipient: ContractAddress = contract_address_const::<2>();
        let amount: u256 = 1;
        erc20.transfer(recipient, amount);
    }

    #[test]
    #[available_gas(2000000)]
    #[should_panic]
    fn test_transfer_from_zero() {
        let (erc20_address, sender) = setup();
        let mut erc20 = IERC20Dispatcher { contract_address: erc20_address };

        set_contract_address(contract_address_const::<0>());
        let recipient: ContractAddress = contract_address_const::<1>();
        let amount: u256 = 100;
        erc20.transfer(recipient, amount);
    }

    #[test]
    #[available_gas(2000000)]
    #[should_panic]
    fn test_transfer_to_zero() {
        let (erc20_address, sender) = setup();
        let mut erc20 = IERC20Dispatcher { contract_address: erc20_address };

        let recipient: ContractAddress = contract_address_const::<0>();
        let amount: u256 = 100;

        let user_initial_balance = 100000;
        erc20.mint(sender, user_initial_balance);

        erc20.transfer(recipient, amount);
    }

    #[test]
    #[available_gas(2000000)]
    fn test_transfer_from() {
        let (erc20_address, owner) = setup();
        let mut erc20 = IERC20Dispatcher { contract_address: erc20_address };

        let recipient: ContractAddress = contract_address_const::<2>();
        let spender: ContractAddress = contract_address_const::<3>();
        let amount: u256 = 100;

        set_contract_address(owner);

        erc20.approve(spender, amount);
        let user_initial_balance = 100000;
        erc20.mint(owner, user_initial_balance);

        set_contract_address(spender);

        let success: bool = erc20.transfer_from(owner, recipient, amount);
        assert(success, 'Should return true');

        // Will dangle without setting as a var
        let spender_allowance: u256 = erc20.allowance(owner, spender);
        assert(erc20.balance_of(recipient) == amount, 'Should eq amount');
        assert(
            erc20.balance_of(owner) == user_initial_balance - amount, 'Should eq suppy - amount'
        );
        assert(spender_allowance == 0, 'Should eq 0');
        assert(erc20.total_supply() == user_initial_balance, 'Total supply should not change');
    }

    #[test]
    #[available_gas(2000000)]
    fn test_transferFrom() {
        let (erc20_address, owner) = setup();
        let mut erc20 = IERC20Dispatcher { contract_address: erc20_address };

        let recipient: ContractAddress = contract_address_const::<2>();
        let spender: ContractAddress = contract_address_const::<3>();
        let amount: u256 = 100;

        set_contract_address(owner);

        erc20.approve(spender, amount);
        let user_initial_balance = 100000;
        erc20.mint(owner, user_initial_balance);

        set_contract_address(spender);

        let success: bool = erc20.transferFrom(owner, recipient, amount);
        assert(success, 'Should return true');

        // Will dangle without setting as a var
        let spender_allowance: u256 = erc20.allowance(owner, spender);
        assert(erc20.balanceOf(recipient) == amount, 'Should eq amount');
        assert(
            erc20.balanceOf(owner) == user_initial_balance - amount, 'Should eq suppy - amount'
        );
        assert(spender_allowance == 0, 'Should eq 0');
        assert(erc20.total_supply() == user_initial_balance, 'Total supply should not change');
    }

    #[test]
    #[available_gas(2000000)]
    fn test_transfer_from_doesnt_consume_infinite_allowance() {
        let (erc20_address, owner) = setup();
        let mut erc20 = IERC20Dispatcher { contract_address: erc20_address };

        let recipient: ContractAddress = contract_address_const::<2>();
        let spender: ContractAddress = contract_address_const::<3>();
        let amount: u256 = 100;
        let user_initial_balance = 100000;
        erc20.mint(owner, user_initial_balance);

        erc20.approve(spender, MAX_U256());

        set_contract_address(spender);
        erc20.transfer_from(owner, recipient, amount);

        let spender_allowance: u256 = erc20.allowance(owner, spender);
        assert(spender_allowance == MAX_U256(), 'Allowance should not change');
    }

    #[test]
    #[available_gas(2000000)]
    #[should_panic]
    fn test_transfer_from_greater_than_allowance() {
        let (erc20_address, owner) = setup();
        let mut erc20 = IERC20Dispatcher { contract_address: erc20_address };

        let recipient: ContractAddress = contract_address_const::<2>();
        let spender: ContractAddress = contract_address_const::<3>();
        let amount: u256 = 100;
        let user_initial_balance = 100000;
        erc20.mint(owner, user_initial_balance);
        let amount_plus_one: u256 = amount + 1;

        erc20.approve(spender, amount);

        set_contract_address(spender);

        erc20.transfer_from(owner, recipient, amount_plus_one);
    }

    #[test]
    #[available_gas(2000000)]
    #[should_panic]
    fn test_transfer_from_to_zero_address() {
        let (erc20_address, owner) = setup();
        let mut erc20 = IERC20Dispatcher { contract_address: erc20_address };

        let recipient: ContractAddress = contract_address_const::<0>();
        let spender: ContractAddress = contract_address_const::<3>();
        let amount: u256 = 100;

        erc20.approve(spender, amount);

        set_contract_address(spender);

        erc20.transfer_from(owner, recipient, amount);
    }

    #[test]
    #[available_gas(2000000)]
    #[should_panic]
    fn test_transfer_from_from_zero_address() {
        let (erc20_address, owner) = setup();
        let mut erc20 = IERC20Dispatcher { contract_address: erc20_address };

        let zero_address: ContractAddress = contract_address_const::<0>();
        let recipient: ContractAddress = contract_address_const::<2>();
        let spender: ContractAddress = contract_address_const::<3>();
        let amount: u256 = 100;

        set_contract_address(zero_address);

        erc20.transfer_from(owner, recipient, amount);
    }

    #[test]
    #[available_gas(2000000)]
    fn test_increase_allowance() {
        let (erc20_address, owner) = setup();
        let mut erc20 = IERC20Dispatcher { contract_address: erc20_address };

        let spender: ContractAddress = contract_address_const::<2>();
        let amount: u256 = 100;

        erc20.approve(spender, amount);
        let success: bool = erc20.increase_allowance(spender, amount);
        assert(success, 'Should return true');

        let spender_allowance: u256 = erc20.allowance(owner, spender);
        assert(spender_allowance == amount + amount, 'Should be amount * 2');
    }

    #[test]
    #[available_gas(2000000)]
    #[should_panic]
    fn test_increase_allowance_to_zero_address() {
        let (erc20_address, owner) = setup();
        let mut erc20 = IERC20Dispatcher { contract_address: erc20_address };

        let spender: ContractAddress = contract_address_const::<0>();
        let amount: u256 = 100;

        erc20.increase_allowance(spender, amount);
    }

    #[test]
    #[available_gas(2000000)]
    #[should_panic]
    fn test_increase_allowance_from_zero_address() {
        let (erc20_address, owner) = setup();
        let mut erc20 = IERC20Dispatcher { contract_address: erc20_address };

        let zero_address: ContractAddress = contract_address_const::<0>();
        let spender: ContractAddress = contract_address_const::<2>();
        let amount: u256 = 100;

        set_contract_address(zero_address);

        erc20.increase_allowance(spender, amount);
    }

    #[test]
    #[available_gas(2000000)]
    fn test_decrease_allowance() {
        let (erc20_address, owner) = setup();
        let mut erc20 = IERC20Dispatcher { contract_address: erc20_address };

        let spender: ContractAddress = contract_address_const::<2>();
        let amount: u256 = 100;

        erc20.approve(spender, amount);
        let success: bool = erc20.decrease_allowance(spender, amount);
        assert(success, 'Should return true');

        let spender_allowance: u256 = erc20.allowance(owner, spender);
        assert(spender_allowance == amount - amount, 'Should be 0');
    }

    #[test]
    #[available_gas(2000000)]
    #[should_panic]
    fn test_decrease_allowance_to_zero_address() {
        let (erc20_address, owner) = setup();
        let mut erc20 = IERC20Dispatcher { contract_address: erc20_address };

        let spender: ContractAddress = contract_address_const::<0>();
        let amount: u256 = 100;

        erc20.decrease_allowance(spender, amount);
    }

    #[test]
    #[available_gas(2000000)]
    #[should_panic]
    fn test_decrease_allowance_from_zero_address() {
        let (erc20_address, owner) = setup();
        let mut erc20 = IERC20Dispatcher { contract_address: erc20_address };

        let zero_address: ContractAddress = contract_address_const::<0>();
        let spender: ContractAddress = contract_address_const::<2>();
        let amount: u256 = 100;

        set_contract_address(zero_address);

        erc20.decrease_allowance(spender, amount);
    }

    #[test]
    #[available_gas(2000000)]
    fn test__mint() {
        let (erc20_address, owner) = setup();
        let mut erc20 = IERC20Dispatcher { contract_address: erc20_address };
        let minter: ContractAddress = contract_address_const::<2>();
        let amount: u256 = 100;

        erc20.mint(minter, amount);

        let minter_balance: u256 = erc20.balance_of(minter);
        assert(minter_balance == amount, 'Should eq amount');

        assert(erc20.total_supply() == amount, 'Should eq total supply');
    }

    #[test]
    #[available_gas(2000000)]
    #[should_panic]
    fn test__mint_to_zero() {
        let (erc20_address, owner) = setup();
        let mut erc20 = IERC20Dispatcher { contract_address: erc20_address };
        let minter: ContractAddress = contract_address_const::<0>();
        let amount: u256 = 100;

        erc20.mint(minter, amount);
    }

    #[test]
    #[available_gas(2000000)]
    fn test_burn() {
        let (erc20_address, owner) = setup();
        let mut erc20 = IERC20Dispatcher { contract_address: erc20_address };

        let amount: u256 = 100;
        let user_initial_balance = 100000;
        erc20.mint(owner, user_initial_balance);
        erc20.burn(amount);

        assert(erc20.total_supply() == user_initial_balance - amount, 'Should eq supply - amount');
        assert(
            erc20.balance_of(owner) == user_initial_balance - amount, 'Should eq supply - amount'
        );
    }

    #[test]
    #[available_gas(2000000)]
    #[should_panic]
    fn test_burn_from_zero() {
        let (erc20_address, owner) = setup();
        let mut erc20 = IERC20Dispatcher { contract_address: erc20_address };

        let zero_address: ContractAddress = contract_address_const::<0>();
        set_contract_address(zero_address);
        let amount: u256 = 100;

        erc20.burn(amount);
    }

    #[test]
    #[available_gas(2000000)]
    fn test_transfer_ownership() {
        let (erc20_address, owner) = setup();
        let mut erc20 = IERC20Dispatcher { contract_address: erc20_address };

        erc20.transfer_ownership(contract_address_const::<2>());

        assert(erc20.get_owner() == contract_address_const::<2>(), 'Owner should change');
    }

    #[test]
    #[available_gas(2000000)]
    #[should_panic]
    fn test_transfer_ownership_revert() {
        let (erc20_address, owner) = setup();
        let mut erc20 = IERC20Dispatcher { contract_address: erc20_address };

        // Set account as default caller
        set_contract_address(contract_address_const::<3>());

        erc20.transfer_ownership(contract_address_const::<2>());
    }
}
