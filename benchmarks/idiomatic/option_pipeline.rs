fn transform(x: u32) -> Option<u32> {
    (x % 5 != 0).then(|| x.wrapping_mul(3).wrapping_add(1))
}
#[unsafe(no_mangle)]
pub extern "C" fn run(seed: u32) -> u32 {
    (0u32..16384)
        .filter_map(|i| transform(seed.wrapping_add(i)))
        .fold(0, u32::wrapping_add)
}
