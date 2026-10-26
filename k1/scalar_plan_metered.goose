// Opt-in private scalar lowering-plan path with declaration-owned metering.
// A source/Core validator must run before planning. These fixed fixture fields
// are not the complete K1 ABI manifest, structural certificate or artifact.
namespace scalar_plan_metered;
import scalar_core;
import scalar_core_metered;
import scalar_plan;
import work;

struct Planned { status: u32 = 0, receipt: work::Receipt = work::Receipt {}, plan: scalar_plan::ScalarLoweringPlan = scalar_plan::ScalarLoweringPlan {} }
struct Checked { status: u32 = 0, receipt: work::Receipt = work::Receipt {} }
// status 0 success, 1 invalid, 2 semantic limit, 3 Core limit, 4 internal.
fn status(r: work::Receipt) -> u32 { return scalar_core_metered::status(r); }

fn make(core: scalar_core::ScalarCore, meter: work::Meter&) -> Planned {
    // Make depends on the entire structural Core, not only its result tag.
    let c = scalar_core_metered::validate(core, meter, 6);
    if c.status != 0 { return Planned { status: c.status, receipt: c.receipt }; }
    var r = work::charge(meter, 6, 4); // revisit the Core root after validation
    if r.status != 0 { return Planned { status: status(r), receipt: r }; }
    r = work::charge(meter, 6, 5); // Core result value edge
    if r.status != 0 { return Planned { status: status(r), receipt: r }; }
    r = work::charge(meter, 6, 4); // result value record
    if r.status != 0 { return Planned { status: status(r), receipt: r }; }
    let value = core.values[core.result_id];
    var opcode: i64 = 0;
    if value.producer == 3 {
        if value.op_id == 1 { opcode = 0x71; }
        else if value.op_id == 2 { opcode = 0x49; }
        else { return Planned { status: 1 }; }
    }
    r = work::charge(meter, 6, 12); // newly constructed plan node
    if r.status != 0 { return Planned { status: status(r), receipt: r }; }
    r = work::charge(meter, 6, 13); // plan owns its copied Core edge
    if r.status != 0 { return Planned { status: status(r), receipt: r }; }
    return Planned { plan: scalar_plan::ScalarLoweringPlan { core: core, schema: 1, edition: 1,
        semantic_policy: 1, optimization_policy: 1, abi: 1,
        parameter_representation: 1, result_representation: 1,
        environment_parameter: 1, source_parameters: 1, opcode: opcode,
        memory_initial_pages: 275, memory_maximum_pages: 275, depth: 1 } };
}

fn validate(plan: scalar_plan::ScalarLoweringPlan, meter: work::Meter&, phase: u32) -> Checked {
    if phase != 6 && phase != 7 { return Checked { status: 4 }; }
    var r = work::charge(meter, phase, 12); // plan record
    if r.status != 0 { return Checked { status: status(r), receipt: r }; }
    if plan.schema != 1 || plan.edition != 1 || plan.semantic_policy != 1 ||
       plan.optimization_policy != 1 || plan.abi != 1 ||
       plan.parameter_representation != 1 || plan.result_representation != 1 ||
       plan.environment_parameter != 1 || plan.source_parameters != 1 ||
       plan.result_slot != 0 || plan.adapter_count != 0 || plan.helper_count != 0 ||
       plan.backing_allocation != 0 || plan.memory_grow != 0 ||
       plan.memory_initial_pages != 275 || plan.memory_maximum_pages != 275 ||
       plan.depth != 1 || plan.frame_bytes != 0 { return Checked { status: 1 }; }
    let opcode = plan.opcode; // cached from the charged plan-header visit
    r = work::charge(meter, phase, 13); // plan -> Core edge
    if r.status != 0 { return Checked { status: status(r), receipt: r }; }
    let owned_core = plan.core;
    let core = scalar_core_metered::validate(owned_core, meter, phase);
    if core.status != 0 { return Checked { status: core.status, receipt: core.receipt }; }
    r = work::charge(meter, phase, 4); // revisit the Core header
    if r.status != 0 { return Checked { status: status(r), receipt: r }; }
    let result_type = owned_core.result_type;
    r = work::charge(meter, phase, 5); // result value edge
    if r.status != 0 { return Checked { status: status(r), receipt: r }; }
    let result_id = owned_core.result_id;
    r = work::charge(meter, phase, 4); // result value record
    if r.status != 0 { return Checked { status: status(r), receipt: r }; }
    let result = owned_core.values[result_id];
    if result.producer == 3 {
        if result.op_id == 1 && opcode == 0x71 && result_type == 1 { return Checked {}; }
        if result.op_id == 2 && opcode == 0x49 && result_type == 2 { return Checked {}; }
        return Checked { status: 1 };
    }
    if opcode != 0 || result_type != 1 { return Checked { status: 1 }; }
    return Checked {};
}
