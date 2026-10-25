use std::fmt::Write;
#[unsafe(no_mangle)]
pub extern "C" fn run(seed: u32) -> u32 {
    let mut output = String::new();
    for i in 0u32..512 {
        write!(output, "{},", seed.wrapping_add(i * 7919)).unwrap();
    }
    output.bytes().fold(0u32, |sum, byte| {
        sum.wrapping_mul(31).wrapping_add(byte as u32)
    })
}
