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

// Given an array this function returns 2 arrays as partitions (A,B)
// A is an array containing all elements less then or equal to the pivot
// B is an array containing all elements greater than the pivot
// Last element of the given array is selected as the pivot
// Copy trait is required since we are desnapping from snapshots and hence the value needs to implement the Copy trait
fn get_partitions<T, impl TCopy: Copy<T>, impl TDrop: Drop<T>, impl TPartialOrd: PartialOrd<T>>(
    array: @Array<T>
) -> (Array<T>, Array<T>) {
    let mut index = 0_u32;
    let mut smaller_elements = ArrayTrait::<T>::new();
    let mut larger_elements: Array<T> = ArrayTrait::<T>::new();
    if (array.len() == 0) {
        return (smaller_elements, larger_elements);
    }

    // we can do array.len() - 1 since the previous if condition returns if array length is 0
    let pivot = *array.at(array.len() - 1);
    loop {
        if (index == array.len() - 1) {
            break ();
        }

        let element = *array.at(index);

        if (element <= pivot) {
            smaller_elements.append(element);
        } else {
            larger_elements.append(element);
        }

        index += 1;
    };

    (smaller_elements, larger_elements)
}

// General idea behind the quicksort algorithm is being used to sort a given array in ascending order
// The last element is chosen as the pivot
// 2 partitions are created - one containing all elements <= than the pivot 
// and one partition containing elements > than the pivot
// Then the partitions are recursively sorted
// Finally the sorted array is created as a concatenation of smaller_sorted_array + pivot + larger_sorted_array
fn sort<T, impl TCopy: Copy<T>, impl TDrop: Drop<T>, impl TPartialOrd: PartialOrd<T>>(
    array: @Array<T>
) -> Array<T> {
    if (array.len() == 0) {
        let mut empty_array = ArrayTrait::<T>::new();
        return empty_array;
    }
    let (smaller_elements, larger_elements) = get_partitions(array);
    let mut sorted_smaller_elements = sort(@smaller_elements);
    let mut sorted_larger_elements = sort(@larger_elements);

    // append pivot to the array of sorted smaller elements
    // we can do array.len() - 1 since the length is guaranteed to be atleast 1 by this point in the function
    sorted_smaller_elements.append(*array.at(array.len() - 1));
    let mut index = 0_u32;

    loop {
        if (index == sorted_larger_elements.len()) {
            break ();
        }

        sorted_smaller_elements.append(*sorted_larger_elements.at(index));
        index += 1;
    };

    sorted_smaller_elements
}

// Generic function to reverse an array of elements
fn reverse<T, impl TCopy: Copy<T>, impl TDrop: Drop<T>>(array: @Array<T>) -> Array<T> {
    let mut index = 0_u32;
    let mut reversed_array = ArrayTrait::<T>::new();

    loop {
        if (index == array.len()) {
            break ();
        }
        reversed_array.append(*array[array.len() - 1 - index]);
        index += 1;
    };

    reversed_array
}
