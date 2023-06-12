#[contract]
mod Starkway {
    use array::{Array, ArrayTrait, Span};
    use core::hash::LegacyHashFelt252;
    use core::integer::u256;
    use core::result::ResultTrait;
    use debug::PrintTrait;
    use starknet::{
        class_hash::ClassHash, class_hash::ClassHashZeroable, ContractAddress,
        contract_address::ContractAddressZeroable, get_caller_address, get_contract_address,
    };
    use starknet::syscalls::{deploy_syscall, emit_event_syscall, send_message_to_l1_syscall};
    use traits::{Default, Into, TryInto};
    use zeroable::Zeroable;

    use starkway::datatypes::{
        fee_range::FeeRange, fee_segment::FeeSegment, l1_address::L1Address,
        l1_address::L1AddressTrait, l1_address::L1AddressTraitImpl,
        l1_token_details::L1TokenDetails, l1_token_details::StorageAccessL1TokenDetails,
        l2_token_details::L2TokenDetails, l2_token_details::StorageAccessL2TokenDetails,
        token_info::TokenAmount, withdrawal_range::WithdrawalRange,
    };
    use starkway::interfaces::{
        IAdminAuthDispatcher, IAdminAuthDispatcherTrait, IBridgeAdapterDispatcher,
        IBridgeAdapterDispatcherTrait, IERC20Dispatcher, IERC20DispatcherTrait,
    };
    use starkway::libraries::fee_library::fee_library::{
        get_default_fee_rate, get_fee_rate, get_fee_range, set_default_fee_rate, set_fee_range,
        set_fee_segment
    };
    use starkway::utils::helpers::is_in_range;

    struct Storage {
        s_admin_auth_address: ContractAddress,
        s_bridge_adapter_by_id: LegacyMap::<u16, ContractAddress>,
        s_bridge_existence_by_id: LegacyMap::<u16, bool>,
        s_bridge_name_by_id: LegacyMap::<u16, felt252>,
        s_deploy_nonce: u128,
        s_ERC20_class_hash: ClassHash,
        s_fee_address: ContractAddress,
        s_fee_withdrawn: LegacyMap::<L1Address, u256>,
        s_native_token_l2_address: LegacyMap::<L1Address, ContractAddress>,
        s_l1_starkway_address: L1Address,
        s_l1_starkway_vault_address: L1Address,
        s_l1_token_details: LegacyMap::<L1Address, L1TokenDetails>,
        s_supported_tokens: LegacyMap::<u32, L1Address>,
        s_supported_tokens_length: u32,
        s_total_fee_collected: LegacyMap::<L1Address, u256>,
        s_whitelisted_token_details: LegacyMap::<ContractAddress, L2TokenDetails>,
        s_whitelisted_token_l2_address: LegacyMap::<(L1Address, u32), ContractAddress>,
        s_whitelisted_token_l2_address_length: LegacyMap::<L1Address, u32>,
        s_withdrawal_ranges: LegacyMap::<L1Address, WithdrawalRange>,
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
        set_default_fee_rate(fee_rate_default);
    }

    //////////
    // View //
    //////////

    // @notice Function to get L1 Starkway contract address
    // @return l1_address - address of L1 Starkway contract
    #[view]
    fn get_l1_starkway_address() -> L1Address {
        s_l1_starkway_address::read()
    }

    // @notice Function to get L1 Starkway Vault contract address
    // @return l1_address - address of L1 Starkway Vault contract
    #[view]
    fn get_l1_starkway_vault_address() -> L1Address {
        s_l1_starkway_vault_address::read()
    }

    // @notice Function to get admin auth contract address
    // @return l2_address - address of admin auth contract
    #[view]
    fn get_admin_auth_address() -> ContractAddress {
        s_admin_auth_address::read()
    }

    // @notice Function to get ERC-20 class hash
    // @return class_hash - class hash of the ERC-20 contract
    #[view]
    fn get_class_hash() -> ClassHash {
        s_ERC20_class_hash::read()
    }

