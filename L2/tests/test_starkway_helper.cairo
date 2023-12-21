#[cfg(test)]
mod test_starkway_helper {
    use array::{Array, ArrayTrait, Span, SpanTrait};
    use serde::Serde;
    use starknet::{ContractAddress, contract_address_const, EthAddress};
    use starknet::testing::{set_caller_address, set_contract_address, pop_log};
    use traits::{Default, Into, TryInto};
    use starkway::datatypes::{L1TokenDetails, WithdrawalRange, L2TokenDetails};
    use starkway::erc20::erc20::StarkwayERC20;
    use starkway::interfaces::{
        IStarkwayDispatcher, IStarkwayDispatcherTrait, IStarkwayHelperDispatcher,
        IStarkwayHelperDispatcherTrait
    };
    use starkway::libraries::reentrancy_guard::ReentrancyGuard;
    use starkway::libraries::fee_library::fee_library;
    use starkway::starkway::Starkway;
    use starkway::starkway_helper::StarkwayHelper;
    use zeroable::Zeroable;
    use tests::utils::{
        setup, deploy, mint, init_token, register_bridge_adapter, deploy_non_native_token,
        whitelist_token
    };
    use tests::utils::DummyAdapter;

    // Mock user in our system
    fn USER1() -> ContractAddress {
        contract_address_const::<3>()
    }

    fn deploy_starkway_helper() -> (
        ContractAddress, ContractAddress, ContractAddress, ContractAddress
    ) {
        let (starkway_address, admin_auth_address, admin_1, admin_2) = setup();

        // Deploy Starkway helper contract
        let mut calldata = ArrayTrait::<felt252>::new();
        starkway_address.serialize(ref calldata);
        let starkway_helper_address = deploy(StarkwayHelper::TEST_CLASS_HASH, 100, calldata);
        return (starkway_address, starkway_helper_address, admin_1, admin_2);
    }

    #[test]
    #[available_gas(20000000)]
    fn test_get_supported_tokens() {
        let (starkway_address, starkway_helper_address, admin_1, admin_2) =
            deploy_starkway_helper();
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };
        let starkway_helper = IStarkwayHelperDispatcher {
            contract_address: starkway_helper_address
        };

        // Set admin_1 as default caller
        set_contract_address(admin_1);

        // Initialising 1st token
        let l1_token_address = EthAddress { address: 100_felt252 };
        let l1_token_details = L1TokenDetails {
            name: 'TEST_TOKEN', symbol: 'TEST', decimals: 18_u8
        };
        starkway.authorised_init_token(l1_token_address, l1_token_details);

        // Fetch native ERC20 address
        let native_erc20_address = starkway.get_native_token_address(l1_token_address);

        // Function to get list of all L1 tokens
        let supported_tokens = starkway_helper.get_supported_tokens();
        assert(*supported_tokens.at(0).name == 'TEST_TOKEN', 'Mismatch in token name');
        assert(*supported_tokens.at(0).symbol == 'TEST', 'Mismatch in token symbol');
        assert(*supported_tokens.at(0).decimals == 18_u8, 'Mismatch in token decimals');
        assert(*supported_tokens.at(0).l1_address == l1_token_address, 'Mismatch in the L1 token');
        assert(
            *supported_tokens.at(0).native_l2_address == native_erc20_address,
            'Mismatch in the L2 address'
        );

        // Set admin_1 as default caller
        set_contract_address(admin_1);

        // Initialising 2nd token
        let l1_token_address2 = EthAddress { address: 101_felt252 };
        let l1_token_details = L1TokenDetails {
            name: 'TEST_TOKEN2', symbol: 'TEST2', decimals: 18_u8
        };
        starkway.authorised_init_token(l1_token_address2, l1_token_details);

        // Fetch native ERC20 address
        let native_erc20_address2 = starkway.get_native_token_address(l1_token_address2);

