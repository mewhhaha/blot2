#[unsafe(no_mangle)]
pub extern "C" fn run(seed: u32) -> u32 {
    let n = 16384 + seed as usize % 1024;
    let mut prime = vec![true; n];
    prime[0] = false;
    prime[1] = false;
    let mut factor = 2;
    while factor * factor < n {
        if prime[factor] {
            for i in (factor * factor..n).step_by(factor) {
                prime[i] = false;
            }
        }
        factor += 1;
    }
    prime
        .iter()
        .enumerate()
        .filter(|(_, p)| **p)
        .map(|(i, _)| i as u32)
        .sum()
}
