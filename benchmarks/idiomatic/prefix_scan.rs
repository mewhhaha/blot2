#[unsafe(no_mangle)]
pub extern "C" fn run(seed: u32) -> u32 {
    let values: Vec<u32> = (0u32..8192).map(|i| seed.wrapping_add(i) % 256).collect();
    values
        .into_iter()
        .scan(0u32, |sum, x| {
            *sum = sum.wrapping_add(x);
            Some(*sum)
        })
        .fold(0, u32::wrapping_add)
}
