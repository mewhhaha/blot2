// Direct backend entry: one Wasm function per `(binding, concrete type)`
// instance reached from the entry module's exports, with fixed layouts and
// no cross-call analysis. See tasks/FAST_COMPILE.md.
//
// Port of compiler/src/direct/direct.zig. The generator's three stores
// (types, the Wasm module and the emitter state) are roots owned by
// `compile`; the Wasm bytes and a failure's message go to the caller's
// buffers.
namespace squid_direct;
import std;
import phase_profile;
import check.core;
import check.types;
import check.diagnostic_code;
import check.wire_schema;
import direct.writer;
import direct.types;
import direct.emit;
import direct.function;

type Module = squid_check_core::Module;
type Body = squid_check_core::Body;
type Ty = u32;
type Error = squid_direct_types::Error;
type Generator = squid_direct_emit::Generator;
type Code = squid_check_diagnostic_code::Code;

// `failed`: `unit`, `span` and `code` describe the diagnostic and `message`
// holds its detail. Otherwise `bytes` holds the Wasm module.
struct Result { failed: bool = false, unit: u32 = 0, span: squid_check_core::Span = squid_check_core::Span { 0, 0 }, code: Code = squid_check_diagnostic_code::Code.storage_unsupported, emitted_functions: i64 = 0, sparks_vectorized: i64 = 0, sparks_scalar_fallback: i64 = 0, staged_dep_units_valid: bool = false, staged_value_digest: u64 = 0 }

fn compile(units: const Module[:], entry: u32, bytes: u8[>..<]&, message: u8[>..<]&, build_inputs:i64 = -1) -> Result {
    var staged_units: u32[>..<] = [];
    return compileWithStaged(units, entry, bytes, message, staged_units, build_inputs);
}

fn compileWithStaged(units: const Module[:], entry: u32, bytes: u8[>..<]&, message: u8[>..<]&, staged_units: u32[>..<]&, build_inputs:i64 = -1) -> Result {
    var types = squid_direct_types::Types { units: units, .. };
    squid_direct_types::init(types);
    var module = squid_direct_writer::Module { .. };
    var state = squid_direct_emit::State { .. };
    let res = compileWith(units, entry, types, module, state, bytes, message, build_inputs);
    if !res.failed && state.staged_dep_units_valid {
        staged_units.append(state.staged_dep_units[..]);
    }
    return res;
}

fn compileWithStagedAndAnalysis(units: const Module[:], entry: u32, pinfo: const squid_check_wire_schema::ProgramInfo&, bytes: u8[>..<]&, message: u8[>..<]&, staged_units: u32[>..<]&, build_inputs:i64 = -1) -> Result {
    var types = squid_direct_types::Types { units: units, .. };
    squid_direct_types::init(types);
    var module = squid_direct_writer::Module { .. };
    var state = squid_direct_emit::State { .. };
    let res = compileWithAnalysis(units, entry, types, module, state, pinfo, bytes, message, build_inputs);
    if !res.failed && state.staged_dep_units_valid {
        staged_units.append(state.staged_dep_units[..]);
    }
    return res;
}

fn compileTracked(units: const Module[:], entry: u32, types: squid_direct_types::Types&, module: squid_direct_writer::Module&, state: squid_direct_emit::State&, bytes: u8[>..<]&, message: u8[>..<]&, build_inputs:i64 = -1) -> Result {
    squid_direct_types::init(types);
    state.track_deps = true;
    return compileWith(units, entry, types, module, state, bytes, message, build_inputs);
}

fn compileTrackedWithAnalysis(units: const Module[:], entry: u32, types: squid_direct_types::Types&, module: squid_direct_writer::Module&, state: squid_direct_emit::State&, pinfo: const squid_check_wire_schema::ProgramInfo&, bytes: u8[>..<]&, message: u8[>..<]&, build_inputs:i64 = -1) -> Result {
    let r_ti = squid_phase_profile::region("direct.types_init", entry, 0, 0);
    squid_direct_types::init(types);
    r_ti.exit();
    state.track_deps = true;
    return compileWithAnalysis(units, entry, types, module, state, pinfo, bytes, message, build_inputs);
}

