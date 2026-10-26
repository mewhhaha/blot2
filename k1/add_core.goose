// Transient checked-add fixture structures. They are not portable artifacts,
// stable declaration identities, a qualified optimizer or K1 public admission.
// Source recognizer, Core shape and proof are checked independently each time.
namespace add_core;
import scalar_core;
import add_proof;
import add_source;

struct AddCoreV4 {
    schema: u32 = 0,
    owner: u32 = 0,
    scope: u32 = 0,
    core: scalar_core::ScalarCore = scalar_core::ScalarCore {},
    evidence: add_proof::Proof = add_proof::Proof {}
}
struct AddPlanV4 {
    checked: AddCoreV4 = AddCoreV4 {},
    schema: u32 = 0,
    edition: u32 = 0,
    semantic_policy: u32 = 0,
    optimization_policy: u32 = 0,
    abi: u32 = 0,
    parameter_representation: u32 = 0, // i32 = 1
    result_representation: u32 = 0,    // i32 = 1
    environment_parameter: u32 = 0,    // present = 1
    source_parameters: u32 = 0,
    result_slot: u32 = 0,
    opcode: u32 = 0,
    adapter_count: u32 = 0,
    helper_count: u32 = 0,
    backing_allocation: u32 = 0,
    memory_grow: u32 = 0,
    memory_initial_pages: u32 = 0,
    memory_maximum_pages: u32 = 0,
    depth: u32 = 0,
    frame_bytes: u32 = 0
}

// Constructors only copy data; they do not assert admission, provenance, or
// manufacture a proof. The proof must come from this compilation's Work.
fn make_core(core: scalar_core::ScalarCore, evidence: add_proof::Proof) -> AddCoreV4 {
    return AddCoreV4 { schema: 4, owner: 1, scope: 1, core: core, evidence: evidence };
}
fn make_plan(checked: AddCoreV4) -> AddPlanV4 {
    return AddPlanV4 { checked: checked, schema: 4, edition: 1, semantic_policy: 1,
        optimization_policy: 1, abi: 1, parameter_representation: 1,
        result_representation: 1, environment_parameter: 1, source_parameters: 1,
        opcode: 0x6a, memory_initial_pages: 275, memory_maximum_pages: 275, depth: 1 };
}

fn same(a: scalar_core::ScalarValue, b: scalar_core::ScalarValue) -> bool {
    return a.producer == b.producer && a.type_id == b.type_id && a.op_id == b.op_id &&
        a.literal == b.literal && a.left_id == b.left_id && a.right_id == b.right_id;
}

// Fixed version mapping is valid only for this single immutable three-value
// fixture. The expected subject is constructed here, not read from the proof.
fn subject() -> add_proof::Subject {
    return add_proof::Subject { owner: 1, scope: 1, parameter: 0, parameter_version: 1,
        zero: 1, zero_version: 2, result: 2, result_version: 3,
        zero_literal: 0, operation: 1 };
}

// 0 valid, 1 malformed/source mismatch, 2 proof work limit, 3 semantic work
// limit. Only compiler-owned Work charged by this compilation may be passed;
// counter values are not a portable receipt or evidence of provenance.
fn validate_core(source: u8[:], candidate: AddCoreV4, work: add_proof::Work&) -> i64 {
    if candidate.schema != 4 || candidate.owner != 1 || candidate.scope != 1 { return 1; }
    let c = candidate.core;
    if c.result_type != 1 || c.value_count != 3 || c.terminator != 1 || c.result_id != 2 ||
       !same(c.values[0], scalar_core::ScalarValue { producer: 1, type_id: 1 }) ||
       !same(c.values[1], scalar_core::ScalarValue { producer: 2, type_id: 1 }) ||
       !same(c.values[2], scalar_core::ScalarValue { producer: 3, type_id: 1, op_id: 3,
              left_id: 0, right_id: 1 }) ||
       !same(c.values[3], scalar_core::ScalarValue {}) { return 1; }
    if add_source::validate(source, c) != 0 { return 1; }
    let checked = add_proof::validate(candidate.evidence, subject(), work);
    return checked.status;
}

// Revalidates source, exact Core, and proof after all plan fields. No stored
// validated flag or semantic hash authorizes code generation.
fn validate_plan(source: u8[:], plan: AddPlanV4, work: add_proof::Work&) -> i64 {
    if plan.schema != 4 || plan.edition != 1 || plan.semantic_policy != 1 ||
       plan.optimization_policy != 1 || plan.abi != 1 ||
       plan.parameter_representation != 1 || plan.result_representation != 1 ||
       plan.environment_parameter != 1 || plan.source_parameters != 1 ||
       plan.result_slot != 0 || plan.opcode != 0x6a || plan.adapter_count != 0 ||
       plan.helper_count != 0 || plan.backing_allocation != 0 || plan.memory_grow != 0 ||
       plan.memory_initial_pages != 275 || plan.memory_maximum_pages != 275 ||
       plan.depth != 1 || plan.frame_bytes != 0 { return 1; }
    return validate_core(source, plan.checked, work);
}
