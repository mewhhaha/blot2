#[unsafe(no_mangle)]
pub extern "C" fn run(seed: u32) -> u32 {
    let values: Vec<u32> = (0u32..8192)
        .map(|i| seed.wrapping_add(i * 7919) % 65536)
        .collect();
    values
        .into_iter()
        .filter(|x| x % 3 == 0)
        .fold(0, u32::wrapping_add)
}
