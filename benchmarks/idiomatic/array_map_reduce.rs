#[unsafe(no_mangle)]
pub extern "C" fn run(seed: u32) -> u32 {
    let values: Vec<u32> = (0u32..8192)
        .map(|i| seed.wrapping_add(i * 7919) % 65536)
        .collect();
    values
        .iter()
        .map(|x| x.wrapping_mul(*x).wrapping_add(3))
        .fold(0, u32::wrapping_add)
}
