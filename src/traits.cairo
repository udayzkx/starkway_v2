use starknet::ContractAddress;

#[abi]
trait IAdminAuth {
    #[view]
    fn get_is_allowed(address: ContractAddress) -> bool;
}

#[abi]
trait IStarkwayERC20 {
    #[external]
    fn mint(to: ContractAddress, amount: u256);
}
