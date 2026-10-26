import add_core;
import add_proof;
import scalar_core;
import scalar_plan;

fn core() -> scalar_core::ScalarCore {
    var c = scalar_core::ScalarCore { result_type: 1, value_count: 3, terminator: 1, result_id: 2,
        name_start: 4, name_end: 5, parameter_start: 23, parameter_end: 24,
        left_start: 35, left_end: 36, operator_start: 37, operator_end: 38,
        right_start: 39, right_end: 40 };
    c.values[0] = scalar_core::ScalarValue { producer: 1, type_id: 1 };
    c.values[1] = scalar_core::ScalarValue { producer: 2, type_id: 1 };
    c.values[2] = scalar_core::ScalarValue { producer: 3, type_id: 1, op_id: 3, left_id: 0, right_id: 1 };
    return c;
}
fn main() {
    let source = "let f: U32 -> U32 = fn x => return x + 0";
    let typed = core();
    var work = add_proof::Work {};
    let built = add_proof::build(add_core::subject(), work);
    assert(built.status == 0);
    let checked = add_core::make_core(typed, built.proof);
    assert(add_core::validate_core(source, checked, work) == 0);
    let plan = add_core::make_plan(checked);
    let before = work.proof_visits;
    assert(add_core::validate_plan(source, plan, work) == 0 && work.proof_visits == before + 10);
    assert(!scalar_core::validate_structure(typed));
    assert(!scalar_plan::validate(scalar_plan::make(typed)));
    var fresh = add_proof::Work {};
    assert(add_core::validate_core(source, checked, fresh) == 1);
    assert(add_core::validate_core("let f: U32 -> U32 = fn x => return x + 1", checked, work) == 1);
    assert(add_core::validate_core("let f: U32 -> U32 = fn y => return x + 0", checked, work) == 1);
    assert(add_core::validate_core("let f: U32 -> U32 = fn x => return x + 0 + 0", checked, work) == 1);
    var x = checked;
    x.schema = 3; assert(add_core::validate_core(source, x, work) == 1); x = checked;
    x.owner = 2; assert(add_core::validate_core(source, x, work) == 1); x = checked;
    x.scope = 2; assert(add_core::validate_core(source, x, work) == 1); x = checked;
    x.core.result_type = 2; assert(add_core::validate_core(source, x, work) == 1); x = checked;
    x.core.value_count = 4; assert(add_core::validate_core(source, x, work) == 1); x = checked;
    x.core.terminator = 2; assert(add_core::validate_core(source, x, work) == 1); x = checked;
    x.core.result_id = 1; assert(add_core::validate_core(source, x, work) == 1); x = checked;
    x.core.values[0].producer = 2; assert(add_core::validate_core(source, x, work) == 1); x = checked;
    x.core.values[1].literal = 1; assert(add_core::validate_core(source, x, work) == 1); x = checked;
    x.core.values[2].op_id = 1; assert(add_core::validate_core(source, x, work) == 1); x = checked;
    x.core.values[2].left_id = 1; assert(add_core::validate_core(source, x, work) == 1); x = checked;
    x.core.values[2].right_id = 0; assert(add_core::validate_core(source, x, work) == 1); x = checked;
    x.core.values[3].literal = 1; assert(add_core::validate_core(source, x, work) == 1); x = checked;
    x.core.operator_start = -1; assert(add_core::validate_core(source, x, work) == 1); x = checked;
    x.core.right_end = 999; assert(add_core::validate_core(source, x, work) == 1); x = checked;
    x.evidence.subject.result_version = 4; assert(add_core::validate_core(source, x, work) == 1); x = checked;
    x.evidence.nodes[2].prior1 = 3; assert(add_core::validate_core(source, x, work) == 1); x = checked;
    x.evidence.terms[1].literal = 1; assert(add_core::validate_core(source, x, work) == 1);

    var p = plan;
    p.schema = 3; assert(add_core::validate_plan(source, p, work) == 1); p = plan;
    p.edition = 2; assert(add_core::validate_plan(source, p, work) == 1); p = plan;
    p.semantic_policy = 2; assert(add_core::validate_plan(source, p, work) == 1); p = plan;
    p.optimization_policy = 2; assert(add_core::validate_plan(source, p, work) == 1); p = plan;
    p.abi = 2; assert(add_core::validate_plan(source, p, work) == 1); p = plan;
    p.parameter_representation = 2; assert(add_core::validate_plan(source, p, work) == 1); p = plan;
    p.result_representation = 2; assert(add_core::validate_plan(source, p, work) == 1); p = plan;
    p.environment_parameter = 0; assert(add_core::validate_plan(source, p, work) == 1); p = plan;
    p.source_parameters = 2; assert(add_core::validate_plan(source, p, work) == 1); p = plan;
    p.result_slot = 1; assert(add_core::validate_plan(source, p, work) == 1); p = plan;
    p.opcode = 0x71; assert(add_core::validate_plan(source, p, work) == 1); p = plan;
    p.adapter_count = 1; assert(add_core::validate_plan(source, p, work) == 1); p = plan;
    p.helper_count = 1; assert(add_core::validate_plan(source, p, work) == 1); p = plan;
    p.backing_allocation = 1; assert(add_core::validate_plan(source, p, work) == 1); p = plan;
    p.memory_grow = 1; assert(add_core::validate_plan(source, p, work) == 1); p = plan;
    p.memory_initial_pages = 274; assert(add_core::validate_plan(source, p, work) == 1); p = plan;
    p.memory_maximum_pages = 276; assert(add_core::validate_plan(source, p, work) == 1); p = plan;
    p.depth = 2; assert(add_core::validate_plan(source, p, work) == 1); p = plan;
    p.frame_bytes = 1; assert(add_core::validate_plan(source, p, work) == 1); p = plan;
    p.checked.evidence.nodes[2].operation_version = 0; assert(add_core::validate_plan(source, p, work) == 1);
    var proof_limit = add_proof::Work { terms: 4, edges: 5, proof_visits: 65536 };
    assert(add_core::validate_plan(source, plan, proof_limit) == 2 && proof_limit.limit_quantity == 3);
    var semantic_limit = add_proof::Work { terms: 4, edges: 5, semantic_visits: 1048576 };
    assert(add_core::validate_plan(source, plan, semantic_limit) == 3 && semantic_limit.limit_quantity == 4);
    print("checked addition Core and plan: passed");
}
