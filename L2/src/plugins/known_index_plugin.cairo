#[starknet::contract]
mod KnownIndexPlugin {
    use array::{Array, ArrayTrait};
    use integer::u32_try_from_felt252;
    use option::OptionTrait;
    use starknet::{
        ContractAddress, EthAddress, eth_address::Felt252TryIntoEthAddress, get_block_timestamp,
        get_caller_address
    };
    use starkway::plugins::datatypes::{
        DropEthAddressContractAddressU32U32U32, LegacyHashEthContractEthU32,
        LegacyHashEthContractEthU32U32, MessageBasicInfo
    };
    use starkway::plugins::interfaces::IKnownIndexPlugin;
    use zeroable::Zeroable;

    /////////////
    // Storage //
    /////////////

    #[storage]
    struct Storage {
        s_last_msg_basic_info: LegacyMap::<(EthAddress, ContractAddress, EthAddress, u32),
        MessageBasicInfo>,
        s_last_msg_payload_data: LegacyMap::<(EthAddress, ContractAddress, EthAddress, u32, u32),
        felt252>,
        s_starkway_address: ContractAddress,
    }

    /////////////////
    // Constructor //
    /////////////////

    /// @notice Constructor for KnownIndexPlugin contract
    /// @param starkway_address - Starkway contract's address in Starknet
    #[constructor]
    fn constructor(ref self: ContractState, starkway_address: ContractAddress) {
        assert(starkway_address.is_non_zero(), 'KIP: Starkway address is zero');
        self.s_starkway_address.write(starkway_address);
    }

    #[external(v0)]
    impl KnownIndexPlugin of IKnownIndexPlugin<ContractState> {
        //////////
        // View //
        //////////

        // @notice - Function to get last message info
        fn get_last_message_info(
            self: @ContractState,
            sender: EthAddress,
            recipient: ContractAddress,
            index_1: EthAddress,
            index_2: u32,
        ) -> MessageBasicInfo {
            self.s_last_msg_basic_info.read((sender, recipient, index_1, index_2))
        }

        // @notice - Function to get last message
        fn get_last_message(
            self: @ContractState,
            sender: EthAddress,
            recipient: ContractAddress,
            index_1: EthAddress,
            index_2: u32
        ) -> (MessageBasicInfo, Array<felt252>) {
            let info = self.s_last_msg_basic_info.read((sender, recipient, index_1, index_2));
            let message_payload_len = info.message_payload_len;
            let message_payload: Array<felt252> = self
                ._read_payload_data(sender, recipient, index_1, index_2, message_payload_len);

            return (info, message_payload);
        }

        // @notice - Function to get current starkway address
        fn get_starkway_address(self: @ContractState) -> ContractAddress {
            self.s_starkway_address.read()
        }

        //////////////
        // External //
        //////////////

        // @notice - Callback function which will be called by the L1 deposit handler from starkway
        // Following is the data format that is expected
        // message_payload[0..9] -> fixed as per Starkway - all deposit related data
        // message_payload[9..] -> arbitrary custom data that will be stored for (sender, recipient) index
        // length of total message_payload is (9 + length of custom data that will be stored)
        // In effect this stores custom data for the last deposit made by a particular sender to a particular recipient
        // Additionally the current timestamp is also stored before the custom data
        // The only way to overwrite data is for the particular sender to deposit tokens to the same recipient
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
            let caller = get_caller_address();
            let starkway_address = self.s_starkway_address.read();
            assert(caller == starkway_address, 'KIP:ONLY_STARKWAY_CALLS_ALLOWED');

            // Prepare message basic info
            let now_timestamp = get_block_timestamp();
            let info = MessageBasicInfo {
                l1_token_address: l1_token_address,
                l2_token_address: l2_token_address,
                l1_sender_address: l1_sender_address,
                l2_recipient_address: l2_recipient_address,
                amount: amount,
                fee: fee,
                timestamp: now_timestamp,
                message_payload_len: message_payload.len()
            };

            assert(message_payload.len() >= 2, 'KIP: Invalid payload size');

            let index_1: EthAddress = Felt252TryIntoEthAddress::try_into(*message_payload.at(0))
                .unwrap();
            let index_2: u32 = u32_try_from_felt252(*message_payload.at(1)).unwrap();

            // Store message to storage
            self
                .s_last_msg_basic_info
                .write((l1_sender_address, l2_recipient_address, index_1, index_2), info);
            self
                ._store_payload_data(
                    l1_sender_address, l2_recipient_address, index_1, index_2, message_payload
                );
        }
    }


    #[generate_trait]
    impl KnownIndexPrivateFunctions of IKnownIndexPrivateFunctions {
        //////////////
        // Internal //
        //////////////

        /// @dev - Recursive helper function to store message's payload data
        /// @param sender - Who sent funds (L1 address)
        /// @param recipient - Who received funds (L2 address)
        /// @param index_1, index_2 - Application specific indexes
        /// @param data - Data array to store
        fn _store_payload_data(
            ref self: ContractState,
            sender: EthAddress,
            recipient: ContractAddress,
            index_1: EthAddress,
            index_2: u32,
            data: Array<felt252>
        ) {
            let data_len = data.len();
            let mut data_index = 0_u32;
            loop {
                if (data_index == data_len) {
                    break ();
                }
                self
                    .s_last_msg_payload_data
                    .write((sender, recipient, index_1, index_2, data_index), *data.at(data_index));
                data_index += 1;
            };
        }

        /// @dev - Recursive helper function to read message's payload data
        /// @param sender - Who sent funds (L1 address)
        /// @param recipient - Who received funds (L2 address)
        /// @param index_1, index_2 - Application specific indexes
        /// @param payload_data_len - length of message payload
        fn _read_payload_data(
            self: @ContractState,
            sender: EthAddress,
            recipient: ContractAddress,
            index_1: EthAddress,
            index_2: u32,
            payload_data_len: u32
        ) -> Array<felt252> {
            let mut payload_data = ArrayTrait::<felt252>::new();
            let mut index = 0_u32;
            loop {
                if (index == payload_data_len) {
                    break ();
                }
                let value = self
                    .s_last_msg_payload_data
                    .read((sender, recipient, index_1, index_2, index));
                payload_data.append(value);
                index += 1;
            };
            payload_data
        }
    }
}
