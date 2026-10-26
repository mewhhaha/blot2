import layout;

fn main() {
    let a, a_ok = layout::checked_add(4294967295, 0);
    assert(a_ok && a == 4294967295);
    let _, b_ok = layout::checked_add(4294967295, 1);
    assert(!b_ok);
    let c, c_ok = layout::checked_mul(4294967295, 1);
    assert(c_ok && c == 4294967295);
    let _, d_ok = layout::checked_mul(2147483648, 2);
    assert(!d_ok);
    let e, e_ok = layout::checked_mul(4294967295, 0);
    assert(e_ok && e == 0);
    let f, f_ok = layout::checked_align(4294967292, 4);
    assert(f_ok && f == 4294967292);
    let _, g_ok = layout::checked_align(4294967293, 4);
    assert(!g_ok);
    let h, h_ok = layout::checked_align(5, 4);
    assert(h_ok && h == 8);
    let _, zero_align = layout::checked_align(5, 0);
    let _, bad_align = layout::checked_align(5, 3);
    assert(!zero_align && !bad_align);

    var nodes: layout::Node[>..] = [];
    var edges: u32[>..] = [];
    nodes.push(layout::Node { kind: 0 }); // Unit
    nodes.push(layout::Node { kind: 1 }); // U32
    nodes.push(layout::Node { kind: 3 }); // Bool
    nodes.push(layout::Node { kind: 4 }); // Index
    let u = layout::analyze(nodes, edges, 0);
    let n = layout::analyze(nodes, edges, 1);
    assert(u.status == 0 && u.size == 0 && u.alignment == 1 && u.plain_element && u.share);
    assert(n.status == 0 && n.size == 4 && n.alignment == 4 && n.plain_element && n.share);
    let b = layout::analyze(nodes, edges, 2);
    let i = layout::analyze(nodes, edges, 3);
    assert(b.guards == 1 && i.guards == 1);
    // Product in declaration order: Unit, U32, Bool, Index.
    edges.push(0); edges.push(1); edges.push(2); edges.push(3);
    nodes.push(layout::Node { kind: 5, first: 0, count: 4 });
    let product = layout::analyze(nodes, edges, 4);
    assert(product.status == 0 && product.size == 12 && product.alignment == 4 && product.plain_element);
    assert(product.structural == 1 && product.leaves == 3 && product.guards == 2);
    // Sum reserves one tag plus largest payload; inactive bytes are a separate
    // publication obligation and are not established by a geometry proof.
    edges.push(0); edges.push(4);
    nodes.push(layout::Node { kind: 6, first: 4, count: 2 });
    let sum = layout::analyze(nodes, edges, 5);
    assert(sum.status == 0 && sum.size == 16 && sum.plain_element && sum.guards == 3);
    // A View is Share but not Plain; a product inherits both classifications.
    nodes.push(layout::Node { kind: 7 });
    edges.push(1); edges.push(6);
    nodes.push(layout::Node { kind: 5, first: 6, count: 2 });
    let view_product = layout::analyze(nodes, edges, 7);
    assert(view_product.status == 0 && view_product.size == 12 && view_product.share && !view_product.plain_element);
    // Result is affine/must-handle, including when nested inside a product.
    edges.push(1); edges.push(0);
    nodes.push(layout::Node { kind: 10, first: 8, count: 2 });
    edges.push(8);
    nodes.push(layout::Node { kind: 5, first: 10, count: 1 });
    let result = layout::analyze(nodes, edges, 8);
    let nested_result = layout::analyze(nodes, edges, 9);
    assert(result.status == 0 && result.size == 8 && !result.share && result.must_handle);
    assert(nested_result.must_handle && !nested_result.share && !nested_result.plain_element);
    // Nat witness prefix is not deduplicated even if a payload might also
    // contain its numerical length. Domain witnesses contribute no bytes.
    edges.push(0);
    nodes.push(layout::Node { kind: 11, first: 11, count: 1, witnesses: 16 });
    let package16 = layout::analyze(nodes, edges, 10);
    assert(package16.status == 0 && package16.size == 64 && package16.plain_element);
    edges.push(0);
    nodes.push(layout::Node { kind: 11, first: 12, count: 1, witnesses: 17 });
    let package17 = layout::analyze(nodes, edges, 11);
    assert(package17.status == 0 && package17.size == 68 && !package17.plain_element && package17.share);

    // Exact 64/256-byte thresholds and one element over each.
    var sizes: layout::Node[>..] = [];
    var size_edges: u32[>..] = [];
    sizes.push(layout::Node { kind: 1 });
    for j in 65 { size_edges.push(0); }
    sizes.push(layout::Node { kind: 5, first: 0, count: 16 });
    sizes.push(layout::Node { kind: 5, first: 0, count: 17 });
    sizes.push(layout::Node { kind: 5, first: 0, count: 64 });
    let row16 = layout::analyze(sizes, size_edges, 1);
    let row17 = layout::analyze(sizes, size_edges, 2);
    let aggregate64 = layout::analyze(sizes, size_edges, 3);
    assert(row16.status == 0 && row16.size == 64 && row16.plain_element);
    assert(row17.status == 0 && row17.size == 68 && !row17.plain_element && row17.share);
    assert(aggregate64.status == 0 && aggregate64.size == 256);
    size_edges.push(3); size_edges.push(0);
    sizes.push(layout::Node { kind: 10, first: 65, count: 2 });
    assert(layout::analyze(sizes, size_edges, 4).status == 2); // Result tag exceeds 256

    // Cycles, bad span and forward references are rejected without following them.
    var bad: layout::Node[>..] = [];
    let zero: u32[] = [0];
    bad.push(layout::Node { kind: 5, first: 0, count: 1 });
    assert(layout::analyze(bad, zero, 0).status == 1);
    var bad_span: layout::Node[>..] = [];
    bad_span.push(layout::Node { kind: 5, first: 4294967295, count: 1 });
    assert(layout::analyze(bad_span, zero, 0).status == 1);
    var bad_kind: layout::Node[>..] = [];
    bad_kind.push(layout::Node { kind: 12 });
    assert(layout::analyze(bad_kind, zero, 0).status == 1);
    var sum_nodes: layout::Node[>..] = [];
    sum_nodes.push(layout::Node { kind: 0 });
    sum_nodes.push(layout::Node { kind: 6, first: 0, count: 5 });
    let sum_edges: u32[] = [0, 0, 0, 0, 0];
    assert(layout::analyze(sum_nodes, sum_edges, 1).status == 2);
    // Excess nesting deterministically declines, including zero-sized products.
    var deep: layout::Node[>..] = [];
    var deep_edges: u32[>..] = [];
    deep.push(layout::Node { kind: 0 });
    for j in 64 {
        deep_edges.push(j as u32);
        deep.push(layout::Node { kind: 5, first: j as u32, count: 1 });
    }
    assert(layout::analyze(deep[0..64], deep_edges, 63).status == 0);
    assert(layout::analyze(deep, deep_edges, 64).status == 2);

    // Structural counts expand reused DAG references, rather than counting
    // distinct IDs, even when all repeated children have zero-size layout.
    var structures: layout::Node[>..] = [];
    var structure_edges: u32[>..] = [];
    structures.push(layout::Node { kind: 5 }); // empty product: one node
    for j in 32 { structure_edges.push(0); }
    structures.push(layout::Node { kind: 5, count: 31 });
    structures.push(layout::Node { kind: 5, count: 32 });
    let exactly32 = layout::analyze(structures, structure_edges, 1);
    let over32 = layout::analyze(structures, structure_edges, 2);
    assert(exactly32.status == 0 && exactly32.structural == 32 && exactly32.plain_element);
    assert(over32.status == 0 && over32.structural == 33 && !over32.plain_element);

    // Sum arms can contain more guards than physical words in their maximum
    // payload, so test the guard limit separately from the size limit.
    var guards: layout::Node[>..] = [];
    var guard_edges: u32[>..] = [];
    guards.push(layout::Node { kind: 3 });
    for j in 4 { guard_edges.push(0); }
    guards.push(layout::Node { kind: 6, count: 4 }); // 5 guards
    for j in 4 { guard_edges.push(1); }
    guards.push(layout::Node { kind: 6, first: 4, count: 4 }); // 21 guards
    guard_edges.push(1); guard_edges.push(1);
    guards.push(layout::Node { kind: 5, first: 8, count: 2 }); // 10 guards
    guard_edges.push(2); guard_edges.push(3);
    guards.push(layout::Node { kind: 6, first: 10, count: 2 }); // 32 guards
    guard_edges.push(2); guard_edges.push(3); guard_edges.push(0);
    guards.push(layout::Node { kind: 6, first: 12, count: 3 }); // 33 guards
    let guards32 = layout::analyze(guards, guard_edges, 4);
    let guards33 = layout::analyze(guards, guard_edges, 5);
    assert(guards32.status == 0 && guards32.guards == 32 && guards32.plain_element);
    assert(guards33.status == 0 && guards33.guards == 33 && !guards33.plain_element);

    // Repeated edge spans are charged for every visit. Exercise exactly the
    // semantic-work limit and its first excess without a large value layout.
    var work_nodes: layout::Node[>..] = [];
    var work_edges: u32[>..] = [];
    work_nodes.push(layout::Node { kind: 0 });
    for j in 8192 { work_edges.push(0); }
    for j in 127 { work_nodes.push(layout::Node { kind: 5, count: 8192 }); }
    work_nodes.push(layout::Node { kind: 5, count: 8063 });
    assert(layout::analyze(work_nodes, work_edges, 128).status == 0);
    work_nodes[128].count = 8064;
    assert(layout::analyze(work_nodes, work_edges, 128).status == 3);

    var too_many_nodes: layout::Node[>..] = [];
    for j in 8193 { too_many_nodes.push(layout::Node { kind: 0 }); }
    assert(layout::analyze(too_many_nodes, zero, 0).status == 4);
    print("layout geometry laws passed");
}
