fn gcd(mut a: u32, mut b: u32) -> u32 {
    while b != 0 {
        (a, b) = (b, a % b);
    }
    a
}
#[unsafe(no_mangle)]
pub extern "C" fn run(seed: u32) -> u32 {
    (0u32..4096)
        .map(|i| gcd(seed.wrapping_add(i * 7919), i * 104729 + 1))
        .fold(0, u32::wrapping_add)
}
