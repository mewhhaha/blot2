enum Expr {
    Value(u32),
    Add(Box<Expr>, Box<Expr>),
    Multiply(Box<Expr>, Box<Expr>),
}
fn make_expr(depth: u32, seed: u32) -> Expr {
    if depth == 0 {
        return Expr::Value(seed % 16);
    }
    let a = Box::new(make_expr(depth - 1, seed.wrapping_mul(3).wrapping_add(1)));
    let b = Box::new(make_expr(depth - 1, seed.wrapping_mul(5).wrapping_add(7)));
    if seed % 2 == 0 {
        Expr::Add(a, b)
    } else {
        Expr::Multiply(a, b)
    }
}
fn evaluate(expr: &Expr) -> u32 {
    match expr {
        Expr::Value(x) => *x,
        Expr::Add(a, b) => evaluate(a).wrapping_add(evaluate(b)),
        Expr::Multiply(a, b) => evaluate(a).wrapping_mul(evaluate(b)),
    }
}
#[unsafe(no_mangle)]
pub extern "C" fn run(seed: u32) -> u32 {
    evaluate(&make_expr(9, seed))
}
