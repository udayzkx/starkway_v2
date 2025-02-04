// This is a dummy contract for testing upgradeability
// It has an extra dummy variable alongwith getter and setter functions for it
#[starknet::contract]
mod Starkway {
    use array::{Array, ArrayTrait, Span};
    use hash::{HashStateTrait, HashStateExTrait};
    use pedersen::PedersenImpl;
    use core::integer::u256;
    use core::result::ResultTrait;
    use debug::PrintTrait;
    use option::OptionTrait;
    use starknet::{
        class_hash::ClassHash, class_hash::ClassHashZeroable, ContractAddress,
        contract_address::ContractAddressZeroable, EthAddress, get_caller_address,
        get_contract_address, contract_address::contract_address_to_felt252
    };
    use starknet::syscalls::{
        deploy_syscall, emit_event_syscall, library_call_syscall, send_message_to_l1_syscall, replace_class_syscall
    };
    use traits::{Default, Into, TryInto};
    use zeroable::Zeroable;

    use starkway::datatypes::{
        FeeRange, FeeSegment, HashEthAddress, L1TokenDetails, L2TokenDetails, TokenAmount,
        WithdrawalRange,
    };
    use tests::dummy_interfaces::{
        IFeeLibDispatcher, IFeeLibDispatcherTrait, IFeeLibLibraryDispatcher, IAdminAuthDispatcher,
        IAdminAuthDispatcherTrait, IBridgeAdapterDispatcher, IBridgeAdapterDispatcherTrait,
        IERC20Dispatcher, IERC20DispatcherTrait, IStarkway, IStarkwayMessageHandlerDispatcher,
        IReentrancyGuardDispatcher, IReentrancyGuardDispatcherTrait,
        IReentrancyGuardLibraryDispatcher, IStarkwayMessageHandlerDispatcherTrait
    };
    use starkway::utils::helpers::{is_in_range, reverse, sort};
    use starkway::libraries::fee_library::fee_library;

    /////////////
    // Storage //
    /////////////

    #[storage]
    struct Storage {
        admin_auth_address: ContractAddress,
        bridge_adapter_by_id: LegacyMap::<u16, ContractAddress>,
        bridge_adapter_existence_by_id: LegacyMap::<u16, bool>,
        bridge_adapter_name_by_id: LegacyMap::<u16, felt252>,
        deploy_nonce: u128,
        ERC20_class_hash: ClassHash,
        fee_address: ContractAddress,
        fee_lib_class_hash: ClassHash,
        fee_withdrawn: LegacyMap::<EthAddress, u256>,
        native_token_l2_address: LegacyMap::<EthAddress, ContractAddress>,
        l1_starkway_address: EthAddress,
        l1_starkway_vault_address: EthAddress,
        l1_token_details: LegacyMap::<EthAddress, L1TokenDetails>,
        reentrancy_guard_class_hash: ClassHash,
        supported_tokens: LegacyMap::<u32, EthAddress>,
        supported_tokens_length: u32,
        dummy_var: u32,
        total_fee_collected: LegacyMap::<EthAddress, u256>,
        whitelisted_token_details: LegacyMap::<ContractAddress, L2TokenDetails>,
        whitelisted_token_l2_address: LegacyMap::<(EthAddress, u32), ContractAddress>,
        whitelisted_token_l2_address_length: LegacyMap::<EthAddress, u32>,
        withdrawal_ranges: LegacyMap::<EthAddress, WithdrawalRange>,
    }

    /////////////////
    // Constructor //
    /////////////////

    #[constructor]
    fn constructor(
        ref self: ContractState,
        admin_auth_contract_address: ContractAddress,
        fee_rate_default: u256,
        fee_lib_class_hash: ClassHash,
        erc20_contract_hash: ClassHash
    ) {
        assert(admin_auth_contract_address.is_non_zero(), 'SW: Address is zero');
        assert(erc20_contract_hash.is_non_zero(), 'SW: Class hash is zero');

        self.admin_auth_address.write(admin_auth_contract_address);
        self.ERC20_class_hash.write(erc20_contract_hash);
        self.fee_lib_class_hash.write(fee_lib_class_hash);
        IFeeLibLibraryDispatcher {
            class_hash: self.fee_lib_class_hash.read()
        }.set_default_fee_rate(fee_rate_default);
    }


    ////////////////
    // L1 Handler //
    ////////////////

    #[l1_handler]
    fn initialize_token(
        ref self: ContractState,
        from_address: felt252,
        l1_token_address: EthAddress,
        token_details: L1TokenDetails
    ) {
        let l1_starkway_vault_address = self.l1_starkway_vault_address.read();
        assert(l1_starkway_vault_address.address == from_address, 'SW: Vault not initializer');

        self._init_token(l1_token_address, token_details);
    }

    #[l1_handler]
    fn deposit(
        ref self: ContractState,
        from_address: felt252,
        l1_token_address: EthAddress,
        sender_l1_address: EthAddress,
        recipient_address: ContractAddress,
        amount: u256,
        fee: u256
    ) {
        self._verify_msg_is_from_starkway(from_address);

        self._process_deposit(l1_token_address, sender_l1_address, recipient_address, amount, fee);
    }

    // @notice Function that gets invoked by L1 Starkway to perform deposit with message handling
    // @param from_address - L1 address from where this function is called
    // @param l1_token_address - L1 ERC-20 token contract address
    // @param sender_l1_address - L1 address of the sender
    // @param recipient_address - Address to which tokens are to be minted
    // @param amount - Amount to deposit
    // @param fee - fee charged
    // @param message_handler - Address of message handler contract (can be plugin or app contract)
    // @param message_payload - arbitrary data that has to be handled by the Message Handler
    #[l1_handler]
    fn deposit_with_message(
        ref self: ContractState,
        from_address: felt252,
        l1_token_address: EthAddress,
        sender_l1_address: EthAddress,
        recipient_address: ContractAddress,
        amount: u256,
        fee: u256,
        message_handler: ContractAddress,
        message_payload: Array<felt252>
    ) {
        self._verify_msg_is_from_starkway(from_address);

        assert(amount != u256 { low: 0, high: 0 }, 'SW: Amount cannot be zero');

        assert(message_handler.is_non_zero(), 'SW: Invalid message handler');

        let native_token_address = self
            ._process_deposit(
                l1_token_address, sender_l1_address, recipient_address, amount, fee, 
            );

        IStarkwayMessageHandlerDispatcher {
            contract_address: message_handler
        }
            .handle_starkway_deposit_message(
                l1_token_address,
                native_token_address,
                sender_l1_address,
                recipient_address,
                amount,
                fee,
                message_payload
            );
    }

