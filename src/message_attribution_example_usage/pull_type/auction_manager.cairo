use core::traits::TryInto;
use starknet::{ContractAddress, EthAddress};

// This application code is for illustrative purposes only
#[starknet::interface]
trait IAuctionManager<TContractState> {
    fn get_auction_winner(self: @TContractState, auction_id: u32) -> EthAddress;
    fn get_starkway_address(self: @TContractState) -> ContractAddress;
    fn get_known_index_plugin_address(self: @TContractState) -> ContractAddress;
    fn handle_starkway_deposit_message(
        ref self: TContractState,
        l1_token_address: EthAddress,
        l2_token_address: ContractAddress,
        l1_sender_address: EthAddress,
        l2_recipient_address: ContractAddress,
        amount: u256,
        fee: u256,
        message_payload: Array<felt252>,
    );
}

#[starknet::contract]
mod AuctionManager {
    use array::{Array, ArrayTrait};
    use integer::{u32_try_from_felt252, u128_try_from_felt252};
    use starknet::{
        ContractAddress, EthAddress, eth_address::EthAddressZeroable, get_caller_address,
        get_contract_address, eth_address::Felt252TryIntoEthAddress
    };
    use option::OptionTrait;
    use starkway::plugins::datatypes::{MessageBasicInfo};
    use starkway::plugins::interfaces::{
        IKnownIndexPluginDispatcher, IKnownIndexPluginDispatcherTrait
    };
    use zeroable::Zeroable;

    /////////////
    // Storage //
    /////////////

    #[storage]
    struct Storage {
        s_starkway_address: ContractAddress, // Address of the starkway contract
        s_known_index_plugin_address: ContractAddress, // Address of known index plugin for retrieving application specific data
        s_auction_winner: LegacyMap::<u32,
        EthAddress>, // Stores L1 address of winner for an auction
    }

    /////////////////
    // Constructor //
    /////////////////

    // @notice Constructor for the contract
    // @param starkway_address - Address of Starkway contract in Starknet
    // @param known_index_plugin_address - Address of Known Index plugin contract in Starknet
    #[constructor]
    fn constructor(
        ref self: ContractState,
        starkway_address: ContractAddress,
        known_index_plugin_address: ContractAddress
    ) {
        assert(starkway_address.is_non_zero(), 'AM:Starkway address is zero');
        self.s_starkway_address.write(starkway_address);
        assert(known_index_plugin_address.is_non_zero(), 'AM: Known index address is zero');
        self.s_known_index_plugin_address.write(known_index_plugin_address);
    }

    #[external(v0)]
    impl AuctionManager of super::IAuctionManager<ContractState> {
        //////////
        // View //
        //////////

        // @notice Function to get winning address corresponding to an auction id
        // @param auction_id - ID corresponding to an auction
        // @return L1 address of the winner in the auction
        fn get_auction_winner(self: @ContractState, auction_id: u32) -> EthAddress {
            self.s_auction_winner.read(auction_id)
        }

        // @notice Function to get starkway address
        // @return Starkway contract address
        fn get_starkway_address(self: @ContractState) -> ContractAddress {
            self.s_starkway_address.read()
        }

        // @notice Function to get known index plugin address
        // @return known index plugin address
        fn get_known_index_plugin_address(self: @ContractState) -> ContractAddress {
            self.s_known_index_plugin_address.read()
        }

        //////////////
        // External //
        //////////////

        /// @notice This message handler expects a payload of atleast length 1
        /// These data elements are auction_id followed by list of bidders (L1 addresses)
        /// The argument list is as per starkway defined interface for deposit message handlers
        fn handle_starkway_deposit_message(
            ref self: ContractState,
            l1_token_address: EthAddress,
            l2_token_address: ContractAddress,
            l1_sender_address: EthAddress,
            l2_recipient_address: ContractAddress,
            amount: u256,
            fee: u256,
            message_payload: Array<felt252>,
        ) {
            let caller = get_caller_address();
            let starkway_address = self.s_starkway_address.read();
            assert(caller == starkway_address, 'AM: Only Starkway calls allowed');

            // Unpack payload
            let message_payload_len = message_payload.len();
            assert(message_payload_len >= 1, 'AM: Invalid payload length');
            let auction_id: u32 = u32_try_from_felt252(*message_payload.at(0)).unwrap();

            let this_address = get_contract_address();

            let winner = self
                ._calculate_winner(l1_sender_address, this_address, auction_id, message_payload);

            // Here, for simplicity we are just writing the winning address to a storage var
            // However, a real-world application would probably transfer the asset to winner or send a message to L1 for doing it
            self.s_auction_winner.write(auction_id, winner);
        }
    }

    #[generate_trait]
    impl AuctionManagerPrivateFunctions of IAuctionManagerPrivateFunctions {
        //////////////
        // Internal //
        //////////////

        /// @notice Recursive function to calculate winning bidder from the given bidder list
        /// For every bidder a call is made to the KnownIndexPlugin to retrieve the final cumulative bid amount
        fn _calculate_winner(
            self: @ContractState,
            l1_sender_address: EthAddress,
            l2_recipient_address: ContractAddress,
            auction_id: u32,
            bidder_list: Array<felt252>
        ) -> EthAddress {
            let mut current_index =
                1_u32; // Index starts from 1 becuase, 0th index is the auction id
            let mut current_winning_amount = u256 { low: 0, high: 0 };
            let bidder_list_len = bidder_list.len();
            let mut current_winner: EthAddress = EthAddressZeroable::zero();
            loop {
                if (current_index == bidder_list_len) {
                    break ();
                }

                let (MessageBasicInfo, message_payload) = IKnownIndexPluginDispatcher {
                    contract_address: self.s_known_index_plugin_address.read()
                }
                    .get_last_message(
                        l1_sender_address,
                        l2_recipient_address,
                        u32_try_from_felt252(*bidder_list.at(current_index)).unwrap(),
                        auction_id,
                    );

                assert(message_payload.len() == 4, 'AM:Invalid payload retrieved');

                // assert message payload len is exactly 4
                let bid_amount_low = u128_try_from_felt252(*message_payload.at(2)).unwrap();
                let bid_amount_high = u128_try_from_felt252(*message_payload.at(3)).unwrap();
                let bid_amount = u256 { low: bid_amount_low, high: bid_amount_high };

                // If this bid is better than current bid, then update the winning amount and winner
                if (current_winning_amount < bid_amount) {
                    current_winning_amount = bid_amount;
                    current_winner =
                        Felt252TryIntoEthAddress::try_into(*bidder_list.at(current_index))
                        .unwrap();
                }
                current_index += 1;
            };
            return current_winner;
        }
    }
}
