use starknet::storage_access::StorageBaseAddress;
use starknet::storage_access::storage_address_from_base_and_offset;
use starknet::StorageAccess;
use traits::Into;
use traits::TryInto;
use option::OptionTrait;
use starknet::SyscallResult;
use starknet::syscalls::storage_read_syscall;
use starknet::syscalls::storage_write_syscall;

#[derive(Copy, Drop, Destruct, Serde)] 
struct FeeRange {
    is_set: bool,  
    min: u256,
    max: u256,
}

impl StorageAccessFeeRange of StorageAccess::<FeeRange> {
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<FeeRange> {
        let is_set = StorageAccess::<bool>::read(address_domain, base)?;

        let min_address_low = storage_address_from_base_and_offset(base, 1_u8);
        let min_address_high = storage_address_from_base_and_offset(base, 2_u8);
        let min_low = storage_read_syscall(address_domain, min_address_low)?.try_into().expect('non u128 value');
        let min_high = storage_read_syscall(address_domain, min_address_high)?.try_into().expect('non u128 value');
        
        let max_address_low = storage_address_from_base_and_offset(base, 3_u8);
        let max_address_high = storage_address_from_base_and_offset(base, 4_u8);
        let max_low = storage_read_syscall(address_domain, max_address_low)?.try_into().expect('non u128 value');
        let max_high = storage_read_syscall(address_domain, max_address_high)?.try_into().expect('non u128 value');

        Result::Ok(
            FeeRange { 
                is_set: is_set, 
                min:  u256 { low: min_low, high: min_high },
                max:  u256 { low: max_low, high: max_high } 
            }
        )
    }

    fn write(address_domain: u32, base: StorageBaseAddress, value: FeeRange) -> SyscallResult<()> {
        StorageAccess::<bool>::write(address_domain, base, value.is_set)?;
        storage_write_syscall(
            address_domain, 
            storage_address_from_base_and_offset(base, 1_u8), 
            value.min.low.into()
        );
        storage_write_syscall(
            address_domain, 
            storage_address_from_base_and_offset(base, 2_u8), 
            value.min.high.into()
        );
        storage_write_syscall(
            address_domain, 
            storage_address_from_base_and_offset(base, 3_u8), 
            value.max.low.into()
        );
        storage_write_syscall(
            address_domain, 
            storage_address_from_base_and_offset(base, 4_u8), 
            value.max.high.into()
        )
    }
}