    #[external(v0)]
    impl StarkwayImpl of IStarkway<ContractState> {

        ////////////////////
        // TEST FUNCTIONS //
        ////////////////////

        //#[cfg(test)]
        //fn initialize_token_test(
        //    ref self: ContractState,
        //    from_address: felt252,
        //    l1_token_address: EthAddress,
        //    token_details: L1TokenDetails
        //) {
        //    let l1_starkway_vault_address = self.l1_starkway_vault_address.read();
        //
        //    assert(l1_starkway_vault_address.address == from_address, 'SW: Vault not initializer');
        //
        //    self._init_token(l1_token_address, token_details);
        //}

        //#[cfg(test)]
        //fn deposit_test(
        //    ref self: ContractState,
        //    from_address: felt252,
        //    l1_token_address: EthAddress,
        //    sender_l1_address: EthAddress,
        //    recipient_address: ContractAddress,
        //    amount: u256,
        //    fee: u256
        //) {
        //    self._verify_msg_is_from_starkway(from_address);


        //    self
        //        ._process_deposit(
        //            l1_token_address, sender_l1_address, recipient_address, amount, fee
        //        );
        //}

        //#[cfg(test)]
        //fn deposit_with_message_test(
        //    ref self: ContractState,
        //    from_address: felt252,
        //    l1_token_address: EthAddress,
        //    sender_l1_address: EthAddress,
        //    recipient_address: ContractAddress,
        //    amount: u256,
        //    fee: u256,
        //    message_handler: ContractAddress,
        //    message_payload: Array<felt252>
        //) {
        //    self._verify_msg_is_from_starkway(from_address);

        //    assert(amount != u256 { low: 0, high: 0 }, 'SW: Amount cannot be zero');
        //    assert(message_handler.is_non_zero(), 'SW: Invalid message handler');

        //    let native_token_address = self
        //        ._process_deposit(
        //            l1_token_address, sender_l1_address, recipient_address, amount, fee, 
        //        );

        //    IStarkwayMessageHandlerDispatcher {
        //        contract_address: message_handler
        //    }
        //        .handle_starkway_deposit_message(
        //            l1_token_address,
        //           native_token_address,
        //            sender_l1_address,
        //            recipient_address,
        //            amount,
        //            fee,
        //            message_payload
        //        );
        //}

        //////////
        // View //
        //////////

        fn get_dummy_var(self: @ContractState) -> u32 {
            self.dummy_var.read()
        }

        fn set_dummy_var(ref self: ContractState, var: u32) {
            self.dummy_var.write(var);
        }
        // @notice Function to get L1 Starkway contract address
        // @return l1_address - address of L1 Starkway contract
        fn get_l1_starkway_address(self: @ContractState) -> EthAddress {
            self.l1_starkway_address.read()
        }

        // @notice Function to get L1 Starkway Vault contract address
        // @return l1_address - address of L1 Starkway Vault contract
        fn get_l1_starkway_vault_address(self: @ContractState) -> EthAddress {
            self.l1_starkway_vault_address.read()
        }

        // @notice Function to get admin auth contract address
        // @return l2_address - address of admin auth contract
        fn get_admin_auth_address(self: @ContractState) -> ContractAddress {
            self.admin_auth_address.read()
        }

        // @notice Function to get ERC-20 class hash
        // @return class_hash - class hash of the ERC-20 contract
        fn get_erc20_class_hash(self: @ContractState) -> ClassHash {
            self.ERC20_class_hash.read()
        }

        // @notice Function to get fee library class hash
        // @return class_hash - class hash of the fee library
        fn get_fee_lib_class_hash(self: @ContractState) -> ClassHash {
            self.fee_lib_class_hash.read()
        }

        // @notice Function to get reentrancy guard class hash
        // @return class_hash - class hash of the reentrancy guard
        fn get_reentrancy_guard_class_hash(self: @ContractState) -> ClassHash {
            self.reentrancy_guard_class_hash.read()
        }

        // @notice Function to get ERC-20 L2 address corresponding to ERC-20 L1 address
        // @param l1_token_address - L1 address of ERC-20 token
        // @return l2_address - address of native L2 ERC-20 token
        fn get_native_token_address(
            self: @ContractState, l1_token_address: EthAddress
        ) -> ContractAddress {
            self.native_token_l2_address.read(l1_token_address)
        }

        // @notice Function to get information corresponding to a particular token
        // @param l1_token_address - L1 address of ERC-20 token
        // @return l1_token_details - ERC-20 token details
        fn get_l1_token_details(
            self: @ContractState, l1_token_address: EthAddress
        ) -> L1TokenDetails {
            self.l1_token_details.read(l1_token_address)
        }

        // @notice Function to get information corresponding to a whitelisted token
        // @param l2_address - L2 address of ERC-20 token
        // @return l2_token_details - whitelisted token details
        fn get_whitelisted_token_details(
            self: @ContractState, l2_address: ContractAddress
        ) -> L2TokenDetails {
            self.whitelisted_token_details.read(l2_address)
        }

        // @notice Function to get L1 addresses of all supported tokens
        // @return addresses_list - addresses list of all supported L1 tokens
        fn get_supported_tokens(self: @ContractState) -> Array<EthAddress> {
            let mut supported_tokens = ArrayTrait::new();
            let len = self.supported_tokens_length.read();
            let mut counter = 0_u32;
            loop {
                if (counter == len) {
                    break ();
                }
                supported_tokens.append(self.supported_tokens.read(counter));
                counter += 1;
            };
            supported_tokens
        }

        // @notice Function to get length of all supported tokens
        // @return length - length of all supported L1 tokens
        fn get_supported_tokens_length(self: @ContractState) -> u32 {
            self.supported_tokens_length.read()
        }

        // @notice Function to get list of all whitelisted token addresses for a specific L1 ERC-20 token address
        // @param l1_token_address - L1 address of ERC-20 token
        // @return addresses_list - addresses list of L2 whitelisted ERC-20 token contracts
        fn get_whitelisted_token_addresses(
            self: @ContractState, l1_token_address: EthAddress
        ) -> Array<ContractAddress> {
            let mut whitelisted_tokens = ArrayTrait::new();
            let len = self.whitelisted_token_l2_address_length.read(l1_token_address);
            let mut counter = 0_u32;
            loop {
                if (counter == len) {
                    break ();
                }
                whitelisted_tokens
                    .append(self.whitelisted_token_l2_address.read((l1_token_address, counter)));
                counter += 1;
            };
            whitelisted_tokens
        }

