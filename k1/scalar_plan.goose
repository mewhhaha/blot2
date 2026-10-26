// Private v2 scalar lowering plan. Owns its complete fixed-width Core by value.
// It is not a serialized artifact, stable ABI digest, K1 certificate, or host
// bridge. Source correspondence must be checked independently before planning.
import scalar_core;
namespace scalar_plan;

struct ScalarLoweringPlan {
    core: scalar_core::ScalarCore = scalar_core::ScalarCore {},
    schema: i64 = 0,
    edition: i64 = 0,
    semantic_policy: i64 = 0,
    optimization_policy: i64 = 0,
    abi: i64 = 0,
    parameter_representation: i64 = 0, // 1 i32
    result_representation: i64 = 0,    // 1 i32 (U32 bits or canonical Bool)
    environment_parameter: i64 = 0,    // 1 environment i32 is first
    source_parameters: i64 = 0,        // 1 source U32 parameter
    result_slot: i64 = 0,              // absent
    opcode: i64 = 0,                   // 0 unary, 0x71 and, 0x49 lt_u
    adapter_count: i64 = 0,
    helper_count: i64 = 0,
    backing_allocation: i64 = 0,
    memory_grow: i64 = 0,
    memory_initial_pages: i64 = 0,
    memory_maximum_pages: i64 = 0,
    depth: i64 = 0,
    frame_bytes: i64 = 0
}

// This constructor is not an admission judgment: source correspondence must
// already have been established by validate::scalar_v2. Bad structure yields a
// non-admissible zero-tag plan, never an implicitly repaired record.
fn make(core: scalar_core::ScalarCore) -> ScalarLoweringPlan {
    if !scalar_core::validate_structure(core) { return ScalarLoweringPlan {}; }
    let result = core.values[core.result_id];
    var opcode: i64 = 0;
    if result.producer == 3 {
        if result.op_id == 1 { opcode = 0x71; }
        else if result.op_id == 2 { opcode = 0x49; }
        else { return ScalarLoweringPlan {}; }
    }
    return ScalarLoweringPlan { core: core, schema: 1, edition: 1,
        semantic_policy: 1, optimization_policy: 1, abi: 1,
        parameter_representation: 1, result_representation: 1,
        environment_parameter: 1, source_parameters: 1, opcode: opcode,
        memory_initial_pages: 275, memory_maximum_pages: 275, depth: 1 };
}

// Checks every represented plan field and revalidates the copied Core rather
// than trusting a completion flag. This is structural validation only; it does
// not establish a binding to source or authenticate executable bytes.
fn validate(plan: ScalarLoweringPlan) -> bool {
    if plan.schema != 1 || plan.edition != 1 || plan.semantic_policy != 1 ||
       plan.optimization_policy != 1 || plan.abi != 1 ||
       plan.parameter_representation != 1 || plan.result_representation != 1 ||
       plan.environment_parameter != 1 || plan.source_parameters != 1 ||
       plan.result_slot != 0 || plan.adapter_count != 0 || plan.helper_count != 0 ||
       plan.backing_allocation != 0 || plan.memory_grow != 0 ||
       plan.memory_initial_pages != 275 || plan.memory_maximum_pages != 275 ||
       plan.depth != 1 || plan.frame_bytes != 0 ||
       !scalar_core::validate_structure(plan.core) { return false; }
    let result = plan.core.values[plan.core.result_id];
    if result.producer == 3 {
        if result.op_id == 1 { return plan.opcode == 0x71 && plan.core.result_type == 1; }
        if result.op_id == 2 { return plan.opcode == 0x49 && plan.core.result_type == 2; }
        return false;
    }
    return plan.opcode == 0 && plan.core.result_type == 1;
}
