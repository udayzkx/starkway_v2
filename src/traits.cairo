use starknet::ContractAddress;
use starkway::utils::l1_address::L1Address;

#[abi]
trait IAdminAuth {
    #[view]
    fn get_is_allowed(address: ContractAddress) -> bool;
}