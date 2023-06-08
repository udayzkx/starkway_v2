use starknet::ContractAddress;
use starkway::datatypes::{l1_address::L1Address, l1_token_details::L1TokenDetails};

#[abi]
trait IAdminAuth {
    #[view]
    fn get_is_allowed(address: ContractAddress) -> bool;
}


#[abi]
trait IStarkway {
    fn get_whitelisted_token_addresses(l1_token_address: L1Address) -> Array<ContractAddress>;
    fn get_supported_tokens() -> Array<L1Address>;
    fn get_native_token_address(l1_token_address: L1Address) -> ContractAddress;
    fn get_l1_token_details(l1_token_address: L1Address) -> L1TokenDetails;
}

#[abi]
trait IERC20 {
    fn name() -> felt252;
    fn symbol() -> felt252;
    fn decimals() -> u8;
    fn total_supply() -> u256;
    fn balance_of(account: ContractAddress) -> u256;
    fn allowance(owner: ContractAddress, spender: ContractAddress) -> u256;
    fn transfer(recipient: ContractAddress, amount: u256) -> bool;
    fn transfer_from(sender: ContractAddress, recipient: ContractAddress, amount: u256) -> bool;
    fn approve(spender: ContractAddress, amount: u256) -> bool;
    fn mint(to: ContractAddress, amount: u256);
}
