use core::traits::PartialEq;
use core::serde::Serde;
use core::array::Array;
use starknet::StorageAccess;
use starknet::storage_access::StorageBaseAddress;
use starknet::SyscallResult;
use starknet::syscalls::storage_read_syscall;
use starknet::syscalls::storage_write_syscall;
use starknet::storage_access::storage_address_from_base;
use core::hash::LegacyHash;

const ETH_ADDRESS_BOUND: felt252 = 1461501637330902918203684832716283019655932542975;

trait L1AddressTrait {
    fn from_felt(value: felt252) -> L1Address;
    fn try_from_felt(value: felt252) -> Option<L1Address>;
    fn is_valid_L1_address(value: felt252) -> bool;
}

#[derive(Copy, Drop, Serde)]
struct L1Address {
    value: felt252,
}

impl L1AddressTraitImpl of L1AddressTrait {
    fn from_felt(value: felt252) -> L1Address {
        assert(L1AddressTrait::is_valid_L1_address(value), 'INVALID_L1_ADDRESS');
        L1Address { value }
    }

    fn try_from_felt(value: felt252) -> Option<L1Address> {
        let is_valid = L1AddressTrait::is_valid_L1_address(value);
        if is_valid {
            Option::Some(L1Address { value })
        } else {
            Option::None(())
        }
    }

    fn is_valid_L1_address(value: felt252) -> bool {
        if value == 0 {
            return false;
        }
        // TODO: Add check that address is valid ETH address
        true
    }
}

impl PartialEqL1Address of PartialEq::<L1Address> {
    #[inline(always)]
    fn eq(lhs: L1Address, rhs: L1Address) -> bool {
        lhs.value == rhs.value
    }

    #[inline(always)]
    fn ne(lhs: L1Address, rhs: L1Address) -> bool {
        !(lhs.value == rhs.value)
    }
}

impl StorageAccessL1Address of StorageAccess::<L1Address> {
    fn read(address_domain: u32, base: StorageBaseAddress) -> SyscallResult<L1Address> {
        Result::Ok(
            L1Address {
                value: StorageAccess::<felt252>::read(address_domain, base)?
            }
        )
    }

    fn write(address_domain: u32, base: StorageBaseAddress, value: L1Address) -> SyscallResult<()> {
        storage_write_syscall(address_domain, storage_address_from_base(base), value.value)
    }
}

impl LegacyHashL1Address of LegacyHash::<L1Address> {
    fn hash(state: felt252, value: L1Address) -> felt252 {
        LegacyHash::<felt252>::hash(state, value.value)
    }
}