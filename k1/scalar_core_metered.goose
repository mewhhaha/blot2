// Private scalar Core construction and structural checking with a shared
// declaration meter. This does not validate source association, full artifact
// ownership, inference sealing, or every K1 work event.
namespace scalar_core_metered;
import scalar_core;
import work;

// status: 0 success, 1 invalid input/Core, 2 semantic limit, 3 Core limit,
// 4 invalid accounting state. A failed construction returns an empty Core.
struct Built { status: u32 = 0, receipt: work::Receipt = work::Receipt {}, core: scalar_core::ScalarCore = scalar_core::ScalarCore {} }
struct Checked { status: u32 = 0, receipt: work::Receipt = work::Receipt {} }
fn status(r: work::Receipt) -> u32 {
    if r.status == 0 { return 0; }
    if r.status == 1 { return 2; }
    if r.status == 3 { return 3; }
    return 4;
}
fn make_impl(result_type: i64, binary_op: i64, left_kind: i64, left_literal: u32,
             right_kind: i64, right_literal: u32, meter: work::Meter&,
             phase: u32, completed: bool) -> Built {
    if (completed && phase != 3) || (!completed && phase != 2 && phase != 5 && phase != 6 && phase != 7) {
        return Built { status: 4 };
    }
    if (left_kind != 0 && left_kind != 1) || (left_kind == 0 && left_literal != 0) ||
       binary_op < 0 || binary_op > 2 { return Built { status: 1 }; }
    if binary_op == 0 {
        if result_type != 1 || right_kind != 0 || right_literal != 0 { return Built { status: 1 }; }
    } else if (right_kind != 0 && right_kind != 1) || (right_kind == 0 && right_literal != 0) ||
              (binary_op == 1 && result_type != 1) || (binary_op == 2 && result_type != 2) {
        return Built { status: 1 };
    }
    // Scratch reconstruction still visits/creates bounded records, but does
    // not increase the count of completed Core operations or blocks.
    let block_event: u32 = if completed { 31 } else { 4 };
    let operation_event: u32 = if completed { 30 } else { 4 };
    var r = work::charge(meter, phase, block_event); // create one Core block
    if r.status != 0 { return Built { status: status(r), receipt: r }; }
    r = work::charge(meter, phase, 4); // create its parameter value
    if r.status != 0 { return Built { status: status(r), receipt: r }; }
    var c = scalar_core::ScalarCore { result_type: result_type, value_count: 1 };
    c.values[0] = scalar_core::ScalarValue { producer: 1, type_id: 1 };
    var left: i64 = 0;
    if left_kind == 1 {
        r = work::charge(meter, phase, operation_event); // constant operation
        if r.status != 0 { return Built { status: status(r), receipt: r }; }
        r = work::charge(meter, phase, 4); // constant result value
        if r.status != 0 { return Built { status: status(r), receipt: r }; }
        left = c.value_count;
        c.values[left] = scalar_core::ScalarValue { producer: 2, type_id: 1, literal: left_literal };
        c.value_count += 1;
    }
    var right: i64 = 0;
    if binary_op != 0 && right_kind == 1 {
        r = work::charge(meter, phase, operation_event);
        if r.status != 0 { return Built { status: status(r), receipt: r }; }
        r = work::charge(meter, phase, 4);
        if r.status != 0 { return Built { status: status(r), receipt: r }; }
        right = c.value_count;
        c.values[right] = scalar_core::ScalarValue { producer: 2, type_id: 1, literal: right_literal };
        c.value_count += 1;
    }
    var output_id = left;
    if binary_op != 0 {
        r = work::charge(meter, phase, operation_event); // binary operation
        if r.status != 0 { return Built { status: status(r), receipt: r }; }
        r = work::charge(meter, phase, 4); // binary result value
        if r.status != 0 { return Built { status: status(r), receipt: r }; }
        r = work::charge(meter, phase, 5); // left operand edge
        if r.status != 0 { return Built { status: status(r), receipt: r }; }
        r = work::charge(meter, phase, 5); // right operand edge
        if r.status != 0 { return Built { status: status(r), receipt: r }; }
        output_id = c.value_count;
        c.values[c.value_count] = scalar_core::ScalarValue { producer: 3, type_id: result_type,
            op_id: binary_op, left_id: left, right_id: right };
        c.value_count += 1;
    }
    r = work::charge(meter, phase, operation_event); // explicit return terminator
    if r.status != 0 { return Built { status: status(r), receipt: r }; }
    r = work::charge(meter, phase, 5); // return value edge
    if r.status != 0 { return Built { status: status(r), receipt: r }; }
    c.result_id = output_id;
    c.terminator = 1;
    return Built { core: c };
}

fn make(result_type: i64, binary_op: i64, left_kind: i64, left_literal: u32,
        right_kind: i64, right_literal: u32, meter: work::Meter&) -> Built {
    return make_impl(result_type, binary_op, left_kind, left_literal, right_kind,
                     right_literal, meter, 3, true);
}
fn make_scratch(result_type: i64, binary_op: i64, left_kind: i64, left_literal: u32,
                right_kind: i64, right_literal: u32, meter: work::Meter&, phase: u32) -> Built {
    return make_impl(result_type, binary_op, left_kind, left_literal, right_kind,
                     right_literal, meter, phase, false);
}