fn finishCompile(entry: u32, module: const squid_direct_writer::Module&, state: const squid_direct_emit::State&, error: Error, message: u8[>..<]&) -> Result {
    if error != squid_direct_types::Error.none {
        if !state.has_failure {
            message.append("Direct backend: unsupported program");
            return Result { failed: true, unit: entry };
        }
        let failure = state.failure;
        message.append(state.text[failure.message.start..failure.message.start + failure.message.len]);
        return Result { failed: true, unit: failure.unit, span: failure.span, code: failure.code };
    }
    return Result { emitted_functions: module.functions.len, sparks_vectorized: state.sparks_vectorized, sparks_scalar_fallback: state.sparks_scalar_fallback, staged_dep_units_valid: state.staged_dep_units_valid, staged_value_digest: state.staged_value_digest };
}

fn compileWith(units: const Module[:], entry: u32, types: squid_direct_types::Types&, module: squid_direct_writer::Module&, state: squid_direct_emit::State&, bytes: u8[>..<]&, message: u8[>..<]&, build_inputs:i64 = -1) -> Result {
    var g = Generator { types: types, module: module, s: state, units: units, build_inputs:build_inputs };
    let error = build(g, entry, bytes);
    return finishCompile(entry, module, state, error, message);
}

fn compileWithAnalysis(units: const Module[:], entry: u32, types: squid_direct_types::Types&, module: squid_direct_writer::Module&, state: squid_direct_emit::State&, pinfo: const squid_check_wire_schema::ProgramInfo&, bytes: u8[>..<]&, message: u8[>..<]&, build_inputs:i64 = -1) -> Result {
    var g = Generator { types: types, module: module, s: state, units: units, build_inputs:build_inputs };
    let error = buildWithAnalysis(g, entry, pinfo, bytes);
    return finishCompile(entry, module, state, error, message);
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
    if !g.hasUnit(entry) { return squid_direct_types::Error.unsupported; }
    var pinfo = squid_check_wire_schema::ProgramInfo {};
    squid_check_wire_schema::analyze(g.units, entry, pinfo);
    if pinfo.issue.failed {
        var err_unit = pinfo.issue.unit;
        if !g.hasUnit(err_unit) { err_unit = entry; }
        return g.failSpanCode(err_unit, pinfo.issue.span, pinfo.issue.code, pinfo.issue.message);
    }
    return buildWithAnalysis(g, entry, pinfo, bytes);
}

