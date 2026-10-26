import scalar_core;
import scalar_plan;

fn spans(c: scalar_core::ScalarCore, binary: bool) -> scalar_core::ScalarCore {
    var x = c;
    x.name_start = 4; x.name_end = 6;
    x.parameter_start = 24; x.parameter_end = 25;
    x.left_start = 36; x.left_end = 37;
    if binary { x.operator_start = 38; x.operator_end = 39; x.right_start = 40; x.right_end = 41; }
    return x;
}
fn main() {
    let unary = spans(scalar_core::build(1, 0, 0, 0, 0, 0), false);
    let bits = spans(scalar_core::build(1, 1, 1, 4294967295, 0, 0), true);
    let less = spans(scalar_core::build(2, 2, 0, 0, 1, 4294967295), true);
    let p1 = scalar_plan::make(unary);
    let p2 = scalar_plan::make(bits);
    let p3 = scalar_plan::make(less);
    assert(scalar_plan::validate(p1) && p1.opcode == 0);
    assert(scalar_plan::validate(p2) && p2.opcode == 0x71);
    assert(scalar_plan::validate(p3) && p3.opcode == 0x49);
    assert(!scalar_plan::validate(scalar_plan::make(scalar_core::ScalarCore {})));
    var p = p2;
    p.schema = 2; assert(!scalar_plan::validate(p)); p = p2;
    p.edition = 2; assert(!scalar_plan::validate(p)); p = p2;
    p.semantic_policy = 2; assert(!scalar_plan::validate(p)); p = p2;
    p.optimization_policy = 2; assert(!scalar_plan::validate(p)); p = p2;
    p.abi = 2; assert(!scalar_plan::validate(p)); p = p2;
    p.parameter_representation = 2; assert(!scalar_plan::validate(p)); p = p2;
    p.result_representation = 2; assert(!scalar_plan::validate(p)); p = p2;
    p.environment_parameter = 0; assert(!scalar_plan::validate(p)); p = p2;
    p.source_parameters = 2; assert(!scalar_plan::validate(p)); p = p2;
    p.result_slot = 1; assert(!scalar_plan::validate(p)); p = p2;
    p.opcode = 0x49; assert(!scalar_plan::validate(p)); p = p2;
    p.adapter_count = 1; assert(!scalar_plan::validate(p)); p = p2;
    p.helper_count = 1; assert(!scalar_plan::validate(p)); p = p2;
    p.backing_allocation = 1; assert(!scalar_plan::validate(p)); p = p2;
    p.memory_grow = 1; assert(!scalar_plan::validate(p)); p = p2;
    p.memory_initial_pages = 274; assert(!scalar_plan::validate(p)); p = p2;
    p.memory_maximum_pages = 276; assert(!scalar_plan::validate(p)); p = p2;
    p.depth = 2; assert(!scalar_plan::validate(p)); p = p2;
    p.frame_bytes = 1; assert(!scalar_plan::validate(p)); p = p2;
    p.core.values[2].right_id = 2; assert(!scalar_plan::validate(p)); p = p2;
    p.core.values[2].op_id = 2; assert(!scalar_plan::validate(p)); p = p2;
    p.core.result_type = 2; assert(!scalar_plan::validate(p)); p = p1;
    p.opcode = 0x71; assert(!scalar_plan::validate(p)); p = p3;
    p.opcode = 0x71; assert(!scalar_plan::validate(p));
    print("scalar lowering plan: passed");
}
