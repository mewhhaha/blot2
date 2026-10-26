// Independent x + 0 source/Core check using a caller-owned declaration meter.
// This is only one required check: candidate construction, owned syntax, plan,
// emitter and artifact checks are not yet all metered and cannot claim a full
// K1 policy receipt or public source admission.
namespace add_source_metered;
import scalar_core;
import validate;
import catalog;
import work;

// 0 valid, 1 invalid, 3 semantic limit, 4 internal accounting error.
fn validate_source(source: u8[:], core: scalar_core::ScalarCore, meter: work::Meter&) -> i64 {
    if source.len > 16777216 { return 1; }
    // This check reads the candidate header and the operator value record.
    let header = work::charge(meter, 5, 4);
    if header.status != 0 { return if header.status == 1 { 3 } else { 4 }; }
    if core.operator_start < 0 || core.operator_start >= source.len ||
       core.operator_end != core.operator_start + 1 || source[core.operator_start] != '+' ||
       core.value_count != 3 || core.result_id != 2 { return 1; }
    let operation = work::charge(meter, 5, 4);
    if operation.status != 0 { return if operation.status == 1 { 3 } else { 4 }; }
    if core.values[2].op_id != 3 { return 1; }
    // Same-length source projection preserves byte offsets; it is compiler
    // scratch, not an executable artifact or a replacement for source identity.
    var projected: u8[>..] = [];
    projected.append(source);
    projected[core.operator_start] = '&';
    var projected_core = core;
    projected_core.values[2].op_id = 1;
    let checked = validate::scalar_v2_with_work(projected, projected_core, catalog::edition(),
        catalog::semantic_policy(), catalog::optimization_policy(), catalog::wasm_abi(), meter);
    if checked != 0 { return if checked == 3 { 3 } else if checked == 4 { 4 } else { 1 }; }
    let first = work::charge(meter, 5, 4);
    if first.status != 0 { return if first.status == 1 { 3 } else { 4 }; }
    if core.values[0].producer != 1 { return 1; }
    let second = work::charge(meter, 5, 4);
    if second.status != 0 { return if second.status == 1 { 3 } else { 4 }; }
    if core.values[1].producer != 2 || core.values[1].literal != 0 { return 1; }
    let result = work::charge(meter, 5, 4);
    if result.status != 0 { return if result.status == 1 { 3 } else { 4 }; }
    let left = work::charge(meter, 5, 5);
    if left.status != 0 { return if left.status == 1 { 3 } else { 4 }; }
    if core.values[2].left_id != 0 { return 1; }
    let right = work::charge(meter, 5, 5);
    if right.status != 0 { return if right.status == 1 { 3 } else { 4 }; }
    if core.values[2].right_id != 1 { return 1; }
    return 0;
}
