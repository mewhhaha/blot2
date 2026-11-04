namespace blot_support;

// Only fixed values belong here. Owning tables stay with the driver; optional
// references use Goose's native nullable reference instead.
struct Option<T> { present: bool = false, value: T }

fn some<T>(value: T) -> Option<T> { Option<T> { true, value } }
fn none<T>() -> Option<T> { Option<T> { false, default<T>() } }
fn value_or<T>(option: Option<T>, fallback: T) -> T {
    if option.present { return option.value; }
    return fallback;
}
fn equal<T>(left: T, right: T) -> bool { left == right }

fn find<T>(values: const T[:], wanted: T) -> i64 {
    for value, index in values { if value == wanted { return index; } }
    return -1;
}

fn contains<T>(values: const T[:], wanted: T) -> bool {
    find(values, wanted) >= 0
}

fn copy_forward<T>(destination: T[:], source: const T[:]) {
    for index in source.len { destination[index] = source[index]; }
}

fn copy_backward<T>(destination: T[:], source: const T[:]) {
    var index = source.len;
    while index > 0 { index--; destination[index] = source[index]; }
}

// A copied view with equal contents is not the same storage authority.
fn same_slice_identity<T>(left: const T[:], right: const T[:]) -> bool {
    if left.len != right.len { return false; }
    if left.len == 0 { return true; }
    let a: const T& = left[0]; let b: const T& = right[0]; return a .== b;
}
