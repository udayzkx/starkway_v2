use starknet::storage_access::StorageBaseAddress;
use starknet::storage_access::storage_address_from_base_and_offset;
use starknet::StorageAccess;
use traits::Into;
use traits::TryInto;
use option::OptionTrait;
use starknet::SyscallResult;
use starknet::syscalls::storage_read_syscall;
use starknet::syscalls::storage_write_syscall;

#[derive(Serde, Destruct)] 
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
