import std;
import module_frontend;

// Test-only independent AVL invariant walk. It checks full ancestor bounds,
// reachability, recorded heights and balance, not just local child order.
recursive fn walk(index: module_frontend::NameIndex&, source: u8[:], node: i64,
                  lower: i64, upper: i64, seen: bool[256]&) -> i64 {
    if node < 0 { return 0; }
    assert(node < index.nodes.len && !seen[node]);
    seen[node] = true;
    let e = index.nodes[node];
    if lower >= 0 {
        let lo = index.nodes[lower];
        assert(module_frontend::name_order(source, lo.start, lo.end, e.start, e.end) < 0);
    }
    if upper >= 0 {
        let hi = index.nodes[upper];
        assert(module_frontend::name_order(source, e.start, e.end, hi.start, hi.end) < 0);
    }
    let lh = walk(index, source, e.left, lower, node, seen);
    let rh = walk(index, source, e.right, node, upper, seen);
    assert(lh - rh >= -1 && lh - rh <= 1);
    let expected = 1 + (if lh > rh { lh } else { rh });
    assert(e.height == expected);
    return expected;
}
fn check(mode: i64) {
    var source: u8[>..] = [];
    var starts: i64[256] = [0; 256];
    var ends: i64[256] = [0; 256];
    for i in 256 {
        starts[i] = source.len;
        format(source, "long_common_prefix_", i);
        ends[i] = source.len;
        source.push(' ');
    }
    var index = module_frontend::NameIndex {};
    for step in 256 {
        let i = if mode == 0 { step } else if mode == 1 { 255 - step } else { (step * 73) % 256 };
        assert(module_frontend::insert_name(index, source, starts[i], ends[i], i));
        var seen: bool[256] = [false; 256];
        let height = walk(index, source, index.root, -1, -1, seen);
        assert(height <= 12 && index.nodes.len == step + 1);
        for j in index.nodes.len { assert(seen[j]); }
        assert(module_frontend::lookup_name(index, source, starts[i], ends[i]) == i);
        assert(!module_frontend::insert_name(index, source, starts[i], ends[i], i));
    }
    for i in 256 { assert(module_frontend::lookup_name(index, source, starts[i], ends[i]) == i); }
    source.append("not_present");
    assert(module_frontend::lookup_name(index, source, source.len - 11, source.len) == -1);
}
fn main() {
    check(0); check(1); check(2);
    // The graph helper must reject an oversized or empty table even when it is
    // called directly, before indexing fixed scratch arrays.
    var declarations: module_frontend::Declaration[>..] = [];
    assert(module_frontend::complete_depths(declarations) == 1);
    for i in 257 { declarations.push(module_frontend::Declaration {}); }
    assert(module_frontend::complete_depths(declarations) == 1);
    print("deterministic AVL invariant laws passed");
}
