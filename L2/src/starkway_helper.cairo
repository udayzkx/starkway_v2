#[starknet::contract]
mod StarkwayHelper {
    use array::ArrayTrait;
    use starknet::{ContractAddress, EthAddress};
    use zeroable::Zeroable;

    use starkway::interfaces::{
        IStarkwayDispatcher, IStarkwayDispatcherTrait, IERC20Dispatcher, IERC20DispatcherTrait,
        IStarkwayHelper
    };
    use starkway::datatypes::{L1TokenDetails, TokenDetails, TokenInfo};

    /////////////
    // Storage //
    /////////////

    #[storage]
    struct Storage {
        s_starkway_address: ContractAddress, 
    }

    /////////////////
    // Constructor //
    /////////////////

    #[constructor]
    fn constructor(ref self: ContractState, starkway_address: ContractAddress) {
        assert(starkway_address.is_non_zero(), 'SWH: Address is zero');
        self.s_starkway_address.write(starkway_address);
    }

    #[external(v0)]
    impl StarkwayHelperImpl of IStarkwayHelper<ContractState> {
        //////////
        // View //
        //////////

        // @notice function to get supported tokens (both native + non native tokens) with balances
        fn get_supported_tokens_with_balance(
            self: @ContractState, user_address: ContractAddress
        ) -> Array<TokenInfo> {
            // Get starkway contract address
            let starkway_address: ContractAddress = self.s_starkway_address.read();
            // Get all supported l1 token addresses
            let l1_token_addresses: Array<EthAddress> = IStarkwayDispatcher {
                contract_address: starkway_address
            }.get_supported_tokens();

            // Init an empty TokenInfo array
            let mut token_info_array = ArrayTrait::<TokenInfo>::new();

            // Made l1_array_iterator u32 because the l1_token_addresses.len() is of 'u32' size
            let mut l1_array_iterator = 0_u32;

            // Loop through all the l1 addresses
            // For each address:
            //      get native l2 address
            //      if user balance > 0:
            //          Add to the token_info_array 
            //      get whitelisted l2 addresses
            //      for each whitelisted l2 address:
            //          if user_balance > 0:
            //              Add to the token_info_array
            loop {
                // Base condition
                if l1_array_iterator == l1_token_addresses.len() {
                    break ();
                }

                // Get the l1 address at current iteration
                let current_l1_token_address = *l1_token_addresses.at(l1_array_iterator);

                // Get the native l2 address for the corresponding l1 address
                let native_l2_token_address = IStarkwayDispatcher {
                    contract_address: starkway_address
                }.get_native_token_address(current_l1_token_address);

                // Get the l1 token details
                let l1_token_details = IStarkwayDispatcher {
                    contract_address: starkway_address
                }.get_l1_token_details(current_l1_token_address);

                // Get the user's balance of the native l2 token
                let user_balance_native_token = IERC20Dispatcher {
                    contract_address: native_l2_token_address
                }.balance_of(user_address);

                let zero_balance = u256 { low: 0, high: 0 };

                // If the user balance is non-zero, add it to the token_info_array
                if user_balance_native_token > zero_balance {
                    // add it to array
                    token_info_array
                        .append(
                            TokenInfo {
                                l2_address: native_l2_token_address,
                                l1_address: current_l1_token_address,
                                native_l2_address: native_l2_token_address,
                                balance: user_balance_native_token,
                                name: l1_token_details.name,
                                symbol: l1_token_details.symbol,
                                decimals: l1_token_details.decimals,
                            }
                        );
                }

                let non_native_token_info_array: Array<TokenInfo> = self
                    .get_non_native_token_balances(user_address, current_l1_token_address);

                let mut non_native_token_iterator = 0;

                loop {
                    // Base condition
                    if non_native_token_iterator == non_native_token_info_array.len() {
                        break ();
                    }

                    token_info_array
                        .append(*non_native_token_info_array.at(non_native_token_iterator));

                    non_native_token_iterator += 1;
                };

                l1_array_iterator += 1;
            };
            token_info_array
        }

