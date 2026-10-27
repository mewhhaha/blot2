// Required-static evaluation of completed Core. Addresses are symbolic object
// relocations; no host pointer, runtime capability, or I/O enters the machine.
import .model;
import math;

struct StaticValue { words: u32[64], kinds: u32[64], targets: u32[64], addends: u32[64], count: u32 }
struct StaticStats { steps: u32, visits: u32, produced_bytes: u32, max_depth: u32 }
struct StaticBinding { binder: u32, type_id: u32, nat: u32, has_nat: bool }
struct StaticEnvironment { constructor: u32, function: u32, captures: Span, bindings: Span }
let STATIC_LOCAL_CLOSURE: u32 = 5;

fn static_bool(value: bool) -> StaticValue { return static_scalar(if value { 1 } else { 0 }); }
fn static_scalar(word: u32) -> StaticValue { var result = StaticValue { count: 1, .. }; result.words[0] = word; return result; }
fn static_extract(value: StaticValue, start: u32, count: u32) -> StaticValue {
    var result = StaticValue { count: count, .. };
    assert(start <= value.count && count <= value.count - start && count <= 64);
    for i in count { result.words[i] = value.words[start + i]; result.kinds[i] = value.kinds[start + i]; result.targets[i] = value.targets[start + i]; result.addends[i] = value.addends[start + i]; }
    return result;
}
fn static_insert(target: StaticValue&, start: u32, value: StaticValue) {
    assert(start <= 64 && value.count <= 64 - start);
    for i in value.count { target.words[start + i] = value.words[i]; target.kinds[start + i] = value.kinds[i]; target.targets[start + i] = value.targets[i]; target.addends[start + i] = value.addends[i]; }
    target.count = max(target.count, start + value.count);
}
fn static_f32(bits: u32) -> f32 {
    let bytes: u8[5] = [4, bits as! u8, (bits >> 8) as! u8, (bits >> 16) as! u8, (bits >> 24) as! u8];
    let decoded, ok = from_bytes<f32[>..]>(bytes); assert(ok && decoded.len == 1); return decoded[0];
}
fn static_bits(value: f32) -> u32 {
    let values: f32[1] = [value]; let bytes = bytes_of(values);
    return (bytes[0] as u32) | ((bytes[1] as u32) << 8) | ((bytes[2] as u32) << 16) | ((bytes[3] as u32) << 24);
}
fn static_arithmetic_bits(value: f32) -> u32 { if value != value { return 0x7fc00000; } return static_bits(value); }
fn static_nearest(value: f32) -> f32 {
    if value != value || value == 0.0 || abs(value) >= 8388608.0 { return value; }
    let lower = floor(value); let fraction = value - lower;
    var rounded = lower;
    if fraction > 0.5 || fraction == 0.5 && ((lower as i64) & 1) != 0 { rounded = lower + 1.0; }
    if rounded == 0.0 { return static_f32(static_bits(value) & 0x80000000); }
    return rounded;
}
fn static_read(c: Core, object: u32, offset: u32, count: u32) -> StaticValue, bool {
    var result = StaticValue { count: count, .. };
    if !id_ok(object, c.static_objects.len) || count > 64 || offset % 4 != 0 { return result, false; }
    let row = c.static_objects[object];
    if !span_ok(row.bytes, c.bytes.len) || offset > row.bytes.count || count * 4 > row.bytes.count - offset { return result, false; }
    for i in count { for byte in 4 { result.words[i] |= (c.bytes[row.bytes.start + offset + 4 * i + byte] as u32) << (8 * byte); } }
    if !span_ok(row.relocations, c.refs.len) { return result, false; }
    for i in row.relocations.count {
        let rid = c.refs[row.relocations.start + i]; if !id_ok(rid, c.static_relocations.len) { return result, false; }
        let r = c.static_relocations[rid];
        if r.offset >= offset && r.offset - offset < count * 4 {
            if r.offset % 4 != 0 { return result, false; } let index = (r.offset - offset) / 4;
            result.kinds[index] = r.kind; result.targets[index] = r.target; result.addends[index] = r.addend;
        }
    }
    return result, true;
}
fn static_closed_result(value: StaticValue, environments: const StaticEnvironment[:], captures: const StaticValue[:], bindings: const StaticBinding[:]) -> StaticValue, bool {
    for i in value.count { if value.kinds[i] == STATIC_LOCAL_CLOSURE { return StaticValue { .. }, false; } }
    return value, true;
}
fn static_evaluate(c: Core, function_id: u32, argument: StaticValue, stats: StaticStats&, diagnostics: Diagnostic[>..]&) -> StaticValue, bool {
    let before = diagnostics.len;
    let value, ok = static_evaluate_at_depth(c, function_id, argument, stats, diagnostics, 1, static_closed_result);
    if !ok && diagnostics.len == before { diagnostics.push(Diagnostic { code: 4020, .. }); }
    return value, ok;
}
fn static_evaluate_initializer(c: Core, function_id: u32, argument: StaticValue, stats: StaticStats&, diagnostics: Diagnostic[>..]&) -> StaticValue, bool {
    let before = diagnostics.len;
    let value, ok = static_evaluate_at_depth(c, function_id, argument, stats, diagnostics, 0, static_closed_result);
    if !ok && diagnostics.len == before { diagnostics.push(Diagnostic { code: 4020, .. }); }
    return value, ok;
}
fn static_evaluate_at_depth<F>(c: Core, function_id: u32, argument: StaticValue, stats: StaticStats&, diagnostics: Diagnostic[>..]&, initial_depth: u32) -> StaticValue, bool {
    var mapping: u32[>..] = []; for i in c.values.len { mapping.push(0); }
    var slots: StaticValue[>..] = [StaticValue { .. }];
    var bindings: StaticBinding[>..<] = [];
    var environments: StaticEnvironment[>..] = [StaticEnvironment { .. }];
    var environment_values: StaticValue[>..] = []; var environment_bindings: StaticBinding[>..] = [];
    var edge_values: StaticValue[>..<] = []; var active: u32[>..<] = [];
    var current_origin: u32 = 0;
    fn fail(code: u32) { diagnostics.push(Diagnostic { code: code, origin: current_origin, detail: if code == 4021 { stats.steps } else if code == 4022 { stats.max_depth } else if code == 4023 { stats.produced_bytes } else { stats.visits }, .. }); return StaticValue { .. }, false from static_evaluate_at_depth; }
    fn visit() { if stats.visits >= LIMIT_VISITS { fail(4025); } stats.visits++; }
    fn step() { visit(); if stats.steps >= 100000 { fail(4021); } stats.steps++; }
    fn get(id: u32) -> StaticValue { visit(); if !id_ok(id, mapping.len) || mapping[id] == 0 { fail(4024); } return slots[mapping[id]]; }
    fn set(id: u32, value: StaticValue) {
        visit(); if !id_ok(id, mapping.len) { fail(4024); }
        if mapping[id] == 0 { mapping[id] = slots.len as u32; slots.push(value); } else { slots[mapping[id]] = value; }
    }
    fn binding(id: u32) -> StaticBinding {
        var index = bindings.len; while index > 0 { visit(); index--; if bindings[index].binder == id { return bindings[index]; } }
        return StaticBinding { .. };
    }
    recursive fn actual(id: u32, depth: u32) -> u32 {
        visit(); if depth > 64 || !id_ok(id, c.types.len) { fail(4024); }
        let t = c.types[id];
        if t.tag == TY_ALIAS || t.tag == TY_FORALL { return actual(c.refs[t.children.start], depth + 1); }
        if t.tag == TY_PARAM { let found = binding(t.binder); if found.type_id == 0 || found.type_id == id { fail(4020); } return actual(found.type_id, depth + 1); }
        return id;
    }
    recursive fn width(id: u32, depth: u32) -> u32 {
        visit(); if depth > 64 { fail(4024); } let t = c.types[actual(id, 0)];
        if t.tag == TY_UNIT { return 0; }
        if t.tag == TY_U32 || t.tag == TY_BOOL || t.tag == TY_F32 || t.tag == TY_INDEX { return 1; }
        if t.tag == TY_VIEW || t.tag == TY_FN { return 2; }
        var size: u32 = 0;
        if t.tag == TY_EXISTS { for i in t.binders.count { visit(); if c.binders[c.refs[t.binders.start + i]].kind == KIND_NAT { size++; } } }
        if t.tag == TY_TUPLE || t.tag == TY_RECORD || t.tag == TY_SUM || t.tag == TY_RESULT || t.tag == TY_EXISTS {
            let count = if t.fields.count != 0 { t.fields.count } else { t.children.count };
            for i in count {
                let child = if t.fields.count != 0 { c.fields[c.refs[t.fields.start + i]].type_id } else { c.refs[t.children.start + i] };
                let n = width(child, depth + 1);
                if t.tag == TY_SUM || t.tag == TY_RESULT { size = max(size, n); } else { size += n; }
                if size > 64 { fail(4024); }
            }
            if t.tag == TY_SUM || t.tag == TY_RESULT { size++; } if size > 64 { fail(4024); } return size;
        }
        fail(4020); return 0;
    }
    fn field_type(type_id: u32, ordinal: u32) -> u32 {
        let t = c.types[actual(type_id, 0)];
        let count = if t.fields.count != 0 { t.fields.count } else { t.children.count };
        if ordinal >= count { fail(4024); }
        return if t.fields.count != 0 { c.fields[c.refs[t.fields.start + ordinal]].type_id } else { c.refs[t.children.start + ordinal] };
    }
    recursive fn term(id: u32, depth: u32) -> u32 {
        visit(); if depth > 64 || !id_ok(id, c.terms.len) { fail(4024); } let t = c.terms[id];
        if t.tag == EXPR_LITERAL { return t.literal; }
        if t.tag == EXPR_BINDER { let found = binding(t.binder); if !found.has_nat { fail(4020); } return found.nat; }
        if t.tag == EXPR_VALUE { let v = get(t.value); if v.count != 1 || v.kinds[0] != 0 { fail(4020); } return v.words[0]; }
        if t.tag == EXPR_LEN && t.value != 0 { let v = get(t.value); if v.count != 2 { fail(4024); } return v.words[1]; }
        if t.tag == EXPR_MAX_MINUS { return 0xffffffff - term(c.refs[t.args.start], depth + 1); }
        if t.args.count == 2 {
            let a = term(c.refs[t.args.start], depth + 1); let b = term(c.refs[t.args.start + 1], depth + 1);
            if t.tag == EXPR_ADD && (a as u64) + (b as u64) <= MAX_U32 { return a + b; }
            if t.tag == EXPR_SUB && a >= b { return a - b; }
            if t.tag == EXPR_MUL && (a as u64) * (b as u64) <= MAX_U32 { return a * b; }
        }
        fail(4020); return 0;
    }
    fn bind_substitutions(span: Span) {
        let mark = bindings.len;
        // Resolve all source-side terms before installing any callee binding.
        for i in span.count {
            visit(); let sub = c.substitutions[c.refs[span.start + i]];
            if sub.kind == KIND_TYPE { bindings.push(StaticBinding { binder: sub.binder, type_id: actual(sub.value, 0), .. }); }
            else if sub.kind == KIND_NAT { bindings.push(StaticBinding { binder: sub.binder, nat: term(sub.value, 0), has_nat: true, .. }); }
            else if sub.kind == KIND_REGION && sub.value != 0 { fail(4020); }
        }
    }
    fn primitive(op_id: u32) {
        let op = c.ops[op_id]; current_origin = op.origin; step();
        let tag = op.tag; let args = c.refs[op.args.start..op.args.start + op.args.count];
        var a = StaticValue { .. }; var b = StaticValue { .. };
        if args.len > 0 { a = get(args[0]); } if args.len > 1 { b = get(args[1]); }
        let x = a.words[0]; let y = b.words[0];
        var result = StaticValue { .. };
        let result_id = if op.results.count != 0 { c.refs[op.results.start] } else { 0 };
        let result_type = if result_id != 0 { c.values[result_id].type_id } else { 0 };
        if tag == OP_UNIT || tag == OP_GENERIC_BIND {}
        else if tag == OP_BOOL || tag == OP_U32 || tag == OP_F32 { result = static_scalar(op.imm0); }
        else if tag == OP_COPY || tag == OP_REFINE || tag == OP_FN_WEAKEN || tag == OP_INDEX_VALUE || tag == OP_F32_FROM_BITS || tag == OP_F32_TO_BITS { result = a; }
        else if tag == OP_TUPLE || tag == OP_RECORD || tag == OP_PACK {
            for value in args { let part = get(value); if part.count > 64 - result.count { fail(4024); } static_insert(result, result.count, part); }
        }
        else if tag == OP_PROJECT {
            var offset: u32 = 0; for i in op.imm0 { offset += width(field_type(c.values[args[0]].type_id, i), 0); }
            result = static_extract(a, offset, width(result_type, 0));
        }
        else if tag == OP_DESTRUCTURE {
            var offset: u32 = 0; for i in op.results.count { let rid = c.refs[op.results.start + i]; let count = width(c.values[rid].type_id, 0); set(rid, static_extract(a, offset, count)); offset += count; }
            return;
        }
        else if tag == OP_SUM { result.count = width(result_type, 0); result.words[0] = op.imm0; if args.len != 0 { static_insert(result, 1, a); } }
        else if tag == OP_TAG { result = static_scalar(x); }
        else if tag == OP_PAYLOAD { if x != op.imm0 { fail(4024); } result = static_extract(a, 1, width(result_type, 0)); }
        else if tag == OP_OPEN {
            let t = c.types[actual(c.values[args[0]].type_id, 0)]; var prefix: u32 = 0;
            for i in t.binders.count { if c.binders[c.refs[t.binders.start + i]].kind == KIND_NAT { prefix++; } }
            set(result_id, static_extract(a, prefix, a.count - prefix)); var index: u32 = 0;
            for i in op.substitutions.count { let sub = c.substitutions[c.refs[op.substitutions.start + i]]; if sub.kind == KIND_NAT { bindings.push(StaticBinding { binder: c.terms[sub.value].binder, nat: a.words[index], has_nat: true, .. }); index++; } }
            for i in 1..op.results.count { set(c.refs[op.results.start + i], static_scalar(a.words[i - 1])); }
            return;
        }
        else if tag == OP_U32_ADD || tag == OP_U32_ADD_WRAP { if tag == OP_U32_ADD && (x as u64) + (y as u64) > MAX_U32 { fail(4024); } result = static_scalar(x + y); }
        else if tag == OP_U32_SUB || tag == OP_U32_SUB_WRAP { if tag == OP_U32_SUB && x < y { fail(4024); } result = static_scalar(x - y); }
        else if tag == OP_U32_MUL || tag == OP_U32_MUL_WRAP { if tag == OP_U32_MUL && (x as u64) * (y as u64) > MAX_U32 { fail(4024); } result = static_scalar(x * y); }
        else if tag == OP_U32_DIV || tag == OP_U32_REM { if y == 0 { fail(4024); } result = static_scalar(if tag == OP_U32_DIV { x / y } else { x % y }); }
        else if tag == OP_U32_EQ { result = static_bool(x == y); }
        else if tag == OP_U32_NE { result = static_bool(x != y); }
        else if tag == OP_U32_LT { result = static_bool(x < y); }
        else if tag == OP_U32_LE { result = static_bool(x <= y); }
        else if tag == OP_U32_GT { result = static_bool(x > y); }
        else if tag == OP_U32_GE { result = static_bool(x >= y); }
        else if tag == OP_U32_AND { result = static_scalar(x & y); }
        else if tag == OP_U32_OR { result = static_scalar(x | y); }
        else if tag == OP_U32_XOR { result = static_scalar(x ^ y); }
        else if tag == OP_U32_NOT { result = static_scalar(~x); }
        else if tag == OP_U32_SHL || tag == OP_U32_SHR { if y >= 32 { fail(4024); } result = static_scalar(if tag == OP_U32_SHL { x << y } else { x >> y }); }
        else if tag == OP_BOOL_NOT { result = static_bool(x == 0); }
        else if tag == OP_BOOL_AND { result = static_bool(x != 0 && y != 0); }
        else if tag == OP_BOOL_OR { result = static_bool(x != 0 || y != 0); }
        else if tag == OP_ADD_FITS { result = static_bool((x as u64) + (y as u64) <= MAX_U32); }
        else if tag == OP_SUB_FITS { result = static_bool(x >= y); }
        else if tag == OP_MUL_FITS { result = static_bool((x as u64) * (y as u64) <= MAX_U32); }
        else if tag == OP_CHECKED_ADD || tag == OP_CHECKED_SUB || tag == OP_CHECKED_MUL || tag == OP_CHECKED_DIV || tag == OP_CHECKED_SHL || tag == OP_CHECKED_SHR {
            result.count = width(result_type, 0); var ok = false; var word: u32 = 0;
            if tag == OP_CHECKED_ADD { ok = (x as u64) + (y as u64) <= MAX_U32; if ok { word = x + y; } }
            if tag == OP_CHECKED_SUB { ok = x >= y; if ok { word = x - y; } }
            if tag == OP_CHECKED_MUL { ok = (x as u64) * (y as u64) <= MAX_U32; if ok { word = x * y; } }
            if tag == OP_CHECKED_DIV { ok = y != 0; if ok { word = x / y; } }
            if tag == OP_CHECKED_SHL { ok = y < 32; if ok { word = x << y; } }
            if tag == OP_CHECKED_SHR { ok = y < 32; if ok { word = x >> y; } }
            result.words[0] = if ok { 0 } else { 1 }; if ok { result.words[1] = word; }
        }
        else if tag == OP_U32_TO_F32 { result = static_scalar(static_bits(x as f32)); }
        else if tag == OP_F32_TO_U32 {
            let fx = static_f32(x); result.count = width(result_type, 0);
            if fx == fx && fx >= 0.0 && (fx as f64) < 4294967296.0 { result.words[1] = trunc(fx) as u32; } else { result.words[0] = 1; }
        }
        else if tag == OP_F32_NEG { result = static_scalar(x ^ 0x80000000); }
        else if tag == OP_F32_ABS { result = static_scalar(x & 0x7fffffff); }
        else if tag >= OP_F32_ADD && tag <= OP_F32_GE || tag >= OP_F32_SQRT && tag <= OP_F32_NEAREST {
            let fx = static_f32(x); let fy = static_f32(y); var value: f32 = 0.0;
            if tag == OP_F32_EQ { result = static_bool(fx == fy); }
            else if tag == OP_F32_NE { result = static_bool(fx != fy); }
            else if tag == OP_F32_LT { result = static_bool(fx < fy); }
            else if tag == OP_F32_LE { result = static_bool(fx <= fy); }
            else if tag == OP_F32_GT { result = static_bool(fx > fy); }
            else if tag == OP_F32_GE { result = static_bool(fx >= fy); }
            else {
                if tag == OP_F32_ADD { value = fx + fy; } else if tag == OP_F32_SUB { value = fx - fy; }
                else if tag == OP_F32_MUL { value = fx * fy; } else if tag == OP_F32_DIV { value = fx / fy; }
                else if tag == OP_F32_SQRT { value = sqrt(fx); }
                else if tag == OP_F32_CEIL { value = ceil(fx); } else if tag == OP_F32_FLOOR { value = floor(fx); }
                else if tag == OP_F32_TRUNC { value = trunc(fx); } else if tag == OP_F32_NEAREST { value = static_nearest(fx); }
                else if tag == OP_F32_MIN || tag == OP_F32_MAX {
                    if fx != fx || fy != fy { value = static_f32(0x7fc00000); }
                    else if fx == fy { value = static_f32(if tag == OP_F32_MIN { x | y } else { x & y }); }
                    else { value = if tag == OP_F32_MIN { min(fx, fy) } else { max(fx, fy) }; }
                } else { fail(4020); }
                result = static_scalar(static_arithmetic_bits(value));
            }
        }
        else if tag == OP_LAYOUT_SIZE || tag == OP_LAYOUT_ALIGN { let size = width(op.imm0, 0) * 4; result = static_scalar(if tag == OP_LAYOUT_SIZE { size } else { if size == 0 { 1 } else { 4 } }); }
        else if tag == OP_NAT_VALUE { let found = binding(op.imm0); if !found.has_nat { fail(4020); } result = static_scalar(found.nat); }
        else if tag == OP_STATIC {
            if !id_ok(op.imm0, c.static_objects.len) { fail(4024); } let object = c.static_objects[op.imm0];
            if object.kind == STATIC_ARRAY { result.count = 2; result.words[1] = object.count; if object.bytes.count != 0 { result.kinds[0] = STATIC_ADDRESS; result.targets[0] = op.imm0; } }
            else { let value, ok = static_read(c, op.imm0, 0, width(object.type_id, 0)); if !ok { fail(4024); } result = value; }
        }
        else if tag == OP_VIEW_LEN { result = static_scalar(a.words[1]); }
        else if tag == OP_TRY_INDEX { result.count = width(result_type, 0); if y < a.words[1] { result.words[0] = 1; result.words[1] = y; } }
        else if tag == OP_VIEW_INDEX {
            if a.count != 2 || y >= a.words[1] { fail(4024); } let words = width(result_type, 0);
            if words != 0 { if a.kinds[0] != STATIC_ADDRESS { fail(4020); } let value, ok = static_read(c, a.targets[0], a.addends[0] + y * words * 4, words); if !ok { fail(4024); } result = value; }
        }
        else if tag == OP_VIEW_SLICE {
            let length = get(args[2]).words[0]; if y > a.words[1] || length > a.words[1] - y { fail(4024); }
            let t = c.types[actual(c.values[args[0]].type_id, 0)]; let size = width(c.refs[t.children.start], 0) * 4;
            let words = width(result_type, 0); result.count = words;
            for i in words - 2 { result.words[i] = length; }
            result.words[words - 1] = length;
            if length != 0 && size != 0 { if a.kinds[0] != STATIC_ADDRESS { fail(4020); } result.kinds[words - 2] = STATIC_ADDRESS; result.targets[words - 2] = a.targets[0]; result.addends[words - 2] = a.addends[0] + y * size; }
        }
        else if tag == OP_CLOSURE {
            let function = c.functions[op.imm0]; result.count = 2;
            if args.len == 0 && op.substitutions.count == 0 { result.kinds[0] = STATIC_FUNCTION; result.targets[0] = op.imm0; }
            else {
                let start = environment_values.len as u32; for value in args { environment_values.push(get(value)); }
                let mark = bindings.len; bind_substitutions(op.substitutions);
                let sub_start = environment_bindings.len as u32; for bound in bindings { environment_bindings.push(bound); } bindings.resize(mark);
                let env_id = environments.len as u32; environments.push(StaticEnvironment { constructor: op_id, function: op.imm0, captures: Span { start: start, count: args.len as u32 }, bindings: Span { start: sub_start, count: (environment_bindings.len as u32) - sub_start } });
                result.kinds[0] = STATIC_LOCAL_CLOSURE; result.targets[0] = env_id;
            }
        }
        else if tag == OP_LOAN_END || tag == OP_DISCARD_ONCE {}
        else { fail(4020); }
        if op.results.count > 1 { fail(4024); } if result_id != 0 { if result.count != width(result_type, 0) { fail(4024); } set(result_id, result); }
    }
    recursive fn evaluate(fid: u32, arg: StaticValue, env: u32, depth: u32) -> StaticValue {
        visit(); stats.max_depth = max(stats.max_depth, depth); if depth > 128 { fail(4022); }
        if !id_ok(fid, c.functions.len) { fail(4024); }
        for target in active { if target == fid { fail(4020); } }
        let f = c.functions[fid]; let ct = c.contracts[f.contract];
        for i in ct.effects.count { let e = c.effects[c.refs[ct.effects.start + i]]; if e.kind != EFFECT_READ || e.region != 0 { fail(4020); } }
        if arg.count != width(ct.arg, 0) { fail(4024); }
        active.push(fid); set(f.param, arg);
        if f.captures.count != 0 {
            if !id_ok(env, environments.len) { fail(4020); } let stored = environments[env];
            if stored.function != fid || stored.captures.count != f.captures.count { fail(4024); }
            for i in f.captures.count { let cap = c.captures[c.refs[f.captures.start + i]]; set(cap.local_value, environment_values[stored.captures.start + i]); }
        }
        var block_id = f.entry;
        while true {
            if !id_ok(block_id, c.blocks.len) { fail(4024); } let block_row = c.blocks[block_id];
            for oi in block_row.ops.count {
                let op_id = c.refs[block_row.ops.start + oi]; let op = c.ops[op_id];
                if op.tag != OP_CALL && op.tag != OP_CALL_INDIRECT { primitive(op_id); continue; }
                current_origin = op.origin; step();
                let args = c.refs[op.args.start..op.args.start + op.args.count];
                if args.len == 0 || op.results.count != 1 { fail(4024); }
                let a = get(args[0]); var input = a; var target = op.imm0; var call_env: u32 = 0;
                let mark = bindings.len;
                if op.tag == OP_CALL_INDIRECT {
                    if args.len != 2 { fail(4024); } input = get(args[1]);
                    if a.kinds[0] == STATIC_FUNCTION { target = a.targets[0]; }
                    else if a.kinds[0] == STATIC_LOCAL_CLOSURE {
                        call_env = a.targets[0]; if !id_ok(call_env, environments.len) { fail(4024); }
                        let stored = environments[call_env]; target = stored.function;
                        for i in stored.bindings.count { bindings.push(environment_bindings[stored.bindings.start + i]); }
                    } else { fail(4020); }
                }
                bind_substitutions(op.substitutions);
                let result = evaluate(target, input, call_env, depth + 1); bindings.resize(mark);
                let result_id = c.refs[op.results.start];
                if result.count != width(c.values[result_id].type_id, 0) { fail(4024); } set(result_id, result);
            }
            let terminal = c.terminators[block_row.term]; current_origin = terminal.origin; step();
            if terminal.tag == TERM_RETURN { let value = get(terminal.subject); active.pop(); return value; }
            if terminal.tag == TERM_UNREACHABLE { fail(4024); }
            var edge_id: u32 = 0;
            if terminal.tag == TERM_JUMP && terminal.edges.count == 1 { edge_id = c.refs[terminal.edges.start]; }
            else if terminal.tag == TERM_BRANCH { let condition = get(terminal.subject).words[0]; if condition > 1 || terminal.edges.count != 2 { fail(4024); } edge_id = c.refs[terminal.edges.start + (if condition != 0 { 0 } else { 1 })]; }
            else if terminal.tag == TERM_SWITCH { let variant = get(terminal.subject).words[0]; for i in terminal.edges.count { let candidate = c.refs[terminal.edges.start + i]; if c.edges[candidate].case_tag == variant { edge_id = candidate; break; } } }
            if !id_ok(edge_id, c.edges.len) { fail(4024); } let edge = c.edges[edge_id]; let target = c.blocks[edge.to];
            if edge.args.count != target.params.count { fail(4024); } let mark = edge_values.len;
            for i in edge.args.count { edge_values.push(get(c.refs[edge.args.start + i])); }
            for i in target.params.count { set(c.refs[target.params.start + i], edge_values[mark + i]); }
            edge_values.resize(mark); block_id = edge.to;
        }
        return StaticValue { .. };
    }
    let value = evaluate(function_id, argument, 0, initial_depth);
    return F(value, environments, environment_values, environment_bindings);
}

