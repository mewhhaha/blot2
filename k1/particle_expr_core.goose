// Private, source-bound F32 expression Core. This is not a function artifact,
// K1 proof/effect/resource contract, particle-loop admission or an ABI.
namespace particle_expr_core;
// 1..4: p.x,p.y,p.vx,p.vy; 5: dt; 6: F32 mul; 7: F32 add.
// Operation spans identify the exact token; child IDs are one-based, earlier
// than the operation, and zero for leaf values.
struct Node { kind: i64 = 0, start: i64 = 0, end: i64 = 0, left: i64 = 0, right: i64 = 0 }
struct Core { source: u8[] = [], nodes: Node[] = [], result: i64 = 0 }
fn same(a: Node, b: Node) -> bool {
    return a.kind == b.kind && a.start == b.start && a.end == b.end && a.left == b.left && a.right == b.right;
}