    // @notice Function to get ERC-20 L2 address corresponding to ERC-20 L1 address
    // @param l1_token_address - L1 address of ERC-20 token
    // @return l2_address - address of native L2 ERC-20 token
    #[view]
    fn get_native_token_address(l1_token_address: L1Address) -> ContractAddress {
        s_native_token_l2_address::read(l1_token_address)
    }

    // @notice Function to get information corresponding to a particular token
    // @param l1_token_address - L1 address of ERC-20 token
    // @return l1_token_details - ERC-20 token details
    #[view]
    fn get_l1_token_details(l1_token_address: L1Address) -> L1TokenDetails {
        s_l1_token_details::read(l1_token_address)
    }

    // @notice Function to get information corresponding to a whitelisted token
    // @param l2_address - L2 address of ERC-20 token
    // @return l2_token_details - whitelisted token details
    #[view]
    fn get_whitelisted_token_details(l2_address: ContractAddress) -> L2TokenDetails {
        s_whitelisted_token_details::read(l2_address)
    }

    // @notice Function to get L1 addresses of all supported tokens
    // @return addresses_list - addresses list of all supported L1 tokens
    #[view]
    fn get_supported_tokens() -> Array<L1Address> {
        let mut supported_tokens = ArrayTrait::new();
        let len = s_supported_tokens_length::read();
        let mut counter = 0_u32;
        loop {
            if (counter == len) {
                break ();
            }
            supported_tokens.append(s_supported_tokens::read(counter));
            counter += 1;
        };
        supported_tokens
    }

    // @notice Function to get list of all whitelisted token addresses for a specific L1 ERC-20 token address
    // @param l1_token_address - L1 address of ERC-20 token
    // @return addresses_list - addresses list of L2 whitelisted ERC-20 token contracts
    #[view]
    fn get_whitelisted_token_addresses(l1_token_address: L1Address) -> Array<ContractAddress> {
        let mut whitelisted_tokens = ArrayTrait::new();
        let len = s_whitelisted_token_l2_address_length::read(l1_token_address);
        let mut counter = 0_u32;
        loop {
            if (counter == len) {
                break ();
            }
            whitelisted_tokens
                .append(s_whitelisted_token_l2_address::read((l1_token_address, counter)));
            counter += 1;
        };
        whitelisted_tokens
    }

    // @notice Function to get withdrawal range for a token
    // @param l1_token_address - ERC-20 L1 contract address of the token
    // @return withdrawal_range - withdrawal range values
    #[view]
    fn get_withdrawal_range(l1_token_address: L1Address) -> WithdrawalRange {
        s_withdrawal_ranges::read(l1_token_address)
    }

