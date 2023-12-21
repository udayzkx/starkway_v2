#[cfg(test)]
mod test_authorised_init_token {
    use array::{Array, ArrayTrait, Span, SpanTrait};
    use option::OptionTrait;
    use serde::Serde;
    use starknet::{ContractAddress, contract_address_const, EthAddress, class_hash_const};
    use starknet::testing::{set_caller_address, set_contract_address, pop_log_raw};
    use traits::{Default, Into, TryInto};

    use starkway::datatypes::L1TokenDetails;
    use starkway::interfaces::{IStarkwayDispatcher, IStarkwayDispatcherTrait, };
    use starkway::starkway::Starkway;
    use zeroable::Zeroable;
    use tests::utils::{setup, deploy, init_token, };

    // Mock user in our system
    fn USER1() -> ContractAddress {
        contract_address_const::<3>()
    }

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
    #[should_panic(expected: ('SW: Caller not admin', 'ENTRYPOINT_FAILED', ))]
    fn test_init_with_unauthorized_user() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };

        // set non admin as the caller
        set_contract_address(USER1());

        let l1_token_address = EthAddress { address: 100_felt252 };
        let l1_token_details = L1TokenDetails {
            name: 'TEST_TOKEN', symbol: 'TEST', decimals: 18_u8
        };
        starkway.authorised_init_token(l1_token_address, l1_token_details);
    }

    #[test]
    #[available_gas(20000000)]
    #[should_panic(expected: ('SW: Class hash is 0', 'ENTRYPOINT_FAILED', ))]
    fn test_init_with_zero_erc20_class_hash() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };

        let l1_token_address = EthAddress { address: 100_felt252 };
        // Declaring L1 token details with zero token name
        let l1_token_details = L1TokenDetails { name: 0_felt252, symbol: 'TEST', decimals: 18_u8 };

        // Set zero erc20 class hash
        starkway.set_erc20_class_hash(class_hash_const::<0>());
        starkway.authorised_init_token(l1_token_address, l1_token_details);
    }

    #[test]
    #[available_gas(20000000)]
    #[should_panic(expected: ('SW: Name is 0', 'ENTRYPOINT_FAILED', ))]
    fn test_init_with_zero_token_name() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };

        let l1_token_address = EthAddress { address: 100_felt252 };
        // Declaring L1 token details with zero token name
        let l1_token_details = L1TokenDetails { name: 0_felt252, symbol: 'TEST', decimals: 18_u8 };
        starkway.authorised_init_token(l1_token_address, l1_token_details);
    }

    #[test]
    #[available_gas(20000000)]
    #[should_panic(expected: ('SW: Symbol is 0', 'ENTRYPOINT_FAILED', ))]
    fn test_init_with_zero_token_symbol() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };

        let l1_token_address = EthAddress { address: 100_felt252 };
        // Declaring L1 token details with zero token symbol
        let l1_token_details = L1TokenDetails {
            name: 'TEST_TOKEN', symbol: 0_felt252, decimals: 18_u8
        };
        starkway.authorised_init_token(l1_token_address, l1_token_details);
    }

    #[test]
    #[available_gas(20000000)]
    #[should_panic(expected: ('SW: Decimals not valid', 'ENTRYPOINT_FAILED', ))]
    fn test_init_with_invalid_decimal_range() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };

        let l1_token_address = EthAddress { address: 100_felt252 };
        // Declaring L1 token details with invalid decimal range
        let l1_token_details = L1TokenDetails {
            name: 'TEST_TOKEN', symbol: 'TEST', decimals: 100_u8
        };
        starkway.authorised_init_token(l1_token_address, l1_token_details);
    }

    #[test]
    #[available_gas(20000000)]
    fn test_init_token() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };
        let l1_token_address = EthAddress { address: 100_felt252 };
        init_token(starkway_address, admin_1, l1_token_address);

        // Function to get details of L1 token address
        let l1_token_details: L1TokenDetails = starkway.get_l1_token_details(l1_token_address);
        assert(l1_token_details.name == 'TEST_TOKEN', 'Mismatch in token name');
        assert(l1_token_details.symbol == 'TEST', 'Mismatch in token symbol');
        assert(l1_token_details.decimals == 18_u8, 'Mismatch in token decimals');

        // Function to get list of all L1 tokens
        let supported_tokens = starkway.get_supported_tokens();
        assert(*supported_tokens.at(0) == l1_token_address, 'Mismatch in the L1 token');

        // Function to get length of all supported L1 tokens
        let supported_tokens_length = starkway.get_supported_tokens_length();
        assert(supported_tokens_length == 1_u32, 'Mismatch in the Length');

        // Get the deployed ERC20 contract address
        let native_erc20_address = starkway.get_native_token_address(l1_token_address);

        let (keys, data) = pop_log_raw(starkway_address).unwrap();
        let mut expected_keys = ArrayTrait::<felt252>::new();
        expected_keys.append(l1_token_address.into());
        expected_keys.append('TEST_TOKEN'.into());
        expected_keys.append('INITIALIZE');

        // compare expected and actual keys
        compare(expected_keys, keys);

        let mut expected_data = ArrayTrait::<felt252>::new();
        expected_data.append(native_erc20_address.into());

        // compare expected and actual values
        compare(expected_data, data);

        // Initialising 2nd token
        let l1_token_address2 = EthAddress { address: 101_felt252 };
        let l1_token_details = L1TokenDetails {
            name: 'TEST_TOKEN2', symbol: 'TEST2', decimals: 18_u8
        };
        starkway.authorised_init_token(l1_token_address2, l1_token_details);

        // Function to get details of L1 token address
        let l1_token_details: L1TokenDetails = starkway.get_l1_token_details(l1_token_address2);
        assert(l1_token_details.name == 'TEST_TOKEN2', 'Mismatch in token name');
        assert(l1_token_details.symbol == 'TEST2', 'Mismatch in token symbol');
        assert(l1_token_details.decimals == 18_u8, 'Mismatch in token decimals');

        // Function to get list of all L1 tokens
        let supported_tokens = starkway.get_supported_tokens();
        assert(*supported_tokens.at(0) == l1_token_address, 'Mismatch in the L1 token');
        assert(*supported_tokens.at(1) == l1_token_address2, 'Mismatch in the L1 token');

        // Function to get length of all supported L1 tokens
        let supported_tokens_length = starkway.get_supported_tokens_length();
        assert(supported_tokens_length == 2_u32, 'Mismatch in the Length');
    }

    #[test]
    #[available_gas(20000000)]
    #[should_panic(expected: ('SW: Native token present', 'ENTRYPOINT_FAILED', ))]
    fn test_initialising_already_initialised_token() {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };
        let l1_token_address = EthAddress { address: 100_felt252 };
        init_token(starkway_address, admin_1, l1_token_address);

        let native_erc20_address = starkway.get_native_token_address(l1_token_address);

        let (keys, data) = pop_log_raw(starkway_address).unwrap();
        let mut expected_keys = ArrayTrait::<felt252>::new();
        expected_keys.append(l1_token_address.into());
        expected_keys.append('TEST_TOKEN'.into());
        expected_keys.append('INITIALIZE');

        // compare expected and actual keys
        compare(expected_keys, keys);

        let mut expected_data = ArrayTrait::<felt252>::new();
        expected_data.append(native_erc20_address.into());

        // compare expected and actual values
        compare(expected_data, data);

        // Calling init_token on the already initialised token
        init_token(starkway_address, admin_1, l1_token_address);
    }
}
