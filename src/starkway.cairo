#[contract]
mod Starkway {
    use array::{Array, Span, ArrayTrait};
    use core::hash::LegacyHashFelt252;
    use core::result::ResultTrait;
    use starknet::{
        ContractAddress, class_hash::ClassHash, class_hash::ClassHashZeroable,
        contract_address::ContractAddressZeroable, get_caller_address, get_contract_address
    };
    use starknet::syscalls::{emit_event_syscall, deploy_syscall};
    use traits::{Into, TryInto};
    use zeroable::Zeroable;

    use starkway::datatypes::{
        l1_token_details::L1TokenDetails, l2_token_details::L2TokenDetails,
        l1_token_details::StorageAccessL1TokenDetails,
        l2_token_details::StorageAccessL2TokenDetails, l1_address::L1Address,
    };
    use starkway::interfaces::{
        IAdminAuthDispatcher, IAdminAuthDispatcherTrait, IStarkwayERC20Dispatcher,
        IStarkwayERC20DispatcherTrait
    };
    use starkway::utils::helpers::is_in_range;
    use core::integer::u256;

    struct Storage {
        s_l1_starkway_address: L1Address,
        s_l1_starkway_vault_address: L1Address,
        s_admin_auth_address: ContractAddress,
        s_fee_address: ContractAddress,
        s_ERC20_class_hash: ClassHash,
        s_l1_token_details: LegacyMap::<L1Address, L1TokenDetails>,
        s_total_fee_collected: LegacyMap::<L1Address, u256>,
        s_fee_withdrawn: LegacyMap::<L1Address, u256>,
        s_bridge_existence_by_id: LegacyMap::<u16, bool>,
        s_bridge_name_by_id: LegacyMap::<u16, felt252>,
        s_bridge_adapter_by_id: LegacyMap::<u16, ContractAddress>,
        s_supported_tokens_length: u32,
        s_supported_tokens: LegacyMap::<u32, L1Address>,
        s_whitelisted_token_l2_address_length: LegacyMap::<L1Address, u32>,
        s_whitelisted_token_l2_address: LegacyMap::<(L1Address, u32), ContractAddress>,
        s_whitelisted_token_details: LegacyMap::<ContractAddress, L2TokenDetails>,
        s_native_token_l2_address: LegacyMap::<L1Address, ContractAddress>,
        // s_withdrawal_ranges: LegacyMap::<felt252, WithdrawalRange>, Currently not present in alpha 6
        s_deploy_nonce: u128,
    }

    /////////////////
    // Constructor //
    /////////////////

    #[constructor]
    fn constructor(
        admin_auth_contract_address: ContractAddress,
        fee_rate_default: u256,
        erc20_contract_hash: ClassHash
    ) {
        assert(admin_auth_contract_address.is_non_zero(), 'Starkway: Address is zero');
        assert(erc20_contract_hash.is_non_zero(), 'Starkway: Class hash is zero');

        s_admin_auth_address::write(admin_auth_contract_address);
        s_ERC20_class_hash::write(erc20_contract_hash);
    // set fee rate once implemented
    }

    //////////
    // View //
    //////////

    #[view]
    fn get_l1_starkway_address() -> L1Address {
        s_l1_starkway_address::read()
    }

    #[view]
    fn get_l1_starkway_vault_address() -> L1Address {
        s_l1_starkway_vault_address::read()
    }

    #[view]
    fn get_admin_auth_address() -> ContractAddress {
        s_admin_auth_address::read()
    }

    #[view]
    fn get_class_hash() -> ClassHash {
        s_ERC20_class_hash::read()
    }

    #[view]
    fn get_native_token_address(l1_token_address: L1Address) -> ContractAddress {
        s_native_token_l2_address::read(l1_token_address)
    }

    #[view]
    fn get_l1_token_details(l1_token_address: L1Address) -> L1TokenDetails {
        s_l1_token_details::read(l1_token_address)
    }

    #[view]
    fn get_whitelisted_token_details(l2_address: ContractAddress) -> L2TokenDetails {
        s_whitelisted_token_details::read(l2_address)
    }

    #[view]
    fn get_supported_tokens() -> Array<L1Address> {
        let mut supported_tokens = ArrayTrait::new();
        let len = s_supported_tokens_length::read();
        let mut counter = 0_u32;
        loop {
            if counter == len {
                break ();
            }
            supported_tokens.append(s_supported_tokens::read(counter));
            counter += 1;
        };
        supported_tokens
    }

    #[view]
    fn get_whitelisted_token_addresses(l1_token_address: L1Address) -> Array<ContractAddress> {
        let mut whitelisted_tokens = ArrayTrait::new();
        let len = s_whitelisted_token_l2_address_length::read(l1_token_address);
        let mut counter = 0_u32;
        loop {
            if counter == len {
                break ();
            }
            whitelisted_tokens.append(
                s_whitelisted_token_l2_address::read((l1_token_address, counter))
            );
            counter += 1;
        };
        whitelisted_tokens
    }

    ////////////////
    // L1 Handler //
    ////////////////

    #[l1_handler]
    fn initialize_token(
        from_address: felt252, l1_token_address: L1Address, token_details: L1TokenDetails
    ) {
        verify_msg_is_from_starkway(from_address);

        init_token(l1_token_address, token_details);
    }

    #[l1_handler]
    fn deposit(
        from_address: felt252,
        l1_token_address: L1Address,
        sender_l1_address: L1Address,
        recipient_address: ContractAddress,
        amount: u256,
        fee: u256
    ) {
        verify_msg_is_from_starkway(from_address);

        process_deposit(l1_token_address, sender_l1_address, recipient_address, amount, fee);
    }

