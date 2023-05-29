use starknet::storage_access::StorageBaseAddress;
use starknet::storage_access::StorageAddress;
use starknet::storage_access::storage_address_from_base_and_offset;
use starknet::storage_access::storage_address_to_felt252;
use starknet::storage_access::storage_base_address_from_felt252;
use starknet::storage_access::StorageAccessU128;
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

#[derive(Serde, Destruct, Copy)] 
struct L1TokenDetails {
    name: felt252,
    symbol: felt252,
    decimals: u8,
}

impl StorageAccessL1TokenDetails of StorageAccess::<L1TokenDetails> {
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<L1TokenDetails> {
        Result::Ok(
            L1TokenDetails {
                name: StorageAccess::<felt252>::read(address_domain, base)?,
                symbol: storage_read_syscall(
                    address_domain, storage_address_from_base_and_offset(base, 1_u8)
                )?,
                decimals: storage_read_syscall(
                    address_domain, storage_address_from_base_and_offset(base, 2_u8)
                )?
                    .try_into()
                    .expect('not L1TokenDetails')
            }
        )
    }

    fn write(address_domain: u32, base: StorageBaseAddress, value: L1TokenDetails) -> SyscallResult<()> {
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

impl StorageAccessL2TokenDetails of StorageAccess::<L2TokenDetails> {
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<L2TokenDetails> {
        Result::Ok(
            L2TokenDetails {
                l1_address: StorageAccess::<L1Address>::read(address_domain, base)?,
                bridge_id: storage_read_syscall(
                    address_domain, storage_address_from_base_and_offset(base, 1_u8)
                )?,
                bridge_address: storage_read_syscall(
                    address_domain, storage_address_from_base_and_offset(base, 2_u8)
                )?
                    .try_into()
                    .expect('not L2TokenDetails')
            }
        )
        
    }

    fn write(address_domain: u32, base: StorageBaseAddress, value: L2TokenDetails) -> SyscallResult<()> {
        StorageAccess::<L1Address>::write(address_domain, base, value.l1_address)?;
        storage_write_syscall(
            address_domain, storage_address_from_base_and_offset(base, 1_u8), value.bridge_id
        );
        storage_write_syscall(
            address_domain, storage_address_from_base_and_offset(base, 2_u8), value.bridge_address.into()
        )
    }
}

#[derive(Drop, Destruct, Serde)] 
struct FeeSegment {
    to_amount: u256,
    fee_rate: u256,
}

impl StorageAccessFeeSegment of StorageAccess::<FeeSegment> {
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<FeeSegment> {
        let address = storage_address_from_base_and_offset(base, 2_u8);
        let address_felt252 = storage_address_to_felt252(address);
        let new_base = storage_base_address_from_felt252(address_felt252);
        Result::Ok(
            FeeSegment {
                to_amount: StorageAccess::<u256>::read(address_domain, base)?,
                fee_rate: StorageAccess::<u256>::read(address_domain, new_base)?
            }
        )
    }

    fn write(address_domain: u32, base: StorageBaseAddress, value: FeeSegment) -> SyscallResult<()> {
        StorageAccess::<u256>::write(address_domain, base, value.to_amount)?;
        storage_write_syscall(
            address_domain, storage_address_from_base_and_offset(base, 2_u8), value.fee_rate.low.into()
        );
        storage_write_syscall(
            address_domain, storage_address_from_base_and_offset(base, 3_u8), value.fee_rate.high.into()
        )
    }
}

#[derive(Drop, Destruct, Serde)] 
struct FeeRange {
    is_set: bool,  
    min: u256,
    max: u256,
}

impl StorageAccessFeeRange of StorageAccess::<FeeRange> {
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<FeeRange> {
        let min_address = storage_address_from_base_and_offset(base, 1_u8);
        let min_address_felt252 = storage_address_to_felt252(min_address);
        let min_new_base = storage_base_address_from_felt252(min_address_felt252);
        let max_address = storage_address_from_base_and_offset(base, 3_u8);
        let max_address_felt252 = storage_address_to_felt252(max_address);
        let max_new_base = storage_base_address_from_felt252(max_address_felt252);
        Result::Ok(
            FeeRange {
                is_set: StorageAccess::<bool>::read(address_domain, base)?,
                min: StorageAccess::<u256>::read(address_domain, min_new_base)?,
                max: StorageAccess::<u256>::read(address_domain, max_new_base)?
            }
        )
    }

    fn write(address_domain: u32, base: StorageBaseAddress, value: FeeRange) -> SyscallResult<()> {
        StorageAccess::<bool>::write(address_domain, base, value.is_set)?;
        storage_write_syscall(
            address_domain, storage_address_from_base_and_offset(base, 1_u8), value.min.low.into()
        );
        storage_write_syscall(
            address_domain, storage_address_from_base_and_offset(base, 2_u8), value.min.high.into()
        );
        storage_write_syscall(
            address_domain, storage_address_from_base_and_offset(base, 3_u8), value.max.low.into()
        );
        storage_write_syscall(
            address_domain, storage_address_from_base_and_offset(base, 4_u8), value.max.high.into()
        )
    }
}