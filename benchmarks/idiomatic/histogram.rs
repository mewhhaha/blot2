#[unsafe(no_mangle)]
pub extern "C" fn run(seed: u32) -> u32 {
    let mut bins = [0u32; 256];
    let mut state = seed;
    for _ in 0..16384 {
        state = state.wrapping_mul(1664525).wrapping_add(1013904223);
        bins[(state / 65536 % 256) as usize] += 1;
    }
    bins.iter()
        .enumerate()
        .map(|(i, n)| n * (i as u32 + 1))
        .sum()
}
