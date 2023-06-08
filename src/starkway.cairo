#[contract]
mod Starkway {
    use starknet::{ 
        ContractAddress,
        class_hash::ClassHash,
        class_hash::ClassHashZeroable,
        contract_address::ContractAddressZeroable,
        get_caller_address,
        get_contract_address
    };
    use debug::PrintTrait;
    use starknet::syscalls::{
        deploy_syscall,
        emit_event_syscall,
        send_message_to_l1_syscall
    };
    use traits::{Into, Default, TryInto};
    use core::result::ResultTrait;
    use core::hash::LegacyHashFelt252;
    use array::{Array, Span, ArrayTrait};
    use core::integer::u256;
    use zeroable::Zeroable;

    use starkway::datatypes::{
        l1_token_details::L1TokenDetails, l2_token_details::L2TokenDetails,
        l1_token_details::StorageAccessL1TokenDetails,
        l2_token_details::StorageAccessL2TokenDetails,
        l1_address::L1Address,
        l1_address::L1AddressTrait,
        l1_address::L1AddressTraitImpl,
        fee_range::FeeRange,
        withdrawal_range::WithdrawalRange        
    };
    use starkway::interfaces::{
        IAdminAuthDispatcher, IAdminAuthDispatcherTrait, IERC20Dispatcher, IERC20DispatcherTrait,
        IBridgeAdapterDispatcher, IBridgeAdapterDispatcherTrait,
    };
    use starkway::utils::helpers::is_in_range;
    use starkway::libraries::fee_library::fee_library::{
        get_fee_rate,
        get_fee_range,
    };

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
        s_withdrawal_ranges: LegacyMap::<L1Address, WithdrawalRange>,
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

