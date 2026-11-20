pub struct Grid {
    pub width: usize,
    pub cells: Vec<u32>,
}

#[derive(Clone, Copy)]
pub enum Direction {
    Left,
    Right,
    Up,
    Down,
}
pub const DIRECTIONS: [Direction; 4] = [
    Direction::Left,
    Direction::Right,
    Direction::Up,
    Direction::Down,
];

impl Grid {
    pub fn from_words(words: &[u32]) -> Self {
        let bytes: Vec<u8> = words
            .iter()
            .map(|&ch| {
                assert!(ch <= 127);
                ch as u8
            })
            .collect();
        Self::parse(std::str::from_utf8(&bytes).expect("ASCII grid"))
    }

    pub fn parse(source: &str) -> Self {
        let mut lines = source.lines();
        let first = lines.next().expect("empty grid");
        let width = first.len();
        assert!(width > 0 && first.is_ascii(), "invalid first row");
        let mut cells: Vec<u32> = first.bytes().map(u32::from).collect();
        for row in lines {
            assert!(row.len() == width && row.is_ascii(), "invalid row");
            cells.extend(row.bytes().map(u32::from));
        }
        Self { width, cells }
    }

    pub fn neighbor(&self, i: usize, direction: Direction) -> Option<usize> {
        match direction {
            Direction::Left if i % self.width > 0 => Some(i - 1),
            Direction::Right if i % self.width + 1 < self.width => Some(i + 1),
            Direction::Up if i >= self.width => Some(i - self.width),
            Direction::Down if i < self.cells.len() - self.width => Some(i + self.width),
            _ => None,
        }
    }
}
