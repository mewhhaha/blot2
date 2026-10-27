// Transient, owned scalar fixture data. No source references, inference state,
// serialization or completed K1 artifact authority is carried by these values.
namespace scalar_core;

struct ScalarValue {
    producer: i64 = 0,
    type_id: i64 = 0,
    op_id: i64 = 0,
    literal: u32 = 0,
    left_id: i64 = 0,
    right_id: i64 = 0
}
struct ScalarCore {
    result_type: i64 = 0,
    value_count: i64 = 0,
    values: ScalarValue[4] = [ScalarValue {}; 4],
    terminator: i64 = 0,
    result_id: i64 = 0,
    name_start: i64 = 0, name_end: i64 = 0,
    parameter_start: i64 = 0, parameter_end: i64 = 0,
    left_start: i64 = 0, left_end: i64 = 0,
    operator_start: i64 = 0, operator_end: i64 = 0,
    right_start: i64 = 0, right_end: i64 = 0
}

// Constructs values only. Caller attaches the copied spans; source association
// is independently checked before emission. Invalid tags yield an empty Core.
fn build(result_type: i64, binary_op: i64, left_kind: i64, left_literal: u32,
         right_kind: i64, right_literal: u32) -> ScalarCore {
    if (left_kind != 0 && left_kind != 1) || (left_kind == 0 && left_literal != 0) ||
       binary_op < 0 || binary_op > 2 { return ScalarCore {}; }
    if binary_op == 0 {
        if result_type != 1 || right_kind != 0 || right_literal != 0 { return ScalarCore {}; }
    } else {
        if (right_kind != 0 && right_kind != 1) || (right_kind == 0 && right_literal != 0) ||
           (binary_op == 1 && result_type != 1) || (binary_op == 2 && result_type != 2) {
            return ScalarCore {};
        }
    }
    var core = ScalarCore {};
    core.result_type = result_type;
    core.value_count = 1;
    core.values[0] = ScalarValue { producer: 1, type_id: 1 };
    var left: i64 = 0;
    if left_kind == 1 {
        left = core.value_count;
        core.values[left] = ScalarValue { producer: 2, type_id: 1, literal: left_literal };
        core.value_count += 1;
    }
    var right: i64 = 0;
    if binary_op != 0 && right_kind == 1 {
        right = core.value_count;
        core.values[right] = ScalarValue { producer: 2, type_id: 1, literal: right_literal };
        core.value_count += 1;
    }
    if binary_op == 0 {
        core.result_id = left;
    } else {
        core.result_id = core.value_count;
        core.values[core.value_count] = ScalarValue { producer: 3, type_id: result_type,
            op_id: binary_op, left_id: left, right_id: right };
        core.value_count += 1;
    }
    core.terminator = 1;
    return core;
}

fn same_value(a: ScalarValue, b: ScalarValue) -> bool {
    return a.producer == b.producer && a.type_id == b.type_id && a.op_id == b.op_id &&
        a.literal == b.literal && a.left_id == b.left_id && a.right_id == b.right_id;
}

// Checks the closed structural language, but does not validate source identity,
// token spelling, lexical scope or binding. Those require separate recognition.
fn validate_structure(c: ScalarCore) -> bool {
    if c.value_count < 1 || c.value_count > 4 || c.terminator != 1 ||
       c.result_id < 0 || c.result_id >= c.value_count ||
       c.name_start < 0 || c.name_end <= c.name_start ||
       c.parameter_start < 0 || c.parameter_end <= c.parameter_start ||
       c.left_start < 0 || c.left_end <= c.left_start { return false; }
    let result = c.values[c.result_id];
    var operation: i64 = 0;
    var left_id = c.result_id;
    var right_id: i64 = 0;
    if result.producer == 3 {
        operation = result.op_id;
        if c.result_id != c.value_count - 1 || (operation != 1 && operation != 2) ||
           result.left_id < 0 || result.left_id >= c.result_id ||
           result.right_id < 0 || result.right_id >= c.result_id ||
           c.operator_start < 0 || c.operator_end <= c.operator_start ||
           c.right_start < 0 || c.right_end <= c.right_start { return false; }
        left_id = result.left_id;
        right_id = result.right_id;
    } else {
        if c.operator_start != 0 || c.operator_end != 0 || c.right_start != 0 || c.right_end != 0 {
            return false;
        }
    }
    let left = c.values[left_id];
    if left.producer != 1 && left.producer != 2 { return false; }
    var left_kind: i64 = 0;
    if left.producer == 2 { left_kind = 1; }
    var right_kind: i64 = 0;
    var right_literal: u32 = 0;
    if operation != 0 {
        let right = c.values[right_id];
        if right.producer != 1 && right.producer != 2 { return false; }
        if right.producer == 2 { right_kind = 1; right_literal = right.literal; }
    }
    let expected = build(c.result_type, operation, left_kind, left.literal, right_kind, right_literal);
    if expected.value_count != c.value_count || expected.result_id != c.result_id ||
       expected.terminator != c.terminator { return false; }
    for i in 4 {
        if !same_value(c.values[i], expected.values[i]) { return false; }
    }
    return true;
}
