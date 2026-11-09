var G:i64[>..<]=[1];
fn leaf() { G.clear(); }
fn middle(view:i64[:]) { leaf(); print(view); }
fn outer(view:i64[:]) { middle(view); }
fn main() { outer(G[..]); }
