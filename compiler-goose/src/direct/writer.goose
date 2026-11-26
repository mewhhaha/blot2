// Lean Wasm module writer (compiler/src/direct/writer.zig). Function bodies
// are encoded straight to bytes by the emitter; this owner only lays out
// sections around them.
namespace blot_direct_writer;
import direct.relocations;
import std;
import support.error;

type ValType = u8;
let VT_i32: ValType = 0x7f;
let VT_i64: ValType = 0x7e;
let VT_f32: ValType = 0x7d;
let VT_f64: ValType = 0x7c;
let VT_v128: ValType = 0x7b;
let VT_funcref: ValType = 0x70;
let VT_externref: ValType = 0x6f;

// Opcodes used by the direct backend.
type Op = u8;
let OP_unreachable_: Op = 0x00;
let OP_nop: Op = 0x01;
let OP_block: Op = 0x02;
let OP_loop: Op = 0x03;
let OP_if_: Op = 0x04;
let OP_else_: Op = 0x05;
let OP_end: Op = 0x0b;
let OP_br: Op = 0x0c;
let OP_br_if: Op = 0x0d;
let OP_br_table: Op = 0x0e;
let OP_return_: Op = 0x0f;
let OP_call: Op = 0x10;
let OP_call_indirect: Op = 0x11;
let OP_return_call: Op = 0x12;
let OP_return_call_indirect: Op = 0x13;

var opt_test_mode: bool = false;
fn testModeEnabled() -> bool { return opt_test_mode; }
fn setTestMode(enabled: bool) { opt_test_mode = enabled; }

var opt_emit_workers: u8 = 1;
fn emitWorkers() -> u8 { return opt_emit_workers; }
fn setEmitWorkers(workers: u8) { opt_emit_workers = workers; }

// Opt-in Wasm 3.0 backend feature toggles (default false: strict deterministic V8 + wtime-aot x64 subset).
var opt_relaxed_simd: bool = false;
var opt_tail_calls: bool = false;
fn relaxedSimdEnabled() -> bool { return opt_relaxed_simd; }
fn tailCallsEnabled() -> bool { return opt_tail_calls; }
fn setWasmFeatures(relaxed_simd: bool, tail_calls: bool) {
    opt_relaxed_simd = relaxed_simd;
    opt_tail_calls = tail_calls;
}
let OP_drop: Op = 0x1a;
let OP_select: Op = 0x1b;
let OP_local_get: Op = 0x20;
let OP_local_set: Op = 0x21;
let OP_local_tee: Op = 0x22;
let OP_global_get: Op = 0x23;
let OP_global_set: Op = 0x24;
let OP_table_get: Op = 0x25;
let OP_table_set: Op = 0x26;
let OP_i32_load: Op = 0x28;
let OP_f32_load: Op = 0x2a;
let OP_i32_load8_u: Op = 0x2d;
let OP_i32_store: Op = 0x36;
let OP_f32_store: Op = 0x38;
let OP_i32_store8: Op = 0x3a;
let OP_memory_size: Op = 0x3f;
let OP_memory_grow: Op = 0x40;
let OP_i32_const: Op = 0x41;
let OP_f32_const: Op = 0x43;
let OP_i32_eqz: Op = 0x45;
let OP_i32_eq: Op = 0x46;
let OP_i32_ne: Op = 0x47;
let OP_i32_lt_s: Op = 0x48;
let OP_i32_lt_u: Op = 0x49;
let OP_i32_gt_s: Op = 0x4a;
let OP_i32_gt_u: Op = 0x4b;
let OP_i32_le_s: Op = 0x4c;
let OP_i32_le_u: Op = 0x4d;
let OP_i32_ge_s: Op = 0x4e;
let OP_i32_ge_u: Op = 0x4f;
let OP_f32_eq: Op = 0x5b;
let OP_f32_ne: Op = 0x5c;
let OP_f32_lt: Op = 0x5d;
let OP_f32_gt: Op = 0x5e;
let OP_f32_le: Op = 0x5f;
let OP_f32_ge: Op = 0x60;
let OP_i32_clz: Op = 0x67;
let OP_i32_add: Op = 0x6a;
let OP_i32_sub: Op = 0x6b;
let OP_i32_mul: Op = 0x6c;
let OP_i32_div_s: Op = 0x6d;
let OP_i32_div_u: Op = 0x6e;
let OP_i32_rem_s: Op = 0x6f;
let OP_i32_rem_u: Op = 0x70;
let OP_i32_and: Op = 0x71;
let OP_i32_or: Op = 0x72;
let OP_i32_xor: Op = 0x73;
let OP_i32_shl: Op = 0x74;
let OP_i32_shr_s: Op = 0x75;
let OP_i32_shr_u: Op = 0x76;
let OP_f32_abs: Op = 0x8b;
let OP_f32_neg: Op = 0x8c;
let OP_f32_ceil: Op = 0x8d;
let OP_f32_floor: Op = 0x8e;
let OP_f32_trunc: Op = 0x8f;
let OP_f32_nearest: Op = 0x90;
let OP_f32_sqrt: Op = 0x91;
let OP_f32_add: Op = 0x92;
let OP_f32_sub: Op = 0x93;
let OP_f32_mul: Op = 0x94;
let OP_f32_div: Op = 0x95;
let OP_f32_min: Op = 0x96;
let OP_f32_max: Op = 0x97;
let OP_f32_convert_i32_s: Op = 0xb2;
let OP_f32_convert_i32_u: Op = 0xb3;
let OP_i32_reinterpret_f32: Op = 0xbc;
let OP_f32_reinterpret_i32: Op = 0xbe;
let OP_ref_null: Op = 0xd0;
let OP_prefix_fc: Op = 0xfc;
let OP_prefix_fd: Op = 0xfd;

