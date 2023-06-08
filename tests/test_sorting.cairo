#[cfg(test)]
mod test_sorting {
    use starkway::utils::helpers::approx_quicksort;
    use array::{Array, ArrayTrait, Span};
    
    #[test]
    #[available_gas(2000000000)]
    fn test_quicksort_basic() {

        let mut data = ArrayTrait::new();
        data.append(7_u32);
        data.append(4_u32);
        data.append(2_u32);
        data.append(6_u32);
        data.append(1_u32);
        data.append(3_u32);
        data.append(5_u32);
        data.append(8_u32);
        data.append(0_u32);

        let mut correct = ArrayTrait::new();
        correct.append(0_u32);
        correct.append(1_u32);
        correct.append(2_u32);
        correct.append(3_u32);
        correct.append(4_u32);
        correct.append(5_u32);
        correct.append(6_u32);
        correct.append(7_u32);
        correct.append(8_u32);

        let mut sorted = approx_quicksort(@data);

        assert(is_equal(ref sorted, ref correct, 0_u32) == true, 'invalid result');
    }

    
    fn is_equal(ref a: Array<u32>, ref b: Array<u32>, index: u32) -> bool {
        let len = a.len();
        if len != b.len() {
            return false;
        }
        let mut i = 0_u32;
        if index == len {
            return true;
        }

        if *a[index] != *b[index] {
            return false;
        }

        is_equal(ref a, ref b, index + 1)
    }
}

