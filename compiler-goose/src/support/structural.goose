// Structural streams are independent of host addresses and padding.
namespace blot_structural;
import support.bytes;
import support.native;
import support.option;

fn equal(left: u8, right: u8) -> bool { left == right }
fn blot_structural::blotStructuralHash<S>(value: u8,sink: S&) {
    let bits = value as! u8;
    var bytes: u8[1] = default<u8[1]>();
    for index in 1 { bytes[index] = (bits >> ((index * 8) as u32)) as! u8; }
    sink.update(bytes);
}
fn equal(left: i8, right: i8) -> bool { left == right }
fn blot_structural::blotStructuralHash<S>(value: i8,sink: S&) {
    let bits = value as! u8;
    var bytes: u8[1] = default<u8[1]>();
    for index in 1 { bytes[index] = (bits >> ((index * 8) as u32)) as! u8; }
    sink.update(bytes);
}
fn equal(left: u16, right: u16) -> bool { left == right }
fn blot_structural::blotStructuralHash<S>(value: u16,sink: S&) {
    let bits = value as! u16;
    var bytes: u8[2] = default<u8[2]>();
    for index in 2 { bytes[index] = (bits >> ((index * 8) as u32)) as! u8; }
    sink.update(bytes);
}
fn equal(left: i16, right: i16) -> bool { left == right }
fn blot_structural::blotStructuralHash<S>(value: i16,sink: S&) {
    let bits = value as! u16;
    var bytes: u8[2] = default<u8[2]>();
    for index in 2 { bytes[index] = (bits >> ((index * 8) as u32)) as! u8; }
    sink.update(bytes);
}
fn equal(left: u32, right: u32) -> bool { left == right }
fn blot_structural::blotStructuralHash<S>(value: u32,sink: S&) {
    let bits = value as! u32;
    var bytes: u8[4] = default<u8[4]>();
    for index in 4 { bytes[index] = (bits >> ((index * 8) as u32)) as! u8; }
    sink.update(bytes);
}
fn equal(left: i32, right: i32) -> bool { left == right }
fn blot_structural::blotStructuralHash<S>(value: i32,sink: S&) {
    let bits = value as! u32;
    var bytes: u8[4] = default<u8[4]>();
    for index in 4 { bytes[index] = (bits >> ((index * 8) as u32)) as! u8; }
    sink.update(bytes);
}
fn equal(left: u64, right: u64) -> bool { left == right }
fn blot_structural::blotStructuralHash<S>(value: u64,sink: S&) {
    let bits = value as! u64;
    var bytes: u8[8] = default<u8[8]>();
    for index in 8 { bytes[index] = (bits >> ((index * 8) as u32)) as! u8; }
    sink.update(bytes);
}
fn equal(left: i64, right: i64) -> bool { left == right }
fn blot_structural::blotStructuralHash<S>(value: i64,sink: S&) {
    let bits = value as! u64;
    var bytes: u8[8] = default<u8[8]>();
    for index in 8 { bytes[index] = (bits >> ((index * 8) as u32)) as! u8; }
    sink.update(bytes);
}
fn equal(left: bool, right: bool) -> bool { left == right }
fn equal(left: f32, right: f32) -> bool { left == right }
fn equal(left: f64, right: f64) -> bool { left == right }
fn blot_structural::blotStructuralHash<S>(value: bool,sink: S&) {
    var byte: u8 = 0; if value { byte = 1; } blot_structural::hash(sink, byte);
}
fn blot_structural::blotStructuralHash<S>(value: f32,sink: S&) { blot_structural::hash(sink, blot_native::f32_bits(value)); }
fn blot_structural::blotStructuralHash<S>(value: f64,sink: S&) { blot_structural::hash(sink, blot_native::f64_bits(value)); }

fn equal<T>(left: const T[:], right: const T[:]) -> bool {
    if left.len != right.len { return false; }
    for index in left.len { if !equal(left[index], right[index]) { return false; } }
    return true;
}
fn blot_structural::blotStructuralHash<S, T>(value: const T[:],sink: S&) {
    blot_structural::hash(sink, value.len as u64);
    for item in value { blot_structural::hash(sink, item); }
}

fn equal<T>(left: blot_support::Option<T>, right: blot_support::Option<T>) -> bool {
    if left.present != right.present { return false; }
    if !left.present { return true; }
    return equal(left.value, right.value);
}
fn blot_support::blotStructuralHash<S,T>(value: blot_support::Option<T>,sink: S&) {
    blot_structural::hash(sink, value.present); if value.present { blot_structural::hash(sink, value.value); }
}

fn equalFields<T>(left: T, right: T) -> bool {
    const for <N, A> in fields<T> { if !equal(left.A, right.A) { return false; } }
    return true;
}
fn hashFields<S,T>(sink: S&, value: T) {
    const for <N, A> in fields<T> { hash(sink, value.A); }
}