// Every function appends to the caller's byte array.
fn byte(bytes: u8[>..<]&, value: u8) { bytes.push(value); }
fn raw(bytes: u8[>..<]&, value: const u8[:]) { bytes.append(value); }
fn uleb(bytes: u8[>..<]&, value: u64) {
    if value < 128 { bytes.push(value as! u8); return; }
    var rest = value;
    loop {
        let low = (rest & 127) as! u8; rest >>= 7;
        if rest == 0 { byte(bytes, low); return; }
        byte(bytes, low | 128);
    }
}
fn sleb(bytes: u8[>..<]&, value: i64) {
    if value >= -64 && value < 64 { bytes.push(((value as! u64) & 127) as! u8); return; }
    var rest = value;
    loop {
        let low = ((rest as! u64) & 127) as! u8; rest >>= 7;
        let done = (rest == 0 && (low & 64) == 0) || (rest == -1 && (low & 64) != 0);
        if done { byte(bytes, low); return; }
        byte(bytes, low | 128);
    }
}
fn ulebLen(value: u64) -> i64 {
    if value < 128 { return 1; }
    var rest = value >> 7;
    var n: i64 = 1;
    while rest != 0 { n += 1; rest >>= 7; }
    return n;
}
fn name(bytes: u8[>..<]&, value: const u8[:]) { uleb(bytes, value.len as! u64); raw(bytes, value); }
// The four bytes of a 32-bit value, least significant first.
fn word(bytes: u8[>..<]&, value: u32) {
    bytes.push(value as! u8);
    bytes.push((value >> 8) as! u8);
    bytes.push((value >> 16) as! u8);
    bytes.push((value >> 24) as! u8);
}

// A run of `Module.text` or `Module.types`.
struct Range { start: i64 = 0, len: i64 = 0 }
// `next` chains the signatures of one hash bucket, as an ordinal plus one.
struct Signature { params: Range, results: Range, next: u32 = 0 }
struct Import { module: Range, name: Range, signature: u32 = 0 }
struct Global { ty: ValType = 0x7f, mutable: bool = false, init: u32 = 0 }
type ExportKind = u8;
let EXPORT_function: ExportKind = 0;
let EXPORT_table: ExportKind = 1;
let EXPORT_memory: ExportKind = 2;
let EXPORT_global: ExportKind = 3;
struct Export { name: Range, kind: ExportKind = 0, index: u32 = 0 }
// A defined function: its signature and complete encoded body (locals + code).
struct Function { signature: u32 = 0, body: Range }
struct Custom { name: Range, payload: Range }
// A function's name for the standard `name` section.
struct FunctionName { present: bool = false, text: Range }

let signature_buckets = 1024;

root struct Module {
    // Parameter and result types of every signature.
    types: ValType[>..] = [],
    // Names, function bodies and custom payloads.
    text: u8[>..] = [],
    signatures: Signature[>..] = [],
    signature_heads: u32[signature_buckets] = [0; signature_buckets],
    imports: Import[>..] = [],
    functions: Function[>..<] = [],
    globals: Global[>..] = [],
    exports: Export[>..] = [],
    // Function indices (import-relative) stored in table 0, slot = position.
    table: u32[>..] = [],
    // Externref slots for host callbacks (table 1); zero when unused.
    host_slots: u32 = 0,
    has_memory: bool = false,
    memory_pages: u32 = 0,
    memory_max_pages: u32 = 0,
    // The start function (exported constants are computed there).
    has_start: bool = false,
    start: u32 = 0,
    data_offset: u32 = 0,
    data: u8[>..<] = [],
    customs: Custom[>..] = [],
    // Function names by function index.
    names: FunctionName[>..<] = [],
    named: i64 = 0,
    // Speculative parallel wave guard (never serialized).
    readonly: bool = false,
    readonly_hit: bool = false
}

