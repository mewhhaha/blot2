enum Tree {
    Leaf(u32),
    Branch(Box<Tree>, Box<Tree>),
}
fn make_tree(depth: u32, seed: u32) -> Tree {
    if depth == 0 {
        Tree::Leaf(seed)
    } else {
        Tree::Branch(
            Box::new(make_tree(depth - 1, seed.wrapping_mul(3).wrapping_add(1))),
            Box::new(make_tree(depth - 1, seed.wrapping_mul(5).wrapping_add(7))),
        )
    }
}
fn sum_tree(tree: &Tree) -> u32 {
    match tree {
        Tree::Leaf(x) => *x,
        Tree::Branch(a, b) => sum_tree(a).wrapping_add(sum_tree(b)),
    }
}
#[unsafe(no_mangle)]
pub extern "C" fn run(seed: u32) -> u32 {
    sum_tree(&make_tree(10, seed))
}
