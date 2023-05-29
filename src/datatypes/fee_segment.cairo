use starknet::storage_access::StorageBaseAddress;
use starknet::storage_access::storage_address_from_base_and_offset;
use starknet::StorageAccess;
use traits::Into;
use traits::TryInto;
use option::OptionTrait;
use starknet::SyscallResult;
use starknet::syscalls::storage_read_syscall;
use starknet::syscalls::storage_write_syscall;

#[derive(Drop, Destruct, Serde)] 
struct FeeSegment {
    to_amount: u256,
    fee_rate: u256,
}

impl StorageAccessFeeSegment of StorageAccess::<FeeSegment> {
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<FeeSegment> {
        let to_amount = StorageAccess::<u256>::read(address_domain, base)?;
        
        let fee_address_low = storage_address_from_base_and_offset(base, 2_u8);
        let fee_address_high = storage_address_from_base_and_offset(base, 3_u8);
        let fee_low = storage_read_syscall(address_domain, fee_address_low)?.try_into().expect('non u128 value');
        let fee_high = storage_read_syscall(address_domain, fee_address_high)?.try_into().expect('non u128 value');
        
        Result::Ok(
            FeeSegment { 
                to_amount: to_amount, 
                fee_rate:  u256 { low: fee_low, high: fee_high } 
            }
        )
    }

    fn write(address_domain: u32, base: StorageBaseAddress, value: FeeSegment) -> SyscallResult<()> {
        StorageAccess::<u256>::write(address_domain, base, value.to_amount)?;
        storage_write_syscall(
            address_domain, 
            storage_address_from_base_and_offset(base, 2_u8), 
            value.fee_rate.low.into()
        );
        storage_write_syscall(
            address_domain, 
            storage_address_from_base_and_offset(base, 3_u8), 
            value.fee_rate.high.into()
        )
    }
}
