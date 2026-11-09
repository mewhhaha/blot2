// Closed phantom argument identity needs no GenericNominal<Leaf> fields.
struct Leaf { n: i64 }
struct GenericNominal<T> { value: T }
struct Phantom<T> { integers: i64[u8], flags: bool[u8] }
fn visit<T>(value: Phantom<T>&) -> i64 {
    return value.integers.len + value.flags.len;
}
fn main() {
    let value = Phantom<GenericNominal<Leaf>> { [1, 2], [true] };
    assert(visit(value) == 3);
    assert(visit(value) == 3);
    print("array gate passed");
}