fn equal<T>(left: T[0], right: T[0]) -> bool {
    for index in 0 { if !equal(left[index], right[index]) { return false; } }
    return true;
}
fn blot_structural::blotStructuralHash<S,T>(value: T[0],sink: S&) {
    for item in value { blot_structural::hash(sink, item); }
}
fn equal<T>(left: T[1], right: T[1]) -> bool {
    for index in 1 { if !equal(left[index], right[index]) { return false; } }
    return true;
}
fn blot_structural::blotStructuralHash<S,T>(value: T[1],sink: S&) {
    for item in value { blot_structural::hash(sink, item); }
}
fn equal<T>(left: T[2], right: T[2]) -> bool {
    for index in 2 { if !equal(left[index], right[index]) { return false; } }
    return true;
}
fn blot_structural::blotStructuralHash<S,T>(value: T[2],sink: S&) {
    for item in value { blot_structural::hash(sink, item); }
}
fn equal<T>(left: T[3], right: T[3]) -> bool {
    for index in 3 { if !equal(left[index], right[index]) { return false; } }
    return true;
}
fn blot_structural::blotStructuralHash<S,T>(value: T[3],sink: S&) {
    for item in value { blot_structural::hash(sink, item); }
}
fn equal<T>(left: T[4], right: T[4]) -> bool {
    for index in 4 { if !equal(left[index], right[index]) { return false; } }
    return true;
}
fn blot_structural::blotStructuralHash<S,T>(value: T[4],sink: S&) {
    for item in value { blot_structural::hash(sink, item); }
}
fn equal<T>(left: T[5], right: T[5]) -> bool {
    for index in 5 { if !equal(left[index], right[index]) { return false; } }
    return true;
}
fn blot_structural::blotStructuralHash<S,T>(value: T[5],sink: S&) {
    for item in value { blot_structural::hash(sink, item); }
}
fn equal<T>(left: T[6], right: T[6]) -> bool {
    for index in 6 { if !equal(left[index], right[index]) { return false; } }
    return true;
}
fn blot_structural::blotStructuralHash<S,T>(value: T[6],sink: S&) {
    for item in value { blot_structural::hash(sink, item); }
}
fn equal<T>(left: T[7], right: T[7]) -> bool {
    for index in 7 { if !equal(left[index], right[index]) { return false; } }
    return true;
}
fn blot_structural::blotStructuralHash<S,T>(value: T[7],sink: S&) {
    for item in value { blot_structural::hash(sink, item); }
}
fn equal<T>(left: T[8], right: T[8]) -> bool {
    for index in 8 { if !equal(left[index], right[index]) { return false; } }
    return true;
}
fn blot_structural::blotStructuralHash<S,T>(value: T[8],sink: S&) {
    for item in value { blot_structural::hash(sink, item); }
}
fn equal<T>(left: T[12], right: T[12]) -> bool {
    for index in 12 { if !equal(left[index], right[index]) { return false; } }
    return true;
}
fn blot_structural::blotStructuralHash<S,T>(value: T[12],sink: S&) {
    for item in value { blot_structural::hash(sink, item); }
}
fn equal<T>(left: T[16], right: T[16]) -> bool {
    for index in 16 { if !equal(left[index], right[index]) { return false; } }
    return true;
}
fn blot_structural::blotStructuralHash<S,T>(value: T[16],sink: S&) {
    for item in value { blot_structural::hash(sink, item); }
}
fn equal<T>(left: T[24], right: T[24]) -> bool {
    for index in 24 { if !equal(left[index], right[index]) { return false; } }
    return true;
}
fn blot_structural::blotStructuralHash<S,T>(value: T[24],sink: S&) {
    for item in value { blot_structural::hash(sink, item); }
}
fn equal<T>(left: T[32], right: T[32]) -> bool {
    for index in 32 { if !equal(left[index], right[index]) { return false; } }
    return true;
}
fn blot_structural::blotStructuralHash<S,T>(value: T[32],sink: S&) {
    for item in value { blot_structural::hash(sink, item); }
}
fn equal<T>(left: T[48], right: T[48]) -> bool {
    for index in 48 { if !equal(left[index], right[index]) { return false; } }
    return true;
}
fn blot_structural::blotStructuralHash<S,T>(value: T[48],sink: S&) {
    for item in value { blot_structural::hash(sink, item); }
}
fn equal<T>(left: T[54], right: T[54]) -> bool {
    for index in 54 { if !equal(left[index], right[index]) { return false; } }
    return true;
}
fn blot_structural::blotStructuralHash<S,T>(value: T[54],sink: S&) {
    for item in value { blot_structural::hash(sink, item); }
}
fn equal<T>(left: T[64], right: T[64]) -> bool {
    for index in 64 { if !equal(left[index], right[index]) { return false; } }
    return true;
}
fn blot_structural::blotStructuralHash<S,T>(value: T[64],sink: S&) {
    for item in value { blot_structural::hash(sink, item); }
}
fn equal<T>(left: T[128], right: T[128]) -> bool {
    for index in 128 { if !equal(left[index], right[index]) { return false; } }
    return true;
}
fn blot_structural::blotStructuralHash<S,T>(value: T[128],sink: S&) {
    for item in value { blot_structural::hash(sink, item); }
}
fn equal<T>(left: T[256], right: T[256]) -> bool {
    for index in 256 { if !equal(left[index], right[index]) { return false; } }
    return true;
}
fn blot_structural::blotStructuralHash<S,T>(value: T[256],sink: S&) {
    for item in value { blot_structural::hash(sink, item); }
}
fn equal<T>(left: T[512], right: T[512]) -> bool {
    for index in 512 { if !equal(left[index], right[index]) { return false; } }
    return true;
}
fn blot_structural::blotStructuralHash<S,T>(value: T[512],sink: S&) {
    for item in value { blot_structural::hash(sink, item); }
}
fn equal<T>(left: T[1024], right: T[1024]) -> bool {
    for index in 1024 { if !equal(left[index], right[index]) { return false; } }
    return true;
}
fn blot_structural::blotStructuralHash<S,T>(value: T[1024],sink: S&) {
    for item in value { blot_structural::hash(sink, item); }
}
fn equal<T>(left: T[4096], right: T[4096]) -> bool {
    for index in 4096 { if !equal(left[index], right[index]) { return false; } }
    return true;
}
fn blot_structural::blotStructuralHash<S,T>(value: T[4096],sink: S&) {
    for item in value { blot_structural::hash(sink, item); }
}

fn hash<S,T>(sink:S&,value:T) {value.blotStructuralHash(sink);}
