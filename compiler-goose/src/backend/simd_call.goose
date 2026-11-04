namespace blot_backend_simd_call;
import check.core;
import .known_call;
import .simd_intrinsics;
import support.option;

struct Plan {
    target: blot_check_core::BindingRef, op: blot_check_core::Op, count: i64,
    arguments: blot_check_core::Id[3], lanes: blot_support::Option<i64>, vectors: i64[3] = [0, 0, 0], vector_count: i64 = 0, pair_parameter: bool = false,
}
fn analyze(units: const blot_check_core::Module[:], owner: u32, id: blot_check_core::Id) -> blot_support::Option<Plan> {
    let call = blot_backend_known_call::resolve(units, owner, id); if !call.present || call.value.count < 2 || call.value.count > 3 { return blot_support::none<Plan>(); }
    let found = blot_backend_known_call::wrapper(units, owner, call.value); if !found.present { return blot_support::none<Plan>(); }
    let source = units[found.value.target.unit - 1]; let root = source.node(found.value.body.root);
    if root.tag != blot_check_core::Tag.scalar || root.c != 0 || !(blot_backend_simd_intrinsics::literalLanes(root.op) || blot_backend_simd_intrinsics::pairs(root.op)) || root.b == 0 { return blot_support::none<Plan>(); }
    let parameters = source.bodyParameters(found.value.body); var used: u8 = 0;
    var plan = Plan { target: found.value.target, op: root.op, count: call.value.count, arguments: [call.value.arguments[0], call.value.arguments[1], call.value.arguments[2]] };
    var first_operand = root.a; var vector_operand = root.b;
    if root.op == blot_check_core::Op.broadcast { first_operand = root.b; vector_operand = root.a; }
    let first = blot_backend_known_call::parameterPosition(source, found.value.target.unit, parameters, first_operand, used); if !first.present { return blot_support::none<Plan>(); }
    if blot_backend_simd_intrinsics::literalLanes(root.op) { plan.lanes = first; } else { plan.vectors[0] = first.value; plan.vector_count = 1; }
    if blot_backend_simd_intrinsics::pairs(root.op) && source.node(vector_operand).tag == blot_check_core::Tag.product {
        let children = source.children(vector_operand); if children.len != 2 { return blot_support::none<Plan>(); }
        for child in children { let position = blot_backend_known_call::parameterPosition(source, found.value.target.unit, parameters, child, used); if !position.present { return blot_support::none<Plan>(); } plan.vectors[plan.vector_count] = position.value; plan.vector_count++; }
    } else {
        let position = blot_backend_known_call::parameterPosition(source, found.value.target.unit, parameters, vector_operand, used); if !position.present { return blot_support::none<Plan>(); }
        plan.vectors[plan.vector_count] = position.value; plan.vector_count++; plan.pair_parameter = blot_backend_simd_intrinsics::pairs(root.op);
    }
    if used != (1 as u8 << call.value.count) - 1 { return blot_support::none<Plan>(); }
    return blot_support::some(plan);
}
