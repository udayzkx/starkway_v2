use starknet::storage_access::StorageBaseAddress;
use starknet::storage_access::storage_address_from_base_and_offset;
use starknet::StorageAccess;
use traits::Into;
use traits::TryInto;
use option::OptionTrait;
use starknet::SyscallResult;
use starknet::syscalls::{ storage_read_syscall, storage_write_syscall};

#[derive(Destruct, Serde)]
struct WithdrawalRange {
    min: u256,
    max: u256,
}

impl StorageAccessWithdrawalRange of StorageAccess<WithdrawalRange> {
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<WithdrawalRange> {
        let min = StorageAccess::<u256>::read(address_domain, base)?;

        let max_address_low = storage_address_from_base_and_offset(base, 2_u8);
        let max_address_high = storage_address_from_base_and_offset(base, 3_u8);
        let max_low = storage_read_syscall(
            address_domain, max_address_low
        )?.try_into().expect('non u128 value');
        let max_high = storage_read_syscall(
            address_domain, max_address_high
        )?.try_into().expect('non u128 value');

        Result::Ok(WithdrawalRange { min: min, max: u256 { low: max_low, high: max_high } })
    }

    fn write(
        address_domain: u32, base: StorageBaseAddress, value: WithdrawalRange
    ) -> SyscallResult<()> {
        StorageAccess::<u256>::write(address_domain, base, value.min)?;
        storage_write_syscall(
            address_domain, storage_address_from_base_and_offset(base, 2_u8), value.max.low.into()
        );
        storage_write_syscall(
            address_domain, storage_address_from_base_and_offset(base, 3_u8), value.max.high.into()
        )
    }
}
