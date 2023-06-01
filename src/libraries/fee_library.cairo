#[contract]
mod fee_library {
    use starkway::datatypes::fee_range::FeeRange;
    use starkway::datatypes::fee_segment::FeeSegment;
    use starkway::datatypes::l1_address::L1Address;

    /////////////
    // Storage //
    /////////////

    struct Storage {
        s_default_fee_rate: u256,
        s_max_fee_segment_tier: LegacyMap::<L1Address, u8>,
        s_fee_segments: LegacyMap::<(L1Address, u8), FeeSegment>,
        s_fee_ranges: LegacyMap::<L1Address, FeeRange>,
    }

    //////////
    // View //
    //////////

    #[view]
    fn get_default_fee_rate() -> u256 {
        s_default_fee_rate::read()
    }

    #[view]
    fn get_max_fee_segment_tier(token_l1_address: L1Address) -> u8 {
        s_max_fee_segment_tier::read(token_l1_address)
    }

    #[view]
    fn get_fee_segment(token_l1_address: L1Address, tier: u8) -> FeeSegment {
        s_fee_segments::read((token_l1_address, tier))
    }

    #[view]
    fn get_fee_range(token_l1_address: L1Address) -> FeeRange {
        s_fee_ranges::read(token_l1_address)
    }

    #[view]
    fn get_fee_rate(token_l1_address: L1Address, amount: u256) -> u256 {
        let max_fee_segment_tier = s_max_fee_segment_tier::read(token_l1_address);
        if max_fee_segment_tier == 0 {
            s_default_fee_rate::read()
        } else {
            find_fee_rate(token_l1_address, amount, max_fee_segment_tier)
        }
    }

    //////////////
    // External //
    //////////////

    #[external]
    fn set_default_fee_rate(default_fee_rate: u256) {
        let MAX_FEE_RATE = u256 { low: 300, high: 0 };
        assert(default_fee_rate <= MAX_FEE_RATE, 'Default_fee_rate > MAX_FEE_RATE');
        s_default_fee_rate::write(default_fee_rate);
    }

    #[external]
    fn set_fee_range(token_l1_address: L1Address, fee_range: FeeRange) {
        assert(fee_range.min <= fee_range.max, 'Min value > Max value');
        s_fee_ranges::write(token_l1_address, fee_range);
    }

    #[external]
    fn set_fee_segment(token_l1_address: L1Address, tier: u8, fee_segment: FeeSegment) {
        assert(tier >= 1, 'Tier should be >= 1');

        let max_fee_segment_tier = s_max_fee_segment_tier::read(token_l1_address);

        assert(tier <= max_fee_segment_tier + 1, 'Tier > max_fee_segment_tier + 1');

        let lower_tier_fee = s_fee_segments::read((token_l1_address, tier - 1));
        if tier
            - 1 != 0 {
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

        let upper_tier_fee = s_fee_segments::read((token_l1_address, tier + 1));
        if max_fee_segment_tier > tier {
            assert(
                fee_segment.to_amount < upper_tier_fee.to_amount, 'Amount invalid wrt upper tier'
            );
            assert(upper_tier_fee.fee_rate < fee_segment.fee_rate, 'Fee invalid wrt upper tier');
        } else {
            s_max_fee_segment_tier::write(token_l1_address, tier);
        }
        s_fee_segments::write((token_l1_address, tier), fee_segment);
    }

    //////////////
    // Internal //
    //////////////

    #[internal]
    fn find_fee_rate(token_l1_address: L1Address, amount: u256, tier: u8) -> u256 {
        let fee_segment = s_fee_segments::read((token_l1_address, tier));
        if tier == 1 {
            return fee_segment.fee_rate;
        }
        if fee_segment.to_amount <= amount {
            return fee_segment.fee_rate;
        } else {
            return find_fee_rate(token_l1_address, amount, tier - 1);
        }
    }
}
