import std;
import module_frontend;

// Deliberately independent per-root path checker for a one-outgoing-edge graph.
fn reference(module: module_frontend::Module&) -> bool {
    let n = module.declarations.len;
    if n == 0 || n > 256 { return false; }
    for root in n {
        var seen: bool[256] = [false; 256];
        var node = root;
        var depth: i64 = 1;
        loop {
            if node < 0 || node >= n || seen[node] { return false; }
            seen[node] = true;
            let d = module.declarations[node];
            if d.form == 3 { node = d.callee_id; depth += 1; }
            else if d.form == 1 || d.form == 2 { break; }
            else { return false; }
            if depth > 256 { return false; }
        }
        if depth > 128 || depth != module.declarations[root].depth { return false; }
    }
    return true;
}
fn expected_depth(module: module_frontend::Module&, root: i64) -> i64 {
    var seen: bool[256] = [false; 256];
    var node = root;
    var depth: i64 = 1;
    loop {
        if node < 0 || node >= module.declarations.len || seen[node] { return 0; }
        seen[node] = true;
        let d = module.declarations[node];
        if d.form == 3 { node = d.callee_id; depth += 1; }
        else if d.form == 1 || d.form == 2 { return depth; }
        else { return 0; }
        if depth > 256 { return 0; }
    }
    return 0;
}
fn next(seed: u32&) -> u32 { seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5; return seed; }
fn main() {
    var source: u8[>..] = [];
    for i in 256 { format(source,"let f",i,": U32 -> U32 = fn x => return x\n"); }
    var m, status = module_frontend::parse(source);
    assert(status == 0 && module_frontend::verifier_unique_names(m));
    let original = m.declarations[255];
    m.declarations[255].name_start = m.declarations[0].name_start;
    m.declarations[255].name_end = m.declarations[0].name_end;
    assert(!module_frontend::verifier_unique_names(m));
    m.declarations[255] = original;
    // Duplicates at distant positions and with long common prefixes must be
    // found independent of source order and merge width.
    for j in 1..256 {
        let saved = m.declarations[j];
        let prior = (j * 73 + 19) % j;
        m.declarations[j].name_start = m.declarations[prior].name_start;
        m.declarations[j].name_end = m.declarations[prior].name_end;
        assert(!module_frontend::verifier_unique_names(m));
        m.declarations[j] = saved;
    }
    assert(module_frontend::verifier_unique_names(m));
    m.declarations[121].name_start = -1;
    assert(!module_frontend::verifier_unique_names(m));
    m.declarations[121].name_start = m.declarations[121].name_end + 1;
    assert(!module_frontend::verifier_unique_names(m));
    // Direct graph helper: exact and one-over resource depths, cycles,
    // forged negative and high targets, invalid forms, incorrect depths.
    var ds: module_frontend::Declaration[>..] = [];
    for i in 129 { ds.push(module_frontend::Declaration { form: if i < 128 { 3 } else { 1 }, callee_id: i + 1, depth: 129 - i }); }
    var g = module_frontend::Module { declarations: copy(ds) };
    assert(!module_frontend::verifier_graph(g)); // depth 129
    g.declarations[0].form = 1; g.declarations[0].depth = 1;
    assert(module_frontend::verifier_graph(g)); // longest remaining chain 128
    g.declarations[0].form = 3; g.declarations[0].callee_id = 0;
    assert(!module_frontend::verifier_graph(g)); // self-cycle
    g.declarations[0].callee_id = -1;
    assert(!module_frontend::verifier_graph(g));
    g.declarations[0].callee_id = 129;
    assert(!module_frontend::verifier_graph(g));
    g.declarations[0].form = 99;
    assert(!module_frontend::verifier_graph(g));
    // Deterministic differential test of arbitrary forward/back edges, cycles,
    // invalid form/target and mutated depth against a separate path walk.
    var seed: u32 = 0x6c8e9cf5;
    for iteration in 1000 {
        let n: i64 = (next(seed) % 256 + 1) as i64;
        var items: module_frontend::Declaration[>..] = [];
        for i in n {
            let choice = next(seed) % 10;
            var d = module_frontend::Declaration { form: 1, depth: 1 };
            if choice < 8 { d.form = 3; d.callee_id = (next(seed) % (n as u32 + 3)) as i64 - 1; }
            else if choice == 8 { d.form = 2; }
            else { d.form = 99; }
            items.push(d);
        }
        var random = module_frontend::Module { declarations: copy(items) };
        for i in n { random.declarations[i].depth = expected_depth(random,i); }
        if iteration % 4 == 0 { let idx = (next(seed) % (n as u32)) as i64; random.declarations[idx].depth += 1; }
        assert(module_frontend::verifier_graph(random) == reference(random));
    }
    // Positive DAGs have all edges towards a later index, including shared
    // callees and long chains. Check both exact and corrupted declared depth.
    for iteration in 400 {
        let n: i64 = (next(seed) % 256 + 1) as i64;
        var items: module_frontend::Declaration[>..] = [];
        for i in n {
            var d = module_frontend::Declaration { form: 1, depth: 1 };
            if i + 1 < n && next(seed) % 4 != 0 {
                d.form = 3;
                d.callee_id = i + 1 + (next(seed) % ((n - i - 1) as u32));
            }
            items.push(d);
        }
        var dag = module_frontend::Module { declarations: copy(items) };
        for i in n { dag.declarations[i].depth = expected_depth(dag,i); }
        assert(reference(dag) && module_frontend::verifier_graph(dag));
        let index = (next(seed) % (n as u32)) as i64;
        dag.declarations[index].depth += 1;
        assert(!module_frontend::verifier_graph(dag));
    }
    print("independent verifier adversarial laws passed");
}
