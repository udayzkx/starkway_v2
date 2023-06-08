use array::{Array, ArrayTrait, Span};
fn is_in_range<T, impl TPartialOrd: PartialOrd<T>, impl TDrop: Drop<T>, impl Tcopy: Copy<T>>(
    value: T, x: T, y: T
) -> bool {
    if value < x {
        return false;
    }
    if value > y {
        return false;
    }
    true
}

fn get_partitions<T,
impl TCopy: Copy<T>,
impl TDrop: Drop<T>,
impl TPartialOrd: PartialOrd<T>>(array: @Array<T>) -> (Array<T>, Array<T>) {

    let mut index = 0_u32;
    let mut smaller_elements:Array<T> = ArrayTrait::new();
    let mut larger_elements:Array<T> = ArrayTrait::new();
    if (array.len() == 0) {
        return (smaller_elements, larger_elements);
    }
    let pivot = *array.at(array.len()-1);
    loop {
        if(index==array.len()-1) {
            break();
        }
        if(*array.at(index)<=pivot) {
            smaller_elements.append(*array.at(index));
        }
        else {
            larger_elements.append(*array.at(index));
        }
        index+=1;
    };
    (smaller_elements, larger_elements)
    
}

fn approx_quicksort<T,
impl TCopy: Copy<T>,
impl TDrop: Drop<T>,
impl TPartialOrd: PartialOrd<T>>(
    array: @Array<T>
) -> Array<T> {
    // find elements smaller & larger than pivot
    // quicksort these arrays separately
    // create new array sorted smaller elements + pivot + sorted larger elements
    // return this new array
    if(array.len()==0) {
        let mut empty_array: Array<T> = ArrayTrait::new();
        return empty_array;
    }
    let (smaller_elements, larger_elements) = get_partitions(array);
    let mut sorted_smaller_elements = approx_quicksort(@smaller_elements);
    let mut sorted_larger_elements = approx_quicksort(@larger_elements);
    //append pivot
    sorted_smaller_elements.append(*array.at(array.len()-1));
    let mut index = 0_u32;

    loop {
        if(index==sorted_larger_elements.len()) {
            break();
        }

        sorted_smaller_elements.append(*sorted_larger_elements.at(index));
        index +=1;
    };
    sorted_smaller_elements

}