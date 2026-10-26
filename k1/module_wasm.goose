// Experimental v3 multi-function Wasm fixture encoder. Callers must perform
// independent source/Core validation; this structural gate is not authority
// for source, effects, ownership, ABI certificates, or executable provenance.
namespace wasm_v3;
import module_core;
import wasm;

fn zero(v: module_core::Value) -> bool {
    return v.producer == 0 && v.type_id == 0 && v.op_id == 0 && v.literal == 0 &&
        v.left_id == 0 && v.right_id == 0 && v.callee_id == 0;
}
fn atom(v: module_core::Value) -> bool {
    if v.type_id != 1 || v.op_id != 0 || v.left_id != 0 || v.right_id != 0 || v.callee_id != 0 { return false; }
    if v.producer == 1 { return v.literal == 0; }
    return v.producer == 2;
}
fn span(start: i64, end: i64, limit: i64) -> bool {
    return start >= 0 && end > start && end <= limit;
}
fn absent(start: i64, end: i64) -> bool { return start == 0 && end == 0; }
fn valid_function(f: module_core::Function, source_len: i64, total: i64) -> bool {
    if !span(f.declaration_start, f.declaration_end, source_len) ||
       !span(f.name_start, f.name_end, f.declaration_end) || f.name_start < f.declaration_start ||
       f.function_start < f.name_end || f.function_start >= f.declaration_end ||
       !span(f.parameter_start, f.parameter_end, f.declaration_end) || f.parameter_start < f.function_start ||
       f.return_start < f.parameter_end || f.return_start >= f.declaration_end ||
       !span(f.expression_start, f.expression_end, f.declaration_end) || f.expression_start < f.return_start ||
       !span(f.left_start, f.left_end, f.expression_end) || f.left_start < f.expression_start ||
       f.depth < 1 || f.depth > 128 || f.frame != 0 || f.result_type != 1 ||
       f.value_count < 1 || f.value_count > 4 || f.terminator != 1 ||
       f.result_id < 0 || f.result_id >= f.value_count { return false; }
    let param = f.values[0];
    if !atom(param) || param.producer != 1 { return false; }
    for i in f.value_count..4 { if !zero(f.values[i]) { return false; } }
    let result = f.values[f.result_id];
    if result.producer == 1 || result.producer == 2 {
        if f.result_id != f.value_count - 1 || f.value_count > 2 || !atom(result) ||
           !absent(f.operator_start, f.operator_end) || !absent(f.right_start, f.right_end) ||
           !absent(f.callee_start, f.callee_end) || f.expression_start != f.left_start ||
           f.expression_end != f.left_end { return false; }
        return (result.producer == 1 && f.value_count == 1) ||
               (result.producer == 2 && f.value_count == 2);
    }
    if f.result_id != f.value_count - 1 || result.type_id != 1 || result.literal != 0 ||
       result.left_id < 0 || result.left_id >= f.result_id { return false; }
    let left = f.values[result.left_id];
    if !atom(left) { return false; }
    var next: i64 = 1;
    if result.left_id != 0 {
        if result.left_id != next || left.producer != 2 { return false; }
        next += 1;
    }
    if result.producer == 3 {
        if result.op_id != 1 || result.callee_id != 0 || result.right_id < 0 ||
           result.right_id >= f.result_id || !absent(f.callee_start, f.callee_end) ||
           !span(f.operator_start, f.operator_end, f.expression_end) || f.operator_start < f.left_end ||
           !span(f.right_start, f.right_end, f.expression_end) || f.right_start < f.operator_end ||
           f.expression_start != f.left_start || f.expression_end != f.right_end { return false; }
        let right = f.values[result.right_id];
        if !atom(right) { return false; }
        if result.right_id != 0 {
            if result.right_id != next || right.producer != 2 { return false; }
            next += 1;
        }
    } else if result.producer == 4 {
        if result.op_id != 0 || result.right_id != 0 || result.callee_id < 0 || result.callee_id >= total ||
           !absent(f.operator_start, f.operator_end) || !absent(f.right_start, f.right_end) ||
           !span(f.callee_start, f.callee_end, f.expression_end) || f.callee_start != f.expression_start ||
           f.callee_end > f.left_start || f.left_end >= f.expression_end { return false; }
    } else { return false; }
    return next == f.result_id;
}

// The target gate sorts its own checked source spans. It does not use the
// producer index, source verifier sort, or a hash as an equality authority.
// target_name_order and target_sift are internal unchecked helpers; use them
// only through target_unique_names, which validates the count and spans.
fn target_name_order(core: module_core::ModuleCore&, a: i64, b: i64) -> i64 {
    let x = core.functions[a];
    let y = core.functions[b];
    var i = x.name_start;
    var j = y.name_start;
    while i < x.name_end && j < y.name_end {
        if core.source[i] < core.source[j] { return -1; }
        if core.source[i] > core.source[j] { return 1; }
        i += 1; j += 1;
    }
    if i == x.name_end && j == y.name_end { return 0; }
    return if i == x.name_end { -1 } else { 1 };
}
fn target_sift(core: module_core::ModuleCore&, names: i64[256]&, root: i64, end: i64) {
    var parent = root;
    loop {
        let left = parent * 2 + 1;
        if left >= end { break; }
        var child = left;
        if left + 1 < end && target_name_order(core, names[left], names[left + 1]) < 0 { child += 1; }
        if target_name_order(core, names[parent], names[child]) >= 0 { break; }
        let saved = names[parent]; names[parent] = names[child]; names[child] = saved;
        parent = child;
    }
}
fn target_unique_names(core: module_core::ModuleCore&) -> bool {
    let count = core.functions.len;
    if count < 1 || count > 256 { return false; }
    var names: i64[256] = [0; 256];
    for i in count {
        let f = core.functions[i];
        if !span(f.name_start, f.name_end, core.source.len) { return false; }
        names[i] = i;
    }
    var root = count / 2;
    while root > 0 { root -= 1; target_sift(core, names, root, count); }
    var end = count;
    while end > 1 {
        end -= 1;
        let saved = names[0]; names[0] = names[end]; names[end] = saved;
        target_sift(core, names, 0, end);
    }
    for i in 1..count { if target_name_order(core, names[i - 1], names[i]) == 0 { return false; } }
    return true;
}

