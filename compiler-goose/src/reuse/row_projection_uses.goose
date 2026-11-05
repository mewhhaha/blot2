// Borrow packed rows only through checked scalar projection chains.
namespace blot_reuse_row_projection_uses;
import check.core;
import check.types;
import backend.layout;
import backend.numeric_rows;
import support.option;

enum PositionKind { storage, leaf }
struct Position { kind: PositionKind, index: u8 }
enum OriginKind { binding, expression }
struct Origin { kind: OriginKind, id: u32 }
struct Proof {
    source: const blot_check_core::Module&,
    binding: blot_check_core::BindingId,
    layouts: const blot_backend_layout::Store&,
    row: blot_backend_layout::Id,
    budget: i64 = 4096,
    definition: blot_check_core::Id = 0,
    numeric: const blot_backend_numeric_rows::Plan? = null,
}

fn childAt(plan: const blot_backend_numeric_rows::Plan&, owner: u8, offset: u32) -> blot_support::Option<Position> {
    for storage, index in plan.storage[..plan.storage_count] {
        if !storage.guard_.present && storage.parent.present && storage.parent.value == owner && storage.offset == offset {
            return blot_support::some(Position { kind: PositionKind.storage, index: index as u8 });
        }
    }
    for leaf, index in plan.leaves[..plan.leaf_count] {
        if !leaf.guard_.present && !leaf.discriminant && leaf.owner == owner && leaf.offset == offset {
            return blot_support::some(Position { kind: PositionKind.leaf, index: index as u8 });
        }
    }
    return blot_support::none<Position>();
}
recursive fn numericPosition(source: const blot_check_core::Module&, id: blot_check_core::Id, origin: Origin, layouts: const blot_backend_layout::Store&, plan: const blot_backend_numeric_rows::Plan&, depth: i64) -> blot_support::Option<Position> {
    if id == 0 || depth >= 16 { return blot_support::none<Position>(); }
    if origin.kind == OriginKind.expression && id == origin.id { return blot_support::some(Position { kind: PositionKind.storage, index: 0 }); }
    let node = source.node(id);
    if node.tag == blot_check_core::Tag.reference {
        let reference = source.reference(id);
        if origin.kind == OriginKind.binding && (reference.unit == 0 || reference.unit == source.unit) && reference.binding == origin.id {
            return blot_support::some(Position { kind: PositionKind.storage, index: 0 });
        }
        return blot_support::none<Position>();
    }
    if node.tag != blot_check_core::Tag.project { return blot_support::none<Position>(); }
    let parent = numericPosition(source, node.a, origin, layouts, plan, depth + 1);
    if !parent.present || parent.value.kind != PositionKind.storage { return blot_support::none<Position>(); }
    var owner = parent.value.index;
    var shape = layouts.node(plan.storage[owner].layout);
    let projection = source.projection(node.b);
    let variants = source.projectionVariants(node.b);
    if shape.tag == blot_backend_layout::Tag.nominal {
        var unit = projection.nominal.unit;
        if unit == 0 { unit = source.unit; }
        if projection.nominal.decl != shape.b || unit != shape.a || variants.len != 1 || !plan.storage[owner].tag.present || variants[0].tag != plan.storage[owner].tag.value { return blot_support::none<Position>(); }
        let payload = childAt(plan, owner, 4);
        if !payload.present || payload.value.kind != PositionKind.storage { return blot_support::none<Position>(); }
        owner = payload.value.index;
        shape = layouts.node(plan.storage[owner].layout);
    } else if projection.nominal.decl != 0 { return blot_support::none<Position>(); }
    let ty = plan.storage[owner].layout;
    if shape.tag == blot_backend_layout::Tag.record {
        let fields = layouts.children(ty);
        for index in 0..fields.len / 2 {
            if fields[index * 2] == projection.field { return childAt(plan, owner, (index * 4) as u32); }
        }
        return blot_support::none<Position>();
    }
    if shape.tag != blot_backend_layout::Tag.product || variants.len != 1 || variants[0].field >= layouts.children(ty).len { return blot_support::none<Position>(); }
    return childAt(plan, owner, variants[0].field * 4);
}
fn numericOffset(source: const blot_check_core::Module&, id: blot_check_core::Id, binding: blot_check_core::BindingId, layouts: const blot_backend_layout::Store&, plan: const blot_backend_numeric_rows::Plan&) -> blot_support::Option<u32> {
    let position = numericPosition(source, id, Origin { kind: OriginKind.binding, id: binding }, layouts, plan, 0);
    if !position.present || position.value.kind != PositionKind.leaf { return blot_support::none<u32>(); }
    return blot_support::some(plan.leaves[position.value.index].word as u32 * 4);
}
fn numericExpressionOffset(source: const blot_check_core::Module&, id: blot_check_core::Id, origin: blot_check_core::Id, layouts: const blot_backend_layout::Store&, plan: const blot_backend_numeric_rows::Plan&) -> blot_support::Option<u32> {
    let position = numericPosition(source, id, Origin { kind: OriginKind.expression, id: origin }, layouts, plan, 0);
    if !position.present || position.value.kind != PositionKind.leaf { return blot_support::none<u32>(); }
    return blot_support::some(plan.leaves[position.value.index].word as u32 * 4);
}
fn fieldOffset(source: const blot_check_core::Module&, index: u32, layouts: const blot_backend_layout::Store&, row: blot_backend_layout::Id) -> blot_support::Option<u32> {
    let projection = source.projection(index);
    if projection.nominal.decl != 0 { return blot_support::none<u32>(); }
    let shape = layouts.node(row);
    if shape.tag == blot_backend_layout::Tag.record {
        let fields = layouts.children(row);
        var index: i64 = 0;
        while index < fields.len {
            if fields[index] == projection.field { return blot_support::some((index * 2) as u32); }
            index += 2;
        }
        return blot_support::none<u32>();
    }
    let variants = source.projectionVariants(index);
    if shape.tag != blot_backend_layout::Tag.product || variants.len != 1 || variants[0].field >= layouts.children(row).len { return blot_support::none<u32>(); }
    return blot_support::some(variants[0].field * 4);
}
recursive fn packedPattern(source: const blot_check_core::Module&, id: blot_check_core::PatternId, depth: i64) -> bool {
    if id == 0 { return true; }
    if depth >= 32 { return false; }
    let pattern = source.pattern(id);
    match pattern.tag {
        wildcard => { return true; },
        bind => { return true; },
        constant => { return scalarPattern(source, pattern); },
        value => { return scalarPattern(source, pattern); },
        constructor => { return packedPattern(source, pattern.b, depth + 1); },
        record_payload => {
            if pattern.a != 1 && source.pattern(pattern.b).tag != blot_check_core::PatternTag.wildcard && source.pattern(pattern.b).tag != blot_check_core::PatternTag.product { return false; }
            return packedPattern(source, pattern.b, depth + 1);
        },
        product => { for child in source.patternChildren(id) { if !packedPattern(source, child, depth + 1) { return false; } } return true; },
        invalid => { return false; },
    }
}
fn scalarPattern(source: const blot_check_core::Module&, pattern: blot_check_core::Pattern) -> bool {
    let tag = source.types.node(pattern.ty).tag;
    return tag == blot_check_types::Tag.unit || tag == blot_check_types::Tag.boolean || tag == blot_check_types::Tag.unsigned32 || tag == blot_check_types::Tag.floating32;
}
fn isRow(proof: const Proof&, id: blot_check_core::Id) -> bool {
    if id == 0 || proof.source.node(id).tag != blot_check_core::Tag.reference { return false; }
    let reference = proof.source.reference(id);
    return (reference.unit == 0 || reference.unit == proof.source.unit) && reference.binding == proof.binding;
}
recursive fn pattern(proof: Proof&, id: blot_check_core::PatternId, depth: i64) -> bool {
    if id == 0 { return true; }
    if depth >= 128 || proof.budget == 0 { return false; }
    proof.budget--;
    let value = proof.source.pattern(id);
    match value.tag {
        wildcard => { return true; },
        constant => { return true; },
        bind => { return value.a != proof.binding; },
        value => { return visit(proof, value.a, depth + 1); },
        constructor => { return pattern(proof, value.b, depth + 1); },
        record_payload => { return pattern(proof, value.b, depth + 1); },
        product => { for child in proof.source.patternChildren(id) { if !pattern(proof, child, depth + 1) { return false; } } return true; },
        invalid => { return false; },
    }
}
recursive fn visit(proof: Proof&, id: blot_check_core::Id, depth: i64) -> bool {
    if id == 0 || id == proof.definition { return true; }
    if depth >= 128 || proof.budget == 0 { return false; }
    proof.budget--;
    let node = proof.source.node(id);
    match node.tag {
        constant => { return true; },
        constructor_function => { return true; },
        primitive_function => { return true; },
        type_constructor => { return true; },
        panic => { return true; },
        reference => { return !isRow(proof, id); },
        project => {
            if proof.numeric != null {
                if numericOffset(proof.source, id, proof.binding, proof.layouts, proof.numeric).present { return true; }
                return visit(proof, node.a, depth + 1);
            }
            if isRow(proof, node.a) { return fieldOffset(proof.source, node.b, proof.layouts, proof.row).present; }
            return visit(proof, node.a, depth + 1);
        },
        bind => { return node.a != proof.binding && visit(proof, node.b, depth + 1); },
        construct => { return visit(proof, node.b, depth + 1); },
        return_ => { return visit(proof, node.a, depth + 1); },
        result_associated => { return visit(proof, node.a, depth + 1); },
        scalar => { return pair(proof, node.a, node.b, depth); },
        associated => { return pair(proof, node.a, node.b, depth); },
        logical => { return pair(proof, node.a, node.b, depth); },
        record_merge => { return pair(proof, node.a, node.b, depth); },
        apply => {
            if isRow(proof, node.b) {
                if proof.source.types.node(proof.source.typeOf(node.a)).tag != blot_check_types::Tag.function { return false; }
                return visit(proof, node.a, depth + 1);
            }
            return pair(proof, node.a, node.b, depth);
        },
        if_value => { return branch(proof, id, node, depth); },
        if_stmt => { return branch(proof, id, node, depth); },
        match_ => {
            let inputs = proof.source.matchInputs(id);
            for input in inputs {
                if isRow(proof, input) { if proof.numeric == null { return false; } }
                else if !visit(proof, input, depth + 1) { return false; }
            }
            for arm in proof.source.matchArms(id) {
                for row in proof.source.armRows(arm) {
                    for value, index in proof.source.rowPatterns(row) {
                        if isRow(proof, inputs[index]) && !packedPattern(proof.source, value, 0) { return false; }
                        if !pattern(proof, value, depth + 1) { return false; }
                    }
                }
                if !visit(proof, arm.guard_, depth + 1) || !visit(proof, arm.body, depth + 1) { return false; }
            }
            return true;
        },
        loop_ => {
            let loop_info = proof.source.loopInfo(id);
            for carry in proof.source.loopCarries(id) { if carry.incoming == proof.binding || carry.backedge == proof.binding { return false; } }
            return pattern(proof, loop_info.pattern, depth + 1) && visit(proof, loop_info.first, depth + 1) && visit(proof, loop_info.end, depth + 1) && visit(proof, loop_info.body, depth + 1);
        },
        call => {
            var callable = proof.source.call(id).callee_type;
            for child in proof.source.children(id) {
                let arrow = proof.source.types.node(callable);
                if isRow(proof, child) { if arrow.tag != blot_check_types::Tag.function { return false; } }
                else if !visit(proof, child, depth + 1) { return false; }
                callable = 0;
                if arrow.tag == blot_check_types::Tag.function { callable = arrow.b; }
            }
            return true;
        },
        block_ => { return children(proof, id, depth); },
        suite => { return children(proof, id, depth); },
        product => { return children(proof, id, depth); },
        record => { return children(proof, id, depth); },
        array => { return children(proof, id, depth); },
        array_op => { return children(proof, id, depth); },
        storage => { return children(proof, id, depth); },
        break_ => { return children(proof, id, depth); },
        _ => { return false; },
    }
}
recursive fn pair(proof: Proof&, a: u32, b: u32, depth: i64) -> bool { return visit(proof, a, depth + 1) && visit(proof, b, depth + 1); }
recursive fn children(proof: Proof&, id: u32, depth: i64) -> bool {
    for child in proof.source.children(id) { if !visit(proof, child, depth + 1) { return false; } }
    return true;
}
recursive fn branch(proof: Proof&, id: u32, node: blot_check_core::Node, depth: i64) -> bool {
    for merge in proof.source.branchMerges(id) { if merge.then_binding == proof.binding || merge.else_binding == proof.binding { return false; } }
    return visit(proof, node.a, depth + 1) && visit(proof, node.b, depth + 1) && visit(proof, node.c, depth + 1);
}
fn check(source: const blot_check_core::Module&, root: blot_check_core::Id, binding: blot_check_core::BindingId, layouts: const blot_backend_layout::Store&, row: blot_backend_layout::Id) -> bool {
    var proof = Proof { source: source, binding: binding, layouts: layouts, row: row, .. };
    return visit(proof, root, 0);
}
fn checkNumeric(source: const blot_check_core::Module&, root: blot_check_core::Id, binding: blot_check_core::BindingId, layouts: const blot_backend_layout::Store&, plan: const blot_backend_numeric_rows::Plan&) -> bool {
    var proof = Proof { source: source, binding: binding, layouts: layouts, row: plan.storage[0].layout, numeric: plan, .. };
    return visit(proof, root, 0);
}
fn checkBinding(source: const blot_check_core::Module&, root: blot_check_core::Id, definition: blot_check_core::Id, binding: blot_check_core::BindingId, layouts: const blot_backend_layout::Store&, row: blot_backend_layout::Id) -> bool {
    for carry in source.loop_carries { if carry.incoming == binding || carry.iteration == binding || carry.backedge == binding || carry.outgoing == binding { return false; } }
    for merge in source.merges { if merge.then_binding == binding || merge.else_binding == binding || merge.result == binding { return false; } }
    var proof = Proof { source: source, binding: binding, layouts: layouts, row: row, definition: definition, .. };
    return visit(proof, root, 0);
}