        // Function to get list of all L1 tokens
        let supported_tokens = starkway_helper.get_supported_tokens();
        assert(*supported_tokens.at(0).name == 'TEST_TOKEN', 'Mismatch in token name');
        assert(*supported_tokens.at(0).symbol == 'TEST', 'Mismatch in token symbol');
        assert(*supported_tokens.at(0).decimals == 18_u8, 'Mismatch in token decimals');
        assert(*supported_tokens.at(0).l1_address == l1_token_address, 'Mismatch in the L1 token');
        assert(
            *supported_tokens.at(0).native_l2_address == native_erc20_address,
            'Mismatch in the L2 address'
        );
        assert(*supported_tokens.at(1).name == 'TEST_TOKEN2', 'Mismatch in token name');
        assert(*supported_tokens.at(1).symbol == 'TEST2', 'Mismatch in token symbol');
        assert(*supported_tokens.at(1).decimals == 18_u8, 'Mismatch in token decimals');
        assert(*supported_tokens.at(1).l1_address == l1_token_address2, 'Mismatch in the L1 token');
        assert(
            *supported_tokens.at(1).native_l2_address == native_erc20_address2,
            'Mismatch in the L2 address'
        );
    }

    #[test]
    #[available_gas(20000000)]
    fn test_get_non_native_token_balances() {
        let (starkway_address, starkway_helper_address, admin_1, admin_2) =
            deploy_starkway_helper();
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };
        let starkway_helper = IStarkwayHelperDispatcher {
            contract_address: starkway_helper_address
        };

        let l1_token_address = EthAddress { address: 100_felt252 };
        init_token(starkway_address, admin_1, l1_token_address);

        // Fetch native ERC20 address
        let native_erc20_address = starkway.get_native_token_address(l1_token_address);

        // Deploy 1st non native erc20 contract
        let non_native_erc20_address1 = deploy_non_native_token(starkway_address, 200);

        // Mint 10000 tokens
        mint(starkway_address, non_native_erc20_address1, USER1(), u256 { low: 10000, high: 0 });

        // Register dummy adapter
        let bridge_adapter_address = register_bridge_adapter(starkway_address, admin_1);

        // Whitelist token
        whitelist_token(
            starkway_address,
            admin_1,
            1_u16,
            contract_address_const::<400>(),
            l1_token_address,
            non_native_erc20_address1
        );

        // Get non native token balance
        let non_native_token_balances = starkway_helper
            .get_non_native_token_balances(USER1(), l1_token_address);
        assert(*non_native_token_balances.at(0).name == 'TEST_TOKEN', 'Mismatch in token name');
        assert(*non_native_token_balances.at(0).symbol == 'TEST', 'Mismatch in token symbol');
        assert(*non_native_token_balances.at(0).decimals == 18_u8, 'Mismatch in token decimals');
        assert(
            *non_native_token_balances.at(0).balance == u256 { low: 10000, high: 0 },
            'Mismatch in token balance'
        );
        assert(
            *non_native_token_balances.at(0).l1_address == l1_token_address,
            'Mismatch in the L1 token'
        );
        assert(
            *non_native_token_balances.at(0).l2_address == non_native_erc20_address1,
            'Mismatch in the L2 token'
        );
        assert(
            *non_native_token_balances.at(0).native_l2_address == native_erc20_address,
            'Mismatch in the native L2 addr'
        );

        // Deploy 2nd non native erc20 contract
        let mut erc20_calldata = ArrayTrait::<felt252>::new();
        let name = 'TEST_TOKEN3';
        let symbol = 'TEST3';
        let decimals = 18_u8;
        let owner = starkway_address;

        name.serialize(ref erc20_calldata);
        symbol.serialize(ref erc20_calldata);
        decimals.serialize(ref erc20_calldata);
        owner.serialize(ref erc20_calldata);
        let non_native_erc20_address2 = deploy(StarkwayERC20::TEST_CLASS_HASH, 300, erc20_calldata);

        // Mint 5000 tokens
        mint(starkway_address, non_native_erc20_address2, USER1(), u256 { low: 5000, high: 0 });

        // Register dummy adapter
        let mut calldata = ArrayTrait::<felt252>::new();
        let adapter_address = deploy(DummyAdapter::TEST_CLASS_HASH, 100, calldata);

        set_contract_address(admin_1);
        starkway.register_bridge_adapter(2_u16, 'ADAPTER2', adapter_address);

        // Whitelist token
        whitelist_token(
            starkway_address,
            admin_1,
            1_u16,
            contract_address_const::<400>(),
            l1_token_address,
            non_native_erc20_address2
        );

        // Get non native token balance
        let non_native_token_balances = starkway_helper
            .get_non_native_token_balances(USER1(), l1_token_address);
        assert(*non_native_token_balances.at(0).name == 'TEST_TOKEN', 'Mismatch in token name');
        assert(*non_native_token_balances.at(0).symbol == 'TEST', 'Mismatch in token symbol');
        assert(*non_native_token_balances.at(0).decimals == 18_u8, 'Mismatch in token decimals');
        assert(
            *non_native_token_balances.at(0).balance == u256 { low: 10000, high: 0 },
            'Mismatch in token balance'
        );
        assert(
            *non_native_token_balances.at(0).l1_address == l1_token_address,
            'Mismatch in the L1 token'
        );
        assert(
            *non_native_token_balances.at(0).l2_address == non_native_erc20_address1,
            'Mismatch in the L2 token'
        );
        assert(
            *non_native_token_balances.at(0).native_l2_address == native_erc20_address,
            'Mismatch in the native L2 addr'
        );
        assert(*non_native_token_balances.at(1).name == 'TEST_TOKEN', 'Mismatch in token name');
        assert(*non_native_token_balances.at(1).symbol == 'TEST', 'Mismatch in token symbol');
        assert(*non_native_token_balances.at(1).decimals == 18_u8, 'Mismatch in token decimals');
        assert(
            *non_native_token_balances.at(1).balance == u256 { low: 5000, high: 0 },
            'Mismatch in token balance'
        );
        assert(
            *non_native_token_balances.at(1).l1_address == l1_token_address,
            'Mismatch in the L1 token'
        );
        assert(
            *non_native_token_balances.at(1).l2_address == non_native_erc20_address2,
            'Mismatch in the L2 token'
        );
        assert(
            *non_native_token_balances.at(1).native_l2_address == native_erc20_address,
            'Mismatch in the native L2 addr'
        );
    }

    #[test]
    #[available_gas(20000000)]
    fn test_get_supported_tokens_with_balance() {
        let (starkway_address, starkway_helper_address, admin_1, admin_2) =
            deploy_starkway_helper();
        let starkway = IStarkwayDispatcher { contract_address: starkway_address };
        let starkway_helper = IStarkwayHelperDispatcher {
            contract_address: starkway_helper_address
        };

        let l1_token_address = EthAddress { address: 100_felt252 };
        init_token(starkway_address, admin_1, l1_token_address);

        // Fetch native ERC20 address
        let native_erc20_address = starkway.get_native_token_address(l1_token_address);

        // Function to get list of all L1 tokens
        let supported_tokens = starkway_helper.get_supported_tokens();
        assert(*supported_tokens.at(0).name == 'TEST_TOKEN', 'Mismatch in token name');
        assert(*supported_tokens.at(0).symbol == 'TEST', 'Mismatch in token symbol');
        assert(*supported_tokens.at(0).decimals == 18_u8, 'Mismatch in token decimals');
        assert(*supported_tokens.at(0).l1_address == l1_token_address, 'Mismatch in the L1 token');
        assert(
            *supported_tokens.at(0).native_l2_address == native_erc20_address,
            'Mismatch in the L2 address'
        );

        // Mint 1000 native ERC20 tokens to user
        mint(starkway_address, native_erc20_address, USER1(), u256 { low: 1000, high: 0 });

        // get_supported_tokens_with_balance
        let non_native_token_balances = starkway_helper.get_supported_tokens_with_balance(USER1());
        assert(*non_native_token_balances.at(0).name == 'TEST_TOKEN', 'Mismatch in token name');
        assert(*non_native_token_balances.at(0).symbol == 'TEST', 'Mismatch in token symbol');
        assert(*non_native_token_balances.at(0).decimals == 18_u8, 'Mismatch in token decimals');
        assert(
            *non_native_token_balances.at(0).balance == u256 { low: 1000, high: 0 },
            'Mismatch in token balance'
        );
        assert(
            *non_native_token_balances.at(0).l1_address == l1_token_address,
            'Mismatch in the L1 token'
        );
        assert(
            *non_native_token_balances.at(0).l2_address == native_erc20_address,
            'Mismatch in the L2 token'
        );
        assert(
            *non_native_token_balances.at(0).native_l2_address == native_erc20_address,
            'Mismatch in the native L2 addr'
        );

        // Deploy 1st non native erc20 contract
        let non_native_erc20_address1 = deploy_non_native_token(starkway_address, 200);

        // Mint 10000 Non native ERC20 tokens
        mint(starkway_address, non_native_erc20_address1, USER1(), u256 { low: 10000, high: 0 });

        // Register dummy adapter
        let bridge_adapter_address = register_bridge_adapter(starkway_address, admin_1);

        // Whitelist token
        whitelist_token(
            starkway_address,
            admin_1,
            1_u16,
            contract_address_const::<400>(),
            l1_token_address,
            non_native_erc20_address1
        );

        // get_supported_tokens_with_balance
        let non_native_token_balances = starkway_helper.get_supported_tokens_with_balance(USER1());
        assert(*non_native_token_balances.at(0).name == 'TEST_TOKEN', 'Mismatch in token name');
        assert(*non_native_token_balances.at(0).symbol == 'TEST', 'Mismatch in token symbol');
        assert(*non_native_token_balances.at(0).decimals == 18_u8, 'Mismatch in token decimals');
        assert(
            *non_native_token_balances.at(0).balance == u256 { low: 1000, high: 0 },
            'Mismatch in token balance'
        );
        assert(
            *non_native_token_balances.at(0).l1_address == l1_token_address,
            'Mismatch in the L1 token'
        );
        assert(
            *non_native_token_balances.at(0).l2_address == native_erc20_address,
            'Mismatch in the L2 token'
        );
        assert(
            *non_native_token_balances.at(0).native_l2_address == native_erc20_address,
            'Mismatch in the native L2 addr'
        );
        assert(*non_native_token_balances.at(1).name == 'TEST_TOKEN', 'Mismatch in token name');
        assert(*non_native_token_balances.at(1).symbol == 'TEST', 'Mismatch in token symbol');
        assert(*non_native_token_balances.at(1).decimals == 18_u8, 'Mismatch in token decimals');
        assert(
            *non_native_token_balances.at(1).balance == u256 { low: 10000, high: 0 },
            'Mismatch in token balance'
        );
        assert(
            *non_native_token_balances.at(1).l1_address == l1_token_address,
            'Mismatch in the L1 token'
        );
        assert(
            *non_native_token_balances.at(1).l2_address == non_native_erc20_address1,
            'Mismatch in the L2 token'
        );
        assert(
            *non_native_token_balances.at(1).native_l2_address == native_erc20_address,
            'Mismatch in the native L2 addr'
        );

        // Deploy 2nd non native erc20 contract
        let mut erc20_calldata = ArrayTrait::<felt252>::new();
        let name = 'TEST_TOKEN3';
        let symbol = 'TEST3';
        let decimals = 18_u8;
        let owner = starkway_address;

        name.serialize(ref erc20_calldata);
        symbol.serialize(ref erc20_calldata);
        decimals.serialize(ref erc20_calldata);
        owner.serialize(ref erc20_calldata);
        let non_native_erc20_address2 = deploy(StarkwayERC20::TEST_CLASS_HASH, 300, erc20_calldata);

        // Mint 5000 tokens
        mint(starkway_address, non_native_erc20_address2, USER1(), u256 { low: 5000, high: 0 });

        // Register dummy adapter
        let mut calldata = ArrayTrait::<felt252>::new();
        let adapter_address = deploy(DummyAdapter::TEST_CLASS_HASH, 100, calldata);

        set_contract_address(admin_1);
        starkway.register_bridge_adapter(2_u16, 'ADAPTER2', adapter_address);

        // Whitelist token
        whitelist_token(
            starkway_address,
            admin_1,
            1_u16,
            contract_address_const::<400>(),
            l1_token_address,
            non_native_erc20_address2
        );

        // get_supported_tokens_with_balance
        let non_native_token_balances = starkway_helper.get_supported_tokens_with_balance(USER1());
        assert(*non_native_token_balances.at(0).name == 'TEST_TOKEN', 'Mismatch in token name');
        assert(*non_native_token_balances.at(0).symbol == 'TEST', 'Mismatch in token symbol');
        assert(*non_native_token_balances.at(0).decimals == 18_u8, 'Mismatch in token decimals');
        assert(
            *non_native_token_balances.at(0).balance == u256 { low: 1000, high: 0 },
            'Mismatch in token balance'
        );
        assert(
            *non_native_token_balances.at(0).l1_address == l1_token_address,
            'Mismatch in the L1 token'
        );
        assert(
            *non_native_token_balances.at(0).l2_address == native_erc20_address,
            'Mismatch in the L2 token'
        );
        assert(
            *non_native_token_balances.at(0).native_l2_address == native_erc20_address,
            'Mismatch in the native L2 addr'
        );
        assert(*non_native_token_balances.at(1).name == 'TEST_TOKEN', 'Mismatch in token name');
        assert(*non_native_token_balances.at(1).symbol == 'TEST', 'Mismatch in token symbol');
        assert(*non_native_token_balances.at(1).decimals == 18_u8, 'Mismatch in token decimals');
        assert(
            *non_native_token_balances.at(1).balance == u256 { low: 10000, high: 0 },
            'Mismatch in token balance'
        );
        assert(
            *non_native_token_balances.at(1).l1_address == l1_token_address,
            'Mismatch in the L1 token'
        );
        assert(
            *non_native_token_balances.at(1).l2_address == non_native_erc20_address1,
            'Mismatch in the L2 token'
        );
        assert(
            *non_native_token_balances.at(1).native_l2_address == native_erc20_address,
            'Mismatch in the native L2 addr'
        );
        assert(*non_native_token_balances.at(2).name == 'TEST_TOKEN', 'Mismatch in token name');
        assert(*non_native_token_balances.at(2).symbol == 'TEST', 'Mismatch in token symbol');
        assert(*non_native_token_balances.at(2).decimals == 18_u8, 'Mismatch in token decimals');
        assert(
            *non_native_token_balances.at(2).balance == u256 { low: 5000, high: 0 },
            'Mismatch in token balance'
        );
        assert(
            *non_native_token_balances.at(2).l1_address == l1_token_address,
            'Mismatch in the L1 token'
        );
        assert(
            *non_native_token_balances.at(2).l2_address == non_native_erc20_address2,
            'Mismatch in the L2 token'
        );
        assert(
            *non_native_token_balances.at(2).native_l2_address == native_erc20_address,
            'Mismatch in the native L2 addr'
        );
    }
}
