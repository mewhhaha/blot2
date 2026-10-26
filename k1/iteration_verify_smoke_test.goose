import iteration_core;
import iteration_verify;
fn main() { var tree = iteration_core::Tree {}; assert(!iteration_verify::verify(tree,"")); }
