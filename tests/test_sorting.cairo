#[cfg(test)]
mod test_sorting {
    use array::{Array, ArrayTrait, Span};
    use starknet::ContractAddress;
    use starknet::contract_address_const;
    use starkway::datatypes::{l1_address::L1Address, token_info::TokenAmount};
    use starkway::utils::helpers::sort;
    
    #[test]
    #[available_gas(2000000000)]
    fn test_sort_basic() {

        let mut data = ArrayTrait::new();
        data.append(9_u32);
        data.append(8_u32);
        data.append(7_u32);
        data.append(6_u32);
        data.append(5_u32);
        data.append(4_u32);
        data.append(3_u32);
        data.append(2_u32);
        data.append(1_u32);

        let mut correct = ArrayTrait::new();
        correct.append(1_u32);
        correct.append(2_u32);
        correct.append(3_u32);
        correct.append(4_u32);
        correct.append(5_u32);
        correct.append(6_u32);
        correct.append(7_u32);
        correct.append(8_u32);
        correct.append(9_u32);

        let mut sorted = sort(@data);
        
        assert(is_equal(@sorted, @correct) == true, 'invalid result 1');
        let mut data = ArrayTrait::<u32>::new();
        let mut empty_array = ArrayTrait::<u32>::new();
        let mut sorted = sort(@data);
        assert(is_equal(@sorted, @empty_array) == true, 'invalid result 2');

        let mut data = ArrayTrait::<u32>::new();
        data.append(9_u32);
        let mut correct = ArrayTrait::<u32>::new();
        correct.append(9_u32);
        let mut sorted = sort(@data);
        assert(is_equal(@sorted, @correct) == true, 'invalid result 3');

        let mut data = ArrayTrait::<u32>::new();
        data.append(9_u32);
        data.append(8_u32);
        let mut correct = ArrayTrait::<u32>::new();
        correct.append(8_u32);   
        correct.append(9_u32);
        let mut sorted = sort(@data);
        assert(is_equal(@sorted, @correct) == true, 'invalid result 4');

        let mut data = ArrayTrait::<u32>::new();
        data.append(8_u32);
        data.append(9_u32);
        let mut correct = ArrayTrait::<u32>::new();
        correct.append(8_u32);   
        correct.append(9_u32);
        let mut sorted = sort(@data);
        assert(is_equal(@sorted, @correct) == true, 'invalid result 5');

        let mut data = ArrayTrait::new();
        data.append(1_u32);
        data.append(2_u32);
        data.append(3_u32);
        data.append(4_u32);
        data.append(5_u32);
        data.append(6_u32);
        data.append(7_u32);
        data.append(8_u32);
        data.append(9_u32);

        let mut correct = ArrayTrait::new();
        correct.append(1_u32);
        correct.append(2_u32);
        correct.append(3_u32);
        correct.append(4_u32);
        correct.append(5_u32);
        correct.append(6_u32);
        correct.append(7_u32);
        correct.append(8_u32);
        correct.append(9_u32);

        let mut sorted = sort(@data);
        
        assert(is_equal(@sorted, @correct) == true, 'invalid result 6');

    }

    #[test]
    #[available_gas(2000000000)]
    fn test_sort_token_amounts() {
        let mut data = ArrayTrait::<TokenAmount>::new();
        let user_1: ContractAddress = contract_address_const::<1>();
        let l1_address_1 = L1Address{value: 1};
        let l1_address_2 = L1Address{value: 2};
        data.append(TokenAmount{l1_address: l1_address_1, 
                    l2_address:user_1, 
                    amount: u256{low:100, high: 0}});

        let mut correct = ArrayTrait::<TokenAmount>::new();
        let user_1: ContractAddress = contract_address_const::<1>();
        correct.append(TokenAmount{
                        l1_address: l1_address_1,
                        l2_address: user_1, 
                        amount: u256{low:100, high: 0}});

        let mut sorted = sort(@data);
        
        assert(is_equal(@sorted, @correct) == true, 'invalid result 1');

        let mut data = ArrayTrait::<TokenAmount>::new();
        let user_1: ContractAddress = contract_address_const::<1>();
        let user_2: ContractAddress = contract_address_const::<2>();
        let user_3: ContractAddress = contract_address_const::<3>();
        data.append(TokenAmount{
                    l1_address: l1_address_2,
                    l2_address:user_1, 
                    amount: u256{low:300, high: 0}});
        data.append(TokenAmount{
                    l1_address: l1_address_2,
                    l2_address:user_2, 
                    amount: u256{low:200, high: 0}});
        data.append(TokenAmount{
                    l1_address: l1_address_2,
                    l2_address:user_3, 
                    amount: u256{low:100, high: 0}});

        let mut correct = ArrayTrait::<TokenAmount>::new();
        let user_1: ContractAddress = contract_address_const::<1>();
        let user_2: ContractAddress = contract_address_const::<2>();
        let user_3: ContractAddress = contract_address_const::<3>();

       
        correct.append(TokenAmount{
                        l1_address: l1_address_2,
                        l2_address:user_1, 
                        amount: u256{low:100, high: 0}});
        correct.append(TokenAmount{
                        l1_address: l1_address_2,
                        l2_address:user_1, 
                        amount: u256{low:200, high: 0}});
        correct.append(TokenAmount{
                        l1_address: l1_address_2,
                        l2_address:user_1, 
                        amount: u256{low:300, high: 0}});

        let mut sorted = sort(@data);
        
        assert(is_equal(@sorted, @correct) == true, 'invalid result 2');


    }
    
    fn is_equal<T, 
    impl TCopy: Copy<T>, 
    impl TDrop: Drop<T>, 
    impl TPartialEq: PartialEq<T>> (a: @Array<T>, b: @Array<T>) -> bool {
        let len = a.len();
        if len != b.len() {
            return false;
        }

        let mut index = 0_u32;
        let mut equality = true;
        loop {
            if (index == a.len()){
                break ();
            }
            if (*a.at(index) != *b.at(index)){
                equality = false;
                break ();
            }
            index += 1;
        };
        equality
    }
}

