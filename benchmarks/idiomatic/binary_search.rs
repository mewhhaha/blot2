#[unsafe(no_mangle)]
pub extern "C" fn run(seed: u32) -> u32 {
    let values: Vec<u32> = (0..4096).map(|i| i * 3).collect();
    (0u32..4096)
        .map(|i| {
            values
                .binary_search(&(seed.wrapping_add(i * 7919) % 16384))
                .map_or(0, |at| at as u32 + 1)
        })
        .sum()
}
