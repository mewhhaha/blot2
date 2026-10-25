#[unsafe(no_mangle)]
pub extern "C" fn run(seed: u32) -> u32 {
    const N: usize = 24;
    let left: Vec<u32> = (0..N * N)
        .map(|i| seed.wrapping_add(i as u32 * 17) % 256)
        .collect();
    let right: Vec<u32> = (0..N * N)
        .map(|i| seed.wrapping_add(i as u32 * 31) % 256)
        .collect();
    let mut output = vec![0u32; N * N];
    for row in 0..N {
        for column in 0..N {
            output[row * N + column] = (0..N)
                .map(|k| left[row * N + k] * right[k * N + column])
                .sum();
        }
    }
    output.into_iter().fold(0, u32::wrapping_add)
}
