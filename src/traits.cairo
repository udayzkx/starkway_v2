use starknet::ContractAddress;
use starkway::datatypes::{ 
        l2_token_details::L2TokenDetails, 
        l1_address::L1Address,
    };

#[abi]
trait IAdminAuth {
    #[view]
    fn get_is_allowed(address: ContractAddress) -> bool;
}

#[abi]
trait IERC20 {

    #[external]
    fn transfer(recipient: ContractAddress, amount: u256) -> bool;

    #[external]
    fn transfer_from(sender: ContractAddress, recipient: ContractAddress, amount: u256) -> bool;

    #[external]
    fn burn(amount: u256);
}

#[abi]
trait IBridgeAdapter {
    #[external]
    fn withdraw(
        token_bridge_address: ContractAddress,
        l2_token_address: ContractAddress,
        l1_recipient: L1Address,
        withdrawal_amount: u256,
        user: ContractAddress
    );
}