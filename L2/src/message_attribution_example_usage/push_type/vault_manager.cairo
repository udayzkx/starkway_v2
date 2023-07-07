use starknet::{ContractAddress, EthAddress};

// This application code is for illustrative purposes only
#[starknet::interface]
trait IInvestmentVault<TContractState> {
    fn invest(
        ref self: TContractState,
        custodian_address: ContractAddress,
        token_address: ContractAddress,
        amount: u256
    );
}

#[starknet::interface]
trait IERC20<TContractState> {
    fn approve(ref self: TContractState, spender: ContractAddress, amount: u256) -> bool;
}

#[starknet::interface]
trait IVaultManager<TContractState> {
    fn get_vault_address(self: @TContractState, vault_id: u32) -> ContractAddress;
    fn handle_starkway_deposit_message(
        ref self: TContractState,
        l1_token_address: EthAddress,
        l2_token_address: ContractAddress,
        l1_sender_address: EthAddress,
        l2_recipient_address: ContractAddress,
        amount: u256,
        fee: u256,
        message_payload: Array<felt252>
    );
    fn register_vault_address(
        ref self: TContractState, vault_id: u32, new_vault_address: ContractAddress
    );
}

#[starknet::contract]
mod VaultManager {
    use array::{Array, ArrayTrait};
    use integer::u32_try_from_felt252;
    use starknet::{
        ContractAddress, contract_address::contract_address_try_from_felt252, EthAddress,
        get_caller_address, get_contract_address
    };
    use option::OptionTrait;
    use super::{IERC20Dispatcher, IERC20DispatcherTrait};
    use super::{IInvestmentVaultDispatcher, IInvestmentVaultDispatcherTrait};
    use zeroable::Zeroable;

    /////////////
    // Storage //
    /////////////

    #[storage]
    struct Storage {
        vault_address: LegacyMap::<u32,
        ContractAddress>, // Mapping to store vault_id -> vault_address
        starkway_address: ContractAddress, // Mapping to store contract address of starkway
        owner_address: ContractAddress, // Mapping to store contract address of owner
    }

    /////////////////
    // Constructor //
    /////////////////

    /// @notice Constructor for the contract
    /// @param current_starkway_address - Address of Starkway contract in Starknet
    #[constructor]
    fn constructor(
        ref self: ContractState, starkway_address_: ContractAddress, owner_: ContractAddress
    ) {
        assert(starkway_address_.is_non_zero(), 'VM:Starkway address cannot be 0');
        self.starkway_address.write(starkway_address_);

        assert(owner_.is_non_zero(), 'VM: Owner address cannot be 0');
        self.owner_address.write(owner_);
    }

    #[external(v0)]
    impl VaultManagerImpl of super::IVaultManager<ContractState> {
        //////////
        // View //
        //////////

        // function to get the vault address
        fn get_vault_address(self: @ContractState, vault_id: u32) -> ContractAddress {
            self.vault_address.read(vault_id)
        }

        //////////////
        // External //
        //////////////

        /// This message handler expects a payload of length 2
        /// These two data elements are vault id and user L2 address (which acts like a custodian and can issue withdrawals)
        fn handle_starkway_deposit_message(
            ref self: ContractState,
            l1_token_address: EthAddress,
            l2_token_address: ContractAddress,
            l1_sender_address: EthAddress,
            l2_recipient_address: ContractAddress,
            amount: u256,
            fee: u256,
            message_payload: Array<felt252>
        ) {
            let caller = get_caller_address();
            let starkway = self.starkway_address.read();
            assert(caller == starkway, 'VM: Only Starkway calls allowed');

            // Check payload size
            assert(message_payload.len() == 2, 'VM: Incorrect payload size');

            // Unpack payload
            let vault_id: u32 = u32_try_from_felt252(*message_payload.at(0)).unwrap();
            let custodian_address: ContractAddress = contract_address_try_from_felt252(
                *message_payload.at(1)
            )
                .unwrap();

            let current_vault_address = self.vault_address.read(vault_id);

            // Check that we have a vault manager corresponding to the vault id
            assert(current_vault_address.is_non_zero(), 'VM: Invalid vault Id');

            let vault_manager_address = get_contract_address();

            // Check that the funds were transferred to this contract
            assert(
                l2_recipient_address == vault_manager_address, 'VM:Amount not transferred to VM'
            );

            // There can be an additional check that the sender was VaultManagerL1 contract on Ethereum but is not strictly necessary

            // Approve the vault address for spending 'amount' number of tokens
            IERC20Dispatcher {
                contract_address: l2_token_address
            }.approve(current_vault_address, amount);

            // Finally call the invest function in vault to make the trade
            IInvestmentVaultDispatcher {
                contract_address: current_vault_address
            }.invest(custodian_address, l2_token_address, amount);
        }

        // Function to register a vault
        fn register_vault_address(
            ref self: ContractState, vault_id: u32, new_vault_address: ContractAddress
        ) {
            let owner = self.owner_address.read();
            let caller = get_caller_address();

            assert(owner == caller, 'VM: Unauthorised Call');

            self.vault_address.write(vault_id, new_vault_address);
        }
    // Withdrawal code is not shown since it is not specific to message attribution framework
    // The withdrawal can be done directly through the vault by the custodian address
    // It can also be routed through the vault manager and the process completed on L1 side through VaultManagerL1
    }
}
