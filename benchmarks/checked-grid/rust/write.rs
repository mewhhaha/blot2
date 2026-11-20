mod adapter;
fn solve_words(words: &[u32]) -> (u32, u32) {
    let mut dest = vec![0u32; words.len()];
    for i in 0..dest.len() {
        dest[i] = words[i].wrapping_add(i as u32);
    }
    (
        dest.iter().copied().fold(0, u32::wrapping_add),
        dest.len() as u32,
    )
}