        // @notice function to get all white listed tokens with balances
        fn get_non_native_token_balances(
            self: @ContractState, user_address: ContractAddress, l1_token_address: EthAddress
        ) -> Array<TokenInfo> {
            // Get starkway contract address
            let starkway_address: ContractAddress = self.s_starkway_address.read();
            // Get all whitelisted l2 addresses
            let whitelisted_l2_token_addresses = IStarkwayDispatcher {
                contract_address: starkway_address
            }.get_whitelisted_token_addresses(l1_token_address);

            // Get the native l2 address for the corresponding l1 address
            let native_l2_token_address = IStarkwayDispatcher {
                contract_address: starkway_address
            }.get_native_token_address(l1_token_address);

            // Get the l1 token details
            let l1_token_details = IStarkwayDispatcher {
                contract_address: starkway_address
            }.get_l1_token_details(l1_token_address);

            // Init vars
            let mut non_native_token_info_array = ArrayTrait::<TokenInfo>::new();
            let zero_balance = u256 { low: 0, high: 0 };

            // Made whitelisted_l2_array_iterator 'u32'` because the whitelisted_l2_token_addresses.len() is of 'u32' size
            let mut whitelisted_l2_array_iterator = 0_u32;

            loop {
                // Base condition
                if whitelisted_l2_array_iterator == whitelisted_l2_token_addresses.len() {
                    break ();
                }

                // Get the current whitelisted l2 address at current iteration
                let current_whitelisted_l2_token_address = *whitelisted_l2_token_addresses
                    .at(whitelisted_l2_array_iterator);

                // Get the user's balance of the whitelisted l2 address
                let user_balance_current_whitelisted_token = IERC20Dispatcher {
                    contract_address: current_whitelisted_l2_token_address
                }.balance_of(user_address);

                // If the user balance is non-zero, add it to the non_native_token_info_array
                if user_balance_current_whitelisted_token > zero_balance {
                    non_native_token_info_array
                        .append(
                            TokenInfo {
                                l2_address: current_whitelisted_l2_token_address,
                                l1_address: l1_token_address,
                                native_l2_address: native_l2_token_address,
                                balance: user_balance_current_whitelisted_token,
                                name: l1_token_details.name,
                                symbol: l1_token_details.symbol,
                                decimals: l1_token_details.decimals,
                            }
                        );
                }
                whitelisted_l2_array_iterator += 1;
            };
            non_native_token_info_array
        }

        // @notice function to get list of all supported tokens with Token details
        fn get_supported_tokens(self: @ContractState) -> Array<TokenDetails> {
            // Get starkway contract address
            let starkway_address: ContractAddress = self.s_starkway_address.read();
            // Get all supported l1 token addresses
            let l1_token_addresses: Array<EthAddress> = IStarkwayDispatcher {
                contract_address: starkway_address
            }.get_supported_tokens();

            // Init an empty Tokens array
            let mut tokens_array = ArrayTrait::<TokenDetails>::new();

            // Made l1_array_iterator u32 because the l1_token_addresses.len() is of 'u32' size
            let mut l1_array_iterator = 0_u32;

            // Loop through all the l1 addresses
            // For each address:
            //      get native l2 address
            //      get l1 token details
            //      Add to the tokens_array 
            loop {
                // Base condition
                if l1_array_iterator == l1_token_addresses.len() {
                    break ();
                }

                // Get the l1 address at current iteration
                let current_l1_token_address = *l1_token_addresses.at(l1_array_iterator);

                // Get the native l2 address for the corresponding l1 address
                let native_l2_token_address = IStarkwayDispatcher {
                    contract_address: starkway_address
                }.get_native_token_address(current_l1_token_address);

                // Get the l1 token details
                let l1_token_details = IStarkwayDispatcher {
                    contract_address: starkway_address
                }.get_l1_token_details(current_l1_token_address);

                // add it to array
                tokens_array
                    .append(
                        TokenDetails {
                            name: l1_token_details.name,
                            symbol: l1_token_details.symbol,
                            decimals: l1_token_details.decimals,
                            l1_address: current_l1_token_address,
                            native_l2_address: native_l2_token_address,
                        }
                    );
                l1_array_iterator += 1;
            };
            tokens_array
        }
    }
}
