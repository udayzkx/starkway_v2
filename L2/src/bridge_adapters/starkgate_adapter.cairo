use starknet::{ContractAddress, EthAddress};

#[starknet::interface]
trait IStarkgateTokenBridge<TContractState> {
    fn initiate_withdraw(
        ref self: TContractState, l1_recipient: EthAddress, withdrawal_amount: u256, 
    );
}

#[starknet::contract]
mod StarkgateAdapter {
    use starknet::{ContractAddress, EthAddress};
    use starkway::interfaces::IBridgeAdapter;
    use super::{IStarkgateTokenBridgeDispatcher, IStarkgateTokenBridgeDispatcherTrait};

    #[storage]
    struct Storage {
        starkgate_bridge_address: ContractAddress, 
    }

    #[external(v0)]
    impl StarkgateTokenBridge of IBridgeAdapter<ContractState> {
        fn withdraw(
            ref self: ContractState,
            token_bridge_address: ContractAddress,
            l2_token_address: ContractAddress,
            l1_recipient: EthAddress,
            withdrawal_amount: u256,
            user: ContractAddress
        ) {
            IStarkgateTokenBridgeDispatcher {
                contract_address: token_bridge_address
            }.initiate_withdraw(l1_recipient, withdrawal_amount);
        }
    }
}
