mod adapter;
mod grid;
fn solve_words(words: &[u32]) -> (u32, u32) {
    let map = grid::Grid::from_words(words);
    (map.width as u32, (map.cells.len() / map.width) as u32)
}
