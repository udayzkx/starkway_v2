use starknet::ContractAddress;
use starkway::datatypes::{
    l2_token_details::L2TokenDetails, l1_address::L1Address, withdrawal_range::WithdrawalRange,
};

#[abi]
trait IAdminAuth {
    #[view]
    fn get_is_allowed(address: ContractAddress) -> bool;
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
}

#[abi]
trait IStarkway {
    #[view]
    fn get_withdrawal_range(l1_token_address: L1Address) -> WithdrawalRange;
    #[view]
    fn get_admin_auth_address() -> ContractAddress;
    #[external]
    fn set_withdrawal_range(l1_token_address: L1Address, withdrawal_range: WithdrawalRange);
    #[external]
    fn set_admin_auth_address(admin_auth_address: ContractAddress);
}
