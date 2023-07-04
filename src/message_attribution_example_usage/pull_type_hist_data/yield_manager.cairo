
use core::integer::u256;
use starknet::{ContractAddress, EthAddress};

#[derive(Copy, Drop, Destruct, Serde, storage_access::StorageAccess)]
struct CumulativeYieldData {
    cumulative_deposit: u256,
    cumulative_interest: u256,
    last_calc_timestamp: u64
}

#[starknet::interface]
trait IYieldManager<TContractState> {

    fn get_yield_info(
        self: @TContractState, 
        user_address: ContractAddress, 
        vault_id: u32) -> CumulativeYieldData;
    
    fn calculate_incremental_yield(ref self: TContractState);
    fn set_yield_manager_l1_address(ref self: TContractState, yield_manager_l1: EthAddress);
    fn set_interest_rate(ref self: TContractState, vault_id: u32, interest_rate: u256);
}

#[starknet::contract]
mod YieldManager {

    use array::{Array, ArrayTrait, Span};
    use core::integer::u256;
    use integer::{u32_try_from_felt252, u128_try_from_felt252, u64_to_felt252};
    use starknet::{
        ContractAddress, contract_address::contract_address_try_from_felt252, EthAddress,
        get_caller_address, get_contract_address, get_block_timestamp
    };
    use option::OptionTrait;
    use zeroable::Zeroable;
    use super::CumulativeYieldData;
    use starkway::plugins::interfaces::{IHistoricalDataPluginDispatcher, IHistoricalDataPluginDispatcherTrait};

    #[storage]
    struct Storage {
        plugin: ContractAddress,
        last_read_timestamp: u64,
        vault_to_interest: LegacyMap<u32, u256>,
        deposit_yield: LegacyMap<(ContractAddress, u32), CumulativeYieldData>,
        yield_manager_l1: EthAddress,
        owner: ContractAddress
    }

    #[constructor]
    fn constructor(
        ref self: ContractState, historical_data_plugin: ContractAddress, owner: ContractAddress
    ) {
        assert(historical_data_plugin.is_non_zero(), 'YM: HDP address cannot be 0');
        self.plugin.write(historical_data_plugin);

        assert(owner.is_non_zero(), 'YM: Owner address cannot be 0');
        self.owner.write(owner);
    }

    fn get_yield_info(
        self: @ContractState, 
        user_address: ContractAddress, 
        vault_id: u32) -> CumulativeYieldData {

        self.deposit_yield.read((user_address, vault_id))
    }

    fn set_yield_manager_l1_address(ref self: ContractState, yield_manager_l1: EthAddress) {

        assert(get_caller_address() == self.owner.read(), 'YM: Only owner can call');
        self.yield_manager_l1.write(yield_manager_l1);
    }


    fn set_interest_rate(ref self: ContractState, vault_id: u32, interest_rate: u256) {

        assert(get_caller_address() == self.owner.read(), 'YM: Only owner can call');
        self.vault_to_interest.write(vault_id, interest_rate);
    }

    fn calculate_incremental_yield(ref self: ContractState) {

        let consumer = get_contract_address();
        let plugin_address = self.plugin.read();
        let current_timestamp = get_block_timestamp();
        let pointer:u64 = IHistoricalDataPluginDispatcher{contract_address: plugin_address}.get_message_pointer(consumer);
        let message_count:u64 = IHistoricalDataPluginDispatcher{contract_address: plugin_address}.get_total_messages_count(consumer);

        self._calculate_yield(pointer, message_count, current_timestamp, plugin_address);

        self.last_read_timestamp.write(current_timestamp);
    }

    #[generate_trait]
    impl YieldManagerPrivateFunctions of IYieldManagerPrivateFunctions {

        fn _calculate_yield(
            ref self: ContractState, 
            pointer: u64, 
            message_count: u64, 
            current_timestamp: u64, 
            plugin_address: ContractAddress) {

            let mut index = pointer;

            loop {
                if (index == message_count) {
                    break();
                }


                let (message_info, payload) = IHistoricalDataPluginDispatcher{contract_address: plugin_address}.
                                                fetch_next_message_and_move_pointer();
                let yield_manager_l1 = self.yield_manager_l1.read();

                assert(message_info.l1_sender_address == yield_manager_l1, 'YM: Invalid L1 sender');

                assert(payload.len() == 3, 'YM: Invalid payload size');

                let vault_id = u32_try_from_felt252(*payload.at(1)).unwrap();
                let user_address = contract_address_try_from_felt252(*payload.at(2)).unwrap();

                let interest_rate = self.vault_to_interest.read(vault_id);
                let yield_data = self.deposit_yield.read((user_address, vault_id));
                let normalizer = u256 {low: 10000, high: 0};
                let time_diff = u256{
                    low: u128_try_from_felt252(u64_to_felt252(current_timestamp - yield_data.last_calc_timestamp)).unwrap(), 
                    high:0};
                let NUM_SECONDS_IN_YEAR = u256 {low: 365*24*60*60, high: 0};
                let previous_interest = (((yield_data.cumulative_deposit*interest_rate)/ normalizer)*time_diff)/ NUM_SECONDS_IN_YEAR;

                let time_diff_for_new_deposit = u256{
                    low:u128_try_from_felt252(u64_to_felt252(current_timestamp - message_info.timestamp)).unwrap(), 
                    high:0};

                let new_interest =  (((message_info.amount*interest_rate)/normalizer)*time_diff_for_new_deposit)/NUM_SECONDS_IN_YEAR;

                let new_total_deposit = yield_data.cumulative_deposit + message_info.amount;
                let new_total_interest = yield_data.cumulative_interest + previous_interest + new_interest;
                let new_yield_data = CumulativeYieldData {
                                        cumulative_deposit: new_total_deposit,
                                        cumulative_interest: new_total_interest,
                                        last_calc_timestamp: current_timestamp
                                    };
                self.deposit_yield.write((user_address, vault_id), new_yield_data);
                index += 1;
                };
            
                
        }


    }

}