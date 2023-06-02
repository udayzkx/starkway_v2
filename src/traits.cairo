use starknet::ContractAddress;

#[abi]
trait IAdminAuth {
    #[view]
    fn get_is_allowed(address: ContractAddress) -> bool;
}

#[abi]
trait IERC20 {
    #[external]
    fn transfer_from(sender: ContractAddress, recipient: ContractAddress, amount: u256) -> bool;

    #[external]
    fn burn(amount: u256);
}