// Publication charges only immutable produced bytes, including array rows.
// An unpublished temporary value never stores a process address.
fn static_publish(b: CoreBuilder, kind: u32, type_id: u32, element_type: u32, count: u32, domain: u32, values: const StaticValue[:], producer: u32, stats: StaticStats&, diagnostics: Diagnostic[>..]&) -> u32, bool {
    var size: u32 = 0;
    var visits: u64 = 0;
    for value in values { visits += 1 + (value.count as u64) * 2; }
    if stats.visits > LIMIT_VISITS || visits > LIMIT_VISITS - stats.visits { diagnostics.push(Diagnostic { code: 4025, .. }); return 0, false; }
    stats.visits += visits as u32;
    for value in values { if value.count > 64 || value.count * 4 > 4194304 - size { diagnostics.push(Diagnostic { code: 4023, .. }); return 0, false; } size += value.count * 4; for i in value.count { if value.kinds[i] > STATIC_DICTIONARY { diagnostics.push(Diagnostic { code: 4020, .. }); return 0, false; } } }
    if stats.produced_bytes > 4194304 || size > 4194304 - stats.produced_bytes { diagnostics.push(Diagnostic { code: 4023, .. }); return 0, false; }
    let bytes = Span { start: b.bytes.len as u32, count: size }; var relocs: u32[>..] = []; var offset: u32 = 0;
    for value in values { for i in value.count {
        for byte in 4 { b.bytes.push((value.words[i] >> (8 * byte)) as! u8); }
        if value.kinds[i] != 0 { let id = b.static_relocations.len as u32; b.static_relocations.push(StaticRelocation { offset: offset, kind: value.kinds[i], target: value.targets[i], addend: value.addends[i] }); relocs.push(id); }
        offset += 4;
    } }
    stats.produced_bytes += size; let id = b.static_objects.len as u32;
    b.static_objects.push(StaticObject { kind: kind, type_id: type_id, element_type: element_type, count: count, domain: domain, bytes: bytes, relocations: ref_span(b, relocs), producer: producer, steps: stats.steps, .. }); return id, true;
}

