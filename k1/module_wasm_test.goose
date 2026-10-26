// Hand-built transient backend fixtures only. The synthetic source text is not
// a source-language admission test; it exercises structural fences and Wasm.
import module_core;
import module_wasm;
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
fn main() {
    var source: u8[>..] = [];
    var functions: module_core::Function[>..] = [];
    functions.push(add(source, "forward", 1, "leaf", 2, 0, 2));
    functions.push(add(source, "literal", 2, "leaf", 2, 4294967295, 2));
    functions.push(add(source, "leaf", 0, "", 0, 0, 1));
    functions.push(add(source, "backward", 1, "forward", 0, 0, 3));
    functions.push(add(source, "mask", 3, "", 0, 2147483648, 1));
    var core = module_core::ModuleCore { source: copy(source), functions: copy(functions) };
    require(module_core::validate(core) == 0 && wasm_v3::structural(core), "fixture structure");
    let image = wasm_v3::emit_module(core);
    require(image.len > 0 && write_file("module_v3.wasm", image), "emit module");
    { var bad = copy(core); bad.functions[0].values[1].callee_id = 256;
      require(wasm_v3::emit_module(bad).len == 0, "invalid callee"); }
    { var bad = copy(core); bad.functions[0].depth = 1;
      require(wasm_v3::emit_module(bad).len == 0, "forged depth"); }
    { var bad = copy(core); bad.functions[0].frame = 1;
      require(wasm_v3::emit_module(bad).len == 0, "forged frame"); }
    { var bad = copy(core); bad.functions[0].name_end = 99999999;
      require(wasm_v3::emit_module(bad).len == 0, "invalid name span"); }
    { var bad = copy(core); bad.functions[0].values[3].producer = 1;
      require(wasm_v3::emit_module(bad).len == 0, "unused forged value"); }
    { var bad = copy(core); bad.functions[0].values[1].left_id = 1;
      require(wasm_v3::emit_module(bad).len == 0, "forward value reference"); }
    { var bad = copy(core); bad.functions[0].values[1].callee_id = 0;
      require(wasm_v3::emit_module(bad).len == 0, "cycle and mismatched target"); }
    { var bad = copy(core); bad.functions[4].values[2].op_id = 2;
      require(wasm_v3::emit_module(bad).len == 0, "unknown operation"); }
    var max_depth = many(128, true);
    require(wasm_v3::emit_module(max_depth).len > 0, "depth 128 accepted");
    require(write_file("module_chain.wasm", wasm_v3::emit_module(max_depth)), "write chain");
    var over_depth = many(129, true);
    require(wasm_v3::emit_module(over_depth).len == 0, "depth 129 rejected");
    var max_count = many(256, false);
    require(wasm_v3::emit_module(max_count).len > 0, "256 declarations accepted");
    require(write_file("module_many.wasm", wasm_v3::emit_module(max_count)), "write many");
    var over_count = many(257, false);
    require(wasm_v3::emit_module(over_count).len == 0, "257 declarations rejected");
    var self_cycle = cycle(1);
    require(module_core::validate(self_cycle) == 8 && wasm_v3::emit_module(self_cycle).len == 0, "self recursion rejected");
    var mutual_cycle = cycle(2);
    require(module_core::validate(mutual_cycle) == 8 && wasm_v3::emit_module(mutual_cycle).len == 0, "mutual recursion rejected");
    print("module Wasm structural tests passed");
}
