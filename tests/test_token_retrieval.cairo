#[cfg(test)]
mod test_token_retrieval{

    use starknet::ContractAddress;
    use starknet::contract_address_const;
    use starknet::ClassHash;
    use starknet::class_hash_const;
    use starknet::testing::set_caller_address;
    use starkway::starkway::Starkway;
    use starkway::admin_auth::AdminAuth;
    use starkway::utils::l1_address::L1Address;
    use array::{Array, Span, ArrayTrait};
   
    fn setup() {
        // Dummy class hash for erc-20 token
        let class_hash: ClassHash = class_hash_const::<12345>();
        // Dummy admin auth address
        let admin_address: ContractAddress = contract_address_const::<6789>();
        Starkway::constructor(admin_address, u256 {low:100, high:0} , class_hash);
    }

    #[test]
    #[available_gas(2000000)]
    fn test_simple_supported_retrieval() {
        setup();
        // Add 1 token to supported_tokens
        Starkway::s_supported_tokens_length::write(1_u32);
        Starkway::s_supported_tokens::write(0_u32, L1Address{value: 1});

        let supported_tokens = Starkway::get_supported_tokens();
        assert(supported_tokens.len() == 1, 'Incorrect length');
        assert(*supported_tokens.at(0) == L1Address{value: 1}, 'Incorrect Address');

        // Add another token
        Starkway::s_supported_tokens_length::write(2_u32);
        Starkway::s_supported_tokens::write(1_u32, L1Address{value: 1234});

        let supported_tokens = Starkway::get_supported_tokens();
        assert(supported_tokens.len() == 2, 'Incorrect length');
        assert(*supported_tokens.at(0) == L1Address{value: 1}, 'Incorrect Address at index 0');
        assert(*supported_tokens.at(1) == L1Address{value: 1234}, 'Incorrect Address at index 1');
    }

    #[test]
    #[available_gas(2000000)]
    fn test_simple_whitelisted_retrieval() {
        setup();

        let l1_address: L1Address = L1Address { value: 10};
        let l1_address_2: L1Address = L1Address { value: 20};
        let l2_address_1 = contract_address_const::<1>();
        let l2_address_2 = contract_address_const::<2>();
        let l2_address_3 = contract_address_const::<3>();
        // Add 1 token to whitelisted_tokens
        Starkway::s_whitelisted_token_l2_address_length::write(l1_address,1_u32);
        Starkway::s_whitelisted_token_l2_address::write((l1_address,0), l2_address_1 );

        let whitelisted_tokens = Starkway::get_whitelisted_token_addresses(l1_address);
        assert(whitelisted_tokens.len() == 1, 'Incorrect length');
        assert(*whitelisted_tokens.at(0) == l2_address_1, 'Incorrect Address');

        // Add another token
        Starkway::s_whitelisted_token_l2_address_length::write(l1_address,2_u32);
        Starkway::s_whitelisted_token_l2_address::write((l1_address,1), l2_address_2 );

        let whitelisted_tokens = Starkway::get_whitelisted_token_addresses(l1_address);
        assert(whitelisted_tokens.len() == 2, 'Incorrect length');
        assert(*whitelisted_tokens.at(0) == l2_address_1, 'Incorrect Address at index 0');
        assert(*whitelisted_tokens.at(1) == l2_address_2, 'Incorrect Address at index 1');

        // Add 1 token to whitelisted_tokens for a different L1Address
        Starkway::s_whitelisted_token_l2_address_length::write(l1_address_2,1_u32);
        Starkway::s_whitelisted_token_l2_address::write((l1_address_2,0), l2_address_3 );

        let whitelisted_tokens = Starkway::get_whitelisted_token_addresses(l1_address_2);
        assert(whitelisted_tokens.len() == 1, 'Incorrect length');
        assert(*whitelisted_tokens.at(0) == l2_address_3, 'Incorrect Address');

        // Re-check for 1st L1Address
        let whitelisted_tokens = Starkway::get_whitelisted_token_addresses(l1_address);
        assert(whitelisted_tokens.len() == 2, 'Incorrect length');
        assert(*whitelisted_tokens.at(0) == l2_address_1, 'Incorrect Address at index 0');
        assert(*whitelisted_tokens.at(1) == l2_address_2, 'Incorrect Address at index 1');
    }
}
