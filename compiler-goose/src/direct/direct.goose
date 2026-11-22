// Direct backend entry: one Wasm function per `(binding, concrete type)`
// instance reached from the entry module's exports, with fixed layouts and
// no cross-call analysis. See tasks/FAST_COMPILE.md.
//
// Port of compiler/src/direct/direct.zig. The generator's three stores
// (types, the Wasm module and the emitter state) are roots owned by
// `compile`; the Wasm bytes and a failure's message go to the caller's
// buffers.
namespace blot_direct;
import std;
import check.core;
import check.types;
import check.diagnostic_code;
import check.wire_schema;
import check.purity;
import direct.writer;
import direct.types;
import direct.emit;
import direct.function;

type Module = blot_check_core::Module;
type Body = blot_check_core::Body;
type Ty = u32;
type Error = blot_direct_types::Error;
type Generator = blot_direct_emit::Generator;
type Code = blot_check_diagnostic_code::Code;

// `failed`: `unit`, `span` and `code` describe the diagnostic and `message`
// holds its detail. Otherwise `bytes` holds the Wasm module.
struct Result { failed: bool = false, unit: u32 = 0, span: blot_check_core::Span = blot_check_core::Span { 0, 0 }, code: Code = blot_check_diagnostic_code::Code.storage_unsupported, emitted_functions: i64 = 0, sparks_vectorized: i64 = 0, sparks_scalar_fallback: i64 = 0 }

fn compile(units: const Module[:], entry: u32, bytes: u8[>..<]&, message: u8[>..<]&, build_inputs:i64 = -1) -> Result {
    var types = blot_direct_types::Types { units: units, .. };
    blot_direct_types::init(types);
    var module = blot_direct_writer::Module { .. };
    var state = blot_direct_emit::State { .. };
    return compileWith(units, entry, types, module, state, bytes, message, build_inputs);
}

fn compileTracked(units: const Module[:], entry: u32, types: blot_direct_types::Types&, module: blot_direct_writer::Module&, state: blot_direct_emit::State&, bytes: u8[>..<]&, message: u8[>..<]&, build_inputs:i64 = -1) -> Result {
    blot_direct_types::init(types);
    state.track_deps = true;
    return compileWith(units, entry, types, module, state, bytes, message, build_inputs);
}

fn compileWith(units: const Module[:], entry: u32, types: blot_direct_types::Types&, module: blot_direct_writer::Module&, state: blot_direct_emit::State&, bytes: u8[>..<]&, message: u8[>..<]&, build_inputs:i64 = -1) -> Result {
    var g = Generator { types: types, module: module, s: state, units: units, build_inputs:build_inputs };
    let error = build(g, entry, bytes);
    if error != blot_direct_types::Error.none {
        if !state.has_failure {
            message.append("Direct backend: unsupported program");
            return Result { failed: true, unit: entry };
        }
        let failure = state.failure;
        message.append(state.text[failure.message.start..failure.message.start + failure.message.len]);
        return Result { failed: true, unit: failure.unit, span: failure.span, code: failure.code };
    }
    return Result { emitted_functions: module.functions.len, sparks_vectorized: state.sparks_vectorized, sparks_scalar_fallback: state.sparks_scalar_fallback };
}

// Whether pool instance `left` initializes before `right`.
fn poolBefore(g: const Generator&, left: u32, right: u32) -> bool {
    let a = g.s.instances[left].key;
    let b = g.s.instances[right].key;
    if a.unit != b.unit { return a.unit < b.unit; }
    if a.id != b.id { return a.id < b.id; }
    return left < right;
}

