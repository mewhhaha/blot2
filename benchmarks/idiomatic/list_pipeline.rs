#[unsafe(no_mangle)]
pub extern "C" fn run(seed: u32) -> u32 {
    let values: Vec<u32> = (0u32..4096).map(|i| seed.wrapping_add(i) % 1024).collect();
    values
        .into_iter()
        .map(|x| x * 3)
        .filter(|x| x % 2 == 0)
        .sum()
}
