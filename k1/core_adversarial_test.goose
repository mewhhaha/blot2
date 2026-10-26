import module_core;

// Build test records in declaration order with real, non-overlapping spans.
// This is not a parser and is not evidence of source completion.
fn append(source: u8[>..]&, functions: module_core::Function[>..]&, number: i64, callee: i64, depth: i64) {
    var f = module_core::Function { depth: depth, result_type: 1, terminator: 1 };
    f.declaration_start = source.len;
    source.append("let ");
    f.name_start = source.len; source.append(str("f", number)); f.name_end = source.len;
    source.append(": U32 -> U32 = ");
    f.function_start = source.len; source.append("fn ");
    f.parameter_start = source.len; source.append("x"); f.parameter_end = source.len;
    source.append(" => "); f.return_start = source.len; source.append("return ");
    f.expression_start = source.len;
    f.values[0] = module_core::Value { producer: 1, type_id: 1 };
    if callee >= 0 {
        f.callee_start = source.len; source.append(str("f", callee)); f.callee_end = source.len;
        source.append("("); f.left_start = source.len; source.append("x"); f.left_end = source.len;
        source.append(")");
        f.values[1] = module_core::Value { producer: 4, type_id: 1, callee_id: callee };
        f.value_count = 2; f.result_id = 1;
    } else if callee == -2 {
        f.left_start = source.len; source.append("x"); f.left_end = source.len;
        source.append(" "); f.operator_start = source.len; source.append("&"); f.operator_end = source.len;
        source.append(" "); f.right_start = source.len; source.append("x"); f.right_end = source.len;
        f.values[1] = module_core::Value { producer: 3, type_id: 1, op_id: 1 };
        f.value_count = 2; f.result_id = 1;
    } else if callee == -3 {
        f.left_start = source.len; source.append("4294967295"); f.left_end = source.len;
        f.values[1] = module_core::Value { producer: 2, type_id: 1, literal: 4294967295 };
        f.value_count = 2; f.result_id = 1;
    } else {
        f.left_start = source.len; source.append("x"); f.left_end = source.len;
        f.value_count = 1;
    }
    f.expression_end = source.len; f.declaration_end = source.len;
    source.append("\n"); functions.push(f);
}

fn chain(size: i64, cycle: bool) -> module_core::ModuleCore {
    var source: u8[>..] = [];
    var functions: module_core::Function[>..] = [];
    for i in size {
        let callee = if i + 1 < size { i + 1 } else if cycle { 0 } else { -1 };
        append(source, functions, i, callee, size - i);
    }
    return module_core::ModuleCore { source: source, functions: functions };
}
// Independent root-walk oracle, intentionally unlike the candidate's
// memoized analysis. Call only on structurally valid generated fixtures.
fn oracle(m: module_core::ModuleCore&, edges: i64[256]&) -> i64 {
    for f, i in m.functions {
        var seen: bool[256] = [false; 256];
        var current = i;
        var depth: i64 = 0;
        loop {
            if seen[current] { return 8; }
            seen[current] = true; depth += 1;
            if edges[current] < 0 { break; }
            current = edges[current];
        }
        if depth > 128 { return 9; }
        if f.depth != depth { return 1; }
    }
    return 0;
}
fn main() {
    var random: i64 = 19;
    for trial in 800 {
        random = (random * 48271) % 2147483647;
        let count = 1 + random % 256;
        var edges: i64[256] = [-1; 256];
        var source: u8[>..] = [];
        var functions: module_core::Function[>..] = [];
        for i in count {
            random = (random * 48271) % 2147483647;
            edges[i] = if random % 4 == 0 { -1 } else { random % count };
        }
        for i in count {
            var current = i;
            var seen: bool[256] = [false; 256];
            var depth: i64 = 0;
            loop {
                if seen[current] { depth = 42; break; }
                seen[current] = true; depth += 1;
                if edges[current] < 0 { break; }
                current = edges[current];
            }
            append(source, functions, i, edges[i], depth);
        }
        var m = module_core::ModuleCore { source: copy(source), functions: copy(functions) };
        assert(module_core::validate(m) == oracle(m, edges));
        random = (random * 48271) % 2147483647;
        let n = random % count;
        let saved = m.functions[n];
        m.functions[n].depth = -1;
        assert(module_core::validate(m) == oracle(m, edges));
        m.functions[n] = saved;
        m.functions[n].name_end = m.source.len + 1;
        assert(module_core::validate(m) == 1);
        m.functions[n] = saved;
        if saved.value_count == 2 {
            m.functions[n].values[1].callee_id = count;
            assert(module_core::validate(m) == 1);
            m.functions[n] = saved;
        }
    }
    // Earlier depth and mismatch must beat a later disconnected cycle.
    var source: u8[>..] = [];
    var functions: module_core::Function[>..] = [];
    for i in 130 { append(source, functions, i, if i < 128 { i + 1 } else if i == 129 { 129 } else { -1 }, 129 - i); }
    var m = module_core::ModuleCore { source: copy(source), functions: copy(functions) };
    assert(module_core::validate(m) == 9);
    m.functions[0].depth = 1;
    // A depth-129 path still takes precedence over its forged depth.
    assert(module_core::validate(m) == 9);
    var short_source: u8[>..] = [];
    var short_functions: module_core::Function[>..] = [];
    append(short_source, short_functions, 0, -1, 99);
    append(short_source, short_functions, 1, 1, 1);
    var disconnected = module_core::ModuleCore { source: copy(short_source), functions: copy(short_functions) };
    assert(module_core::validate(disconnected) == 1);
    disconnected.functions[0].depth = 1;
    assert(module_core::validate(disconnected) == 8);
    // Exercise heap construction with monotone and reversed names, then
    // replace the last same-length name with a far-apart duplicate.
    for reverse in 2 {
        var ns: u8[>..] = [];
        var fs: module_core::Function[>..] = [];
        for i in 256 { append(ns, fs, if reverse == 0 { i } else { 255 - i }, -1, 1); }
        var names = module_core::ModuleCore { source: copy(ns), functions: copy(fs) };
        assert(module_core::validate(names) == 0);
        var left: i64 = 0;
        var right: i64 = 0;
        var found = false;
        for i in 256 {
            for j in i {
                let a = names.functions[i];
                let b = names.functions[j];
                if !found && i - j > 100 && a.name_end - a.name_start == b.name_end - b.name_start {
                    left = j; right = i; found = true;
                }
            }
        }
        assert(found);
        let a = names.functions[left];
        let b = names.functions[right];
        for i in b.name_end - b.name_start { names.source[b.name_start + i] = names.source[a.name_start + i]; }
        assert(module_core::validate(names) == 1);
    }
    print("Core graph adversarial checks: passed");
}
