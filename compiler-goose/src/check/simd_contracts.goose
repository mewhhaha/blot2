// Four-lane product authority is reconstructed from the intrinsic catalog.
namespace blot_check_simd_contracts;
import backend.simd_intrinsics;
import check.core;
import check.types;
import support.error;

fn scalar(types: const blot_check_core::Types&, id: blot_check_types::Id, tag: blot_check_types::Tag) -> bool {
    return id < types.nodes.len && types.node(id).tag == tag;
}
fn product(types: const blot_check_core::Types&, id: blot_check_types::Id, count: u32) -> const blot_check_types::Id[:], bool {
    if id >= types.nodes.len { return types.extra[..0], false; }
    let node = types.node(id);
    if node.tag != blot_check_types::Tag.product || node.b != count || node.a > types.extra.len || count > types.extra.len - node.a {
        return types.extra[..0], false;
    }
    return types.extra[node.a..node.a + count], true;
}
fn vector(types: const blot_check_core::Types&, id: blot_check_types::Id, lane: blot_backend_simd_intrinsics::Lane) -> bool {
    let values, present = product(types, id, 4);
    if !present { return false; }
    var tag = blot_check_types::Tag.floating32;
    if lane == blot_backend_simd_intrinsics::Lane.unsigned { tag = blot_check_types::Tag.unsigned32; }
    for value in values { if !scalar(types, value, tag) { return false; } }
    return true;
}
fn pair(types: const blot_check_core::Types&, id: blot_check_types::Id, lane: blot_backend_simd_intrinsics::Lane) -> bool {
    let values, present = product(types, id, 2);
    if !present { return false; }
    return vector(types, values[0], lane) && vector(types, values[1], lane);
}
fn matches(types: const blot_check_core::Types&, description: blot_backend_simd_intrinsics::Intrinsic,
           inputs: const blot_check_types::Id[:], output: blot_check_types::Id) -> bool {
    if inputs.len != description.arity { return false; }
    let lane = description.lane();
    if description.shape == blot_backend_simd_intrinsics::Shape.reduce {
        return vector(types, inputs[0], lane) && scalar(types, output, blot_check_types::Tag.boolean);
    }
    if !vector(types, output, description.resultLane()) { return false; }
    match description.shape {
        unary, convert => { return vector(types, inputs[0], lane); },
        binary, compare => { return vector(types, inputs[0], lane) && vector(types, inputs[1], lane); },
        shift, broadcast => { return vector(types, inputs[0], lane) && scalar(types, inputs[1], blot_check_types::Tag.unsigned32); },
        select, shuffle => { return vector(types, inputs[0], blot_backend_simd_intrinsics::Lane.unsigned) && pair(types, inputs[1], lane); },
        madd => { return vector(types, inputs[0], lane) && pair(types, inputs[1], lane); },
        swizzle => { return vector(types, inputs[0], blot_backend_simd_intrinsics::Lane.unsigned) && vector(types, inputs[1], lane); },
        reduce => { assert(false); return false; },
    }
}
fn validate(types: const blot_check_core::Types&, operation_: blot_check_core::Op,
            inputs: const blot_check_types::Id[:], output: blot_check_types::Id) -> blot_error::Error {
    for lane in [blot_backend_simd_intrinsics::Lane.unsigned, blot_backend_simd_intrinsics::Lane.floating] {
        let description = blot_backend_simd_intrinsics::operation(operation_, lane);
        if description.present && matches(types, description.value, inputs, output) { return blot_error::Error.none; }
    }
    return blot_error::Error.invalid_artifact;
}