fn isEmittedBody(body: const Body&) -> bool {
    return body.exported || (squid_direct_writer::testModeEnabled() && body.test_kind != 0);
}
fn emitTestMetadata(module: squid_direct_writer::Module&, m: const Module&) {
    var count: u32 = 0;
    for body in m.bodies {
        if body.test_kind != 0 { count++; }
    }
    if count == 0 { return; }
    var section: u8[>..<] = [];
    section.push(1);
    squid_direct_writer::uleb(section, count);
    for body in m.bodies {
        if body.test_kind == 0 { continue; }
        section.push(body.test_kind - 1);
        squid_direct_writer::name(section, m.name(body.declaration_name));
        squid_direct_writer::name(section, m.name(body.test_name));
        squid_direct_writer::name(section, "");
        squid_direct_writer::uleb(section, body.test_line);
    }
    module.custom("squid:tests", section[..]);
}
fn emitTrapMetadata(module: squid_direct_writer::Module&, state: const squid_direct_emit::State&) {
    if state.traps.len == 0 { return; }
    var section: u8[>..<] = [];
    section.push(1);
    squid_direct_writer::word(section, state.traps.len as u32);
    for entry in state.traps {
        section.push(entry.kind);
        squid_direct_writer::word(section, entry.unit);
        squid_direct_writer::word(section, entry.start);
        squid_direct_writer::word(section, entry.end);
        squid_direct_writer::word(section, entry.message_len);
        let msg_start = entry.message_start as i64;
        let msg_end = msg_start + (entry.message_len as i64);
        squid_direct_writer::raw(section, state.trap_text[msg_start..msg_end]);
    }
    module.custom("squid:traps", section[..]);
}
fn buildWithAnalysis(g: Generator&, entry: u32, pinfo: const squid_check_wire_schema::ProgramInfo&, bytes: u8[>..<]&) -> Error {
    if !g.hasUnit(entry) { return squid_direct_types::Error.unsupported; }
    g.s.rt_flags_known = true;
    g.s.rt_has_fork = pinfo.has_fork;
    g.s.rt_has_persistent = pinfo.has_persistent_state;
    g.s.kernels.append(pinfo.kernels[..]);
    g.s.processes.append(pinfo.processes[..]);
    g.s.wire_word_tags.append(pinfo.word_tags[..]);
    g.s.float_bits_observable = squid_direct_function::analyzeFloatBitsObservable(g, entry, pinfo);
    let m .= g.units[entry - 1];
    var entries: u8[>..<] = [];
    var constants: u8[>..<] = [];
    var inits: u32[>..<] = [];
    var count: u32 = 0;
    // Host callback imports precede every defined function.
    for at in 0..m.bodies.len {
        if !isEmittedBody(m.bodies[at]) { continue; }
        let parameter, has_parameter, error = exportedParameter(g, m, m.bodies[at]);
        if error != squid_direct_types::Error.none { return error; }
        if !has_parameter { continue; }
        let first, second, is_callback = squid_direct_function::callbackAbi(g, parameter);
        if is_callback { let import_id = squid_direct_function::hostImport(g, first, second); }
    }
    let r_exp = squid_phase_profile::region("direct.exports", entry, 0, 0);
    for at in 0..m.bodies.len {
        if !isEmittedBody(m.bodies[at]) { continue; }
        let parameter, has_parameter, error = exportedParameter(g, m, m.bodies[at]);
        if error != squid_direct_types::Error.none { r_exp.exit(); return error; }
        if !has_parameter { continue; }
        let emitted = squid_direct_function::emitExport(g, m, m.bodies[at], entries);
        if emitted != squid_direct_types::Error.none { r_exp.exit(); return emitted; }
        count += 1;
    }
    for at in 0..m.bodies.len {
        if !isEmittedBody(m.bodies[at]) { continue; }
        let parameter, has_parameter, error = exportedParameter(g, m, m.bodies[at]);
        if error != squid_direct_types::Error.none { r_exp.exit(); return error; }
        if has_parameter { continue; }
        let init_function, error = squid_direct_function::emitConstantExport(g, m, m.bodies[at], constants);
        if error != squid_direct_types::Error.none { r_exp.exit(); return error; }
        inits.push(init_function);
    }
    let kernel_exports, kerr = squid_direct_function::emitKernelExports(g, m, entries);
    if kerr != squid_direct_types::Error.none { r_exp.exit(); return kerr; }
    count += kernel_exports;
    let process_exports, perr = squid_direct_function::emitProcessExports(g, m, entries);
    if perr != squid_direct_types::Error.none { r_exp.exit(); return perr; }
    count += process_exports;
    r_exp.exit();
    if count == 0 && inits.len == 0 { return g.failCode(m, 0, squid_check_diagnostic_code::Code.no_entry, "the entry module exports nothing"); }
    let r_emit = squid_phase_profile::region("direct.emit_all", entry, 0, 0);
    let emitted = g.emitAll();
    r_emit.exitWithItems(0, g.module.functions.len);
    if emitted != squid_direct_types::Error.none { return emitted; }
    if g.s.seq_rt_ready { squid_direct_function::patchSeqReleaseEntries(g, inits[..]); }
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
        let pool_function, error = squid_direct_function::poolInits(g, m, pools[..]);
        if error != squid_direct_types::Error.none { return error; }
        starts.push(pool_function);
    }
    for init_function in inits { starts.push(init_function); }
    if starts.len != 0 {
        let start_function = squid_direct_function::startFunction(g, m, starts[..]);
        g.module.start = start_function;
        g.module.has_start = true;
    }
    let failure, has_summary = g.summary();
    if has_summary {
        g.s.failure = failure;
        g.s.has_failure = true;
        return squid_direct_types::Error.unsupported;
    }
    var abi: u8[>..<] = [];
    abi.push(8);
    squid_direct_writer::uleb(abi, count);
    squid_direct_writer::raw(abi, entries[..]);
    squid_direct_writer::uleb(abi, inits.len as! u64);
    squid_direct_writer::raw(abi, constants[..]);
    g.module.custom("squid:abi", abi[..]);
    if squid_direct_writer::testModeEnabled() { emitTestMetadata(g.module, m); }
    emitTrapMetadata(g.module, g.s);
    if g.s.traps.len != 0 && !g.s.exported_storage && g.module.has_memory {
        g.module.exportItem("squid:memory", squid_direct_writer::EXPORT_memory, 0);
    }
    if count != 0 { squid_direct_function::emitInvocationFinish(g, m); }
    for si in 1..g.s.staged_dep_units.len {
        let key = g.s.staged_dep_units[si];
        var sj = si;
        while sj > 0 && g.s.staged_dep_units[sj - 1] > key {
            g.s.staged_dep_units[sj] = g.s.staged_dep_units[sj - 1];
            sj -= 1;
        }
        g.s.staged_dep_units[sj] = key;
    }
    g.s.staged_dep_units_valid = true;
    if g.module.data.len != 0 {
        g.module.data_offset = squid_direct_runtime::arena_start;
        if !g.module.has_memory {
            g.module.has_memory = true;
            g.module.memory_pages = 1;
            g.module.memory_max_pages = 1;
        }
        let rodata_end = (squid_direct_runtime::arena_start + (g.module.data.len as u32) + 15) & 0xfffffff0;
        let min_pages = (rodata_end + 0xffff) / 0x10000;
        if g.module.memory_pages < min_pages { g.module.memory_pages = min_pages; }
        if g.module.memory_max_pages < min_pages { g.module.memory_max_pages = min_pages; }
        if g.s.has_rt {
            g.module.globals[g.s.rt.arena_top].init = rodata_end;
            if min_pages > 1 {
                g.module.globals[g.s.rt.page_top].init = min_pages * 65536;
            }
        }
    }
    let r_asm = squid_phase_profile::region("direct.assemble", entry, 0, 0);
    squid_direct_writer::assemble(g.module, bytes);
    r_asm.exitWithItems(g.module.functions.len, bytes.len);
    return squid_direct_types::Error.none;
}

