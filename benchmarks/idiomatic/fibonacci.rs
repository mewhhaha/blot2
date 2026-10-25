#[unsafe(no_mangle)]
pub extern "C" fn run(seed: u32) -> u32 {
    (0..2048)
        .map(|index| {
            let (mut a, mut b) = (0u32, 1u32);
            for _ in 0..24 + seed.wrapping_add(index) % 16 {
                (a, b) = (b, a.wrapping_add(b));
            }
            a
        })
        .fold(0, u32::wrapping_add)
}