fn empty(v: scalar_core::ScalarValue) -> bool {
    return v.producer == 0 && v.type_id == 0 && v.op_id == 0 && v.literal == 0 &&
           v.left_id == 0 && v.right_id == 0;
}
fn parameter(v: scalar_core::ScalarValue) -> bool {
    return v.producer == 1 && v.type_id == 1 && v.op_id == 0 && v.literal == 0 &&
           v.left_id == 0 && v.right_id == 0;
}
fn constant(v: scalar_core::ScalarValue) -> bool {
    return v.producer == 2 && v.type_id == 1 && v.op_id == 0 && v.left_id == 0 && v.right_id == 0;
}
// This rederives the canonical fixed-size value order without invoking the
// unmetered builder. Absent slots are bounded representation fields, not nodes.
fn validate(c: scalar_core::ScalarCore, meter: work::Meter&, phase: u32) -> Checked {
    if phase < 5 || phase > 7 { return Checked { status: 4 }; }
    var r = work::charge(meter, phase, 4); // Core header
    if r.status != 0 { return Checked { status: status(r), receipt: r }; }
    // Cache header scalars while its charged visit is active. Later traversal
    // follows value edges without silently revisiting the header record.
    let value_count = c.value_count;
    let result_type = c.result_type;
    let name_start = c.name_start; let name_end = c.name_end;
    let parameter_start = c.parameter_start; let parameter_end = c.parameter_end;
    let left_start = c.left_start; let left_end = c.left_end;
    let operator_start = c.operator_start; let operator_end = c.operator_end;
    let right_start = c.right_start; let right_end = c.right_end;
    if value_count < 1 || value_count > 4 ||
       name_start < 0 || name_end <= name_start ||
       parameter_start < 0 || parameter_end <= parameter_start ||
       left_start < 0 || left_end <= left_start { return Checked { status: 1 }; }
    r = work::charge(meter, phase, 4); // explicit return terminator record
    if r.status != 0 { return Checked { status: status(r), receipt: r }; }
    if c.terminator != 1 { return Checked { status: 1 }; }
    for i in value_count..4 { if !empty(c.values[i]) { return Checked { status: 1 }; } }
    r = work::charge(meter, phase, 5); // return value edge
    if r.status != 0 { return Checked { status: status(r), receipt: r }; }
    let result_id = c.result_id;
    if result_id < 0 || result_id >= value_count { return Checked { status: 1 }; }
    r = work::charge(meter, phase, 4); // returned value record
    if r.status != 0 { return Checked { status: status(r), receipt: r }; }
    let result = c.values[result_id];
    if result.producer != 3 {
        if result_type != 1 || operator_start != 0 || operator_end != 0 ||
           right_start != 0 || right_end != 0 { return Checked { status: 1 }; }
        if result.producer == 1 {
            if value_count != 1 || result_id != 0 || !parameter(result) { return Checked { status: 1 }; }
        } else if result.producer == 2 {
            if value_count != 2 || result_id != 1 || !constant(result) { return Checked { status: 1 }; }
            r = work::charge(meter, phase, 4); // block parameter record
            if r.status != 0 { return Checked { status: status(r), receipt: r }; }
            if !parameter(c.values[0]) { return Checked { status: 1 }; }
        } else { return Checked { status: 1 }; }
        return Checked {};
    }
    if result_id != value_count - 1 || result.literal != 0 ||
       (result.op_id != 1 && result.op_id != 2) ||
       (result.op_id == 1 && (result.type_id != 1 || result_type != 1)) ||
       (result.op_id == 2 && (result.type_id != 2 || result_type != 2)) ||
       operator_start < 0 || operator_end <= operator_start ||
       right_start < 0 || right_end <= right_start { return Checked { status: 1 }; }
    r = work::charge(meter, phase, 5); // left edge
    if r.status != 0 { return Checked { status: status(r), receipt: r }; }
    let left_id = result.left_id;
    if left_id < 0 || left_id >= result_id { return Checked { status: 1 }; }
    r = work::charge(meter, phase, 5); // right edge
    if r.status != 0 { return Checked { status: status(r), receipt: r }; }
    let right_id = result.right_id;
    if right_id < 0 || right_id >= result_id { return Checked { status: 1 }; }
    r = work::charge(meter, phase, 4); // canonical parameter record
    if r.status != 0 { return Checked { status: status(r), receipt: r }; }
    if !parameter(c.values[0]) { return Checked { status: 1 }; }
    var next: i64 = 1;
    for id in [left_id, right_id] {
        r = work::charge(meter, phase, 4); // each operand visit, even when repeated
        if r.status != 0 { return Checked { status: status(r), receipt: r }; }
        let value = c.values[id];
        if id == 0 { if !parameter(value) { return Checked { status: 1 }; } }
        else {
            if id != next || !constant(value) { return Checked { status: 1 }; }
            next += 1;
        }
    }
    if next != result_id { return Checked { status: 1 }; }
    return Checked {};
}