fn build(g: Generator&, entry: u32, bytes: u8[>..<]&) -> Error {
    if !g.hasUnit(entry) { return blot_direct_types::Error.unsupported; }
    var pinfo = blot_check_wire_schema::ProgramInfo {};
    blot_check_wire_schema::analyze(g.units, entry, pinfo);
    if pinfo.issue.failed {
        var err_unit = pinfo.issue.unit;
        if !g.hasUnit(err_unit) { err_unit = entry; }
        return g.failSpanCode(err_unit, pinfo.issue.span, pinfo.issue.code, pinfo.issue.message);
    }
    g.s.kernels.append(pinfo.kernels[..]);
    g.s.processes.append(pinfo.processes[..]);
    g.s.wire_word_tags.append(pinfo.word_tags[..]);
    let pres = blot_check_purity::analyze(g.units, entry);
    if pres.issue.failed {
        var err_unit = pres.issue.unit;
        if !g.hasUnit(err_unit) { err_unit = entry; }
        return g.failSpanCode(err_unit, pres.issue.span, pres.issue.code, pres.issue.message);
    }
    let m .= g.units[entry - 1];
    var entries: u8[>..<] = [];
    var constants: u8[>..<] = [];
    var inits: u32[>..<] = [];
    var count: u32 = 0;
    // Host callback imports precede every defined function.
    for at in 0..m.bodies.len {
        if !m.bodies[at].exported { continue; }
        let parameter, has_parameter, error = exportedParameter(g, m, m.bodies[at]);
        if error != blot_direct_types::Error.none { return error; }
        if !has_parameter { continue; }
        let first, second, is_callback = blot_direct_function::callbackAbi(g, parameter);
        if is_callback { let import_id = blot_direct_function::hostImport(g, first, second); }
    }
    for at in 0..m.bodies.len {
        if !m.bodies[at].exported { continue; }
        let parameter, has_parameter, error = exportedParameter(g, m, m.bodies[at]);
        if error != blot_direct_types::Error.none { return error; }
        if !has_parameter { continue; }
        let emitted = blot_direct_function::emitExport(g, m, m.bodies[at], entries);
        if emitted != blot_direct_types::Error.none { return emitted; }
        count += 1;
    }
    for at in 0..m.bodies.len {
        if !m.bodies[at].exported { continue; }
        let parameter, has_parameter, error = exportedParameter(g, m, m.bodies[at]);
        if error != blot_direct_types::Error.none { return error; }
        if has_parameter { continue; }
        let init_function, error = blot_direct_function::emitConstantExport(g, m, m.bodies[at], constants);
        if error != blot_direct_types::Error.none { return error; }
        inits.push(init_function);
    }
    if count == 0 && inits.len == 0 && m.kernels.len == 0 && m.processes.len == 0 { return g.fail(m, 0, "the entry module exports nothing"); }
    let emitted = g.emitAll();
    if emitted != blot_direct_types::Error.none { return emitted; }
    var starts: u32[>..<] = [];
    var pools: u32[>..<] = [];
    for pool_id in g.s.pool_order { pools.push(pool_id); }
    // Insertion sort: a program reads few array constants.
    for at in 1..pools.len {
        let moved = pools[at];
        var hole = at;
        while hole > 0 && poolBefore(g, moved, pools[hole - 1]) {
            pools[hole] = pools[hole - 1];
            hole -= 1;
        }
        pools[hole] = moved;
    }
    if pools.len != 0 {
        let pool_function, error = blot_direct_function::poolInits(g, m, pools[..]);
        if error != blot_direct_types::Error.none { return error; }
        starts.push(pool_function);
    }
    for init_function in inits { starts.push(init_function); }
    if starts.len != 0 {
        let start_function = blot_direct_function::startFunction(g, m, starts[..]);
        g.module.start = start_function;
        g.module.has_start = true;
    }
    let failure, has_summary = g.summary();
    if has_summary {
        g.s.failure = failure;
        g.s.has_failure = true;
        return blot_direct_types::Error.unsupported;
    }
    var abi: u8[>..<] = [];
    abi.push(8);
    blot_direct_writer::uleb(abi, count);
    blot_direct_writer::raw(abi, entries[..]);
    blot_direct_writer::uleb(abi, inits.len as! u64);
    blot_direct_writer::raw(abi, constants[..]);
    g.module.custom("blot:abi", abi[..]);
    if count != 0 { blot_direct_function::emitInvocationFinish(g, m); }
    blot_direct_writer::assemble(g.module, bytes);
    return blot_direct_types::Error.none;
}

// The parameter type of an exported function, or of an exported constant
// whose value is a function; absent for an exported scalar constant.
fn exportedParameter(g: Generator&, m: const Module&, body: const Body&) -> Ty, bool, Error {
    if unhandledEffect(m, m.binding(body.binding).ty) { return 0, false, g.failCode(m, body.root, blot_check_diagnostic_code::Code.entry_type, "an exported function cannot leave source effects unhandled"); }
    if body.is_function {
        let parameters = m.bodyParameters(body);
        if parameters.len != 1 { return 0, false, g.fail(m, body.root, "entry functions take exactly one parameter"); }
        let lowered, error = g.types.lower(m, parameters[0].ty, blot_direct_types::Env {});
        if error != blot_direct_types::Error.none { return 0, false, g.failCode(m, body.root, blot_check_diagnostic_code::Code.entry_type, "an exported binding needs a concrete type"); }
        return lowered, true, blot_direct_types::Error.none;
    }
    let ty, error = g.types.lower(m, m.binding(body.binding).ty, blot_direct_types::Env {});
    if error != blot_direct_types::Error.none { return 0, false, g.failCode(m, body.root, blot_check_diagnostic_code::Code.entry_type, "an exported binding needs a concrete type"); }
    let n = g.types.node(ty);
    if n.tag == blot_direct_types::Tag.function { return n.a, true, blot_direct_types::Error.none; }
    return 0, false, blot_direct_types::Error.none;
}

// Whether the outer arrow of `ty` has an effect other than Foreign.
fn unhandledEffect(m: const Module&, ty: blot_check_types::Id) -> bool {
    var arrow = ty;
    var n = m.types.node(arrow);
    while n.tag == blot_check_types::Tag.forall || n.tag == blot_check_types::Tag.usage {
        arrow = n.a;
        n = m.types.node(arrow);
    }
    if n.tag != blot_check_types::Tag.function || n.c == 0 { return false; }
    for label in m.types.rowLabels(n.c) {
        let operation = m.types.operation(label);
        let foreign = operation.identity.unit == 0 && operation.identity.decl == 1 && operation.instance.unit == 0 && operation.instance.decl == 0 && operation.arguments.len == 0;
        if !foreign { return true; }
    }
    return false;
}
