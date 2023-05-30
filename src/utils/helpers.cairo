fn is_in_range<T, impl TPartialOrd: PartialOrd<T>, impl TDrop: Drop<T>, impl Tcopy: Copy<T>>(value: T, x: T, y: T) -> bool {
    if value < x {return false;}
    if value > y {return false;}
    true
}