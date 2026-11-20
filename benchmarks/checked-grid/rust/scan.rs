mod adapter;
fn solve_words(words: &[u32]) -> (u32, u32) {
    let mut sum = 0u32;
    let mut weighted = 0u32;
    for (i, &word) in words.iter().enumerate() {
        sum = sum.wrapping_add(word);
        weighted = weighted.wrapping_add(word.wrapping_mul((i & 7) as u32));
    }
    (sum, weighted)
}
