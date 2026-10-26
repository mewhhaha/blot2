// Differential-test driver. The same deterministic inputs are hashed by the
// pinned Zig standard-library oracle; no oracle is required by the compiler.
import blake3;
import std;

fn hex(bytes: u8[32]) -> u8[>..] {
    let digits = "0123456789abcdef";
    var result: u8[>..] = [];
    for b in bytes { result.push(digits[b / 16]); result.push(digits[b % 16]); }
    return result;
}
fn main() {
    let sizes: i64[] = [0, 1, 3, 31, 63, 64, 65, 67, 127, 255, 511, 777,
        1023, 1024, 1025, 1535, 2047, 2048, 2049, 2053, 3071, 3072, 3073,
        4095, 4097, 4099, 8193, 16383, 25001, 65537, 65539, 100000,
        131071, 1048576, 2097149, 8388611, 16777215, 16777216];
    for mode in 3 {
        var data: u8[>..] = [];
        var random: u32 = 0x12345678;
        for i in 16777216 {
            if mode == 2 {
                random = random * 1664525 + 1013904223;
                data.push((random >> 24) as u8);
            } else { data.push((if mode == 0 { i % 251 } else { (i * 73 + 19) % 251 }) as u8); }
        }
        for size in sizes { print(mode, ":", size, ":", hex(blake3::hash(data[..size]))); }
    }
}
