mod adapter;
mod grid;
use grid::{Direction, Grid, DIRECTIONS};

fn sight(grid: &Grid, origin: usize, direction: Direction) -> (bool, u32) {
    let height = grid.cells[origin];
    let mut position = origin;
    let mut distance = 0;
    while let Some(next) = grid.neighbor(position, direction) {
        distance += 1;
        if grid.cells[next] >= height {
            return (false, distance);
        }
        position = next;
    }
    (true, distance)
}

fn solve(grid: &Grid) -> (u32, u32) {
    let (mut visible_count, mut best) = (0, 0);
    for i in 0..grid.cells.len() {
        assert!((48..=57).contains(&grid.cells[i]));
        let (mut visible, mut scenic) = (false, 1);
        for direction in DIRECTIONS {
            let (clear, distance) = sight(grid, i, direction);
            visible |= clear;
            scenic *= distance;
        }
        visible_count += u32::from(visible);
        best = best.max(scenic);
    }
    (visible_count, best)
}

fn solve_words(words: &[u32]) -> (u32, u32) {
    solve(&Grid::from_words(words))
}
