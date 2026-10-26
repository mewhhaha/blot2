// Owned, transient v3 scalar-module model. Structural validation is not source
// grammar/completion, portable artifact authentication, or K1 admission.
namespace module_core;

struct Value {
    producer: i64 = 0, type_id: i64 = 0, op_id: i64 = 0,
    literal: u32 = 0, left_id: i64 = 0, right_id: i64 = 0, callee_id: i64 = 0
}
struct Function {
    declaration_start: i64 = 0, declaration_end: i64 = 0,
    name_start: i64 = 0, name_end: i64 = 0,
    function_start: i64 = 0,
    parameter_start: i64 = 0, parameter_end: i64 = 0,
    return_start: i64 = 0,
    expression_start: i64 = 0, expression_end: i64 = 0,
    left_start: i64 = 0, left_end: i64 = 0,
    operator_start: i64 = 0, operator_end: i64 = 0,
    right_start: i64 = 0, right_end: i64 = 0,
    callee_start: i64 = 0, callee_end: i64 = 0,
    depth: i64 = 0, frame: i64 = 0,
    result_type: i64 = 0, value_count: i64 = 0,
    values: Value[4] = [Value {}; 4],
    terminator: i64 = 0, result_id: i64 = 0
}
struct ModuleCore { source: u8[] = [], functions: Function[] = [] }

fn same(a: Value, b: Value) -> bool {
    return a.producer == b.producer && a.type_id == b.type_id && a.op_id == b.op_id &&
        a.literal == b.literal && a.left_id == b.left_id && a.right_id == b.right_id &&
        a.callee_id == b.callee_id;
}
fn span(start: i64, end: i64, length: i64) -> bool {
    return start >= 0 && end > start && end <= length;
}
fn letter(c: u8) -> bool {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_';
}
fn name_ok(source: u8[:], start: i64, end: i64) -> bool {
    if !span(start, end, source.len) || !letter(source[start]) { return false; }
    for i in start + 1..end {
        let c = source[i];
        if !letter(c) && !(c >= '0' && c <= '9') { return false; }
    }
    return true;
}

// Independently sort checked names with a bounded heap. The byte comparator
// is authoritative and does not consult any producer-owned name index.
// compare_names and sift_names are internal unchecked helpers: call them only
// from unique_names after it has checked the count and every name span.
fn compare_names(m: ModuleCore&, a: i64, b: i64) -> i64 {
    let left = m.functions[a];
    let right = m.functions[b];
    var i = left.name_start;
    var j = right.name_start;
    while i < left.name_end && j < right.name_end {
        if m.source[i] < m.source[j] { return -1; }
        if m.source[i] > m.source[j] { return 1; }
        i += 1; j += 1;
    }
    if i == left.name_end && j == right.name_end { return 0; }
    return if i == left.name_end { -1 } else { 1 };
}
fn sift_names(m: ModuleCore&, names: i64[256]&, root: i64, end: i64) {
    var at = root;
    loop {
        let left = at * 2 + 1;
        if left >= end { break; }
        var greatest = left;
        let right = left + 1;
        if right < end && compare_names(m, names[right], names[left]) > 0 { greatest = right; }
        if compare_names(m, names[at], names[greatest]) >= 0 { break; }
        let saved = names[at]; names[at] = names[greatest]; names[greatest] = saved;
        at = greatest;
    }
}
fn unique_names(m: ModuleCore&) -> bool {
    let count = m.functions.len;
    if count < 1 || count > 256 { return false; }
    var names: i64[256] = [0; 256];
    for i in count {
        let f = m.functions[i];
        if !span(f.name_start, f.name_end, m.source.len) { return false; }
        names[i] = i;
    }
    var root = count / 2;
    while root > 0 { root -= 1; sift_names(m, names, root, count); }
    var end = count;
    while end > 1 {
        end -= 1;
        let saved = names[0]; names[0] = names[end]; names[end] = saved;
        sift_names(m, names, 0, end);
    }
    for i in 1..count {
        if compare_names(m, names[i - 1], names[i]) == 0 { return false; }
    }
    return true;
}

