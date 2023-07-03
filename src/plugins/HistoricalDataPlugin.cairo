#[starknet::contract]
mod HistoricalDataPlugin {

    use array::{Array, ArrayTrait, Span};
    use core::integer::u256;
    use core::result::ResultTrait;
    use option::OptionTrait;
    use starknet::{
        ContractAddress,
        contract_address::ContractAddressZeroable, EthAddress, get_caller_address,
        contract_address::Felt252TryIntoContractAddress,
        contract_address::contract_address_try_from_felt252,
        get_contract_address, get_block_timestamp,
        eth_address::EthAddressZeroable
    };
    use traits::{Default, Into, TryInto};
    use zeroable::Zeroable;
    use starkway::plugins::datatypes::{MessageBasicInfo, LegacyHashContractAddressEthAddress};
    use starkway::plugins::interfaces::IHistoricalDataPlugin;

    #[storage]
    struct Storage {
        number_of_messages:LegacyMap::<ContractAddress, u64>,
        msg_basic_info:LegacyMap::<(ContractAddress, u64), MessageBasicInfo>,
        msg_payload_data:LegacyMap::<(ContractAddress, u64, u32), felt252>,
        starkway_address: ContractAddress,
        write_permission_required: LegacyMap::<ContractAddress, bool>,
        allow_list_len: LegacyMap<ContractAddress, u32>,
        allow_list:LegacyMap::<(ContractAddress, u32), EthAddress>,
        allow_list_index: LegacyMap::<(ContractAddress, EthAddress), u32>,
        whitelisted_address: LegacyMap::<(ContractAddress, EthAddress), bool>,
        data_pointer: LegacyMap<ContractAddress, u64>,
    }

    /////////////////
    // Constructor //
    /////////////////

    /// @notice Constructor for the contract
    /// @param starkway_address - Address of Starkway contract in Starknet
    #[constructor]
    fn constructor(
        ref self: ContractState,
        starkway_address: ContractAddress
    ) {
        assert(starkway_address.is_non_zero(), 'HDP: Invalid starkway addr');
        self.starkway_address.write(starkway_address);
    }

    // Concrete implementation of the external (read/write) functions
    #[external(v0)]
    impl HistoricalDataPlugin of IHistoricalDataPlugin<ContractState> {

        //////////
        // View //
        //////////

        // @notice - Returns length of allow list (or number of addresses in allow list) for a consumer
        fn get_allow_list_len(self: @ContractState, consumer: ContractAddress) -> u32 {
            self.allow_list_len.read(consumer)
        }

        // @notice - Returns allow list for a consumer
        // @param consumer - address for which allow list needs to be returned
        // @return - Array of EthAddress which are allowed to write messages to store for consumer
        fn get_allow_list(self: @ContractState, consumer: ContractAddress) -> Array<EthAddress> {
            let mut allow_list = ArrayTrait::new();

            let mut index = 0_u32;
            let allow_list_len = self.allow_list_len.read(consumer);
            loop {

                if(index == allow_list_len) {
                    break();
                }
                allow_list.append(self.allow_list.read((consumer, index)));
                index += 1;
            };
            allow_list
        }

        // @notice - Function to get basic message info (apart from payload) for a consumer, index combination
        fn get_message_info_at_index(
            self: @ContractState, 
            consumer: ContractAddress, 
            message_index: u64) -> MessageBasicInfo {

            self.msg_basic_info.read((consumer, message_index))
        }

        // @notice - Function to get actual custom data stored for a consumer, message_index combination
        // This reads without updating pointer for the stored message array
        fn get_message_at_index(
            self: @ContractState,
            consumer: ContractAddress,
            message_index: u64) -> (MessageBasicInfo, Array<felt252>) {

            return self._read_message(consumer, message_index);

        }

        // @notice - Function to get current pointer value for message list for consumer
        // This pointer represents the oldest unread message
        fn get_message_pointer(self: @ContractState, consumer: ContractAddress) -> u64 {

            self.data_pointer.read(consumer)
        }

        // @notice - Function to get total number of messages stored for consumer
        fn get_total_messages_count(self: @ContractState, consumer: ContractAddress) -> u64 {

            self.number_of_messages.read(consumer)
        }

        /// @notice - To view Starkway's address in Starknet
        fn get_starkway_address(self: @ContractState) -> ContractAddress {
            self.starkway_address.read()
        }

        // @notice - Function to ascertain whether 'writer' can store messages for 'consumer' or write to its message list
        fn is_allowed_to_write(
            self: @ContractState, 
            consumer: ContractAddress, 
            writer: EthAddress) -> bool {

            self._resolve_is_allowed_to_write(consumer, writer)
        }


        //////////////
        // External //
        //////////////

        // @notice - Callback function which will be called by the L1 deposit handler from starkway
        // Following is the data format that is expected
        // message_payload[0] -> Address of intended consumer for this message - 
        // message will be stored in mapping for this consumer
        // message_payload[1..] -> arbitrary custom data that will be stored for consumer at current index
        // In effect this stores custom data for the last deposit made by a particular sender for a particular consumer
        // Additionally the current timestamp is also stored before the custom data
        // This data is appended to message list for the consumer