// This rechecks owned-table structure, names and the call graph before any
// code generation. It is deliberately not a source grammar validator.
fn structural(core: module_core::ModuleCore&) -> bool {
    let count = core.functions.len;
    if core.source.len > 16777216 || count < 1 || count > 256 { return false; }
    for f in core.functions {
        if !valid_function(f, core.source.len, count) { return false; }
        if !wasm::identifier(core.source[f.name_start..f.name_end]) { return false; }
    }
    if !target_unique_names(core) { return false; }
    for f in core.functions {
        let value = f.values[f.result_id];
        if value.producer == 4 {
            let target = core.functions[value.callee_id];
            if core.source[f.callee_start..f.callee_end] != core.source[target.name_start..target.name_end] { return false; }
            // Both depths were independently bounded in valid_function. A
            // strict decrement along every edge rules out any cycle, while
            // the exact leaf value below anchors the canonical graph depth.
            if f.depth != target.depth + 1 { return false; }
        } else if f.depth != 1 { return false; }
    }
    return true;
}
fn operand(out: u8[>..]&, v: module_core::Value) {
    if v.producer == 1 { out.push(0x20); out.push(1); }
    else { out.push(0x41); wasm::signed_i32_leb(out, v.literal); }
}
fn emit_module(core: module_core::ModuleCore&) -> u8[] {
    if !wasm::fixture_geometry_valid() || module_core::validate(core) != 0 || !structural(core) { return []; }
    var output: u8[>..] = [0, 0x61, 0x73, 0x6d, 1, 0, 0, 0];
    for b in [1, 7, 1, 0x60, 2, 0x7f, 0x7f, 1, 0x7f] { output.push(b as u8); }
    var functions: u8[>..] = [];
    wasm::unsigned_leb(functions, core.functions.len);
    for f in core.functions { functions.push(0); }
    output.push(3); wasm::unsigned_leb(output, functions.len); output.append(functions);
    var memory: u8[>..] = [1, 1];
    wasm::unsigned_leb(memory, 275); wasm::unsigned_leb(memory, 275);
    output.push(5); wasm::unsigned_leb(output, memory.len); output.append(memory);
    var exports: u8[>..] = [];
    wasm::unsigned_leb(exports, core.functions.len);
    for f, i in core.functions {
        let name = core.source[f.name_start..f.name_end];
        wasm::unsigned_leb(exports, name.len); exports.append(name);
        exports.push(0); wasm::unsigned_leb(exports, i);
    }
    output.push(7); wasm::unsigned_leb(output, exports.len); output.append(exports);
    var code: u8[>..] = [];
    wasm::unsigned_leb(code, core.functions.len);
    for f in core.functions {
        let value = f.values[f.result_id];
        var body: u8[>..] = [0]; // zero locals
        if value.producer == 3 {
            operand(body, f.values[value.left_id]); operand(body, f.values[value.right_id]);
            body.push(0x71); // i32.and
        } else if value.producer == 4 {
            body.push(0x41); body.push(0); // environment = 0, before the argument
            operand(body, f.values[value.left_id]);
            body.push(0x10); wasm::unsigned_leb(body, value.callee_id);
        } else { operand(body, value); }
        body.push(0x0b);
        wasm::unsigned_leb(code, body.len); code.append(body);
    }
    output.push(10); wasm::unsigned_leb(output, code.len); output.append(code);
    // Same non-authoritative fixture-only geometry metadata as the scalar
    // emitter; it is not a K1 ABI manifest or certificate.
    let metadata_name = "blot.k1.fixture.memory";
    let metadata = "{\"version\":1,\"page_bytes\":65536,\"pages\":275,\"granule_bytes\":4096,\"static_bytes\":0,\"dictionary_bytes\":0,\"control\":[0,16],\"owners\":[16,8192],\"owner_slots\":256,\"owner_stride\":32,\"bitmap\":[8208,512],\"frame\":[8720,1048576],\"ingress\":[1057296,65536],\"egress\":[1122832,65536],\"alignment_padding\":[1188368,3568],\"pool\":[1191936,16777216],\"page_padding\":[17969152,53248],\"memory_bytes\":18022400}";
    var custom: u8[>..] = [];
    wasm::unsigned_leb(custom, metadata_name.len); custom.append(metadata_name); custom.append(metadata);
    output.push(0); wasm::unsigned_leb(output, custom.len); output.append(custom);
    return output;
}
