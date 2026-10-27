// Experimental, standalone K1 layout geometry. This module does not grant
// ownership, domain, lifetime, dictionary, or publication authority. Callers
// must independently validate semantic types and their identities.
namespace layout;

// Arithmetic helpers return (value, ok); failure never returns a wrapped size.
fn checked_add(a: u32, b: u32) -> u32, bool {
    if b > 4294967295 - a { return 0, false; }
    return a + b, true;
}
fn checked_mul(a: u32, b: u32) -> u32, bool {
    if a != 0 && b > 4294967295 / a { return 0, false; }
    return a * b, true;
}
fn checked_align(value: u32, alignment: u32) -> u32, bool {
    if alignment == 0 || (alignment & (alignment - 1)) != 0 { return 0, false; }
    let rem = value & (alignment - 1);
    if rem == 0 { return value, true; }
    return checked_add(value, alignment - rem);
}

// Postorder table. Kinds: 0 Unit, 1 U32, 2 F32, 3 Bool, 4 Index,
// 5 product, 6 ordinary sum, 7 View, 8 FnMany, 9 affine two-word
// descriptor, 10 Result, 11 existential Nat/Domain package. All child
// references must point strictly backward; cycles and forward references are
// malformed. Product children are in physical field order. Sum/Result children
// are declaration-order payloads. A package has one payload and `witnesses`
// Nat-prefix words; Domain binders do not add words.
//
// Kinds 7/8/9 describe geometry only; this model does not prove the nested
// type well-formed, loans, resource bounds, usage, or lifetime. It intentionally
// lacks function signatures and identities, so cannot validate a K1 artifact.
struct Node { kind: u32, first: u32 = 0, count: u32 = 0, witnesses: u32 = 0 }
struct Shape {
    // 0 success; 1 malformed table; 2 k1_layout_limit; 3 semantic work limit;
    // 4 frozen type-graph node limit.
    status: i64 = 0,
    size: u32 = 0,
    alignment: u32 = 1,
    structural: u32 = 0,
    leaves: u32 = 0,
    guards: u32 = 0,
    depth: u32 = 1,
    plain_shape: bool = false,
    share: bool = false,
    must_handle: bool = false,
    plain_element: bool = false
}

// Saturated counts permit layouts to carry "above Plain budget" without
// overflowing even when a DAG repeats large zero-sized children. Counts are
// conservative occurrence counts, not counts of distinct table identities.
fn count_add(a: u32, b: u32) -> u32 {
    if a >= 65 || b >= 65 || a + b > 65 { return 65; }
    return a + b;
}
fn max_u32(a: u32, b: u32) -> u32 { if a > b { return a; } return b; }
fn failure(status: i64) -> Shape { return Shape { status: status }; }

fn analyze(nodes: Node[:], edges: u32[:], root: u32) -> Shape {
    if nodes.len > 8192 { return failure(4); }
    if nodes.len == 0 || root >= nodes.len { return failure(1); }
    // Every node and edge visit is charged before it is performed. The node
    // bound limits scratch allocation; unused edge entries are not visits.
    var computed: Shape[>..] = [];
    var work: i64 = 0;
    for node, index in nodes {
        work += 1;
        if work > 1048576 { return failure(3); }
        if node.kind > 11 { return failure(1); }
        if node.first > edges.len || node.count > edges.len - node.first { return failure(1); }
        if node.kind <= 4 || node.kind == 7 || node.kind == 8 || node.kind == 9 {
            if node.count != 0 || node.first != 0 || node.witnesses != 0 { return failure(1); }
        } else {
            if node.kind != 11 && node.witnesses != 0 { return failure(1); }
            if node.kind == 6 && (node.count == 0 || node.count > 4) { return failure(2); }
            if node.kind == 10 && node.count != 2 { return failure(1); }
            if node.kind == 11 && (node.count != 1 || node.witnesses > 32) { return failure(1); }
        }
        var shape = Shape {};
        if node.kind == 0 { shape.plain_shape = true; shape.share = true; }
        else if node.kind <= 4 {
            shape.size = 4; shape.alignment = 4;
            shape.leaves = 1; shape.plain_shape = true; shape.share = true;
            if node.kind == 3 || node.kind == 4 { shape.guards = 1; }
        } else if node.kind == 7 || node.kind == 8 || node.kind == 9 {
            shape.size = 8; shape.alignment = 4;
            shape.leaves = 2;
            shape.share = node.kind != 9;
        } else {
            shape.structural = 1;
            shape.plain_shape = node.kind != 10;
            shape.share = node.kind != 10;
            shape.must_handle = node.kind == 10;
            var payload: u32 = 0;
            for i in node.count as i64 {
                work += 1;
                if work > 1048576 { return failure(3); }
                let child_id = edges[node.first + i];
                if child_id >= index { return failure(1); }
                let child = computed[child_id];
                shape.depth = max_u32(shape.depth, child.depth + 1);
                if shape.depth > 64 { return failure(2); }
                shape.structural = count_add(shape.structural, child.structural);
                shape.leaves = count_add(shape.leaves, child.leaves);
                shape.guards = count_add(shape.guards, child.guards);
                shape.plain_shape = shape.plain_shape && child.plain_shape;
                shape.share = shape.share && child.share;
                shape.must_handle = shape.must_handle || child.must_handle;
                if node.kind == 5 {
                    let value, ok = checked_add(payload, child.size);
                    if !ok { return failure(2); }
                    payload = value;
                } else { payload = max_u32(payload, child.size); }
            }
            if node.kind == 6 || node.kind == 10 {
                let value, ok = checked_add(payload, 4);
                if !ok { return failure(2); }
                payload = value;
                shape.leaves = count_add(shape.leaves, 1); // discriminant
                shape.guards = count_add(shape.guards, 1); // valid tag
            }
            if node.kind == 11 {
                let prefix, multiply_ok = checked_mul(node.witnesses, 4);
                if !multiply_ok { return failure(2); }
                let value, ok = checked_add(payload, prefix);
                if !ok { return failure(2); }
                payload = value;
                shape.leaves = count_add(shape.leaves, node.witnesses);
            }
            if payload > 256 { return failure(2); }
            shape.size = payload;
            if payload != 0 { shape.alignment = 4; }
        }
        shape.plain_element = shape.plain_shape && shape.size <= 64 &&
            shape.structural <= 32 && shape.leaves <= 64 && shape.guards <= 32;
        computed.push(shape);
    }
    return computed[root as i64];
}
