use starknet::ContractAddress;

#[abi]
trait IAdminAuth {
    #[view]
    fn get_is_allowed(address: ContractAddress) -> bool;
}