    // @notice Function to check whether there is sufficient liquidity in any one token for the transfer
    // It also assumes that all tokens in transfer list are unique - there is no incentive to get incorrect
    // assessment on feasibility of a transaction
    // The sum of amounts in transfer list should be equal to sum(withdrawal_amount, fee)
    // @param transfer_list - list of tokens to be transferred to L1 (for which user has given approval)
    // @param l1_token_address - Address of ERC20 token on L1 side
    // @param withdrawal_amount - The net amount to be withdrawn
    // @param fee - Fee for the withdrawn amount (calculated on the withdrawn amount)
    // @return True/False value indicating whether withdrawal is possible for given transfer list
    #[view]
    fn can_withdraw_single(
        transfer_list: Array<TokenAmount>,
        l1_token_address: L1Address,
        withdrawal_amount: u256,
        fee: u256,
    ) -> bool {
        if (transfer_list.len() == 0) {
            return true;
        }

        let native_l2_address = s_native_token_l2_address::read(l1_token_address);
        assert(native_l2_address.is_non_zero(), 'Starkway: Token uninitialized');

        // Calculate total amount to be withdrawn based on the transfer list provided
        // This call will also check that all tokens in transfer_list are actually whitelisted or 
        // native and represent the same l1 token
        let amount: u256 = _calculate_withdrawal_amount(
            @transfer_list, l1_token_address, native_l2_address, 
        );
        if (amount == 0_u256) {
            return true;
        }

        // We do not verify that fee is correct for given withdrawal_amount
        // Since there is no economic incentive to send incorrect values to this function
        // and user of this function is expected to call fee related function to get correct fee value
        let expected_amount: u256 = withdrawal_amount + fee;
        assert(amount == expected_amount, 'Starkway: Mismatched amount');

        _verify_withdrawal_amount(l1_token_address, withdrawal_amount);

        let token_list: Array<ContractAddress> = get_whitelisted_token_addresses(l1_token_address);
        let bridge_address: ContractAddress = get_contract_address();
        let user: ContractAddress = get_caller_address();

        // We cannot transfer user tokens to bridge since this is a view function
        // Hence while constructing the bridge balances we add the corresponding balances from the transfer list
        let token_balance_list: Array<TokenAmount> = _create_token_balance_list_with_user_token(
            @token_list, bridge_address, @transfer_list, 
        );

        let l2_token_address = _find_sufficient_single_non_native_token(
            token_balance_list, withdrawal_amount
        );

        // if we find such a token then we can make the transfer - return TRUE
        if (l2_token_address.is_non_zero()) {
            return true;
        }

        let native_transfer_amount = _get_user_transfer_amount(@transfer_list, native_l2_address);
        if (withdrawal_amount <= native_transfer_amount) {
            return true;
        }

        // We only need withdrawal_amount - what the user is transferring from the bridge
        // Withdrawal_amount is strictly greater than native_transfer_amount hence this subtraction works
        let net_withdrawal_amount: u256 = withdrawal_amount - native_transfer_amount;

        // check if the liquidity for the native token is sufficient
        let is_native_sufficient = _check_if_native_balance_sufficient(
            net_withdrawal_amount, bridge_address, native_l2_address
        );

        return is_native_sufficient;
    }

    // @notice - Function to calculate fee for a given L1 token and withdrawal amount
    // @param l1_token_address - ERC-20 L1 contract address of the token
    // @param withdrawal_amount - withdrawal amount for which fee is to be calculated
    // @return fee - calculated fee
    #[view]
    fn calculate_fee(l1_token_address: L1Address, withdrawal_amount: u256) -> u256 {
        let fee_rate = get_fee_rate(l1_token_address, withdrawal_amount);
        let FEE_NORMALIZER = u256 { low: 10000, high: 0 };
        let fee = (withdrawal_amount * fee_rate) / FEE_NORMALIZER;
        let fee_range = get_fee_range(l1_token_address);

        if (fee_range.is_set) {
            if (fee < fee_range.min) {
                return fee_range.min;
            }
            if (fee > fee_range.max) {
                return fee_range.max;
            }
        }
        return fee;
    }

    // @notice - function to get cumulative fees collected for a particular L1 token
    // @param l1_token_address - L1_token corresponding to which we want to know fees collected
    // @return total_fees - total fees collected so far for given L1_token
    #[view]
    fn get_cumulative_fees(l1_token_address: L1Address) -> u256 {
        let native_token_address = s_native_token_l2_address::read(l1_token_address);
        assert(native_token_address.is_non_zero(), 'Starkway: Token uninitialized');
        s_total_fee_collected::read(l1_token_address)
    }

    // @notice - function to get cumulative fees withdrawn for a particular L1 token
    // @param l1_token_address - L1_token corresponding to which we want to know fees withdrawn
    // @return total_fees - total fees withdrawn so far for given L1_token
    #[view]
    fn get_cumulative_fees_withdrawn(l1_token_address: L1Address) -> u256 {
        let native_token_address = s_native_token_l2_address::read(l1_token_address);
        assert(native_token_address.is_non_zero(), 'Starkway: Token uninitialized');
        s_fee_withdrawn::read(l1_token_address)
    }