    #[view]
    fn get_withdrawal_range(l1_token_address: L1Address) -> WithdrawalRange {
        s_withdrawal_ranges::read(l1_token_address)
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

    // @notice - Function to calculate fee for a given L1 token and withdrawal amount
    // @param l1_token_address - ERC-20 L1 contract address of the token
    // @param withdrawal_amount - withdrawal amount for which fee is to be calculated
    // @return fee - calculated fee
    #[view]
    fn calculate_fee(l1_token_address: L1Address, withdrawal_amount: u256) -> u256 {
        let fee_rate = get_fee_rate(l1_token_address, withdrawal_amount);
        let FEE_NORMALIZER = u256{low: 10000, high: 0};
        let fee = (withdrawal_amount * fee_rate)/ FEE_NORMALIZER;
        let fee_range = get_fee_range(l1_token_address);

        if(fee_range.is_set) {
            if fee < fee_range.min {
                return fee_range.min;
            }
            if fee > fee_range.max {
                return fee_range.max;
            }
        }
        return fee;
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

    #[external]
    fn withdraw(
        l2_token_address: ContractAddress,
        l1_token_address: L1Address,
        l1_recipient: L1Address,
        withdrawal_amount: u256,
        fee: u256
    ) {
        //TODO reentrancy guard

        assert(L1AddressTraitImpl::is_valid_L1_address(l1_token_address.into()), 'SW: Invalid token address');
        assert(L1AddressTraitImpl::is_valid_L1_address(l1_recipient.into()), 'SW: Invalid L1 recipient');

        // Check if token is initialized
        let native_token_address = s_native_token_l2_address::read(l1_token_address);
        assert(native_token_address.is_non_zero(), 'SW: Native token uninitialized');

        // Check withdrawal amount is within withdrawal range
        _verify_withdrawal_amount(l1_token_address, withdrawal_amount);
        
        let calculated_fee = calculate_fee(l1_token_address, withdrawal_amount);
        assert(calculated_fee == fee, 'SW: Fee mismatch');
        let total_fee_collected = s_total_fee_collected::read(l1_token_address);
        let updated_fee_collected = total_fee_collected + calculated_fee;
        s_total_fee_collected::write(l1_token_address, updated_fee_collected);

        let bridge_address: ContractAddress = get_contract_address();
        let sender: ContractAddress = get_caller_address();
        let total_amount = withdrawal_amount + fee;

        // Transfer withdrawal_amount + fee to bridge
        IERC20Dispatcher{contract_address: l2_token_address}.transfer_from(sender, bridge_address, total_amount);

        // Transfer only withdrawal_amount to L1 (either through Starkway or 3rd party bridge)
        if (native_token_address == l2_token_address) {
            _transfer_for_user_native(
                l1_token_address, 
                l1_recipient,
                sender, 
                withdrawal_amount, 
                native_token_address);
        }
        else {
            let token_details = s_whitelisted_token_details::read(l2_token_address);
            assert(token_details.l1_address == l1_token_address, 'SW: Token not whitelisted');

            _transfer_for_user_non_native(
                token_details,
                l1_recipient,
                l2_token_address,
                withdrawal_amount
            );
        } 

        // Emit WITHDRAW event for off-chain consumption
        let mut keys = ArrayTrait::new();
        keys.append(l1_recipient.into());
        keys.append(sender.into());
        let hash_value = LegacyHashFelt252::hash(l1_recipient.into(), sender.into());
        keys.append(hash_value);
        keys.append('WITHDRAW');
        keys.append(l1_token_address.into());
        keys.append(l2_token_address.into());
        let mut data = ArrayTrait::new();
        data.append(withdrawal_amount.low.into());
        data.append(withdrawal_amount.high.into());
        data.append(fee.low.into());
        data.append(fee.high.into());

        emit_event_syscall(keys.span(), data.span());
    }
    
    fn set_withdrawal_range(l1_token_address: L1Address, withdrawal_range: WithdrawalRange) {
        verify_caller_is_admin();
        let native_token_address: ContractAddress = s_native_token_l2_address::read(
            l1_token_address
        );
        assert(native_token_address.is_non_zero(), 'Starkway: Token uninitialized');
        let zero: u256 = u256 { low: 0, high: 0 };
        if withdrawal_range.max != zero {
            assert(withdrawal_range.min < withdrawal_range.max, 'Starkway: Invalid min and max');
        }
        s_withdrawal_ranges::write(l1_token_address, withdrawal_range);
    }

    //////////////
    // Internal //
    //////////////

    #[internal]
    fn verify_caller_is_admin() {
        let admin_auth_address: ContractAddress = s_admin_auth_address::read();
        let caller: ContractAddress = get_caller_address();
        let is_admin: bool = IAdminAuthDispatcher {
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

    // @dev - Function to transfer native token to L1 on behalf of the user
    fn _transfer_for_user_native(
        l1_token_address: L1Address,
        l1_recipient: L1Address,
        sender: ContractAddress,
        withdrawal_amount: u256,
        native_token_address: ContractAddress
    ) {
        IERC20Dispatcher{contract_address: native_token_address}.burn(withdrawal_amount);

        let mut message_payload = ArrayTrait::new();
        message_payload.append('WITHDRAW');
        message_payload.append(l1_token_address.into());
        message_payload.append(l1_recipient.into());
        message_payload.append(sender.into());
        message_payload.append(withdrawal_amount.low.into());
        message_payload.append(withdrawal_amount.high.into());

        send_message_to_l1_syscall(
            to_address: s_l1_starkway_address::read().into(), payload: message_payload.span()
        );
    }

    // @dev - Function to transfer non-native token on behalf of the user
    fn _transfer_for_user_non_native(
        token_details: L2TokenDetails,
        l1_recipient: L1Address,
        l2_token_address: ContractAddress,
        withdrawal_amount: u256
    ) {
        // transfer the amount to the registered adapter (which connects to the 3rd party token bridge)
        // perform withdrawal through the adapter
        let bridge_adapter_address = s_bridge_adapter_by_id::read(token_details.bridge_id);
        assert(bridge_adapter_address.is_non_zero(), 'SW: Bridge Adapter not reg');

        IERC20Dispatcher{contract_address: l2_token_address}.transfer(bridge_adapter_address, withdrawal_amount);

        // adapter is the recipient and responsible for withdrawing from 3rd party bridge
        IBridgeAdapterDispatcher{contract_address: bridge_adapter_address}.withdraw(
            token_details.bridge_address,
            l2_token_address,
            l1_recipient,
            withdrawal_amount,
            get_caller_address() //sender
        );
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

        IERC20Dispatcher { contract_address: native_token_address }.mint(recipient_address, amount);

        let starkway_address: ContractAddress = get_contract_address();
        IERC20Dispatcher { contract_address: native_token_address }.mint(starkway_address, fee);

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

    #[internal]
    fn _verify_withdrawal_amount(l1_token_address: L1Address, withdrawal_amount: u256) {
        let withdrawal_range = s_withdrawal_ranges::read(l1_token_address);
        let safety_threshold = withdrawal_range.max;
        assert(withdrawal_amount < safety_threshold, 'Starkway: amount > threshold');
        let min_withdrawal_amount = withdrawal_range.min;
        assert(min_withdrawal_amount <= withdrawal_amount, 'Starkway: min_withdraw > amount');
    }
}
