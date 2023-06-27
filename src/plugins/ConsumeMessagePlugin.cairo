#[contract]
mod ConsumeMessagePlugin {
    use array::{Array, ArrayTrait};
    use core::integer::u256;
    use option::OptionTrait;
    use starknet::{
        ContractAddress, contract_address::Felt252TryIntoContractAddress, get_caller_address,
    };
    use traits::{Into, TryInto};
    use zeroable::Zeroable;

    use starkway::datatypes::l1_address::L1Address;

    /////////////
    // Storage //
    /////////////

    struct Storage {
        s_message_counter: LegacyMap::<felt252, u128>,
        s_starkway_address: ContractAddress,
    }

    /////////////////
    // Constructor //
    /////////////////

    /// @notice Constructor for ConsumeMessagePlugin contract
    /// @param starkway_address - Starkway contract's address in Starknet
    #[constructor]
    fn constructor(starkway_address: ContractAddress) {
        assert(starkway_address.is_non_zero(), 'CMP: Starkway address is zero');
        s_starkway_address::write(starkway_address);
    }

    //////////
    // View //
    //////////

    // @notice Function to get outstanding number of messages to be consumed and message hash 
    // @param l1_token_address - L1 ERC-20 token contract address
    // @param l1_sender_address - L1 address of the sender
    // @param l2_funds_recipient_address - Address to which tokens are to be minted
    // @param l2_msg_consumer_address - Address of message consumer contract
    // @param amount - Amount to deposit
    // @param message_payload - Arbitrary data passed through while deposit
    // @return message_count - Outstanding number of messages to be consumed 
    // @return message_hash - Hash of a message
    #[view]
    fn number_of_messages_by_params(
        l1_token_address: L1Address,
        l1_sender_address: L1Address,
        l2_funds_recipient_address: ContractAddress,
        l2_msg_consumer_address: ContractAddress,
        amount: u256,
        message_payload: Array<felt252>
    ) -> (u128, felt252) {
        let msg_hash = _compute_msg_hash(
            l1_token_address,
            l1_sender_address,
            l2_funds_recipient_address,
            l2_msg_consumer_address,
            amount,
            message_payload,
        );
        (s_message_counter::read(msg_hash), msg_hash)
    }

    // @notice Function to get outstanding number of messages to be consumed 
    // @param message_hash - Hash of a message
    // @return message_count - Outstanding number of messages to be consumed 
    #[view]
    fn number_of_messages_by_hash(msg_hash: felt252) -> u128 {
        s_message_counter::read(msg_hash)
    }

    //////////////
    // External //
    //////////////

    // @notice Function to handle starkway deposit message 
    // @param l1_token_address - L1 ERC-20 token contract address
    // @param l2_token_address - L2 ERC-20 token contract address
    // @param l1_sender_address - L1 address of the sender
    // @param l2_recipient_address - Address to which tokens are to be minted
    // @param amount - Amount to deposit
    // @param fee - Fee charged during the deposit
    // @param message_payload - Arbitrary data passed through while deposit
    #[external]
    fn handle_starkway_deposit_message(
        l1_token_address: L1Address,
        l2_token_address: ContractAddress,
        l1_sender_address: L1Address,
        l2_recipient_address: ContractAddress,
        amount: u256,
        fee: u256,
        message_payload: Array<felt252>
    ) {
        let caller = get_caller_address();
        let starkway_address = s_starkway_address::read();
        assert(caller == starkway_address, 'CMP:ONLY_STARKWAY_CALLS_ALLOWED');

        let consumer = _resolve_consumer_and_payload(l2_recipient_address, @message_payload);

        let msg_hash = _compute_msg_hash(
            l1_token_address,
            l1_sender_address,
            l2_recipient_address,
            consumer,
            amount,
            message_payload,
        );

        let current_count = s_message_counter::read(msg_hash);
        s_message_counter::write(msg_hash, current_count + 1);
    }

    // @notice Function to consume message sent during deposit
    // @param l1_token_address - L1 ERC-20 token contract address
    // @param l1_sender_address - L1 address of the sender
    // @param l2_funds_recipient_address - Address to which tokens are to be minted
    // @param amount - Deposited amount
    // @param message_payload - Arbitrary data passed through while deposit
    #[external]
    fn consume_message(
        l1_token_address: L1Address,
        l1_sender_address: L1Address,
        l2_funds_recipient_address: ContractAddress,
        amount: u256,
        message_payload: Array<felt252>
    ) {
        let consumer = get_caller_address();
        let msg_hash = _compute_msg_hash(
            l1_token_address,
            l1_sender_address,
            l2_funds_recipient_address,
            consumer,
            amount,
            message_payload,
        );

        let current_count = s_message_counter::read(msg_hash);
        assert(current_count != 0, 'CMP: INVALID_MESSAGE_TO_CONSUME');
        s_message_counter::write(msg_hash, current_count - 1);
    }

    //////////////
    // Internal //
    //////////////

    // @dev - Internal function to resolve consumer and payload
    fn _resolve_consumer_and_payload(
        l2_recipient_address: ContractAddress, message_payload: @Array<felt252>
    ) -> ContractAddress {
        let message_payload_len = message_payload.len();
        if (message_payload_len == 0) {
            return l2_recipient_address;
        } else {
            let msg_consumer = *message_payload[0];
            return msg_consumer.try_into().unwrap();
        }
    }

    // @dev - Internal function to compute message hash
    fn _compute_msg_hash(
        l1_token_address: L1Address,
        l1_sender_address: L1Address,
        l2_funds_recipient_address: ContractAddress,
        l2_msg_consumer_address: ContractAddress,
        amount: u256,
        message_payload: Array<felt252>,
    ) -> felt252 {
        let mut base_msg_data = ArrayTrait::<felt252>::new();

        base_msg_data.append(l1_token_address.into());
        base_msg_data.append(l1_sender_address.into());
        base_msg_data.append(l2_funds_recipient_address.into());
        base_msg_data.append(l2_msg_consumer_address.into());
        base_msg_data.append(amount.low.into());
        base_msg_data.append(amount.high.into());

        let mut message_payload_len = message_payload.len();
        let mut payload_index = 0_u32;

        // This check is added to not include first element of the message payload, 
        // as it was already included in base_msg_data as consumer
        if (message_payload_len != 0) {
            payload_index = 1_u32;
        }

        loop {
            if (payload_index == message_payload_len) {
                break ();
            }
            base_msg_data.append(*message_payload[payload_index]);
            payload_index += 1;
        };

        hash_chain(base_msg_data.len() - 1, base_msg_data)
    }

    // @dev - Internal function to compute hash recursively
    fn hash_chain(index: u32, message_payload: Array<felt252>) -> felt252 {
        if (index == -1) {
            return 0;
        }
        pedersen(hash_chain(index - 1, message_payload), *message_payload[index])
    }
}