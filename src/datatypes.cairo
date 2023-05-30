use starknet::storage_access::StorageBaseAddress;
use starknet::storage_access::StorageAddress;
use starknet::storage_access::storage_address_from_base_and_offset;
use starknet::storage_access::storage_address_to_felt252;
use starknet::storage_access::storage_base_address_from_felt252;
use starknet::StorageAccess;
use traits::Into;
use traits::TryInto;
use option::OptionTrait;
use starknet::SyscallResult;
use starknet::syscalls::storage_read_syscall;
use starknet::syscalls::storage_write_syscall;
use starknet::ContractAddress;
use starknet::contract_address::ContractAddressIntoFelt252;
use starknet::contract_address::Felt252TryIntoContractAddress;
use starkway::utils::l1_address::L1Address;
use starkway::utils::l1_address::StorageAccessL1Address;

#[derive(Serde, Destruct)]
struct L1TokenDetails {
    name: felt252,
    symbol: felt252,
    decimals: u8,
}

#[derive(Serde, Destruct, Drop)]
struct TokenInfo {
    l2_address: ContractAddress,
    l1_address: L1Address,
    balance: u256,
    name: felt252,
    symbol: felt252,
    decimals: u8,
    native_l2_address: ContractAddress,
}

impl StorageAccessL1TokenDetails of StorageAccess<L1TokenDetails> {
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<L1TokenDetails> {
        Result::Ok(
            L1TokenDetails {
                name: StorageAccess::<felt252>::read(address_domain, base)?,
                symbol: storage_read_syscall(
                    address_domain, storage_address_from_base_and_offset(base, 1_u8)
                )?,
                decimals: storage_read_syscall(
                    address_domain, storage_address_from_base_and_offset(base, 2_u8)
                )?.try_into().expect('not L1TokenDetails')
            }
        )
    }

    fn write(
        address_domain: u32, base: StorageBaseAddress, value: L1TokenDetails
    ) -> SyscallResult<()> {
        StorageAccess::<felt252>::write(address_domain, base, value.name)?;
        storage_write_syscall(
            address_domain, storage_address_from_base_and_offset(base, 1_u8), value.symbol
        );
        storage_write_syscall(
            address_domain, storage_address_from_base_and_offset(base, 2_u8), value.decimals.into()
        )
    }
}

#[derive(Serde, Destruct)]
struct L2TokenDetails {
    l1_address: L1Address,
    bridge_id: felt252,
    bridge_address: ContractAddress,
}

impl StorageAccessL2TokenDetails of StorageAccess<L2TokenDetails> {
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<L2TokenDetails> {
        Result::Ok(
            L2TokenDetails {
                l1_address: StorageAccess::<L1Address>::read(address_domain, base)?,
                bridge_id: storage_read_syscall(
                    address_domain, storage_address_from_base_and_offset(base, 1_u8)
                )?,
                bridge_address: storage_read_syscall(
                    address_domain, storage_address_from_base_and_offset(base, 2_u8)
                )?.try_into().expect('not L2TokenDetails')
            }
        )
    }

    fn write(
        address_domain: u32, base: StorageBaseAddress, value: L2TokenDetails
    ) -> SyscallResult<()> {
        StorageAccess::<L1Address>::write(address_domain, base, value.l1_address)?;
        storage_write_syscall(
            address_domain, storage_address_from_base_and_offset(base, 1_u8), value.bridge_id
        );
        storage_write_syscall(
            address_domain,
            storage_address_from_base_and_offset(base, 2_u8),
            value.bridge_address.into()
        )
    }
}
