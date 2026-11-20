mod adapter;
fn solve_words(words: &[u32]) -> (u32, u32) {
    let view = &words[words.len() / 2..];
    (
        view.iter().copied().fold(0, u32::wrapping_add),
        view.len() as u32,
    )
}
