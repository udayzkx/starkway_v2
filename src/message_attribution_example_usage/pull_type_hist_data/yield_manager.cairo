
#[derive(Copy, Drop, Destruct, Serde, storage_access::StorageAccess)]
struct CumulativeYieldData {
    cumulative_deposit: u256,
    cumulative_interest: u256,
    last_calc_timestamp: u64
}

#[starknet::interface]
trait IYieldManager {

    fn get_yield_info(
        self: @ContractState, 
        user_address: ContractAddress, 
        vault_id: u32) -> CumulativeYieldData;
    
    fn calculate_incremental_yield(ref self: ContractState);
    fn set_yield_manager_l1_address(ref self: ContractState, yield_manager_l1: EthAddress);
    fn set_interest_rate(ref self: ContractState, vault_id: u32, interest_rate: u16);
}

#[starknet::contract]
mod YieldManager {

    use super::CumulativeYieldData;

    #[storage]
    struct Storage {
        plugin: ContractAddress,
        last_read_timestamp: u64,
        vault_to_interest: LegacyMap<u32, u16>,
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


    fn set_interest_rate(ref self: ContractState, vault_id: u32, interest_rate: u16) {

        assert(get_caller_address() == self.owner.read(), 'YM: Only owner can call');
        self.vault_to_interest.write(vault_id, interest_rate);
    }

}