// The parameter type of an exported function, or of an exported constant
// whose value is a function; absent for an exported scalar constant.
fn exportedParameter(g: Generator&, m: const Module&, body: const Body&) -> Ty, bool, Error {
    let has_unhandled, eff_name = unhandledEffect(g, m, m.binding(body.binding).ty);
    if has_unhandled {
        g.failOpenCode(m, body.root, squid_check_diagnostic_code::Code.entry_type);
        g.put("an exported function cannot leave source effects unhandled");
        if eff_name.len != 0 {
            g.put(" (unhandled: ");
            g.put(eff_name);
            g.put(")");
        }
        g.put("; handle with `with ...:` or `do <provider>:`");
        return 0, false, g.failClose();
    }
    if body.is_function {
        let parameters = m.bodyParameters(body);
        if parameters.len != 1 { return 0, false, g.fail(m, body.root, "io entry functions take exactly one parameter"); }
        let lowered, error = g.types.lower(m, parameters[0].ty, squid_direct_types::Env {});
        if error != squid_direct_types::Error.none { return 0, false, g.failCode(m, body.root, squid_check_diagnostic_code::Code.entry_type, "an exported binding needs a concrete type"); }
        return lowered, true, squid_direct_types::Error.none;
    }
    let ty, error = g.types.lower(m, m.binding(body.binding).ty, squid_direct_types::Env {});
    if error != squid_direct_types::Error.none { return 0, false, g.failCode(m, body.root, squid_check_diagnostic_code::Code.entry_type, "an exported binding needs a concrete type"); }
    let n = g.types.node(ty);
    if n.tag == squid_direct_types::Tag.function { return n.a, true, squid_direct_types::Error.none; }
    return 0, false, squid_direct_types::Error.none;
}

// Whether the outer arrow of `ty` has an effect other than Foreign, plus its diagnostic name if known.
fn lookupOperationName(m: const Module&, id: squid_check_types::NominalIdentity) -> const u8[:] {
    for entry in m.operation_names {
        if entry.identity.unit == id.unit && entry.identity.decl == id.decl {
            if entry.diagnostic_name.len != 0 { return m.name(entry.diagnostic_name); }
        }
    }
    return "";
}
fn unhandledEffect(g: const Generator&, m: const Module&, ty: squid_check_types::Id) -> bool, const u8[:] {
    var arrow = ty;
    var n = m.types.node(arrow);
    while n.tag == squid_check_types::Tag.forall || n.tag == squid_check_types::Tag.usage {
        arrow = n.a;
        n = m.types.node(arrow);
    }
    if n.tag != squid_check_types::Tag.function || n.c == 0 { return false, ""; }
    for label in m.types.rowLabels(n.c) {
        let operation = m.types.operation(label);
        let foreign = operation.identity.unit == 0 && operation.identity.decl == 1 && operation.instance.unit == 0 && operation.instance.decl == 0 && operation.arguments.len == 0;
        if !foreign {
            let local_name = lookupOperationName(m, operation.identity);
            if local_name.len != 0 { return true, local_name; }
            if operation.identity.unit != 0 && g.hasUnit(operation.identity.unit) {
                let home_name = lookupOperationName(g.units[operation.identity.unit - 1], operation.identity);
                if home_name.len != 0 { return true, home_name; }
            }
            return true, "";
        }
    }
    return false, "";
}