    // @notice Function to get fee rate for a specific withdrawal amount
    // @param l1_token_address - L1 ERC-20 contract address of the token
    // @param amount - amount for which fee rate needs to be fetched
    // @return fee_rate - fee rate corresponding to an amount
    #[view]
    fn fetch_fee_rate(l1_token_address: L1Address, amount: u256) -> u256 {
        get_fee_rate(l1_token_address, amount)
    }

    // @notice Function to get default fee rate
    // @return default_fee_rate - default fee rate value
    #[view]
    fn fetch_default_fee_rate() -> u256 {
        get_default_fee_rate()
    }

    ////////////////
    // L1 Handler //
    ////////////////

    #[l1_handler]
    fn initialize_token(
        from_address: felt252, l1_token_address: L1Address, token_details: L1TokenDetails
    ) {
        _verify_msg_is_from_starkway(from_address);

        _init_token(l1_token_address, token_details);
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
        _verify_msg_is_from_starkway(from_address);

        _process_deposit(l1_token_address, sender_l1_address, recipient_address, amount, fee);
    }

    //////////////
    // External //
    //////////////

    // @notice Function to set L1 Starkway address, callable by only admin
    // @param l1_address - L1 Starkway contract address
    #[external]
    fn set_l1_starkway_address(l1_address: L1Address) {
        _verify_caller_is_admin();
        s_l1_starkway_address::write(l1_address);
    }

    // @notice Function to set L1 Starkway Vault address, callable by only admin
    // @param l1_address - L1 Starkway Vault contract address
    #[external]
    fn set_l1_starkway_vault_address(l1_address: L1Address) {
        _verify_caller_is_admin();
        let current_address: L1Address = s_l1_starkway_vault_address::read();
        assert(current_address.value == 0, 'Starkway: Vault already set');
        s_l1_starkway_vault_address::write(l1_address);
    }

    // @notice Function to set admin auth address, callable by only admin
    // @param admin_auth_address - admin auth contract address
    #[external]
    fn set_admin_auth_address(admin_auth_address: ContractAddress) {
        _verify_caller_is_admin();
        s_admin_auth_address::write(admin_auth_address);
    }

    // @notice Function to set class hash of ERC-20 contract, callable by admin
    // @param class_hash - class hash of ERC-20 contract
    #[external]
    fn set_class_hash(class_hash: ClassHash) {
        _verify_caller_is_admin();
        s_ERC20_class_hash::write(class_hash);
    }

