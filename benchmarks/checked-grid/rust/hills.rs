mod adapter;
mod grid;
use grid::{Grid, DIRECTIONS};

const UNSEEN: u32 = u32::MAX;

fn elevation(ch: u32) -> u32 {
    match ch {
        83 => 97,
        69 => 122,
        _ => ch,
    }
}

fn distances(grid: &Grid, finish: usize) -> Vec<u32> {
    let mut steps = vec![UNSEEN; grid.cells.len()];
    let mut queue = vec![0; grid.cells.len()];
    queue[0] = finish;
    let mut head = 0;
    let mut tail = 1;
    steps[finish] = 0;
    while head != tail {
        let here = queue[head];
        head += 1;
        for direction in DIRECTIONS {
            let Some(next) = grid.neighbor(here, direction) else {
                continue;
            };
            if steps[next] != UNSEEN {
                continue;
            }
            if elevation(grid.cells[next]) + 1 < elevation(grid.cells[here]) {
                continue;
            }
            steps[next] = steps[here] + 1;
            queue[tail] = next;
            tail += 1;
        }
    }
    steps
}

fn marker(grid: &Grid, ch: u32) -> usize {
    let mut found = grid.cells.iter().enumerate().filter(|(_, &v)| v == ch);
    let (i, _) = found.next().expect("missing marker");
    assert!(found.next().is_none(), "duplicate marker");
    i
}

fn solve(grid: &Grid) -> (u32, u32) {
    assert!(grid
        .cells
        .iter()
        .all(|&ch| matches!(ch, 97..=122 | 83 | 69)));
    let start = marker(grid, 83);
    let finish = marker(grid, 69);
    let steps = distances(grid, finish);
    let best = grid
        .cells
        .iter()
        .zip(&steps)
        .filter_map(|(&ch, &d)| (elevation(ch) == 97).then_some(d))
        .min()
        .unwrap_or(UNSEEN);
    (steps[start], best)
}

fn solve_words(words: &[u32]) -> (u32, u32) {
    solve(&Grid::from_words(words))
}
