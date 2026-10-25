#[unsafe(no_mangle)]
pub extern "C" fn run(seed: u32) -> u32 {
    let left: Vec<u32> = (0u32..8192)
        .map(|i| seed.wrapping_add(i * 17) % 1024)
        .collect();
    let right: Vec<u32> = (0u32..8192)
        .map(|i| seed.wrapping_add(i * 31) % 1024)
        .collect();
    left.iter()
        .zip(right)
        .map(|(a, b)| a * b)
        .fold(0, u32::wrapping_add)
}