        fn handle_starkway_deposit_message(
            ref self: ContractState,
            l1_token_address: EthAddress,
            l2_token_address: ContractAddress,
            l1_sender_address: EthAddress,
            l2_recipient_address: ContractAddress,
            amount: u256,
            fee: u256,
            message_payload: Array<felt252>
        ) {
            assert(get_caller_address() == self.starkway_address.read(), 'HDP: Caller not SW');
            assert(message_payload.len() >= 1, 'HDP: Invalid payload length');

            let temp_felt_address = *message_payload.at(0_u32);
            let consumer: ContractAddress = contract_address_try_from_felt252(temp_felt_address).unwrap();

            assert(self._resolve_is_allowed_to_write(consumer, l1_sender_address), 'HDP: Unauthorised write');

            let timestamp = get_block_timestamp();

            let msg_basic_info = MessageBasicInfo{
                l1_token_address: l1_token_address,
                l2_token_address: l2_token_address,
                l1_sender_address: l1_sender_address,
                l2_recipient_address: l2_recipient_address,
                amount: amount,
                fee: fee,
                timestamp: timestamp,
                message_payload_len: message_payload.len(),
            };

            let msg_count = self.number_of_messages.read(consumer);
            self.number_of_messages.write(consumer, msg_count + 1);
            self.msg_basic_info.write((consumer, msg_count), msg_basic_info);
            
            let mut index = 0_u32;
            loop {
                if (index == message_payload.len()) {
                    break();
                }

                self.msg_payload_data.write((consumer, msg_count, index), *message_payload.at(index));
                index +=1;
            };
        }

        // @notice - Called by a consuming address to read the next unread message in the message list and advance data pointer
        // since the data is being returned - this function is intended to be used by smart contracts on-chain
        // @return - basic message info (ref: MessageBasicInfo struct) and message payload
        fn fetch_next_message_and_move_pointer(ref self: ContractState) -> (MessageBasicInfo, Array<felt252>) {

            let consumer = get_caller_address();
            let current_pointer = self.data_pointer.read(consumer);
            self.data_pointer.write(consumer, current_pointer + 1);
            self._read_message(consumer, current_pointer)
        }

        // @notice - Function used by a consumer to set global permission for its message list
        // @param permission - true (write based on allow list) / false (any address can write/store message)
        fn set_permission_required(ref self: ContractState, permission: bool) {

            let consumer = get_caller_address();
            self.write_permission_required.write(consumer, permission);
        }

        // @notice - Funcition to be used by a consumer to add an L1 address to its allow list
        // @param address - L1 address to be whitelisted
        fn add_to_allow_list(ref self: ContractState, eth_address: EthAddress) {

            // caller of this function becomes consumer and can modify allow list only for itself
            let consumer = get_caller_address();
            assert(!self.whitelisted_address.read((consumer, eth_address)), 'HDP: Already whitelisted');
            let current_allow_list_len = self.allow_list_len.read(consumer);
            self.allow_list_len.write(consumer, current_allow_list_len + 1);
            self.allow_list.write((consumer, current_allow_list_len), eth_address);
            self.whitelisted_address.write((consumer, eth_address), true);
            self.allow_list_index.write((consumer, eth_address), current_allow_list_len);
        }

        // @notice - Funcition to be used by a consumer to remove an L1 address from its allow list
        // @param address - L1 address to be removed from allow list
        fn remove_from_allow_list(ref self: ContractState, eth_address: EthAddress) {

            let consumer = get_caller_address();
            assert(self.whitelisted_address.read((consumer, eth_address)), 'HDP: Already de-whitelisted');

            let current_len = self.allow_list_len.read(consumer);
            let current_index = self.allow_list_index.read((consumer, eth_address));

            // If address is last in the allow list, simply remove without swapping
            if (current_len - current_index == 1) {

                self.whitelisted_address.write((consumer, eth_address), false);
                self.allow_list_len.write(consumer, current_len - 1);
                self.allow_list.write((consumer, current_index), EthAddressZeroable::zero());
                self.allow_list_index.write((consumer, eth_address), 0_u32); 
            }
            else {
                // Swap last address in list with address to be removed
                // Also update index for this address in allow_list_index

                self.whitelisted_address.write((consumer, eth_address), false);
                self.allow_list_len.write(consumer, current_len - 1);

                let last_address = self.allow_list.read((consumer, current_len - 1));
                self.allow_list.write((consumer, current_index), last_address);
                self.allow_list.write((consumer, current_len - 1), EthAddressZeroable::zero());
                self.allow_list_index.write((consumer, eth_address), 0_u32);
                self.allow_list_index.write((consumer, last_address), current_index);
            }
        }
    }

    #[generate_trait]
    impl HistoricalDataPluginPrivatefunctions of IHistoricalDataPluginPrivatefunctions {

        /// @dev - Helper function to populate array of message payload data
        /// @param consumer - address of the consumer of the message
        /// @param msg_index - index of the message
        /// @return - basic message info (ref: MessageBasicInfo struct) and message payload
        fn _read_message(
            self: @ContractState,
            consumer: ContractAddress,
            msg_index: u64) -> (MessageBasicInfo, Array<felt252>) {

            assert(msg_index < self.number_of_messages.read(consumer), 'HDP: Msg index out of bounds');
            let msg_basic_info = self.msg_basic_info.read((consumer, msg_index));

            let payload_len = msg_basic_info.message_payload_len;
            let mut msg = ArrayTrait::new();
            let mut index = 0_u32;

            loop {

                if(index == payload_len) {
                    break();
                }

                msg.append(self.msg_payload_data.read((consumer, msg_index, index)));
                index +=1;
            };

            (msg_basic_info, msg)
        }

        // @dev - Function to check whether writer can write to or store messages in the message list for a consuming address
        fn _resolve_is_allowed_to_write(
            self: @ContractState, 
            consumer: ContractAddress, 
            writer: EthAddress) -> bool {

            let global_permission = self.write_permission_required.read(consumer);
            if (global_permission) {
                return true;
            }
            
            let is_whitelisted = self.whitelisted_address.read((consumer, writer));
            is_whitelisted
        }
    }

}