        // @notice Function to get withdrawal range for a token
        // @param l1_token_address - ERC-20 L1 contract address of the token
        // @return withdrawal_range - withdrawal range values
        fn get_withdrawal_range(
            self: @ContractState, l1_token_address: EthAddress
        ) -> WithdrawalRange {
            self.withdrawal_ranges.read(l1_token_address)
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
        fn can_withdraw_multi(
            self: @ContractState,
            transfer_list: Array<TokenAmount>,
            l1_token_address: EthAddress,
            withdrawal_amount: u256,
            fee: u256,
        ) -> bool {
            let native_l2_address = self.native_token_l2_address.read(l1_token_address);
            assert(native_l2_address.is_non_zero(), 'SW: Token uninitialized');

            if (transfer_list.len() == 0) {
                return true;
            }

            // Calculate total amount to be withdrawn based on the transfer list provided
            // This call will also check that all tokens in transfer_list are actually whitelisted or 
            // native and represent the same l1 token
            let amount: u256 = self
                ._calculate_withdrawal_amount(
                    @transfer_list, l1_token_address, native_l2_address, 
                );
            if (amount == 0_u256) {
                return true;
            }

            // We do not verify that fee is correct for given withdrawal_amount
            // Since there is no economic incentive to send incorrect values to this function
            // and user of this function is expected to call fee related function to get correct fee value
            let expected_amount: u256 = withdrawal_amount + fee;
            assert(amount == expected_amount, 'SW: Mismatched amount');

            self._verify_withdrawal_amount(l1_token_address, withdrawal_amount);

            let token_list: Array<ContractAddress> = self
                .get_whitelisted_token_addresses(l1_token_address);
            let bridge_address: ContractAddress = get_contract_address();
            let user: ContractAddress = get_caller_address();

            // We cannot transfer user tokens to bridge since this is a view function
            // Hence while constructing the bridge balances we add the corresponding balances from the transfer list
            let token_balance_list: Array<TokenAmount> = self
                ._create_token_balance_list_with_user_token(
                    @token_list, bridge_address, @transfer_list, l1_token_address
                );

            let l2_token_address = self
                ._find_sufficient_single_non_native_token(token_balance_list, withdrawal_amount);

            // if we find such a token then we can make the transfer - return TRUE
            if (l2_token_address.is_non_zero()) {
                return true;
            }

            let native_transfer_amount = self
                ._get_user_transfer_amount(@transfer_list, native_l2_address);
            if (withdrawal_amount <= native_transfer_amount) {
                return true;
            }

            // We only need withdrawal_amount - what the user is transferring from the bridge
            // Withdrawal_amount is strictly greater than native_transfer_amount hence this subtraction works
            let net_withdrawal_amount: u256 = withdrawal_amount - native_transfer_amount;

            // check if the liquidity for the native token is sufficient
            let is_native_sufficient = self
                ._check_if_native_balance_sufficient(
                    net_withdrawal_amount, bridge_address, native_l2_address
                );

            return is_native_sufficient;
        }

        // @notice - Function to calculate fee for a given L1 token and withdrawal amount
        // @param l1_token_address - ERC-20 L1 contract address of the token
        // @param withdrawal_amount - withdrawal amount for which fee is to be calculated
        // @return fee - calculated fee
        fn calculate_fee(
            self: @ContractState, l1_token_address: EthAddress, withdrawal_amount: u256
        ) -> u256 {
            let fee_rate = self.get_fee_rate(l1_token_address, withdrawal_amount);
            let FEE_NORMALIZER = u256 { low: 10000, high: 0 };
            let fee = (withdrawal_amount * fee_rate) / FEE_NORMALIZER;

            let fee_range = IFeeLibLibraryDispatcher {
                class_hash: self.fee_lib_class_hash.read()
            }.get_fee_range(l1_token_address);

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

        // @notice - This function takes as input the l1_address of the token and the amount to withdraw, expected fees
        // It then prepares a list of l2_tokens for which user should provide approvals 
        // to the bridge alongwith list of tokens that need
        // to be transferred
        // approval list will be a subset of the actual transfer list since not all tokens may require fresh approvals
        // First a list of the whitelisted l2 token addresses is prepared and the native l2 token address is appended to it
        // Then a list of <l1_token_address, l2 address, balance in uint256> is prepared for the user
        // <l1_token_address, l2 address, amount> is represented by the struct type TokenAmount
        // Then a sorted list of TokenAmounts is prepared (in decreasing order)
        // We then iterate through this list to figure out the least number of tokens to use to give effect to the withdrawal
        // The idea is that the lesser the number of tokens being transferred for the withdrawal, the lesser the gas fees
        // @param l1_address - L1 ERC-20 contract address of the token
        // @param amount - amount that needs to be withdrawn
        // @param user - L2 address of the user
        // @param fee - withdrawal fee associated with the withdrawal obtained from calculate_fee
        // @return approval_list - list of token addresses and amount that needs to be approved by the user
        // @return transfer_list - list of token addresses and amount that needs to be transferred to Starkway from the user
        fn prepare_withdrawal_lists(
            self: @ContractState,
            l1_address: EthAddress,
            amount: u256,
            user: ContractAddress,
            fee: u256
        ) -> (Array<TokenAmount>, Array<TokenAmount>) {
            // Check if token is initialized
            let native_token_address = self.native_token_l2_address.read(l1_address);
            assert(native_token_address.is_non_zero(), 'SW: Native token uninitialized');

            self._verify_withdrawal_amount(l1_address, amount);
            let bridge_address = get_contract_address();
            let zero_balance = u256 { low: 0, high: 0 };

            let mut token_list = self.get_whitelisted_token_addresses(l1_address);
            token_list.append(native_token_address);

            let user_token_balance_list: Array<TokenAmount> = self
                ._create_token_balance_list(@token_list, user, l1_address);

            let mut approval_list = ArrayTrait::<TokenAmount>::new();
            let mut transfer_list = ArrayTrait::<TokenAmount>::new();

            if (amount == zero_balance) {
                return (approval_list, transfer_list);
            }

            assert(user_token_balance_list.len() != 0, 'SW: Insufficient balance');
            let ascending_sorted_list = sort(@user_token_balance_list);

            // reverse the sorted list to get list in descending order of balances
            let sorted_token_balance_list = reverse(@ascending_sorted_list);

            let total_withdrawal_amount = amount + fee;

            // create approval and transfer lists using the minimum number of tokens
            let (approval_list, transfer_list) = self
                ._create_approval_and_transfer_list(
                    @sorted_token_balance_list, total_withdrawal_amount, user, bridge_address
                );
            (approval_list, transfer_list)
        }

        // @notice - function to get cumulative fees collected for a particular L1 token
        // @param l1_token_address - L1_token corresponding to which we want to know fees collected
        // @return total_fees - total fees collected so far for given L1_token
        fn get_cumulative_fees(self: @ContractState, l1_token_address: EthAddress) -> u256 {
            let native_token_address = self.native_token_l2_address.read(l1_token_address);
            assert(native_token_address.is_non_zero(), 'SW: Token uninitialized');
            self.total_fee_collected.read(l1_token_address)
        }

        // @notice - function to get cumulative fees withdrawn for a particular L1 token
        // @param l1_token_address - L1_token corresponding to which we want to know fees withdrawn
        // @return total_fees - total fees withdrawn so far for given L1_token
        fn get_cumulative_fees_withdrawn(
            self: @ContractState, l1_token_address: EthAddress
        ) -> u256 {
            let native_token_address = self.native_token_l2_address.read(l1_token_address);
            assert(native_token_address.is_non_zero(), 'SW: Token uninitialized');
            self.fee_withdrawn.read(l1_token_address)
        }

        // @notice Function to get fee rate for a specific withdrawal amount
        // @param l1_token_address - L1 ERC-20 contract address of the token
        // @param amount - amount for which fee rate needs to be fetched
        // @return fee_rate - fee rate corresponding to an amount
        fn get_fee_rate(self: @ContractState, l1_token_address: EthAddress, amount: u256) -> u256 {
            IFeeLibLibraryDispatcher {
                class_hash: self.fee_lib_class_hash.read()
            }.get_fee_rate(l1_token_address, amount)
        }

        // @notice Function to get default fee rate
        // @return default_fee_rate - default fee rate value
        fn get_default_fee_rate(self: @ContractState) -> u256 {
            IFeeLibLibraryDispatcher {
                class_hash: self.fee_lib_class_hash.read()
            }.get_default_fee_rate()
        }

        // @notice Function to get fee range for a specific l1 token address
        // @param l1_token_address - L1 token address
        // @return fee_range - fee_range value for a specified l1 token address
        fn get_fee_range(self: @ContractState, l1_token_address: EthAddress) -> FeeRange {
            IFeeLibLibraryDispatcher {
                class_hash: self.fee_lib_class_hash.read()
            }.get_fee_range(l1_token_address)
        }

        //////////////
        // External //
        //////////////

        // @notice Function to set L1 Starkway address, callable by only admin
        // @param l1_address - L1 Starkway contract address
        fn set_l1_starkway_address(ref self: ContractState, l1_address: EthAddress) {
            self._verify_caller_is_admin();
            self.l1_starkway_address.write(l1_address);
        }

        // @notice Function to set L1 Starkway Vault address, callable by only admin
        // @param l1_address - L1 Starkway Vault contract address
        fn set_l1_starkway_vault_address(ref self: ContractState, l1_address: EthAddress) {
            self._verify_caller_is_admin();
            let current_address: EthAddress = self.l1_starkway_vault_address.read();
            assert(current_address.is_zero(), 'SW: Vault already set');
            self.l1_starkway_vault_address.write(l1_address);
        }

        // @notice Function to set admin auth address, callable by only admin
        // @param admin_auth_address - admin auth contract address
        fn set_admin_auth_address(ref self: ContractState, admin_auth_address: ContractAddress) {
            self._verify_caller_is_admin();
            self.admin_auth_address.write(admin_auth_address);
        }

        // @notice Function to set class hash of ERC-20 contract, callable by admin
        // @param class_hash - class hash of ERC-20 contract
        fn set_erc20_class_hash(ref self: ContractState, class_hash: ClassHash) {
            self._verify_caller_is_admin();
            self.ERC20_class_hash.write(class_hash);
        }

        // @notice Function to set class hash of FeeLib contract, callable by admin
        // @param class_hash - class hash of FeeLib contract
        fn set_fee_lib_class_hash(ref self: ContractState, class_hash: ClassHash) {
            self._verify_caller_is_admin();
            self.fee_lib_class_hash.write(class_hash);
        }

        // @notice Function to set class hash of ReentrancyGuard contract, callable by admin
        // @param class_hash - class hash of ReentrancyGuard contract
        fn set_reentrancy_guard_class_hash(ref self: ContractState, class_hash: ClassHash) {
            self._verify_caller_is_admin();
            self.reentrancy_guard_class_hash.write(class_hash);
        }

        // @notice Function to register a bridge adapter
        // @param bridge_adapter_id - ID of the bridge that needs to be registered
        // @param bridge_adapter_name - name of the bridge
        // @param bridge_adapter_address - address of the bridge adapter
        fn register_bridge_adapter(
            ref self: ContractState,
            bridge_adapter_id: u16,
            bridge_adapter_name: felt252,
            bridge_adapter_address: ContractAddress
        ) {
            self._verify_caller_is_admin();
            assert(
                self.bridge_adapter_existence_by_id.read(bridge_adapter_id) == false,
                'SW: Bridge Adapter exists'
            );
            assert(bridge_adapter_id > 0_u16, 'SW: Bridge Adapter id invalid');
            assert(bridge_adapter_address.is_non_zero(), 'SW: Adapter address is 0');
            assert(bridge_adapter_name != 0, 'SW: Bridge Adapter name invalid');
            self.bridge_adapter_existence_by_id.write(bridge_adapter_id, true);
            self.bridge_adapter_name_by_id.write(bridge_adapter_id, bridge_adapter_name);
            self.bridge_adapter_by_id.write(bridge_adapter_id, bridge_adapter_address);
        }

        // @notice Function to withdraw a single native or non native token
        // @param l2_token_address - address of L2 ERC-20 contract which needs to be withdrawn
        // @param l1_token_address - address of the corresponding L1 ERC-20 contract
        // @param l1_recipient - address of the L1 recipient
        // @param withdrawal_amount - amount that needs to be withdrawn
        // @param fee - fee associated with the amount
        fn withdraw(
            ref self: ContractState,
            l2_token_address: ContractAddress,
            l1_token_address: EthAddress,
            l1_recipient: EthAddress,
            withdrawal_amount: u256,
            fee: u256
        ) {
            IReentrancyGuardLibraryDispatcher {
                class_hash: self.reentrancy_guard_class_hash.read()
            }.start();

            // Check if token is initialized
            let native_token_address = self.native_token_l2_address.read(l1_token_address);
            assert(native_token_address.is_non_zero(), 'SW: Native token uninitialized');

            // Check withdrawal amount is within withdrawal range
            self._verify_withdrawal_amount(l1_token_address, withdrawal_amount);

            let calculated_fee = self.calculate_fee(l1_token_address, withdrawal_amount);
            assert(calculated_fee == fee, 'SW: Fee mismatch');
            let total_fee_collected = self.total_fee_collected.read(l1_token_address);
            let updated_fee_collected = total_fee_collected + calculated_fee;
            self.total_fee_collected.write(l1_token_address, updated_fee_collected);

            let bridge_address: ContractAddress = get_contract_address();
            let sender: ContractAddress = get_caller_address();
            let total_amount = withdrawal_amount + fee;

            // Transfer withdrawal_amount + fee to bridge
            IERC20Dispatcher {
                contract_address: l2_token_address
            }.transfer_from(sender, bridge_address, total_amount);

            // Transfer only withdrawal_amount to L1 (either through Starkway or 3rd party bridge)
            if (native_token_address == l2_token_address) {
                self
                    ._transfer_for_user_native(
                        l1_token_address,
                        l1_recipient,
                        sender,
                        withdrawal_amount,
                        native_token_address
                    );
            } else {
                let token_details = self.whitelisted_token_details.read(l2_token_address);
                assert(token_details.l1_address == l1_token_address, 'SW: Token not whitelisted');

                self
                    ._transfer_for_user_non_native(
                        token_details, l1_recipient, l2_token_address, withdrawal_amount
                    );
            }

            // Emit WITHDRAW event for off-chain consumption
            let mut keys = ArrayTrait::new();
            keys.append(l1_recipient.into());
            keys.append(sender.into());
            let hash_value = PedersenImpl::new(l1_recipient.into())
                                        .update_with(contract_address_to_felt252(sender)).finalize();
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

            IReentrancyGuardLibraryDispatcher {
                class_hash: self.reentrancy_guard_class_hash.read()
            }.end();
        }

        // @notice Function to set withdrawal amount range for a token
        // @param l1_token_address - token for which to set withdrawal range
        // @param withdrawal_range - new withdrawal range amounts that needs to be set
        fn set_withdrawal_range(
            ref self: ContractState, l1_token_address: EthAddress, withdrawal_range: WithdrawalRange
        ) {
            self._verify_caller_is_admin();
            let native_token_address: ContractAddress = self
                .native_token_l2_address
                .read(l1_token_address);
            assert(native_token_address.is_non_zero(), 'SW: Token uninitialized');
            let zero: u256 = u256 { low: 0, high: 0 };
            if (withdrawal_range.max != zero) {
                assert(withdrawal_range.min < withdrawal_range.max, 'SW: Invalid min and max');
            }
            self.withdrawal_ranges.write(l1_token_address, withdrawal_range);
        }

        // @notice - Function that allows admin to transfer fees collected in a particular l2_token to an L2 address
        // @param l1_token_address - L1 token corresponding to the L2 token
        // @param l2_token_address - L2 token for which fees collected are to be transferred
        // @param l2_recipient - recipient address on L2
        // @param withdrawal_amount - Amount of fees to be transferred
        fn withdraw_admin_fees(
            ref self: ContractState,
            l1_token_address: EthAddress,
            l2_token_address: ContractAddress,
            l2_recipient: ContractAddress,
            withdrawal_amount: u256
        ) {
            IReentrancyGuardLibraryDispatcher {
                class_hash: self.reentrancy_guard_class_hash.read()
            }.start();

            self._verify_caller_is_admin();
            let starkway_address = get_contract_address();
            let native_l2_address: ContractAddress = self
                .native_token_l2_address
                .read(l1_token_address);
            assert(native_l2_address.is_non_zero(), 'SW: Token uninitialized');
            assert(l2_recipient.is_non_zero(), 'SW: L2 recipient cannot be zero');
            assert(withdrawal_amount != u256 { low: 0, high: 0 }, 'SW: Amount cannot be zero');

            if (native_l2_address != l2_token_address) {
                let token_details = self.whitelisted_token_details.read(l2_token_address);
                assert(token_details.l1_address == l1_token_address, 'SW: Token not whitelisted');
            }

            // We do not keep track of fees collected at the level of individual L2_tokens (native/non native)
            // Hence, we assume that balance of any L2 token represents the fees remaining in that L2 token
            let current_fee_balance = IERC20Dispatcher {
                contract_address: l2_token_address
            }.balance_of(starkway_address);
            assert(withdrawal_amount <= current_fee_balance, 'SW:Amount exceeds fee collected');

            let current_total_fee_collected = self.total_fee_collected.read(l1_token_address);
            let current_fee_withdrawn = self.fee_withdrawn.read(l1_token_address);
            let net_fee_remaining = current_total_fee_collected - current_fee_withdrawn;

            // Below case would be triggered, if transfer of tokens happen from outside 
            // (which is not through deposit). Below condition prevents admin from withdrawing those tokens.
            // Commenting the condition for withdrawal to happen
            // assert(withdrawal_amount <= net_fee_remaining, 'SW:Amount exceeds fee remaining');

            let updated_fees_withdrawn: u256 = current_fee_withdrawn + withdrawal_amount;
            self.fee_withdrawn.write(l1_token_address, updated_fees_withdrawn);

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

            IReentrancyGuardLibraryDispatcher {
                class_hash: self.reentrancy_guard_class_hash.read()
            }.end();
        }

        // @notice Function to update default fee rate
        // @param default_fee_rate - default fee rate value
        fn set_default_fee_rate(ref self: ContractState, default_fee_rate: u256) {
            self._verify_caller_is_admin();
            IFeeLibLibraryDispatcher {
                class_hash: self.fee_lib_class_hash.read()
            }.set_default_fee_rate(default_fee_rate);
        }

        // @notice Function to update fee ranges
        // @param l1_token_address - L1 contract address of the token
        // @param fee_range - fee range details
        fn set_fee_range(
            ref self: ContractState, l1_token_address: EthAddress, fee_range: FeeRange
        ) {
            self._verify_caller_is_admin();
            IFeeLibLibraryDispatcher {
                class_hash: self.fee_lib_class_hash.read()
            }.set_fee_range(l1_token_address, fee_range);
        }

        // @notice Function to update fee segments
        // @param l1_token_address - L1 contract address of the token
        // @param tier - tier of the fee segment that is being set
        // @param fee_segment - fee segment details
        fn set_fee_segment(
            ref self: ContractState, l1_token_address: EthAddress, tier: u8, fee_segment: FeeSegment
        ) {
            self._verify_caller_is_admin();
            IFeeLibLibraryDispatcher {
                class_hash: self.fee_lib_class_hash.read()
            }.set_fee_segment(l1_token_address, tier, fee_segment);
        }

        // @notice Function to initialize ERC-20 token by admin in case initialisation from L1 couldn't complete
        // @param l1_token_address - L1 ERC-20 token contract address
        // @param token_details - L1 token details
        fn authorised_init_token(
            ref self: ContractState, l1_token_address: EthAddress, token_details: L1TokenDetails
        ) {
            self._verify_caller_is_admin();
            self._init_token(l1_token_address, token_details);
        }

        // @notice Function to whitelist a token
        // @param l2_token_address - Token L2 address
        // @param l2_token_details - L2 Token details structure (see in DataTypes)
        fn whitelist_token(
            ref self: ContractState,
            l2_token_address: ContractAddress,
            l2_token_details: L2TokenDetails
        ) {
            self._verify_caller_is_admin();

            let bridge_adapter_exists = self
                .bridge_adapter_existence_by_id
                .read(l2_token_details.bridge_adapter_id);
            assert(bridge_adapter_exists, 'SW: Bridge Adapter not regd');
            assert(l2_token_address.is_non_zero(), 'SW: L2 address cannot be 0');
            assert(l2_token_details.bridge_address.is_non_zero(), 'SW: Bridge address cannot be 0');

            let native_token_address = self
                .native_token_l2_address
                .read(l2_token_details.l1_address);
            assert(native_token_address.is_non_zero(), 'SW: ERC20 token not initialized');

            self.whitelisted_token_details.write(l2_token_address, l2_token_details);
            let current_len = self
                .whitelisted_token_l2_address_length
                .read(l2_token_details.l1_address);
            self
                .whitelisted_token_l2_address
                .write((l2_token_details.l1_address, current_len), l2_token_address);
            self
                .whitelisted_token_l2_address_length
                .write(l2_token_details.l1_address, current_len + 1);
        }

        // @notice - This function allows user to withdraw tokens using Starkway only if any 1 whitelisted/native token's liquidity
        // is suffcient to cover the withdrawal
        // the transfer list is supposed to be a list of TokenAmounts for which user has given approval to the bridge
        // and the total amount for this list needs to be withdrawn on L1 side
        // We dont check that the transfer list is the most optimized/in decreasing order of token balances according to what
        // prepare_withdrawal_lists function would have returned - the reason is that there is no incentive for the user to
        // withdraw differently
        // This function should be called after checking feasibility of withdrawal with can_withdraw_multi view function
        // in any case, user has full control over what they want to transfer/withdraw
        // This function withdraws exact amount passed as argument and fee given should be equal to fee calculated for this amount
        // @param transfer_list - list of tokens to be transferred to L1 (for which user has given approval)
        // @param l1_recipient - address of recipient on L1 side
        // @param l1_token_address - Address of ERC20 token on L1 side
        // @param withdrawal_amount - The net amount to be withdrawn
        // @param fee - Fee for the withdrawn amount (calculated on the withdrawn amount)
        fn withdraw_multi(
            ref self: ContractState,
            transfer_list: Array<TokenAmount>,
            l1_recipient: EthAddress,
            l1_token_address: EthAddress,
            withdrawal_amount: u256,
            fee: u256,
        ) {
            IReentrancyGuardLibraryDispatcher {
                class_hash: self.reentrancy_guard_class_hash.read()
            }.start();

            let native_l2_address: ContractAddress = self
                .native_token_l2_address
                .read(l1_token_address);
            assert(native_l2_address.is_non_zero(), 'SW: Token uninitialized');
            assert(withdrawal_amount != u256 { low: 0, high: 0 }, 'SW: Amount cannot be zero');

            self._verify_withdrawal_amount(l1_token_address, withdrawal_amount);

            let calculated_fee: u256 = self.calculate_fee(l1_token_address, withdrawal_amount);
            let current_fee = self.total_fee_collected.read(l1_token_address);
            let new_fee = calculated_fee + current_fee;
            self.total_fee_collected.write(l1_token_address, new_fee);
            assert(calculated_fee == fee, 'SW: Fee mismatch');

            // Calculate total amount to be withdrawn based on the transfer list provided
            // This call will also check that all tokens in transfer_list are actually whitelisted or 
            // native and represent the same l1 token
            let amount: u256 = self
                ._calculate_withdrawal_amount(
                    @transfer_list, l1_token_address, native_l2_address, 
                );

            let expected_amount: u256 = withdrawal_amount + fee;
            assert(amount == expected_amount, 'SW: Withdrawal amount mismatch');

            let bridge_address = get_contract_address();
            let user = get_caller_address();

            // transfer all user tokens to the bridge
            // If there is no permission or insufficient balance for any token then transaction will revert
            self._transfer_user_tokens(transfer_list, user, bridge_address);

            // Emit WITHDRAW_MULTI event for off-chain consumption
            let mut keys = ArrayTrait::new();
            keys.append(l1_recipient.into());
            keys.append(l1_token_address.into());
            keys.append(user.into());
            let hash_value = PedersenImpl::new(l1_recipient.into())
                                        .update_with(contract_address_to_felt252(user)).finalize();
            keys.append(hash_value);
            keys.append('WITHDRAW_MULTI');
            let mut data = ArrayTrait::new();
            data.append(withdrawal_amount.low.into());
            data.append(withdrawal_amount.high.into());
            data.append(fee.low.into());
            data.append(fee.high.into());

            let token_list: Array<ContractAddress> = self
                .get_whitelisted_token_addresses(l1_token_address);
            let token_balance_list: Array<TokenAmount> = self
                ._create_token_balance_list(@token_list, bridge_address, l1_token_address);

            // get address of any l2_token whose liquidity is sufficient to cover the withdrawal
            let l2_token_address = self
                ._find_sufficient_single_non_native_token(token_balance_list, withdrawal_amount);

            // if we find such a token then make the transfer through the bridge adapter and we are done
            if (l2_token_address.is_non_zero()) {
                let token_details = self.whitelisted_token_details.read(l2_token_address);
                self
                    ._transfer_for_user_non_native(
                        token_details, l1_recipient, l2_token_address, withdrawal_amount
                    );

                data.append(l2_token_address.into());
                emit_event_syscall(keys.span(), data.span());
            } else {
                // check if the liquidity for the native token is sufficient
                let is_native_sufficient = self
                    ._check_if_native_balance_sufficient(
                        withdrawal_amount, bridge_address, native_l2_address
                    );

                // if yes, then make the transfer and we are done
                if (is_native_sufficient) {
                    self
                        ._transfer_for_user_native(
                            l1_token_address,
                            l1_recipient,
                            user,
                            withdrawal_amount,
                            native_l2_address
                        );

                    data.append(native_l2_address.into());
                    emit_event_syscall(keys.span(), data.span());
                } else {
                    assert(is_native_sufficient, 'SW: No single token liquidity');
                }
            }

            IReentrancyGuardLibraryDispatcher {
                class_hash: self.reentrancy_guard_class_hash.read()
            }.end();
        }

        // @notice - Function to upgrade class hash of this contract - Starkway
        fn upgrade_class_hash(ref self: ContractState, new_class_hash: ClassHash) {

            self._verify_caller_is_admin();
            assert(new_class_hash.is_non_zero(), 'SW: Invalid new class hash');
            replace_class_syscall(new_class_hash);
        }
    }

    #[generate_trait]
    impl StarkwayPrivateFunctions of IStarkwayPrivateFunctions {
        //////////////
        // Internal //
        //////////////

        // @dev - Internal function to check authorization
        fn _verify_caller_is_admin(self: @ContractState) {
            let admin_auth_address: ContractAddress = self.admin_auth_address.read();
            let caller: ContractAddress = get_caller_address();
            let is_admin: bool = IAdminAuthDispatcher {
                contract_address: admin_auth_address
            }.get_is_allowed(caller);
            assert(is_admin == true, 'SW: Caller not admin');
        }

        // @dev - Internal function to verify message is from starkway address
        fn _verify_msg_is_from_starkway(self: @ContractState, from_address: felt252) {
            let l1_starkway_address = self.l1_starkway_address.read();
            assert(l1_starkway_address.address == from_address, 'SW: Message not from SW L1');
        }

        // @dev - Internal function to initialize ERC-20 token
        fn _init_token(
            ref self: ContractState, l1_token_address: EthAddress, token_details: L1TokenDetails
        ) {
            let native_address: ContractAddress = self
                .native_token_l2_address
                .read(l1_token_address);
            assert(native_address.is_zero(), 'SW: Native token present');

            let class_hash: ClassHash = self.ERC20_class_hash.read();
            assert(class_hash.is_non_zero(), 'SW: Class hash is 0');

            assert(token_details.name != 0, 'SW: Name is 0');
            assert(token_details.symbol != 0, 'SW: Symbol is 0');

            let res: bool = is_in_range(token_details.decimals, 1_u8, 18_u8);
            assert(res == true, 'SW: Decimals not valid');

            let nonce = self.deploy_nonce.read();
            self.deploy_nonce.write(nonce + 1);

            let starkway_address: ContractAddress = get_contract_address();
            let mut calldata = ArrayTrait::new();
            calldata.append(token_details.name);
            calldata.append(token_details.symbol);
            calldata.append(token_details.decimals.into());
            calldata.append(starkway_address.into());
            let calldata_span = calldata.span();

            let (contract_address, _) = deploy_syscall(
                class_hash, nonce.into(), calldata_span, false
            )
                .unwrap();

            self.native_token_l2_address.write(l1_token_address, contract_address);
            self.l1_token_details.write(l1_token_address, token_details);

            let current_len = self.supported_tokens_length.read();
            self.supported_tokens_length.write(current_len + 1);
            self.supported_tokens.write(current_len, l1_token_address);

            let mut keys = ArrayTrait::new();
            keys.append(l1_token_address.into());
            keys.append(token_details.name);
            keys.append('INITIALISE');
            let mut data = ArrayTrait::new();
            data.append(contract_address.into());

            emit_event_syscall(keys.span(), data.span());
        }

        // @dev - Internal function to transfer native token to L1 on behalf of the user
        fn _transfer_for_user_native(
            self: @ContractState,
            l1_token_address: EthAddress,
            l1_recipient: EthAddress,
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
                to_address: self.l1_starkway_address.read().into(), payload: message_payload.span()
            );
        }

        // @dev - Internal function to transfer non-native token on behalf of the user
        fn _transfer_for_user_non_native(
            self: @ContractState,
            token_details: L2TokenDetails,
            l1_recipient: EthAddress,
            l2_token_address: ContractAddress,
            withdrawal_amount: u256
        ) {
            // transfer the amount to the registered adapter (which connects to the 3rd party token bridge)
            // perform withdrawal through the adapter
            let bridge_adapter_address = self
                .bridge_adapter_by_id
                .read(token_details.bridge_adapter_id);
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
            ref self: ContractState,
            l1_token_address: EthAddress,
            sender_l1_address: EthAddress,
            recipient_address: ContractAddress,
            amount: u256,
            fee: u256
        ) -> ContractAddress {
            assert(recipient_address.is_non_zero(), 'SW: Invalid recipient');

            let native_token_address = self.native_token_l2_address.read(l1_token_address);
            assert(native_token_address.is_non_zero(), 'SW: Token uninitialized');

            IERC20Dispatcher {
                contract_address: native_token_address
            }.mint(recipient_address, amount);

            let starkway_address: ContractAddress = get_contract_address();
            IERC20Dispatcher { contract_address: native_token_address }.mint(starkway_address, fee);

            let current_collected_fee: u256 = self.total_fee_collected.read(l1_token_address);
            self.total_fee_collected.write(l1_token_address, current_collected_fee + fee);

            let mut keys = ArrayTrait::new();
            keys.append(sender_l1_address.address);
            keys.append(recipient_address.into());
            let hash_value = PedersenImpl::new(sender_l1_address.into())
                                        .update_with(contract_address_to_felt252(recipient_address)).finalize();
            keys.append(hash_value);
            keys.append(l1_token_address.address);
            keys.append('DEPOSIT');
            let mut data = ArrayTrait::new();
            data.append(amount.low.into());
            data.append(amount.high.into());
            data.append(fee.low.into());
            data.append(fee.high.into());
            data.append(native_token_address.into());

            emit_event_syscall(keys.span(), data.span());
            return native_token_address;
        }

        // @dev - Internal function to check for safety threshold on the withdrawal amount
        fn _verify_withdrawal_amount(
            self: @ContractState, l1_token_address: EthAddress, withdrawal_amount: u256
        ) {
            let withdrawal_range = self.withdrawal_ranges.read(l1_token_address);
            let safety_threshold = withdrawal_range.max;
            assert(withdrawal_amount < safety_threshold, 'SW: amount > threshold');
            let min_withdrawal_amount = withdrawal_range.min;
            assert(min_withdrawal_amount <= withdrawal_amount, 'SW: min_withdraw > amount');
        }

        // @dev - Internal function to calculate withdrawal amount based on the list of tokens to be transferred (TokenAmounts)
        fn _calculate_withdrawal_amount(
            self: @ContractState,
            transfer_list: @Array<TokenAmount>,
            l1_token_address: EthAddress,
            native_l2_address: ContractAddress,
        ) -> u256 {
            let transfer_list_len = transfer_list.len();
            let mut index = 0_u32;
            let mut amount = u256 { low: 0, high: 0 };
            loop {
                if (index == transfer_list_len) {
                    break ();
                }

                if (*transfer_list.at(index).l2_address != native_l2_address) {
                    let token_details: L2TokenDetails = self
                        .whitelisted_token_details
                        .read(*transfer_list.at(index).l2_address);
                    // check that all tokens passed for withdrawal represent same l1_token_address
                    assert(token_details.l1_address == l1_token_address, 'SW: L1 address Mismatch');
                }

                assert(
                    *transfer_list.at(index).l1_address == l1_token_address,
                    'SW: Incompatible L1 addr'
                );
                amount += *transfer_list.at(index).amount;
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
            self: @ContractState,
            token_list: @Array<ContractAddress>,
            bridge: ContractAddress,
            transfer_list: @Array<TokenAmount>,
            l1_token_address: EthAddress,
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
                }.balance_of(bridge);
                let user_transfer_amount: u256 = self
                    ._get_user_transfer_amount(transfer_list, *token_list[token_list_index]);
                let final_amount: u256 = balance + user_transfer_amount;
                // Create TokenAmount object
                let user_balance: TokenAmount = TokenAmount {
                    l1_address: l1_token_address,
                    l2_address: *token_list[token_list_index],
                    amount: final_amount
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
            self: @ContractState,
            transfer_list: @Array<TokenAmount>,
            l2_token_address: ContractAddress
        ) -> u256 {
            let transfer_list_len = transfer_list.len();
            let mut index = 0_u32;
            let mut amount: u256 = u256 { low: 0, high: 0 };
            loop {
                if (index == transfer_list_len) {
                    break ();
                }
                if (*transfer_list.at(index).l2_address == l2_token_address) {
                    amount = *transfer_list.at(index).amount;
                    break ();
                }
                index += 1;
            };
            amount
        }

        // @dev - Internal function to find any non-native L2 token which is sufficient to cover withdrawal
        // we dont need to calculate from sorted list since we do not care which non-native token is used
        fn _find_sufficient_single_non_native_token(
            self: @ContractState, token_balance_list: Array<TokenAmount>, amount: u256
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
                if (amount <= *token_balance_list.at(index).amount) {
                    l2_address = *token_balance_list.at(index).l2_address;
                    break ();
                }
                index += 1;
            };
            l2_address
        }

        // @dev - Internal function to check whether balance for native L2 token is sufficient to cover withdrawal
        fn _check_if_native_balance_sufficient(
            self: @ContractState,
            withdrawal_amount: u256,
            bridge_address: ContractAddress,
            native_token: ContractAddress
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

        // @dev - Internal function to create list of tokens for a user for which user has non-zero balance
        fn _create_token_balance_list(
            self: @ContractState,
            token_list: @Array<ContractAddress>,
            user: ContractAddress,
            l1_token_address: EthAddress
        ) -> Array<TokenAmount> {
            let mut index = 0_u32;
            let zero_balance = u256 { low: 0, high: 0 };
            let mut user_token_list = ArrayTrait::<TokenAmount>::new();
            loop {
                if (index == token_list.len()) {
                    break ();
                }

                let balance = IERC20Dispatcher {
                    contract_address: *token_list[index]
                }.balance_of(user);

                if (balance > zero_balance) {
                    user_token_list
                        .append(
                            TokenAmount {
                                l1_address: l1_token_address,
                                l2_address: *token_list[index],
                                amount: balance
                            }
                        )
                }

                index += 1;
            };

            user_token_list
        }

        // @dev - Internal function to create list of tokens and amounts that need to be approved and that need to be transferred
        // We iterate through the token_balance_list (which is sorted in decreasing order of balances) to create approval
        // and transfer lists using the minimum number of tokens
        fn _create_approval_and_transfer_list(
            self: @ContractState,
            token_balance_list: @Array<TokenAmount>,
            withdrawal_amount: u256,
            user: ContractAddress,
            bridge: ContractAddress
        ) -> (Array<TokenAmount>, Array<TokenAmount>) {
            let mut index = 0_u32;
            let mut approval_list = ArrayTrait::<TokenAmount>::new();
            let mut transfer_list = ArrayTrait::<TokenAmount>::new();
            let mut balance_left = withdrawal_amount;
            let zero_balance = u256 { low: 0, high: 0 };
            loop {
                if (index == token_balance_list.len()) {
                    break ();
                }

                if (balance_left <= *token_balance_list.at(index).amount) {
                    let allowance = IERC20Dispatcher {
                        contract_address: *token_balance_list.at(index).l2_address
                    }.allowance(user, bridge);
                    if (allowance < balance_left) {
                        approval_list
                            .append(
                                TokenAmount {
                                    l1_address: *token_balance_list.at(index).l1_address,
                                    l2_address: *token_balance_list.at(index).l2_address,
                                    amount: balance_left - allowance
                                }
                            );
                    }

                    transfer_list
                        .append(
                            TokenAmount {
                                l1_address: *token_balance_list.at(index).l1_address,
                                l2_address: *token_balance_list.at(index).l2_address,
                                amount: balance_left
                            }
                        );
                    balance_left = u256 { low: 0, high: 0 };
                    break ();
                } else {
                    let allowance = IERC20Dispatcher {
                        contract_address: *token_balance_list.at(index).l2_address
                    }.allowance(user, bridge);
                    if (allowance < *token_balance_list.at(index).amount) {
                        approval_list
                            .append(
                                TokenAmount {
                                    l1_address: *token_balance_list.at(index).l1_address,
                                    l2_address: *token_balance_list.at(index).l2_address,
                                    amount: *token_balance_list.at(index).amount - allowance
                                }
                            );
                    }
                    transfer_list
                        .append(
                            TokenAmount {
                                l1_address: *token_balance_list.at(index).l1_address,
                                l2_address: *token_balance_list.at(index).l2_address,
                                amount: *token_balance_list.at(index).amount
                            }
                        );
                    balance_left -= *token_balance_list.at(index).amount;
                }

                index += 1;
            };

            assert(balance_left == zero_balance, 'SW: Insufficient balance');
            (approval_list, transfer_list)
        }

        // @dev - Recursive function to transfer all user tokens to the bridge
        fn _transfer_user_tokens(
            self: @ContractState,
            transfer_list: Array<TokenAmount>,
            user: ContractAddress,
            bridge_address: ContractAddress,
        ) {
            let mut index = 0_u32;
            let transfer_list_len = transfer_list.len();
            loop {
                if (index == transfer_list_len) {
                    break ();
                }
                // Transfer amount that can be withdrawn after deducting fee to Starkway
                IERC20Dispatcher {
                    contract_address: *transfer_list.at(index).l2_address
                }.transfer_from(user, bridge_address, *transfer_list.at(index).amount);
                index += 1;
            };
        }
    }
}
