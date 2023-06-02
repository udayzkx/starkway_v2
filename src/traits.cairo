use starknet::ContractAddress;
use starkway::datatypes::{l1_address::L1Address, withdrawal_range::WithdrawalRange};

trait IAdminAuth {
    #[view]
    fn get_is_allowed(address: ContractAddress) -> bool;
}

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
    #[external]
    fn set_withdrawal_range(l1_token_address: L1Address, withdrawal_range: WithdrawalRange);
}
