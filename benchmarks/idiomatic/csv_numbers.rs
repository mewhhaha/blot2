use std::fmt::Write;
#[unsafe(no_mangle)]
pub extern "C" fn run(seed: u32) -> u32 {
    let mut input = String::new();
    for i in 0u32..512 {
        write!(input, "{},", seed.wrapping_add(i * 7919) % 65536).unwrap();
    }
    input
        .trim_end_matches(',')
        .split(',')
        .map(|part| part.parse::<u32>().unwrap())
        .sum()
}
