#[starknet::contract]
mod HistoricalDataPlugin {

    #[derive(Copy, Drop, Destruct, Serde, storage_access::StorageAccess)]
    struct MessageBasicInfo {
        l1_token_address: EthAddress,
        l2_token_address: ContractAddress,
        l1_sender_address: EthAddress,
        l2_recipient_address: ContractAddress,
        amount: u256,
        fee: u256,
        timestamp: felt252,
        message_payload_len: u32,
    }

    #[storage]
    struct Storage {
        number_of_messages:LegacyMap::<ContractAddress, u64>,
        msg_basic_info:LegacyMap::<(ContractAddress, u64), MessageBasicInfo>,
        msg_payload_data:LegacyMap::<(ContractAddress, u64, u32), felt252>,
        starkway_address: ContractAddress,
        write_permission_required: LegacyMap::<ContractAddress, bool>,
        allow_list_len: u32,
        allow_list:LegacyMap::<(ContractAddress, u32), ContractAddress>,
        allow_list_index: LegacyMap::<(ContractAddress, ContractAddress), u32>,
        whitelisted_address: LegacyMap::<(ContractAddress, ContractAddress), bool>,
        data_pointer: LegacyMap<ContractAddress, u64>,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        starkway_address: ContractAddress
    ) {

        assert(starkway_address.is_non_zero(), 'HDP: Invalid starkway addr');
        self.starkway_address.write(starkway_address);
    }

    #[generate_trait]
    #[external(v0)]
    impl HistoricalDataPlugin of IHistoricalDataPlugin<ContractState> {

        fn get_allow_list_len(self: @ContractState, consumer: ContractAddress) -> u64 {
            self.allow_list_len.read(consumer)
        }

        fn get_allow_list(self: @ContractState, consumer: ContractAddress) -> Array<ContractAddress> {

            let mut allow_list = ArrayTrait::new();

            let mut index = 0_u32;
            let allow_list_len = self.allow_list_len(consumer);
            loop {

                if(index == allow_list_len) {
                    break();
                }

                allow_list.append(self.allow_list.read((consumer, index)));
                index += 1;
            };

            allow_list
        }

        fn get_message_info_at_index(
            self: @ContractState, 
            consumer: ContractAddress, 
            message_index: u64) -> MessageBasicInfo {

            self.msg_basic_info.read((consumer, message_index))
        }

        fn get_message_at_index(
            self: @ContractState,
            consumer: ContractAddress,
            message_index: u64) -> (MessageBasicInfo, Array<felt252>) {

            return _read_message(consumer, message_index);

        }

        fn get_message_pointer(self: @ContractState, consumer: ContractAddress) -> u64 {

            self.data_pointer.read(consumer)
        }

        fn get_total_messages_count(self: @ContractState, consumer: ContractAddress) -> u64 {

            self.number_of_messages.read(consumer)
        }

        fn get_starkway_address(self: @ContractState) -> ContractAddress {
            self.starkway_address.read()
        }

        fn is_allowed_to_write(
            self: @ContractState, 
            consumer: ContractAddress, 
            writer: EthAddress) -> bool {

            _resolve_is_allowed_to_write(consumer, writer)
        }
    }

    #[generate_trait]
    impl HistoricalDataPluginPrivatefunctions of IHistoricalDataPluginPrivatefunctions {

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

                msg.append(self.message_payload_data.read((consumer, msg_index, index)));
                index +=1;
            };

            (msg_basic_info, msg)
        }

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