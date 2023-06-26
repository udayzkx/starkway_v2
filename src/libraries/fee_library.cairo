#[starknet::contract]
mod fee_library {
    use core::hash::LegacyHash;
    use starknet::EthAddress;
    use starkway::datatypes::{fee_range::FeeRange, fee_segment::FeeSegment};
    use starkway::interfaces::IFeeLib;

    impl LegacyHashEthAddress of LegacyHash<EthAddress> {
        fn hash(state: felt252, value: EthAddress) -> felt252 {
            LegacyHash::<felt252>::hash(state, value.address)
        }
    }

    /////////////
    // Storage //
    /////////////

    #[storage]
    struct Storage {
        s_default_fee_rate: u256,
        s_max_fee_segment_tier: LegacyMap::<EthAddress, u8>,
        s_fee_segments: LegacyMap::<(EthAddress, u8), FeeSegment>,
        s_fee_ranges: LegacyMap::<EthAddress, FeeRange>,
    }

    #[external(v0)]
    impl FeeLibImpl of IFeeLib<ContractState> {
        //////////
        // View //
        //////////

        fn get_default_fee_rate(self: @ContractState) -> u256 {
            self.s_default_fee_rate.read()
        }

        fn get_max_fee_segment_tier(self: @ContractState, token_l1_address: EthAddress) -> u8 {
            self.s_max_fee_segment_tier.read(token_l1_address)
        }

        fn get_fee_segment(
            self: @ContractState, token_l1_address: EthAddress, tier: u8
        ) -> FeeSegment {
            self.s_fee_segments.read((token_l1_address, tier))
        }

        fn get_fee_range(self: @ContractState, token_l1_address: EthAddress) -> FeeRange {
            self.s_fee_ranges.read(token_l1_address)
        }

        fn get_fee_rate(self: @ContractState, token_l1_address: EthAddress, amount: u256) -> u256 {
            let max_fee_segment_tier = self.s_max_fee_segment_tier.read(token_l1_address);
            if (max_fee_segment_tier == 0) {
                self.s_default_fee_rate.read()
            } else {
                self._find_fee_rate(token_l1_address, amount, max_fee_segment_tier)
            }
        }

        //////////////
        // External //
        //////////////

        fn set_default_fee_rate(ref self: ContractState, default_fee_rate: u256) {
            let MAX_FEE_RATE = u256 { low: 300, high: 0 };
            assert(default_fee_rate <= MAX_FEE_RATE, 'Default_fee_rate > MAX_FEE_RATE');
            self.s_default_fee_rate.write(default_fee_rate);
        }

        fn set_fee_range(
            ref self: ContractState, token_l1_address: EthAddress, fee_range: FeeRange
        ) {
            assert(fee_range.min <= fee_range.max, 'Min value > Max value');
            self.s_fee_ranges.write(token_l1_address, fee_range);
        }

        fn set_fee_segment(
            ref self: ContractState, token_l1_address: EthAddress, tier: u8, fee_segment: FeeSegment
        ) {
            assert(tier >= 1, 'Tier should be >= 1');

            let max_fee_segment_tier = self.s_max_fee_segment_tier.read(token_l1_address);

            assert(tier <= max_fee_segment_tier + 1, 'Tier > max_fee_segment_tier + 1');

            let lower_tier_fee = self.s_fee_segments.read((token_l1_address, tier - 1));

            if (tier - 1 != 0) {
                assert(
                    lower_tier_fee.to_amount < fee_segment.to_amount,
                    'Amount invalid wrt lower tier'
                );
                assert(
                    fee_segment.fee_rate < lower_tier_fee.fee_rate, 'Fee invalid wrt lower tier'
                );
            } else {
                assert(
                    fee_segment.to_amount == u256 { low: 0, high: 0 },
                    'To_amount of tier1 should be 0'
                );
            }

            let upper_tier_fee = self.s_fee_segments.read((token_l1_address, tier + 1));
            if (max_fee_segment_tier > tier) {
                assert(
                    fee_segment.to_amount < upper_tier_fee.to_amount,
                    'Amount invalid wrt upper tier'
                );
                assert(
                    upper_tier_fee.fee_rate < fee_segment.fee_rate, 'Fee invalid wrt upper tier'
                );
            } else {
                self.s_max_fee_segment_tier.write(token_l1_address, tier);
            }
            self.s_fee_segments.write((token_l1_address, tier), fee_segment);
        }
    }

    #[generate_trait]
    impl FeeLibPrivateFunctions of IFeeLibPrivateFunctions {
        //////////////
        // Internal //
        //////////////

        fn _find_fee_rate(
            self: @ContractState, token_l1_address: EthAddress, amount: u256, tier: u8
        ) -> u256 {
            let fee_segment = self.s_fee_segments.read((token_l1_address, tier));
            if (tier == 1) {
                return fee_segment.fee_rate;
            }
            if (fee_segment.to_amount <= amount) {
                return fee_segment.fee_rate;
            } else {
                return self._find_fee_rate(token_l1_address, amount, tier - 1);
            }
        }
    }
}