struct StaticTypeMemo { type_id: u32, environment: u32, closed: u32 }
fn static_evaluate_publish_initializer(b: CoreBuilder, function_id: u32, argument: StaticValue, producer: u32, stats: StaticStats&, diagnostics: Diagnostic[>..]&) -> StaticValue, bool {
    fn finish(value: StaticValue, environments: const StaticEnvironment[:], captures: const StaticValue[:], bindings: const StaticBinding[:]) -> StaticValue, bool {
        var types: StaticTypeMemo[>..] = []; var scratch: u32[>..<] = [];
        var materialized: u32[>..] = []; for env in environments { materialized.push(0); }
        fn fail() { diagnostics.push(Diagnostic { code: 4020, .. }); return StaticValue { .. }, false from finish; }
        fn visit() { if stats.visits >= LIMIT_VISITS { diagnostics.push(Diagnostic { code: 4025, .. }); return StaticValue { .. }, false from finish; } stats.visits++; }
        fn binding(environment: u32, binder: u32) -> StaticBinding {
            if !id_ok(environment, environments.len) { fail(); } let span = environments[environment].bindings;
            var index = span.count; while index > 0 { visit(); index--; let row = bindings[span.start + index]; if row.binder == binder { return row; } }
            return StaticBinding { .. };
        }
        recursive fn term(id: u32, environment: u32, old_contract: u32, new_contract: u32, depth: u32) -> u32 {
            if id == 0 { return 0; } visit(); if depth > 64 || !id_ok(id, b.terms.len) { fail(); } var row = b.terms[id];
            if row.tag == EXPR_BINDER { let bound = binding(environment, row.binder); if bound.has_nat { let result = b.terms.len as u32; b.terms.push(Term { tag: EXPR_LITERAL, type_id: row.type_id, literal: bound.nat, .. }); return result; } }
            if (row.tag == EXPR_ARG || row.tag == EXPR_RESULT) && row.binder == old_contract { row.binder = new_contract; }
            if row.type_id != 0 { row.type_id = shape(row.type_id, environment, depth + 1); }
            let mark = scratch.len; for i in row.args.count { scratch.push(term(b.refs[row.args.start + i], environment, old_contract, new_contract, depth + 1)); }
            row.args = ref_span(b, scratch[mark..]); scratch.resize(mark); let result = b.terms.len as u32; b.terms.push(row); return result;
        }
        fn facts(span: Span, environment: u32, old_contract: u32, new_contract: u32, depth: u32) -> Span {
            let mark = scratch.len;
            for i in span.count { visit(); var row = b.facts[b.refs[span.start + i]]; row.left = term(row.left, environment, old_contract, new_contract, depth + 1); row.right = term(row.right, environment, old_contract, new_contract, depth + 1); row.third = term(row.third, environment, old_contract, new_contract, depth + 1); scratch.push(b.facts.len as u32); b.facts.push(row); }
            let result = ref_span(b, scratch[mark..]); scratch.resize(mark); return result;
        }
        recursive fn needs_closing(id: u32, environment: u32, depth: u32) -> bool {
            visit(); if depth > 64 || !id_ok(id, b.types.len) { fail(); }
            let t = b.types[id]; if t.tag == TY_PARAM || t.region != 0 { return true; }
            if t.nat != 0 && b.terms[t.nat].tag != EXPR_LITERAL || t.capacity != 0 && b.terms[t.capacity].tag != EXPR_LITERAL { return true; }
            for i in t.children.count { if needs_closing(b.refs[t.children.start + i], environment, depth + 1) { return true; } }
            for i in t.fields.count { if needs_closing(b.fields[b.refs[t.fields.start + i]].type_id, environment, depth + 1) { return true; } }
            // Closed callable contracts keep their identity so required resource
            // completion updates the source body and captured schema together.
            if t.contract != 0 { let ct = b.contracts[t.contract]; if ct.requires.count + ct.ensures.count + ct.on_true.count + ct.on_false.count != 0 { return true; } }
            return false;
        }
        recursive fn shape(id: u32, environment: u32, depth: u32) -> u32 {
            visit(); if depth > 64 || !id_ok(id, b.types.len) { fail(); }
            for row in types { if row.type_id == id && row.environment == environment { return row.closed; } }
            if !needs_closing(id, environment, 0) { return id; }
            var row = b.types[id];
            if row.tag == TY_PARAM { let bound = binding(environment, row.binder); if bound.type_id == 0 || bound.type_id == id { fail(); } return shape(bound.type_id, environment, depth + 1); }
            if row.tag == TY_ALIAS { return shape(b.refs[row.children.start], environment, depth + 1); }
            if row.tag == TY_FORALL { fail(); }
            if row.tag == TY_FN { row.region = 0; }
            if row.region != 0 { fail(); }
            row.nat = term(row.nat, environment, 0, 0, depth + 1); row.capacity = term(row.capacity, environment, 0, 0, depth + 1);
            let mark = scratch.len; for i in row.children.count { scratch.push(shape(b.refs[row.children.start + i], environment, depth + 1)); }
            row.children = ref_span(b, scratch[mark..]); scratch.resize(mark);
            for i in row.fields.count { var field = b.fields[b.refs[row.fields.start + i]]; field.type_id = shape(field.type_id, environment, depth + 1); scratch.push(b.fields.len as u32); b.fields.push(field); }
            row.fields = ref_span(b, scratch[mark..]); scratch.resize(mark);
            if row.contract != 0 {
                let old = row.contract; var ct = b.contracts[old]; if ct.binders.count != 0 { fail(); }
                let next = b.contracts.len as u32; b.contracts.push(Contract { .. });
                ct.arg = shape(ct.arg, environment, depth + 1); ct.result = shape(ct.result, environment, depth + 1);
                ct.requires = facts(ct.requires, environment, old, next, depth + 1); ct.ensures = facts(ct.ensures, environment, old, next, depth + 1);
                ct.on_true = facts(ct.on_true, environment, old, next, depth + 1); ct.on_false = facts(ct.on_false, environment, old, next, depth + 1);
                for i in ct.effects.count { let effect = b.effects[b.refs[ct.effects.start + i]]; if effect.region != 0 { fail(); } }
                for i in ct.layout_premises.count { var premise = b.layout_premises[b.refs[ct.layout_premises.start + i]]; premise.type_id = shape(premise.type_id, environment, depth + 1); scratch.push(b.layout_premises.len as u32); b.layout_premises.push(premise); }
                ct.layout_premises = ref_span(b, scratch[mark..]); scratch.resize(mark); b.contracts[next] = ct; row.contract = next;
            }
            let result = b.types.len as u32; b.types.push(row); types.push(StaticTypeMemo { type_id: id, environment: environment, closed: result }); return result;
        }
        fn u32_type() -> u32 { for t, i in b.types { if i != 0 && t.tag == TY_U32 { return i as u32; } } let id = b.types.len as u32; b.types.push(TypeNode { tag: TY_U32, .. }); return id; }
        recursive fn close(value: StaticValue, depth: u32) -> StaticValue {
            visit(); if depth > 64 { fail(); } var result = value;
            for index in value.count {
                visit(); if value.kinds[index] != STATIC_LOCAL_CLOSURE { continue; }
                let eid = value.targets[index]; if !id_ok(eid, environments.len) || index + 1 >= value.count { fail(); }
                let env = environments[eid]; let function = b.functions[env.function]; let constructor = b.ops[env.constructor];
                var adapter: u32 = 0; for row, i in b.callable_adapters { if i != 0 && row.op == env.constructor { adapter = i as u32; break; } }
                var environment = materialized[eid];
                if environment == 0 {
                    var image = StaticValue { .. }; let mark = scratch.len; let unsigned = u32_type();
                    var target_offset: u32 = 0;
                    if adapter != 0 {
                        let descriptor = b.callable_adapters[adapter];
                        for i in descriptor.captures.count {
                            let capture = b.adapter_captures[b.refs[descriptor.captures.start + i]]; visit(); if capture.offset != image.count * 4 || image.count == 64 { fail(); }
                            scratch.push(unsigned);
                            if capture.kind == KIND_TYPE { image.kinds[image.count] = STATIC_DICTIONARY; image.targets[image.count] = shape(capture.source, eid, 0); }
                            else if capture.kind == KIND_NAT { let tid = term(capture.source, eid, 0, 0, 0); if b.terms[tid].tag != EXPR_LITERAL { fail(); } image.words[image.count] = b.terms[tid].literal; }
                            else { fail(); } image.count++;
                        }
                        target_offset = descriptor.target_environment_offset;
                        if target_offset != image.count * 4 { fail(); }
                    }
                    {
                        for i in function.environment_bindings.count {
                            let capture = b.environment_bindings[b.refs[function.environment_bindings.start + i]]; visit(); if target_offset + capture.offset != image.count * 4 || image.count == 64 { fail(); }
                            let bound = binding(eid, capture.binder); scratch.push(unsigned);
                            if capture.kind == KIND_TYPE { if bound.type_id == 0 { fail(); } image.kinds[image.count] = STATIC_DICTIONARY; image.targets[image.count] = shape(bound.type_id, eid, 0); }
                            else if capture.kind == KIND_NAT { if !bound.has_nat { fail(); } image.words[image.count] = bound.nat; }
                            else { fail(); } image.count++;
                        }
                        if env.captures.count != function.captures.count { fail(); }
                        for i in env.captures.count {
                            let capture = b.captures[b.refs[function.captures.start + i]]; let nested = close(captures[env.captures.start + i], depth + 1);
                            if nested.count > 64 - image.count { fail(); } static_insert(image, image.count, nested); scratch.push(shape(b.values[capture.value].type_id, eid, 0));
                        }
                    }
                    let ty = b.types.len as u32; b.types.push(TypeNode { tag: TY_TUPLE, children: ref_span(b, scratch[mark..]), .. }); scratch.resize(mark);
                    let id, ok = static_publish(b, STATIC_ENVIRONMENT, ty, 0, 1, 0, [image], producer, stats, diagnostics); if !ok { return StaticValue { .. }, false from finish; }
                    b.static_objects[id].function = env.function; b.static_objects[id].constructor = env.constructor; materialized[eid] = id; environment = id;
                }
                result.kinds[index] = STATIC_CLOSURE; result.targets[index] = env.constructor; result.addends[index] = environment;
                result.words[index] = 0; result.words[index + 1] = 0;
                if b.static_objects[environment].bytes.count != 0 { result.kinds[index + 1] = STATIC_ADDRESS; result.targets[index + 1] = environment; result.addends[index + 1] = 0; }
            }
            return result;
        }
        return close(value, 0), true;
    }
    return static_evaluate_at_depth(core_view(b), function_id, argument, stats, diagnostics, 0, finish);
}