fn own(module: Module&, value: const u8[:]) -> Range {
    let result = Range { start: module.text.len, len: value.len };
    module.text.append(value);
    return result;
}
fn text(module: const Module&, range: Range) -> const u8[:] { module.text[range.start..range.start + range.len] }
fn types(module: const Module&, range: Range) -> const ValType[:] { module.types[range.start..range.start + range.len] }
fn same(left: const u8[:], right: const u8[:]) -> bool {
    if left.len != right.len { return false; }
    for value, index in left { if value != right[index] { return false; } }
    return true;
}
fn bucket(params: const ValType[:], results: const ValType[:]) -> i64 {
    var hash: u64 = 1469598103934665603;
    for value in params { hash = (hash ^ value) * 1099511628211; }
    hash = (hash ^ 255) * 1099511628211;
    for value in results { hash = (hash ^ value) * 1099511628211; }
    return (hash % signature_buckets) as! i64;
}
fn findSignature(module: const Module&, params: const ValType[:], results: const ValType[:]) -> u32, bool {
    let home = bucket(params, results);
    var at = module.signature_heads[home];
    while at != 0 {
        let known = module.signatures[at - 1];
        if same(types(module, known.params), params) && same(types(module, known.results), results) {
            return at - 1, true;
        }
        at = known.next;
    }
    return 0, false;
}
// The index of the signature with these types, added when it is new.
fn signature(module: Module&, params: const ValType[:], results: const ValType[:]) -> u32 {
    let home = bucket(params, results);
    var at = module.signature_heads[home];
    while at != 0 {
        let known = module.signatures[at - 1];
        if same(types(module, known.params), params) && same(types(module, known.results), results) {
            return at - 1;
        }
        at = known.next;
    }
    if module.readonly { module.readonly_hit = true; return 0; }
    let id = module.signatures.len as! u32;
    let owned_params = Range { start: module.types.len, len: params.len };
    module.types.append(params);
    let owned_results = Range { start: module.types.len, len: results.len };
    module.types.append(results);
    module.signatures.push(Signature { params: owned_params, results: owned_results, next: module.signature_heads[home] });
    module.signature_heads[home] = id + 1;
    return id;
}
// Imports precede defined functions in the index space; add them first.
fn importFunction(module: Module&, from: const u8[:], member: const u8[:], signature_id: u32) -> u32 {
    if module.readonly { module.readonly_hit = true; return 0; }
    assert(module.functions.len == 0);
    let id = module.imports.len as! u32;
    let owned_module = own(module, from);
    let owned_name = own(module, member);
    module.imports.push(Import { module: owned_module, name: owned_name, signature: signature_id });
    return id;
}
// Reserves a defined function; its body is supplied later.
fn addFunction(module: Module&, signature_id: u32) -> u32 {
    if module.readonly { module.readonly_hit = true; return 0; }
    let id = (module.imports.len + module.functions.len) as! u32;
    module.functions.push(Function { signature: signature_id, body: Range {} });
    return id;
}
fn setBody(module: Module&, function: u32, body: const u8[:]) {
    if module.readonly { module.readonly_hit = true; return; }
    let owned = own(module, body);
    module.functions[function - module.imports.len].body = owned;
}
fn addGlobal(module: Module&, ty: ValType, mutable: bool, init_value: u32) -> u32 {
    if module.readonly { module.readonly_hit = true; return 0; }
    let id = module.globals.len as! u32;
    module.globals.push(Global { ty: ty, mutable: mutable, init: init_value });
    return id;
}
fn exportItem(module: Module&, exported: const u8[:], kind: ExportKind, index: u32) {
    if module.readonly { module.readonly_hit = true; return; }
    let owned = own(module, exported);
    module.exports.push(Export { name: owned, kind: kind, index: index });
}
fn tableSlot(module: Module&, function: u32) -> u32 {
    if module.readonly { module.readonly_hit = true; return 0; }
    let slot = module.table.len as! u32;
    module.table.push(function);
    return slot;
}
fn custom(module: Module&, section_name: const u8[:], payload: const u8[:]) {
    if module.readonly { module.readonly_hit = true; return; }
    let owned_name = own(module, section_name);
    let owned_payload = own(module, payload);
    module.customs.push(Custom { name: owned_name, payload: owned_payload });
}
fn setName(module: Module&, function: u32, value: const u8[:]) {
    if module.readonly { module.readonly_hit = true; return; }
    let owned = own(module, value);
    while module.names.len <= function { module.names.push(FunctionName { present: false, text: Range {} }); }
    if !module.names[function as i64].present { module.named += 1; }
    module.names[function as i64] = FunctionName { present: true, text: owned };
}

