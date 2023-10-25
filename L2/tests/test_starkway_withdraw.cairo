use starknet::{ContractAddress, EthAddress};

#[cfg(test)]
mod test_starkway_withdraw {
    use array::{Array, ArrayTrait, Span, SpanTrait};
    use core::hash::{HashStateTrait, HashStateExTrait};
    use core::integer::u256;
    use core::result::ResultTrait;
    use debug::{PrintTrait, print_felt252};
    use option::OptionTrait;
    use pedersen::PedersenImpl;
    use serde::Serde;
    use starknet::class_hash::ClassHash;
    use starknet::{ContractAddress, contract_address_const, EthAddress, contract_address::contract_address_to_felt252};
    use starknet::testing::{set_caller_address, set_contract_address, pop_log_raw};
    use traits::{Default, Into, TryInto};
    use starkway::admin_auth::AdminAuth;
    use starkway::datatypes::{L1TokenDetails, WithdrawalRange, L2TokenDetails};
    use starkway::erc20::erc20::StarkwayERC20;
    use starkway::interfaces::{
        IAdminAuthDispatcher, IAdminAuthDispatcherTrait, IStarkwayDispatcher,
        IStarkwayDispatcherTrait, IERC20Dispatcher, IERC20DispatcherTrait, IBridgeAdapterDispatcher,
        IBridgeAdapterDispatcherTrait
    };
    use starkway::libraries::reentrancy_guard::ReentrancyGuard;
    use starkway::libraries::fee_library::fee_library;
    use starkway::starkway::Starkway;
    use zeroable::Zeroable;
    use tests::utils::{setup, deploy, mint, init_token, register_bridge_adapter, deploy_non_native_token, 
        whitelist_token, whitelist_token_camelCase};
    use tests::utils::DummyAdapter;
    
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

    #[test]
    #[available_gas(20000000)]
    fn test_mint_and_withdraw() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();

        let l1_token_address = EthAddress { address: 100_felt252 };
        let l1_recipient = EthAddress { address: 200_felt252 };
        init_token(starkway_address, admin_1, l1_token_address);

        let starkway = IStarkwayDispatcher { contract_address: starkway_address };

        let native_erc20_address = starkway.get_native_token_address(l1_token_address);

        let user = contract_address_const::<30>();
        let amount1 = u256 { low: 1000, high: 0 };
        let amount2 = u256 { low: 100, high: 0 };
        let fee = u256 { low: 2, high: 0 };

        // Mint tokens to user
        mint(starkway_address, native_erc20_address, user, amount1);

        // Call approval and withdrawal functions as user
        set_contract_address(user);
        let calculated_fee = starkway.calculate_fee(l1_token_address, amount2);

        let erc20 = IERC20Dispatcher { contract_address: native_erc20_address };

        // Balances before withdrawal
        let balance_user_before = erc20.balance_of(user);
        let balance_starkway_before = erc20.balance_of(starkway_address);
        let total_supply_before = erc20.total_supply();
        let cumulative_fees_before = starkway.get_cumulative_fees(l1_token_address);

        // User approves starkway to spend amount2 tokens
        erc20.approve(starkway_address, amount2 + fee);

        starkway.withdraw(native_erc20_address, l1_token_address, l1_recipient, amount2, fee);

        // Balances after withdrawal
        let balance_user_after = erc20.balance_of(user);
        let balance_starkway_after = erc20.balance_of(starkway_address);
        let total_supply_after = erc20.total_supply();
        let cumulative_fees_after = starkway.get_cumulative_fees(l1_token_address);

        assert(balance_user_before == balance_user_after + amount2 + fee, 'Incorrect user balance');
        assert(
            balance_starkway_before == balance_starkway_after - fee, 'Incorrect Starkway balance'
        );

        // Total supply reduces since starkway burns the tokens equivalent to withdrawal_amount
        assert(total_supply_before == total_supply_after + amount2, 'Incorrect total supply');
        assert(cumulative_fees_before == cumulative_fees_after - fee, 'Incorrect fee collection');

        let (keys, data) = pop_log_raw(starkway_address).unwrap();

