#[unsafe(no_mangle)]
pub extern "C" fn run(seed: u32) -> u32 {
    let values: Vec<u32> = (0u32..8192)
        .map(|i| seed.wrapping_add(i / 7) % 16)
        .collect();
    let mut output = Vec::new();
    let (mut current, mut length) = (values[0], 0u32);
    for value in values {
        if value == current {
            length += 1;
        } else {
            output.push((current, length));
            current = value;
            length = 1;
        }
    }
    output.push((current, length));
    output.into_iter().fold(0u32, |sum, (value, count)| {
        sum.wrapping_mul(31).wrapping_add(value * count)
    })
}
