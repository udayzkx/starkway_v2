use starknet::storage_access::StorageBaseAddress;
use starknet::storage_access::storage_address_from_base_and_offset;
use starknet::StorageAccess;
use traits::Into;
use traits::TryInto;
use option::OptionTrait;
use starknet::SyscallResult;
use starknet::syscalls::storage_read_syscall;
use starknet::syscalls::storage_write_syscall;
use starknet::ContractAddress;
use starknet::contract_address::Felt252TryIntoContractAddress;
use starkway::datatypes::l1_address::L1Address;

#[derive(Serde, Destruct)]
struct L2TokenDetails {
    l1_address: L1Address,
    bridge_id: u16,
    bridge_address: ContractAddress,
}

impl StorageAccessL2TokenDetails of StorageAccess<L2TokenDetails> {
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<L2TokenDetails> {
        Result::Ok(
            L2TokenDetails {
                l1_address: StorageAccess::<L1Address>::read(address_domain, base)?,
                bridge_id: storage_read_syscall(
                    address_domain, storage_address_from_base_and_offset(base, 1_u8)
                )?
                    .try_into()
                    .expect('incorrect id'),
                bridge_address: storage_read_syscall(
                    address_domain, storage_address_from_base_and_offset(base, 2_u8)
                )?
                    .try_into()
                    .expect('not L2TokenDetails')
            }
        )
    }

    fn write(
        address_domain: u32, base: StorageBaseAddress, value: L2TokenDetails
    ) -> SyscallResult<()> {
        StorageAccess::<L1Address>::write(address_domain, base, value.l1_address)?;
        storage_write_syscall(
            address_domain, storage_address_from_base_and_offset(base, 1_u8), value.bridge_id.into()
        );
        storage_write_syscall(
            address_domain,
            storage_address_from_base_and_offset(base, 2_u8),
            value.bridge_address.into()
        )
    }
}