        // Since first event emitted is going to be the init token event, we skip it and pop the next event
        let (keys, data) = pop_log_raw(starkway_address).unwrap();
        let mut expected_keys = ArrayTrait::<felt252>::new();
        expected_keys.append(l1_recipient.into());
        expected_keys.append(user.into());
        expected_keys.append(PedersenImpl::new(l1_recipient.into())
                                        .update_with(contract_address_to_felt252(user)).finalize());
        expected_keys.append('WITHDRAW');
        expected_keys.append(l1_token_address.into());
        expected_keys.append(native_erc20_address.into());

        // compare expected and actual keys
        compare(expected_keys, keys);

        let mut expected_data = ArrayTrait::<felt252>::new();
        expected_data.append(amount2.low.into());
        expected_data.append(amount2.high.into());
        expected_data.append(fee.low.into());
        expected_data.append(fee.high.into());

        // compare expected and actual values
        compare(expected_data, data);
    }

    #[test]
    #[available_gas(20000000)]
    #[should_panic(expected: ('SW: Native token uninitialized', 'ENTRYPOINT_FAILED'))]
    fn test_withdraw_uninitialized_token() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();

        let l1_token_address = EthAddress { address: 100_felt252 };
        let l1_recipient = EthAddress { address: 200_felt252 };

        // No call to initialise token, hence withdraw should not work

        let mut erc20_calldata = ArrayTrait::<felt252>::new();
        let name = 'TEST_TOKEN';
        let symbol = 'TEST';
        let decimals = 18_u8;
        let owner = starkway_address;

        name.serialize(ref erc20_calldata);
        symbol.serialize(ref erc20_calldata);
        decimals.serialize(ref erc20_calldata);
        owner.serialize(ref erc20_calldata);
        let native_erc20_address = deploy(StarkwayERC20::TEST_CLASS_HASH, 100, erc20_calldata);

        let starkway = IStarkwayDispatcher { contract_address: starkway_address };

        let user = contract_address_const::<30>();
        let amount1 = u256 { low: 1000, high: 0 };
        let amount2 = u256 { low: 100, high: 0 };
        let fee = u256 { low: 2, high: 0 };

        mint(starkway_address, native_erc20_address, user, amount1);

        set_contract_address(user);
        let calculated_fee = starkway.calculate_fee(l1_token_address, amount2);

        let erc20 = IERC20Dispatcher { contract_address: native_erc20_address };

        erc20.approve(starkway_address, amount2 + fee);
        starkway.withdraw(native_erc20_address, l1_token_address, l1_recipient, amount2, fee);
    }

    #[test]
    #[available_gas(20000000)]
    #[should_panic(expected: ('SW: amount > threshold', 'ENTRYPOINT_FAILED'))]
    fn test_greater_than_withdrawal_range() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();

        let l1_token_address = EthAddress { address: 100_felt252 };
        let l1_recipient = EthAddress { address: 200_felt252 };
        init_token(starkway_address, admin_1, l1_token_address);

        let starkway = IStarkwayDispatcher { contract_address: starkway_address };

        // Reset max of withdrawal range to be lower than withdrawal amount
        set_contract_address(admin_1);
        let withdrawal_range = WithdrawalRange {
            min: u256 { low: 2, high: 0 }, max: u256 { low: 10, high: 0 }
        };
        starkway.set_withdrawal_range(l1_token_address, withdrawal_range);

        let native_erc20_address = starkway.get_native_token_address(l1_token_address);

        let user = contract_address_const::<30>();
        let amount1 = u256 { low: 1000, high: 0 };
        let amount2 = u256 { low: 100, high: 0 };
        let fee = u256 { low: 2, high: 0 };

        mint(starkway_address, native_erc20_address, user, amount1);

        // Call approval and withdrawal functions as user
        set_contract_address(user);
        let calculated_fee = starkway.calculate_fee(l1_token_address, amount2);
        assert(fee == calculated_fee, 'Incorrect fee');

        let erc20 = IERC20Dispatcher { contract_address: native_erc20_address };

        erc20.approve(starkway_address, amount2 + fee);
        starkway.withdraw(native_erc20_address, l1_token_address, l1_recipient, amount2, fee);
    }

    #[test]
    #[available_gas(20000000)]
    fn test_infinite_withdrawal_range() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();

        let l1_token_address = EthAddress { address: 100_felt252 };
        let l1_recipient = EthAddress { address: 200_felt252 };
        init_token(starkway_address, admin_1, l1_token_address);

        let starkway = IStarkwayDispatcher { contract_address: starkway_address };

        // Reset max of withdrawal range to be lower than withdrawal amount
        set_contract_address(admin_1);
        let withdrawal_range = WithdrawalRange {
            min: 2, max: 0
        };
        starkway.set_withdrawal_range(l1_token_address, withdrawal_range);

        let native_erc20_address = starkway.get_native_token_address(l1_token_address);

        let user = contract_address_const::<30>();
        let amount1 = 1000;
        let amount2 = 100;
        let fee = 2;

        mint(starkway_address, native_erc20_address, user, amount1);

        // Call approval and withdrawal functions as user
        set_contract_address(user);
        let calculated_fee = starkway.calculate_fee(l1_token_address, amount2);
        assert(fee == calculated_fee, 'Incorrect fee');

        let erc20 = IERC20Dispatcher { contract_address: native_erc20_address };

        erc20.approve(starkway_address, amount2 + fee);
        // Balances before withdrawal
        let balance_user_before = erc20.balance_of(user);
        let balance_starkway_before = erc20.balance_of(starkway_address);
        let total_supply_before = erc20.total_supply();
        let cumulative_fees_before = starkway.get_cumulative_fees(l1_token_address);
        starkway.withdraw(native_erc20_address, l1_token_address, l1_recipient, amount2, fee);

        // Balances after withdrawal
        let balance_user_after = erc20.balance_of(user);
        let balance_starkway_after = erc20.balance_of(starkway_address);
        let total_supply_after = erc20.total_supply();
        let cumulative_fees_after = starkway.get_cumulative_fees(l1_token_address);

        assert(balance_user_before == balance_user_after + amount2 + fee, 'Incorrect user balance');
        assert(
            balance_starkway_before == balance_starkway_after - fee, 'Incorrect Starkway balance'
        );

        // Total supply reduces since starkway burns the tokens equivalent to withdrawal_amount
        assert(total_supply_before == total_supply_after + amount2, 'Incorrect total supply');
        assert(cumulative_fees_before == cumulative_fees_after - fee, 'Incorrect fee collection');   
    }

    #[test]
    #[available_gas(20000000)]
    #[should_panic(expected: ('SW: Withdrawal not allowed', 'ENTRYPOINT_FAILED'))]
    fn test_withdraw_no_permission() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();

        let l1_token_address = EthAddress { address: 100_felt252 };
        let l1_recipient = EthAddress { address: 200_felt252 };
        init_token(starkway_address, admin_1, l1_token_address);

        let starkway = IStarkwayDispatcher { contract_address: starkway_address };

        // Disallow withdrawal for l1_token_address
        set_contract_address(admin_1);
        
        let native_erc20_address = starkway.get_native_token_address(l1_token_address);
        starkway.set_is_withdraw_allowed(native_erc20_address, false);
        let user = contract_address_const::<30>();
        let amount1 = 1000;
        let amount2 = 100;
        let fee = 2;

        mint(starkway_address, native_erc20_address, user, amount1);

        // Call approval and withdrawal functions as user
        set_contract_address(user);
        let calculated_fee = starkway.calculate_fee(l1_token_address, amount2);
        assert(fee == calculated_fee, 'Incorrect fee');

        let erc20 = IERC20Dispatcher { contract_address: native_erc20_address };

        erc20.approve(starkway_address, amount2 + fee);
        starkway.withdraw(native_erc20_address, l1_token_address, l1_recipient, amount2, fee);
    }

    #[test]
    #[available_gas(20000000)]
    #[should_panic(expected: ('SW: min_withdraw > amount', 'ENTRYPOINT_FAILED'))]
    fn test_lesser_than_withdrawal_range() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();

        let l1_token_address = EthAddress { address: 100_felt252 };
        let l1_recipient = EthAddress { address: 200_felt252 };
        init_token(starkway_address, admin_1, l1_token_address);

        let starkway = IStarkwayDispatcher { contract_address: starkway_address };
        set_contract_address(admin_1);

        // Reset min of withdrawal range to be higher than withdrawal amount
        let withdrawal_range = WithdrawalRange {
            min: u256 { low: 101, high: 0 }, max: u256 { low: 0, high: 1000 }
        };
        starkway.set_withdrawal_range(l1_token_address, withdrawal_range);

        let native_erc20_address = starkway.get_native_token_address(l1_token_address);

        let user = contract_address_const::<30>();
        let amount1 = u256 { low: 1000, high: 0 };
        let amount2 = u256 { low: 100, high: 0 };
        let fee = u256 { low: 2, high: 0 };

        mint(starkway_address, native_erc20_address, user, amount1);

        set_contract_address(user);
        let calculated_fee = starkway.calculate_fee(l1_token_address, amount2);
        assert(fee == calculated_fee, 'Incorrect fee');

        let erc20 = IERC20Dispatcher { contract_address: native_erc20_address };

        erc20.approve(starkway_address, amount2 + fee);
        starkway.withdraw(native_erc20_address, l1_token_address, l1_recipient, amount2, fee);
    }

    #[test]
    #[available_gas(20000000)]
    #[should_panic(expected: ('SW: Fee mismatch', 'ENTRYPOINT_FAILED'))]
    fn test_fee_mismatch() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();

        let l1_token_address = EthAddress { address: 100_felt252 };
        let l1_recipient = EthAddress { address: 200_felt252 };
        init_token(starkway_address, admin_1, l1_token_address);

        let starkway = IStarkwayDispatcher { contract_address: starkway_address };

        let native_erc20_address = starkway.get_native_token_address(l1_token_address);

        let user = contract_address_const::<30>();
        let amount1 = u256 { low: 1000, high: 0 };
        let amount2 = u256 { low: 100, high: 0 };
        let fee = u256 { low: 1, high: 0 }; // Deliberately using wrong fee

        mint(starkway_address, native_erc20_address, user, amount1);

        set_contract_address(user);
        let calculated_fee = starkway.calculate_fee(l1_token_address, amount2);

        let erc20 = IERC20Dispatcher { contract_address: native_erc20_address };

        let balance_user_before = erc20.balance_of(user);
        let balance_starkway_before = erc20.balance_of(starkway_address);
        let total_supply_before = erc20.total_supply();

        erc20.approve(starkway_address, amount2 + fee);
        starkway.withdraw(native_erc20_address, l1_token_address, l1_recipient, amount2, fee);
    }

    #[test]
    #[available_gas(20000000)]
    #[should_panic(expected: ('u256_sub Overflow', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED'))]
    fn test_without_approval() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();

        let l1_token_address = EthAddress { address: 100_felt252 };
        let l1_recipient = EthAddress { address: 200_felt252 };
        init_token(starkway_address, admin_1, l1_token_address);

        let starkway = IStarkwayDispatcher { contract_address: starkway_address };

        let native_erc20_address = starkway.get_native_token_address(l1_token_address);

        let user = contract_address_const::<30>();
        let amount1 = u256 { low: 1000, high: 0 };
        let amount2 = u256 { low: 100, high: 0 };
        let fee = u256 { low: 2, high: 0 };

        mint(starkway_address, native_erc20_address, user, amount1);

        set_contract_address(user);
        let calculated_fee = starkway.calculate_fee(l1_token_address, amount2);

        let erc20 = IERC20Dispatcher { contract_address: native_erc20_address };

        //erc20.approve(starkway_address, amount2+fee); - no approval means no withdrawal
        starkway.withdraw(native_erc20_address, l1_token_address, l1_recipient, amount2, fee);
    }

    #[test]
    #[available_gas(20000000)]
    #[should_panic(expected: ('u256_sub Overflow', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED'))]
    fn test_insufficient_balance() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();

        let l1_token_address = EthAddress { address: 100_felt252 };
        let l1_recipient = EthAddress { address: 200_felt252 };
        init_token(starkway_address, admin_1, l1_token_address);

        let starkway = IStarkwayDispatcher { contract_address: starkway_address };

        let native_erc20_address = starkway.get_native_token_address(l1_token_address);

        let user = contract_address_const::<30>();
        let amount1 = u256 { low: 100, high: 0 };
        let amount2 = u256 { low: 100, high: 0 };
        let fee = u256 { low: 2, high: 0 };

        // User is minted tokens insufficient to cover withdrawal_amount + fee
        mint(starkway_address, native_erc20_address, user, amount1);

        set_contract_address(user);
        let calculated_fee = starkway.calculate_fee(l1_token_address, amount2);

        let erc20 = IERC20Dispatcher { contract_address: native_erc20_address };

        erc20.approve(starkway_address, amount2 + fee);
        starkway.withdraw(native_erc20_address, l1_token_address, l1_recipient, amount2, fee);
    }

    #[test]
    #[available_gas(20000000)]
    #[should_panic(expected: ('SW: L1 recipient cannot be 0', 'ENTRYPOINT_FAILED'))]
    fn test_zero_l1_recipient() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();

        let l1_token_address = EthAddress { address: 100_felt252 };
        let l1_recipient = EthAddress { address: 0_felt252 };
        init_token(starkway_address, admin_1, l1_token_address);

        let starkway = IStarkwayDispatcher { contract_address: starkway_address };

        let native_erc20_address = starkway.get_native_token_address(l1_token_address);

        let user = contract_address_const::<30>();
        let amount1:u256 = 100;
        let amount2:u256 = 100;
        let fee:u256 = 2;

        // User is minted tokens insufficient to cover withdrawal_amount + fee
        mint(starkway_address, native_erc20_address, user, amount1 + fee);

        set_contract_address(user);
        let calculated_fee = starkway.calculate_fee(l1_token_address, amount2);

        let erc20 = IERC20Dispatcher { contract_address: native_erc20_address };

        erc20.approve(starkway_address, amount2 + fee);
        starkway.withdraw(native_erc20_address, l1_token_address, l1_recipient, amount2, fee);
    }

    #[test]
    #[available_gas(20000000)]
    #[should_panic(expected: ('SW: Token not whitelisted', 'ENTRYPOINT_FAILED'))]
    fn test_withdraw_non_whitelisted_token() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();

        let l1_token_address = EthAddress { address: 100_felt252 };
        let l1_recipient = EthAddress { address: 200_felt252 };
        init_token(starkway_address, admin_1, l1_token_address);

        let starkway = IStarkwayDispatcher { contract_address: starkway_address };

        let native_erc20_address = starkway.get_native_token_address(l1_token_address);

        let mut erc20_calldata = ArrayTrait::<felt252>::new();
        let name = 'TEST_TOKEN2';
        let symbol = 'TEST2';
        let decimals = 18_u8;
        let owner = starkway_address;

        name.serialize(ref erc20_calldata);
        symbol.serialize(ref erc20_calldata);
        decimals.serialize(ref erc20_calldata);
        owner.serialize(ref erc20_calldata);
        let non_native_erc20_address = deploy(StarkwayERC20::TEST_CLASS_HASH, 100, erc20_calldata);

        let starkway = IStarkwayDispatcher { contract_address: starkway_address };

        let user = contract_address_const::<30>();
        let amount1 = u256 { low: 1000, high: 0 };
        let amount2 = u256 { low: 100, high: 0 };
        let fee = u256 { low: 2, high: 0 };

        mint(starkway_address, non_native_erc20_address, user, amount1);
        set_contract_address(admin_1);
        starkway.set_is_withdraw_allowed(non_native_erc20_address, true);
        set_contract_address(user);
        let calculated_fee = starkway.calculate_fee(l1_token_address, amount2);

        let erc20 = IERC20Dispatcher { contract_address: non_native_erc20_address };

        erc20.approve(starkway_address, amount2 + fee);
        starkway.withdraw(non_native_erc20_address, l1_token_address, l1_recipient, amount2, fee);
    }

    #[test]
    #[available_gas(20000000)]
    fn test_non_native_withdrawal() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();

        let l1_token_address = EthAddress { address: 100_felt252 };
        let l1_recipient = EthAddress { address: 200_felt252 };
        init_token(starkway_address, admin_1, l1_token_address);

        let starkway = IStarkwayDispatcher { contract_address: starkway_address };

        let native_erc20_address = starkway.get_native_token_address(l1_token_address);

        let mut erc20_calldata = ArrayTrait::<felt252>::new();
        let name = 'TEST_TOKEN2';
        let symbol = 'TEST2';
        let decimals = 18_u8;
        let owner = starkway_address;

        name.serialize(ref erc20_calldata);
        symbol.serialize(ref erc20_calldata);
        decimals.serialize(ref erc20_calldata);
        owner.serialize(ref erc20_calldata);
        let non_native_erc20_address = deploy(StarkwayERC20::TEST_CLASS_HASH, 100, erc20_calldata);

        let starkway = IStarkwayDispatcher { contract_address: starkway_address };

        let user = contract_address_const::<30>();
        let amount1 = u256 { low: 1000, high: 0 };
        let amount2 = u256 { low: 100, high: 0 };
        let fee = u256 { low: 2, high: 0 };

        mint(starkway_address, non_native_erc20_address, user, amount1);

        // Register dummy adapter
        let bridge_adapter_address = register_bridge_adapter(starkway_address, admin_1);

        // Whitelist token
        whitelist_token(
            starkway_address,
            admin_1,
            1_u16,
            contract_address_const::<400>(),
            l1_token_address,
            non_native_erc20_address
        );

        set_contract_address(user);
        let calculated_fee = starkway.calculate_fee(l1_token_address, amount2);

        let erc20 = IERC20Dispatcher { contract_address: non_native_erc20_address };

        let balance_user_before = erc20.balance_of(user);
        let balance_starkway_before = erc20.balance_of(starkway_address);
        let balance_adapter_before = erc20.balance_of(bridge_adapter_address);

        erc20.approve(starkway_address, amount2 + fee);
        starkway.withdraw(non_native_erc20_address, l1_token_address, l1_recipient, amount2, fee);

        let balance_user_after = erc20.balance_of(user);
        let balance_starkway_after = erc20.balance_of(starkway_address);
        let balance_adapter_after = erc20.balance_of(bridge_adapter_address);

        assert(balance_user_before == balance_user_after + amount2 + fee, 'Incorrect user balance');
        assert(
            balance_starkway_before == balance_starkway_after - fee, 'Incorrect Starkway balance'
        );

        // withdrawal_amount should be deposited with dummy adapter
        assert(
            balance_adapter_before == balance_adapter_after - amount2, 'Incorrect adapter balance'
        );
    }

    #[test]
    #[available_gas(20000000)]
    fn test_non_native_withdrawal_camel() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();

        let l1_token_address = EthAddress { address: 100_felt252 };
        let l1_recipient = EthAddress { address: 200_felt252 };
        init_token(starkway_address, admin_1, l1_token_address);

        let starkway = IStarkwayDispatcher { contract_address: starkway_address };

        let native_erc20_address = starkway.get_native_token_address(l1_token_address);

        let mut erc20_calldata = ArrayTrait::<felt252>::new();
        let name = 'TEST_TOKEN2';
        let symbol = 'TEST2';
        let decimals = 18_u8;
        let owner = starkway_address;

        name.serialize(ref erc20_calldata);
        symbol.serialize(ref erc20_calldata);
        decimals.serialize(ref erc20_calldata);
        owner.serialize(ref erc20_calldata);
        let non_native_erc20_address = deploy(StarkwayERC20::TEST_CLASS_HASH, 100, erc20_calldata);

        let starkway = IStarkwayDispatcher { contract_address: starkway_address };

        let user = contract_address_const::<30>();
        let amount1 = u256 { low: 1000, high: 0 };
        let amount2 = u256 { low: 100, high: 0 };
        let fee = u256 { low: 2, high: 0 };

        mint(starkway_address, non_native_erc20_address, user, amount1);

        // Register dummy adapter
        let bridge_adapter_address = register_bridge_adapter(starkway_address, admin_1);

        // Whitelist token
        whitelist_token_camelCase(
            starkway_address,
            admin_1,
            1_u16,
            contract_address_const::<400>(),
            l1_token_address,
            non_native_erc20_address
        );

        set_contract_address(user);
        let calculated_fee = starkway.calculate_fee(l1_token_address, amount2);

        let erc20 = IERC20Dispatcher { contract_address: non_native_erc20_address };

        let balance_user_before = erc20.balance_of(user);
        let balance_starkway_before = erc20.balance_of(starkway_address);
        let balance_adapter_before = erc20.balance_of(bridge_adapter_address);

        erc20.approve(starkway_address, amount2 + fee);
        starkway.withdraw(non_native_erc20_address, l1_token_address, l1_recipient, amount2, fee);

        let balance_user_after = erc20.balance_of(user);
        let balance_starkway_after = erc20.balance_of(starkway_address);
        let balance_adapter_after = erc20.balance_of(bridge_adapter_address);

        assert(balance_user_before == balance_user_after + amount2 + fee, 'Incorrect user balance');
        assert(
            balance_starkway_before == balance_starkway_after - fee, 'Incorrect Starkway balance'
        );

        // withdrawal_amount should be deposited with dummy adapter
        assert(
            balance_adapter_before == balance_adapter_after - amount2, 'Incorrect adapter balance'
        );
    }
}
