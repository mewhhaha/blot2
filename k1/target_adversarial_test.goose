// Hand-built transient backend fixtures only. The synthetic source text is not
// a source-language admission test; it exercises structural fences and Wasm.
import module_core;
import module_wasm;
import wasm;
import os;
import std;

fn require(ok: bool, message: u8[:]) { if !ok { abort(str("module wasm test: ", message)); } }
fn add(src: u8[>..]&, name: u8[:], mode: i64, target: u8[:], target_id: i64,
       literal: u32, depth: i64) -> module_core::Function {
    var f = module_core::Function {};
    f.declaration_start = src.len;
    f.name_start = src.len; src.append(name); f.name_end = src.len;
    f.function_start = src.len; src.push('(');
    f.parameter_start = src.len; src.push('x'); f.parameter_end = src.len;
    src.append(") "); f.return_start = src.len; src.append("return ");
    f.expression_start = src.len;
    f.values[0] = module_core::Value { producer: 1, type_id: 1 };
    f.value_count = 1; f.result_type = 1; f.terminator = 1; f.depth = depth;
    if mode == 0 {
        f.left_start = src.len; src.push('x'); f.left_end = src.len;
        f.result_id = 0;
    } else if mode == 1 || mode == 2 {
        f.callee_start = src.len; src.append(target); f.callee_end = src.len; src.push('(');
        f.left_start = src.len;
        var argument: i64 = 0;
        if mode == 1 { src.push('x'); }
        else {
            format(src, literal);
            argument = 1;
            f.values[1] = module_core::Value { producer: 2, type_id: 1, literal: literal };
            f.value_count += 1;
        }
        f.left_end = src.len; src.push(')');
        f.result_id = f.value_count;
        f.values[f.result_id] = module_core::Value { producer: 4, type_id: 1,
            left_id: argument, callee_id: target_id };
        f.value_count += 1;
    } else {
        f.left_start = src.len; src.push('x'); f.left_end = src.len;
        src.push(' '); f.operator_start = src.len; src.push('&'); f.operator_end = src.len;
        src.push(' '); f.right_start = src.len; format(src, literal); f.right_end = src.len;
        f.values[1] = module_core::Value { producer: 2, type_id: 1, literal: literal };
        f.values[2] = module_core::Value { producer: 3, type_id: 1, op_id: 1, right_id: 1 };
        f.result_id = 2; f.value_count = 3;
    }
    f.expression_end = src.len; f.declaration_end = src.len; src.push('\n');
    return f;
}
fn many(count: i64, chain: bool) -> module_core::ModuleCore {
    var source: u8[>..] = [];
    var functions: module_core::Function[>..] = [];
    for i in count {
        let name = str("f", i);
        if chain && i + 1 < count {
            let target = str("f", i + 1);
            functions.push(add(source, name, 1, target, i + 1, 0, count - i));
        } else { functions.push(add(source, name, 0, "", 0, 0, 1)); }
    }
    return module_core::ModuleCore { source: copy(source), functions: copy(functions) };
}
fn cycle(count: i64) -> module_core::ModuleCore {
    var source: u8[>..] = [];
    var functions: module_core::Function[>..] = [];
    for i in count {
        let name = str("f", i);
        let next = (i + 1) % count;
        let target = str("f", next);
        functions.push(add(source, name, 1, target, next, 0, 1));
    }
    return module_core::ModuleCore { source: copy(source), functions: copy(functions) };
}
fn reference_structural(core: module_core::ModuleCore&) -> bool {
    let count = core.functions.len;
    if core.source.len > 16777216 || count < 1 || count > 256 { return false; }
    for f in core.functions {
        if !wasm_v3::valid_function(f, core.source.len, count) { return false; }
        if !wasm::identifier(core.source[f.name_start..f.name_end]) { return false; }
    }
    for f, i in core.functions {
        for j in 0..i {
            let earlier = core.functions[j];
            if core.source[f.name_start..f.name_end] == core.source[earlier.name_start..earlier.name_end] { return false; }
        }
        let value = f.values[f.result_id];
        if value.producer == 4 {
            let target = core.functions[value.callee_id];
            if core.source[f.callee_start..f.callee_end] != core.source[target.name_start..target.name_end] { return false; }
        }
        // Walk the sole-call chain afresh. This bounds work to 256 * 128,
        // rejects cycles and checks the exact depth of each declaration.
        var current = i;
        var depth: i64 = 1;
        loop {
            let cur = core.functions[current];
            let last = cur.values[cur.result_id];
            if last.producer != 4 { break; }
            if depth >= 128 { return false; }
            current = last.callee_id;
            depth += 1;
        }
        if depth != f.depth { return false; }
    }
    return true;
}
fn next(seed: u32&) -> u32 { seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5; return seed; }
fn main() {
    var seed: u32 = 0x5e73ac91;
    for iteration in 800 {
        let count = (next(seed) % 256 + 1) as i64;
        var links: i64[256] = [-1; 256];
        var depths: i64[256] = [1; 256];
        var j = count;
        while j > 0 {
            j -= 1;
            if j + 1 < count && next(seed) % 4 != 0 {
                links[j] = j + 1 + (next(seed) % ((count - j - 1) as u32));
                depths[j] = depths[links[j]] + 1;
            }
        }
        var source: u8[>..] = [];
        var functions: module_core::Function[>..] = [];
        for i in count {
            // Permuted numeric suffixes challenge sorting independently of function order.
            let name = str("commonprefix", (i * 73) % 257);
            if links[i] < 0 { functions.push(add(source, name, 0, "", 0, 0, 1)); }
            else {
                let target = str("commonprefix", (links[i] * 73) % 257);
                functions.push(add(source, name, 1, target, links[i], 0, depths[i]));
            }
        }
        var core = module_core::ModuleCore { source: copy(source), functions: copy(functions) };
        assert(reference_structural(core) && wasm_v3::structural(core));
        let index = (next(seed) % (count as u32)) as i64;
        core.functions[index].depth += 1;
        assert(wasm_v3::structural(core) == reference_structural(core));
        assert(!wasm_v3::structural(core));
    }
    for count in [1, 2, 128, 129, 255, 256] {
        var leaves = many(count, false);
        assert(wasm_v3::structural(leaves) == reference_structural(leaves));
        var cyclic = cycle(count);
        assert(!reference_structural(cyclic) && !wasm_v3::structural(cyclic));
    }
    // Compare exact source names, not hashes or the producer's index.
    var source: u8[>..] = [];
    var functions: module_core::Function[>..] = [];
    for i in 256 { functions.push(add(source, str("prefix", (i * 73) % 257), 0, "", 0, 0, 1)); }
    var core = module_core::ModuleCore { source: copy(source), functions: copy(functions) };
    assert(wasm_v3::target_unique_names(core));
    for i in 1..256 {
        let saved = core.functions[i];
        let prior = (i * 73 + 19) % i;
        core.functions[i].name_start = core.functions[prior].name_start;
        core.functions[i].name_end = core.functions[prior].name_end;
        assert(!wasm_v3::target_unique_names(core));
        core.functions[i] = saved;
    }
    core.functions[5].name_start = -1;
    assert(!wasm_v3::target_unique_names(core));
    print("target structural adversarial tests passed");
}