// Return 0 valid, 1 malformed, 8 recursive graph, 9 depth exceeds 128.
// The caller must independently re-recognize source/lexical targets and bind
// the Core to it before using this model for any semantic decision.
fn validate(m: ModuleCore&) -> i64 {
    if m.source.len > 16777216 || m.functions.len < 1 || m.functions.len > 256 { return 1; }
    var previous_end: i64 = 0;
    for f in m.functions {
        if !span(f.declaration_start, f.declaration_end, m.source.len) ||
           f.declaration_start < previous_end ||
           !name_ok(m.source, f.name_start, f.name_end) ||
           !name_ok(m.source, f.parameter_start, f.parameter_end) ||
           f.name_start < f.declaration_start || f.name_end > f.function_start ||
           f.function_start < 0 || f.function_start >= f.parameter_start ||
           f.parameter_end > f.return_start || f.return_start < 0 ||
           f.return_start >= f.expression_start ||
           !span(f.expression_start, f.expression_end, m.source.len) ||
           f.expression_end > f.declaration_end ||
           !span(f.left_start, f.left_end, m.source.len) ||
           f.left_start < f.expression_start || f.left_end > f.expression_end ||
           f.frame != 0 || f.result_type != 1 || f.value_count < 1 || f.value_count > 4 ||
           f.terminator != 1 || f.result_id < 0 || f.result_id >= f.value_count { return 1; }
        previous_end = f.declaration_end;
        // Derive a fresh canonical sequence from the result and its typed
        // operands; comparing all slots also rejects unused forged records.
        let result = f.values[f.result_id];
        var left_id = f.result_id;
        var right_id: i64 = 0;
        var kind: i64 = 1;
        if result.producer == 3 || result.producer == 4 {
            if f.result_id != f.value_count - 1 || result.left_id < 0 || result.left_id >= f.result_id { return 1; }
            left_id = result.left_id;
            kind = result.producer;
            if kind == 3 {
                if result.right_id < 0 || result.right_id >= f.result_id ||
                   !span(f.operator_start, f.operator_end, m.source.len) ||
                   !span(f.right_start, f.right_end, m.source.len) ||
                   f.left_start != f.expression_start || f.left_end > f.operator_start ||
                   f.operator_end > f.right_start || f.right_end != f.expression_end ||
                   f.callee_start != 0 || f.callee_end != 0 { return 1; }
                right_id = result.right_id;
            } else {
                if result.callee_id < 0 || result.callee_id >= m.functions.len ||
                   f.operator_start != 0 || f.operator_end != 0 || f.right_start != 0 || f.right_end != 0 ||
                   !name_ok(m.source, f.callee_start, f.callee_end) ||
                   f.callee_start != f.expression_start || f.callee_end > f.left_start { return 1; }
            }
        } else {
            if f.left_start != f.expression_start || f.left_end != f.expression_end ||
               f.operator_start != 0 || f.operator_end != 0 || f.right_start != 0 || f.right_end != 0 ||
               f.callee_start != 0 || f.callee_end != 0 { return 1; }
        }
        let left = f.values[left_id];
        if left.producer != 1 && left.producer != 2 { return 1; }
        var expected: Value[4] = [Value {}; 4];
        expected[0] = Value { producer: 1, type_id: 1 };
        var count: i64 = 1;
        var wanted_left: i64 = 0;
        if left.producer == 2 {
            wanted_left = count;
            expected[count] = Value { producer: 2, type_id: 1, literal: left.literal };
            count += 1;
        }
        if kind == 3 {
            let right = f.values[right_id];
            if right.producer != 1 && right.producer != 2 { return 1; }
            var wanted_right: i64 = 0;
            if right.producer == 2 {
                wanted_right = count;
                expected[count] = Value { producer: 2, type_id: 1, literal: right.literal };
                count += 1;
            }
            expected[count] = Value { producer: 3, type_id: 1, op_id: 1,
                                       left_id: wanted_left, right_id: wanted_right };
            count += 1;
        } else if kind == 4 {
            expected[count] = Value { producer: 4, type_id: 1,
                                       left_id: wanted_left, callee_id: result.callee_id };
            count += 1;
        }
        let wanted_result = if kind == 1 { wanted_left } else { count - 1 };
        if count != f.value_count || f.result_id != wanted_result { return 1; }
        for n in 4 { if !same(f.values[n], expected[n]) { return 1; } }
    }
    if !unique_names(m) { return 1; }
    // All declarations have been span-checked; it is now safe to resolve the
    // copied call-target names. A local U32 parameter shadows a top-level name.
    for f in m.functions {
        let result = f.values[f.result_id];
        if result.producer == 4 {
            let target = m.functions[result.callee_id];
            let called = m.source[f.callee_start..f.callee_end];
            if called != m.source[target.name_start..target.name_end] ||
               called == m.source[f.parameter_start..f.parameter_end] { return 1; }
        }
    }
    // Independent bounded tri-state walks memoize the result for every root.
    // A negative depth marks a path reaching a cycle. Iterate roots again in
    // original order to retain the old cycle/depth/mismatch diagnostic order.
    let count = m.functions.len;
    var state: u8[256] = [0; 256];
    var depth: i64[256] = [0; 256];
    var path: i64[256] = [0; 256];
    for root in count {
        if state[root] == 2 { continue; }
        var length: i64 = 0;
        var current = root;
        var base: i64 = 0;
        loop {
            if state[current] == 1 { base = -1; break; }
            if state[current] == 2 { base = depth[current]; break; }
            state[current] = 1;
            path[length] = current; length += 1;
            let node = m.functions[current];
            let result = node.values[node.result_id];
            if result.producer != 4 { break; }
            current = result.callee_id;
        }
        while length > 0 {
            length -= 1;
            let node = path[length];
            if base >= 0 { base += 1; }
            depth[node] = base;
            state[node] = 2;
        }
    }
    for f, i in m.functions {
        if depth[i] < 0 { return 8; }
        if depth[i] > 128 { return 9; }
        if f.depth != depth[i] { return 1; }
    }
    return 0;
}

