#[unsafe(no_mangle)]
pub extern "C" fn run(seed: u32) -> u32 {
    let (mut state, mut total) = (seed, 0u32);
    for _ in 0..65536 {
        state = state.wrapping_mul(1664525).wrapping_add(1013904223);
        total = total.wrapping_add(state / 65536);
    }
    total
}