fn section(out: u8[>..<]&, id: u8, payload: u8[>..<]&) {
    byte(out, id);
    uleb(out, payload.len as! u64);
    raw(out, payload[..]);
    payload.clear();
}
// Appends the whole module to `out`.
fn assemble(module: const Module&, out: u8[>..<]&) {
    var payload: u8[>..<] = [];
    raw(out, [0 as u8, 97, 115, 109, 1, 0, 0, 0]);
    // 1: types
    uleb(payload, module.signatures.len as! u64);
    for sig in module.signatures {
        byte(payload, 0x60);
        uleb(payload, sig.params.len as! u64);
        raw(payload, types(module, sig.params));
        uleb(payload, sig.results.len as! u64);
        raw(payload, types(module, sig.results));
    }
    section(out, 1, payload);
    // 2: imports
    if module.imports.len != 0 {
        uleb(payload, module.imports.len as! u64);
        for item in module.imports {
            name(payload, text(module, item.module));
            name(payload, text(module, item.name));
            byte(payload, 0);
            uleb(payload, item.signature);
        }
        section(out, 2, payload);
    }
    // 3: functions
    uleb(payload, module.functions.len as! u64);
    for function in module.functions { uleb(payload, function.signature); }
    section(out, 3, payload);
    // 4: tables (0: closures, 1: host callbacks)
    if module.table.len != 0 || module.host_slots != 0 {
        uleb(payload, 2);
        byte(payload, VT_funcref);
        byte(payload, 1);
        uleb(payload, module.table.len as! u64);
        uleb(payload, module.table.len as! u64);
        byte(payload, VT_externref);
        byte(payload, 1);
        uleb(payload, module.host_slots);
        uleb(payload, module.host_slots);
        section(out, 4, payload);
    }
    // 5: memory (min = memory_pages, max = memory_max_pages or memory_pages)
    if module.has_memory {
        uleb(payload, 1);
        byte(payload, 1);
        uleb(payload, module.memory_pages);
        var max_pages = module.memory_max_pages;
        if max_pages == 0 { max_pages = module.memory_pages; }
        uleb(payload, max_pages);
        section(out, 5, payload);
    }
    // 6: globals
    if module.globals.len != 0 {
        uleb(payload, module.globals.len as! u64);
        for global in module.globals {
            byte(payload, global.ty);
            byte(payload, if global.mutable { 1 } else { 0 });
            if global.ty == VT_f32 {
                byte(payload, OP_f32_const);
                word(payload, global.init);
            } else {
                byte(payload, OP_i32_const);
                sleb(payload, global.init as! i32);
            }
            byte(payload, OP_end);
        }
        section(out, 6, payload);
    }
    // 7: exports
    uleb(payload, module.exports.len as! u64);
    for item in module.exports {
        name(payload, text(module, item.name));
        byte(payload, item.kind);
        uleb(payload, item.index);
    }
    section(out, 7, payload);
    // 8: start
    if module.has_start {
        uleb(payload, module.start);
        section(out, 8, payload);
    }
    // 9: elements (table 0, offset 0, function indices)
    if module.table.len != 0 {
        uleb(payload, 1);
        byte(payload, 0);
        byte(payload, OP_i32_const);
        sleb(payload, 0);
        byte(payload, OP_end);
        uleb(payload, module.table.len as! u64);
        for function in module.table { uleb(payload, function); }
        section(out, 9, payload);
    }
    // 10: code — stream bodies directly into `out` (avoids double-copying multi-MB code sections).
    var code_size: i64 = ulebLen(module.functions.len as! u64);
    for function in module.functions {
        code_size += ulebLen(function.body.len as! u64) + function.body.len;
    }
    byte(out, 10);
    uleb(out, code_size as! u64);
    let code_start = out.len;
    uleb(out, module.functions.len as! u64);
    for function in module.functions {
        uleb(out, function.body.len as! u64);
        blot_direct_relocations::linkBody(function.body.start, out.len - code_start);
        raw(out, text(module, function.body));
    }
    blot_direct_relocations::finishCode(code_start);
    // 11: data
    if module.data.len != 0 {
        uleb(payload, 1);
        byte(payload, 0);
        byte(payload, OP_i32_const);
        sleb(payload, module.data_offset as! i32);
        byte(payload, OP_end);
        uleb(payload, module.data.len as! u64);
        raw(payload, module.data[..]);
        section(out, 11, payload);
    }
    for item in module.customs {
        name(payload, text(module, item.name));
        raw(payload, text(module, item.payload));
        section(out, 0, payload);
    }
    if module.named != 0 {
        var map: u8[>..<] = [];
        uleb(map, module.named as! u64);
        for entry, index in module.names {
            if entry.present {
                uleb(map, index as! u64);
                name(map, text(module, entry.text));
            }
        }
        name(payload, "name");
        byte(payload, 1);
        uleb(payload, map.len as! u64);
        raw(payload, map[..]);
        section(out, 0, payload);
    }
}