    // @notice Function to register a bridge
    // @param bridge_id - ID of the bridge that needs to be registered
    // @param bridge_name - name of the bridge
    // @param bridge_adapter_address - address of the bridge adapter
    #[external]
    fn register_bridge(
        bridge_id: u16, bridge_name: felt252, bridge_adapter_address: ContractAddress
    ) {
        _verify_caller_is_admin();
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

    // @notice Function to withdraw a single native or non native token
    // @param l2_token_address - address of L2 ERC-20 contract which needs to be withdrawn
    // @param l1_token_address - address of the corresponding L1 ERC-20 contract
    // @param l1_recipient - address of the L1 recipient
    // @param withdrawal_amount - amount that needs to be withdrawn
    // @param fee - fee associated with the amount
    #[external]
    fn withdraw(
        l2_token_address: ContractAddress,
        l1_token_address: L1Address,
        l1_recipient: L1Address,
        withdrawal_amount: u256,
        fee: u256
    ) {
        //TODO reentrancy guard

        assert(
            L1AddressTraitImpl::is_valid_L1_address(l1_token_address.into()),
            'SW: Invalid token address'
        );
        assert(
            L1AddressTraitImpl::is_valid_L1_address(l1_recipient.into()), 'SW: Invalid L1 recipient'
        );

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
        IERC20Dispatcher {
            contract_address: l2_token_address
        }.transfer_from(sender, bridge_address, total_amount);

        // Transfer only withdrawal_amount to L1 (either through Starkway or 3rd party bridge)
        if (native_token_address == l2_token_address) {
            _transfer_for_user_native(
                l1_token_address, l1_recipient, sender, withdrawal_amount, native_token_address
            );
        } else {
            let token_details = s_whitelisted_token_details::read(l2_token_address);
            assert(token_details.l1_address == l1_token_address, 'SW: Token not whitelisted');

            _transfer_for_user_non_native(
                token_details, l1_recipient, l2_token_address, withdrawal_amount
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

    // @notice Function to set withdrawal amount range for a token
    // @param l1_token_address - token for which to set withdrawal range
    // @param withdrawal_range - new withdrawal range amounts that needs to be set
    #[external]
    fn set_withdrawal_range(l1_token_address: L1Address, withdrawal_range: WithdrawalRange) {
        _verify_caller_is_admin();
        let native_token_address: ContractAddress = s_native_token_l2_address::read(
            l1_token_address
        );
        assert(native_token_address.is_non_zero(), 'Starkway: Token uninitialized');
        let zero: u256 = u256 { low: 0, high: 0 };
        if (withdrawal_range.max != zero) {
            assert(withdrawal_range.min < withdrawal_range.max, 'Starkway: Invalid min and max');
        }
        s_withdrawal_ranges::write(l1_token_address, withdrawal_range);
    }

    // @notice - Function that allows admin to transfer fees collected in a particular l2_token to an L2 address
    // @param l1_token_address - L1 token corresponding to the L2 token
    // @param l2_token_address - L2 token for which fees collected are to be transferred
    // @param l2_recipient - recipient address on L2
    // @param withdrawal_amount - Amount of fees to be transferred
    #[external]
    fn withdraw_admin_fees(
        l1_token_address: L1Address,
        l2_token_address: ContractAddress,
        l2_recipient: ContractAddress,
        withdrawal_amount: u256
    ) {
        //TODO reentrancy guard

        _verify_caller_is_admin();
        let starkway_address = get_contract_address();
        let native_l2_address: ContractAddress = s_native_token_l2_address::read(l1_token_address);
        assert(native_l2_address.is_non_zero(), 'Starkway: Token uninitialized');

        if (native_l2_address != l2_token_address) {
            let token_details = s_whitelisted_token_details::read(l2_token_address);
            assert(token_details.l1_address == l1_token_address, 'Starkway: Token not whitelisted');
        }

        // We do not keep track of fees collected at the level of individual L2_tokens (native/non native)
        // Hence, we assume that balance of any L2 token represents the fees remaining in that L2 token
        let current_fee_balance = IERC20Dispatcher {
            contract_address: l2_token_address
        }.balance_of(starkway_address);
        assert(withdrawal_amount <= current_fee_balance, 'SW:Amount exceeds fee collected');

        let current_total_fee_collected = s_total_fee_collected::read(l1_token_address);
        let current_fee_withdrawn = s_fee_withdrawn::read(l1_token_address);
        let net_fee_remaining = current_total_fee_collected - current_fee_withdrawn;
        assert(withdrawal_amount <= net_fee_remaining, 'SW:Amount exceeds fee remaining');

        let updated_fees_withdrawn: u256 = current_fee_withdrawn + withdrawal_amount;
        s_fee_withdrawn::write(l1_token_address, updated_fees_withdrawn);

        IERC20Dispatcher {
            contract_address: l2_token_address
        }.transfer(l2_recipient, withdrawal_amount);

        // Emit WITHDRAW_FEES event for off-chain consumption
        let mut keys = ArrayTrait::new();
        keys.append(l1_token_address.into());
        keys.append(l2_token_address.into());
        keys.append('WITHDRAW_FEES');
        let mut data = ArrayTrait::new();
        data.append(l2_recipient.into());
        data.append(withdrawal_amount.low.into());
        data.append(withdrawal_amount.high.into());

        emit_event_syscall(keys.span(), data.span());
    }

    // @notice Function to update default fee rate
    // @param default_fee_rate - default fee rate value
    #[external]
    fn update_default_fee_rate(default_fee_rate: u256) {
        _verify_caller_is_admin();
        set_default_fee_rate(default_fee_rate);
    }

    // @notice Function to update fee ranges
    // @param l1_token_address - L1 contract address of the token
    // @param fee_range - fee range details
    #[external]
    fn update_fee_range(l1_token_address: L1Address, fee_range: FeeRange) {
        _verify_caller_is_admin();
        set_fee_range(l1_token_address, fee_range);
    }

    // @notice Function to update fee segments
    // @param l1_token_address - L1 contract address of the token
    // @param tier - tier of the fee segment that is being set
    // @param fee_segment - fee segment details
    #[external]
    fn update_fee_segment(l1_token_address: L1Address, tier: u8, fee_segment: FeeSegment) {
        _verify_caller_is_admin();
        set_fee_segment(l1_token_address, tier, fee_segment);
    }

    //////////////
    // Internal //
    //////////////

    // @dev - Internal function to check authorization
    fn _verify_caller_is_admin() {
        let admin_auth_address: ContractAddress = s_admin_auth_address::read();
        let caller: ContractAddress = get_caller_address();
        let is_admin: bool = IAdminAuthDispatcher {
            contract_address: admin_auth_address
        }.get_is_allowed(caller);
        assert(is_admin == true, 'Starkway: Caller not admin');
    }

    // @dev - Internal function to verify message is from starkway address
    fn _verify_msg_is_from_starkway(from_address: felt252) {
        let l1_starkway_address = s_l1_starkway_address::read();
        assert(l1_starkway_address.value == from_address, 'Starkway: Invalid l1 address');
    }

    // @dev - Internal function to initialize ERC-20 token
    fn _init_token(l1_token_address: L1Address, token_details: L1TokenDetails) {
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

        let (contract_address, _) = deploy_syscall(class_hash, nonce.into(), calldata_span, false)
            .unwrap();

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

    // @dev - Internal function to transfer native token to L1 on behalf of the user
    fn _transfer_for_user_native(
        l1_token_address: L1Address,
        l1_recipient: L1Address,
        sender: ContractAddress,
        withdrawal_amount: u256,
        native_token_address: ContractAddress
    ) {
        IERC20Dispatcher { contract_address: native_token_address }.burn(withdrawal_amount);

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

    // @dev - Internal function to transfer non-native token on behalf of the user
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

        IERC20Dispatcher {
            contract_address: l2_token_address
        }.transfer(bridge_adapter_address, withdrawal_amount);

        // adapter is the recipient and responsible for withdrawing from 3rd party bridge
        IBridgeAdapterDispatcher {
            contract_address: bridge_adapter_address
        }
            .withdraw(
                token_details.bridge_address,
                l2_token_address,
                l1_recipient,
                withdrawal_amount,
                get_caller_address() //sender
            );
    }

    // @dev - Internal function to do the actual processing of deposit (called by all external functions / l1_handlers)
    fn _process_deposit(
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

    // @dev - Internal function to check for safety threshold on the withdrawal amount
    fn _verify_withdrawal_amount(l1_token_address: L1Address, withdrawal_amount: u256) {
        let withdrawal_range = s_withdrawal_ranges::read(l1_token_address);
        let safety_threshold = withdrawal_range.max;
        assert(withdrawal_amount < safety_threshold, 'Starkway: amount > threshold');
        let min_withdrawal_amount = withdrawal_range.min;
        assert(min_withdrawal_amount <= withdrawal_amount, 'Starkway: min_withdraw > amount');
    }

    // @dev - Internal function to calculate withdrawal amount based on the list of tokens to be transferred (TokenAmounts)
    fn _calculate_withdrawal_amount(
        transfer_list: @Array<TokenAmount>,
        l1_token_address: L1Address,
        native_l2_address: ContractAddress,
    ) -> u256 {
        let transfer_list_len = transfer_list.len();
        let mut index = 0_u32;
        let mut amount = u256 { low: 0, high: 0 };
        loop {
            if (index == transfer_list_len) {
                break ();
            }
            if (*transfer_list[index].l2_address != native_l2_address) {
                let token_details: L2TokenDetails = s_whitelisted_token_details::read(
                    *transfer_list[index].l2_address
                );
                // check that all tokens passed for withdrawal represent same l1_token_address
                assert(
                    token_details.l1_address == l1_token_address, 'Starkway: L1 address Mismatch'
                );
            }
            amount += *transfer_list[index].amount;
            index += 1;
        };
        amount
    }

    // @dev - Internal function to construct list of token balances for the bridge which are greater than 0
    // This function also adds the user transfer tokens to the balances of corresponding whitelisted tokens
    // This is required to avoid making actual transfer from user to bridge
    // It is assumed that transfer list has only unique tokens since there is no economic incentive for user to try
    // and get incorrect assessment on feasibility of a withdrawal
    // This function is intended to be used from the view function which provides feasibility of a withdrawal
    fn _create_token_balance_list_with_user_token(
        token_list: @Array<ContractAddress>,
        user: ContractAddress,
        transfer_list: @Array<TokenAmount>,
    ) -> Array<TokenAmount> {
        let mut token_balance_list = ArrayTrait::<TokenAmount>::new();
        let token_list_len = token_list.len();
        let mut token_list_index = 0_u32;
        let zero_balance = u256 { low: 0, high: 0 };
        loop {
            if (token_list_index == token_list_len) {
                break ();
            }
            // Get balance of current token
            let balance: u256 = IERC20Dispatcher {
                contract_address: *token_list[token_list_index]
            }.balance_of(user);
            let user_transfer_amount: u256 = _get_user_transfer_amount(
                transfer_list, *token_list[token_list_index]
            );
            let final_amount: u256 = balance + user_transfer_amount;
            // Create TokenAmount object
            let user_balance: TokenAmount = TokenAmount {
                l2_address: *token_list[token_list_index], amount: final_amount
            };

            if (user_balance.amount > zero_balance) {
                token_balance_list.append(user_balance);
            }
            token_list_index += 1;
        };
        token_balance_list
    }

    // @dev - Internal function to get token amount being transferred corresponding to a particular L2_token_address
    fn _get_user_transfer_amount(
        transfer_list: @Array<TokenAmount>, l2_token_address: ContractAddress
    ) -> u256 {
        let transfer_list_len = transfer_list.len();
        let mut index = 0_u32;
        let mut amount: u256 = u256 { low: 0, high: 0 };
        loop {
            if (index == transfer_list_len) {
                break ();
            }
            if (*transfer_list[index].l2_address == l2_token_address) {
                amount = *transfer_list[index].amount;
                break ();
            }
            index += 1;
        };
        amount
    }

    // @dev - Internal function to find any non-native L2 token which is sufficient to cover withdrawal
    // we dont need to calculate from sorted list since we do not care which non-native token is used
    fn _find_sufficient_single_non_native_token(
        token_balance_list: Array<TokenAmount>, amount: u256
    ) -> ContractAddress {
        let mut index = 0_u32;
        let token_balance_list_len = token_balance_list.len();
        let mut l2_address: ContractAddress = Zeroable::zero();
        loop {
            if (index == token_balance_list_len) {
                break ();
            }
            // if token balance is sufficient to cover the amount to be withdrawn then return the l2_address and index
            // ideally the check should be that amount <= saftey_threshold for token
            if (amount <= *token_balance_list[index].amount) {
                l2_address = *token_balance_list[index].l2_address;
                break ();
            }
            index += 1;
        };
        l2_address
    }

    // @dev - Internal function to check whether balance for native L2 token is sufficient to cover withdrawal
    fn _check_if_native_balance_sufficient(
        withdrawal_amount: u256, bridge_address: ContractAddress, native_token: ContractAddress
    ) -> bool {
        if (native_token.is_zero()) {
            return false;
        }
        let balance = IERC20Dispatcher {
            contract_address: native_token
        }.balance_of(bridge_address);

        if (withdrawal_amount <= balance) {
            return true;
        } else {
            return false;
        }
    }
}
