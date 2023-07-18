#[starknet::contract]
mod DummyAdapter {
    use starknet::{ContractAddress, EthAddress};
    use starkway::interfaces::IBridgeAdapter;

    #[storage]
    struct Storage {
        starkgate_bridge_address: ContractAddress, 
    }

    #[external(v0)]
    impl DummyAdapterImpl of IBridgeAdapter<ContractState> {
        fn withdraw(
            ref self: ContractState,
            token_bridge_address: ContractAddress,
            l2_token_address: ContractAddress,
            l1_recipient: EthAddress,
            withdrawal_amount: u256,
            user: ContractAddress
        ) {}
    }
}

use array::{Array, ArrayTrait, Span, SpanTrait};
use core::hash::{LegacyHashFelt252};
use core::integer::u256;
use core::result::ResultTrait;
use debug::{PrintTrait, print_felt252};
use option::OptionTrait;
use serde::Serde;
use starknet::class_hash::ClassHash;
use starknet::{ContractAddress, contract_address_const, EthAddress};
use starknet::testing::{set_caller_address, set_contract_address, pop_log};
use traits::{Default, Into, TryInto};
use starkway::admin_auth::AdminAuth;
    use starkway::datatypes::{L1TokenDetails, WithdrawalRange, L2TokenDetails, TokenAmount};
    use starkway::erc20::erc20::StarkwayERC20;
    use starkway::interfaces::{
        IAdminAuthDispatcher, IAdminAuthDispatcherTrait, IStarkwayDispatcher,
        IStarkwayDispatcherTrait, IERC20Dispatcher, IERC20DispatcherTrait, IBridgeAdapterDispatcher,
        IBridgeAdapterDispatcherTrait
    };
    use starkway::libraries::reentrancy_guard::ReentrancyGuard;
    use starkway::libraries::fee_library::fee_library;
    use starkway::starkway::Starkway;
    use zeroable::Zeroable;

fn deploy(
    contract_class_hash: felt252, salt: felt252, calldata: Array<felt252>
) -> ContractAddress {
    set_contract_address(contract_address_const::<100>());
    let (address, _) = starknet::deploy_syscall(
        contract_class_hash.try_into().unwrap(), salt, calldata.span(), false
    )
        .unwrap();
    address
}

fn setup() -> (ContractAddress, ContractAddress, ContractAddress, ContractAddress) {
    let admin_1: ContractAddress = contract_address_const::<10>();
    let admin_2: ContractAddress = contract_address_const::<20>();

    // Deploy Admin auth contract
    let mut admin_auth_calldata = ArrayTrait::<felt252>::new();
    admin_1.serialize(ref admin_auth_calldata);
    admin_2.serialize(ref admin_auth_calldata);

    let admin_auth_address = deploy(AdminAuth::TEST_CLASS_HASH, 100, admin_auth_calldata);

    // Deploy Starkway contract
    let mut starkway_calldata = ArrayTrait::<felt252>::new();
    let fee_rate = u256 { low: 200, high: 0 };
    let fee_lib_class_hash = fee_library::TEST_CLASS_HASH;
    let erc20_class_hash = StarkwayERC20::TEST_CLASS_HASH;
    admin_auth_address.serialize(ref starkway_calldata);
    fee_rate.serialize(ref starkway_calldata);
    fee_lib_class_hash.serialize(ref starkway_calldata);
    erc20_class_hash.serialize(ref starkway_calldata);
    let starkway_address = deploy(Starkway::TEST_CLASS_HASH, 100, starkway_calldata);

    // Set class hash for re-entrancy guard library
    let starkway = IStarkwayDispatcher { contract_address: starkway_address };

    // Set admin_1 as default caller
    set_contract_address(admin_1);

    starkway
        .set_reentrancy_guard_class_hash(ReentrancyGuard::TEST_CLASS_HASH.try_into().unwrap());

    return (starkway_address, admin_auth_address, admin_1, admin_2);
}

fn mint(
    starkway_address: ContractAddress,
    erc20_address: ContractAddress,
    to: ContractAddress,
    amount: u256
) {
    // Call as owner which is starkway
    set_contract_address(starkway_address);
    let erc20 = IERC20Dispatcher { contract_address: erc20_address };
    erc20.mint(to, amount);
}

fn init_token(
    starkway_address: ContractAddress, admin_1: ContractAddress, l1_token_address: EthAddress
) {
    set_contract_address(admin_1);

    let starkway = IStarkwayDispatcher { contract_address: starkway_address };
    let l1_token_details = L1TokenDetails {
        name: 'TEST_TOKEN', symbol: 'TEST', decimals: 18_u8
    };
    starkway.authorised_init_token(l1_token_address, l1_token_details);

    // Set withdrawal range
    let withdrawal_range = WithdrawalRange {
        min: u256 { low: 2, high: 0 }, max: u256 { low: 0, high: 1000 }
    };
    starkway.set_withdrawal_range(l1_token_address, withdrawal_range);
}

fn register_bridge_adapter(
    starkway_address: ContractAddress, admin_1: ContractAddress
) -> ContractAddress {
    let mut calldata = ArrayTrait::<felt252>::new();

    let adapter_address = deploy(DummyAdapter::TEST_CLASS_HASH, 100, calldata);

    set_contract_address(admin_1);
    let starkway = IStarkwayDispatcher { contract_address: starkway_address };
    starkway.register_bridge_adapter(1_u16, 'ADAPTER', adapter_address);
    adapter_address
}

fn whitelist_token(
    starkway_address: ContractAddress,
    admin_1: ContractAddress,
    bridge_adapter_id: u16,
    bridge_address: ContractAddress,
    l1_token_address: EthAddress,
    l2_token_address: ContractAddress
) {
    set_contract_address(admin_1);
    let starkway = IStarkwayDispatcher { contract_address: starkway_address };
    let l2_token_details = L2TokenDetails {
        l1_address: l1_token_address,
        bridge_adapter_id: bridge_adapter_id,
        bridge_address: bridge_address
    };
    starkway.whitelist_token(l2_token_address, l2_token_details);
}

fn deploy_non_native_token(starkway_address: ContractAddress, salt: felt252) -> ContractAddress{

    let mut erc20_calldata = ArrayTrait::<felt252>::new();
    let name = 'TEST_TOKEN2';
    let symbol = 'TEST2';
    let decimals = 18_u8;
    let owner = starkway_address;

    name.serialize(ref erc20_calldata);
    symbol.serialize(ref erc20_calldata);
    decimals.serialize(ref erc20_calldata);
    owner.serialize(ref erc20_calldata);
    let non_native_erc20_address = deploy(StarkwayERC20::TEST_CLASS_HASH, salt, erc20_calldata);
    non_native_erc20_address
}