    //////////////
    // External //
    //////////////

    #[external]
    fn set_l1_starkway_address(l1_address: L1Address) {
        verify_caller_is_admin();
        s_l1_starkway_address::write(l1_address);
    }

    #[external]
    fn set_l1_starkway_vault_address(l1_address: L1Address) {
        verify_caller_is_admin();
        let current_address: L1Address = s_l1_starkway_vault_address::read();
        assert(current_address.value == 0, 'Starkway: Vault already set');
        s_l1_starkway_vault_address::write(l1_address);
    }

    #[external]
    fn set_admin_auth_address(admin_auth_address: ContractAddress) {
        verify_caller_is_admin();
        s_admin_auth_address::write(admin_auth_address);
    }

    #[external]
    fn set_class_hash(class_hash: ClassHash) {
        verify_caller_is_admin();
        s_ERC20_class_hash::write(class_hash);
    }

    #[external]
    fn register_bridge(
        bridge_id: u16, bridge_name: felt252, bridge_adapter_address: ContractAddress
    ) {
        verify_caller_is_admin();
        assert(
            s_bridge_existence_by_id::read(bridge_id) == false, 'Starkway: Bridge already exists'
        );
        assert(bridge_id > 0_u16, 'Starkway: Bridge id not valid');
        assert(bridge_adapter_address.is_non_zero(), 'Starkway: Adapter address is 0');
        assert(bridge_name != 0, 'Starkway: Bridge name not valid');
        s_bridge_existence_by_id::write(bridge_id, true);
        s_bridge_name_by_id::write(bridge_id, bridge_name);
        s_bridge_adapter_by_id::write(bridge_id, bridge_adapter_address);
    }

    //////////////
    // Internal //
    //////////////

    #[internal]
    fn verify_caller_is_admin() {
        let admin_auth_address: ContractAddress = s_admin_auth_address::read();
        let caller: ContractAddress = get_caller_address();
        let is_admin = IAdminAuthDispatcher {
            contract_address: admin_auth_address
        }.get_is_allowed(caller);
        assert(is_admin == true, 'Starkway: Caller not admin');
    }

    #[internal]
    fn verify_msg_is_from_starkway(from_address: felt252) {
        let l1_starkway_address = s_l1_starkway_address::read();
        assert(l1_starkway_address.value == from_address, 'Starkway: Invalid l1 address');
    }

    #[internal]
    fn init_token(l1_token_address: L1Address, token_details: L1TokenDetails) {
        let native_address: ContractAddress = s_native_token_l2_address::read(l1_token_address);
        assert(native_address.is_zero(), 'Starkway: Native token present');

        let class_hash: ClassHash = s_ERC20_class_hash::read();
        assert(class_hash.is_non_zero(), 'Starkway: Class hash is 0');

        assert(token_details.name != 0, 'Starkway: Name is 0');
        assert(token_details.symbol != 0, 'Starkway: Symbol is 0');

        let res: bool = is_in_range(token_details.decimals, 1_u8, 18_u8);
        assert(res == true, 'Starkway: Decimals not valid');

        let nonce = s_deploy_nonce::read();
        s_deploy_nonce::write(nonce + 1);

        let starkway_address: ContractAddress = get_contract_address();
        let mut calldata = ArrayTrait::new();
        calldata.append(token_details.name);
        calldata.append(token_details.symbol);
        calldata.append(token_details.decimals.into());
        calldata.append(starkway_address.into());
        let calldata_span = calldata.span();

        let (contract_address, _) = deploy_syscall(
            class_hash, nonce.into(), calldata_span, false
        ).unwrap();

        s_native_token_l2_address::write(l1_token_address, contract_address);
        s_l1_token_details::write(l1_token_address, token_details);

        let current_len = s_supported_tokens_length::read();
        s_supported_tokens_length::write(current_len + 1);
        s_supported_tokens::write(current_len, l1_token_address);

        let mut keys = ArrayTrait::new();
        keys.append(l1_token_address.into());
        keys.append(token_details.name);
        keys.append('initialise');
        let mut data = ArrayTrait::new();
        data.append(contract_address.into());

        emit_event_syscall(keys.span(), data.span());
    }

    #[internal]
    fn process_deposit(
        l1_token_address: L1Address,
        sender_l1_address: L1Address,
        recipient_address: ContractAddress,
        amount: u256,
        fee: u256
    ) -> ContractAddress {
        assert(recipient_address.is_non_zero(), 'Starkway: Invalid recipient');

        let native_token_address = s_native_token_l2_address::read(l1_token_address);
        assert(native_token_address.is_non_zero(), 'Starkway: Token uninitialized');

        IStarkwayERC20Dispatcher {
            contract_address: native_token_address
        }.mint(recipient_address, amount);

        let starkway_address: ContractAddress = get_contract_address();
        IStarkwayERC20Dispatcher {
            contract_address: native_token_address
        }.mint(starkway_address, fee);

        let current_collected_fee: u256 = s_total_fee_collected::read(l1_token_address);
        s_total_fee_collected::write(l1_token_address, current_collected_fee + fee);

        let mut keys = ArrayTrait::new();
        keys.append(sender_l1_address.value);
        keys.append(recipient_address.into());
        let hash_value = LegacyHashFelt252::hash(sender_l1_address.value, recipient_address.into());
        keys.append(hash_value);
        keys.append('deposit');
        let mut data = ArrayTrait::new();
        data.append(amount.low.into());
        data.append(amount.high.into());
        data.append(fee.low.into());
        data.append(fee.high.into());
        data.append(l1_token_address.value);
        data.append(native_token_address.into());

        emit_event_syscall(keys.span(), data.span());
        return native_token_address;
    }
}
