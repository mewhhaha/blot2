namespace blot_runtime_storage_packets;
import backend.runtime_ir;
import backend.runtime_code;
import backend.wasm;
import support.emitter;
import support.error;
import support.option;

type Error = blot_error::Error;
type Module = blot_backend_wasm::Module;
type Local = blot_backend_runtime_code::Local;
struct Runtime { allocate: u32, reset: u32, length: u32, base: u32, end: u32, top: u32 }

fn configure(module: Module&, runtime: Runtime, base: u32, capacity: u32) -> Error {
    let end = base as u64 + capacity as u64;
    if base == 0 || capacity < 4 || (base | capacity) & 3 != 0 || end > module.fixed_memory_bytes as u64 {
        return Error.invalid_transport_region;
    }
    module.globals[runtime.base].bits = base;
    module.globals[runtime.end].bits = end as u32;
    module.globals[runtime.top].bits = base;
    return Error.none;
}
fn emit(module: Module&) -> Runtime, Error {
    if module.arena.present || module.array_transport.present { abort("transport must precede the arena"); }
    let scalar = blot_backend_runtime_ir::ROLE_scalar;
    let word = blot_backend_runtime_ir::VT_i32;
    let params = [word];
    let allocate, e0 = blot_backend_wasm::addTypedFunction(module, params, word, scalar);
    if e0 != Error.none { return default<Runtime>(), e0; }
    let reset, e1 = blot_backend_wasm::addTypedFunction(module, params, word, scalar);
    if e1 != Error.none { return default<Runtime>(), e1; }
    let length, e2 = blot_backend_wasm::addTypedFunction(module, params, word, scalar);
    if e2 != Error.none { return default<Runtime>(), e2; }
    let base, e3 = blot_backend_wasm::addGlobal(module, blot_backend_runtime_ir::SC_u32, 0, false);
    if e3 != Error.none { return default<Runtime>(), e3; }
    let end, e4 = blot_backend_wasm::addGlobal(module, blot_backend_runtime_ir::SC_u32, 0, false);
    if e4 != Error.none { return default<Runtime>(), e4; }
    let top, e5 = blot_backend_wasm::addGlobal(module, blot_backend_runtime_ir::SC_u32, 0, true);
    if e5 != Error.none { return default<Runtime>(), e5; }
    let runtime = Runtime { allocate, reset, length, base, end, top };
    {
        var c = blot_emitter::init(module, allocate);
        let bytes = Local { 0 }; let address = blot_emitter::temp(c);
        blot_emitter::value(c, bytes); blot_emitter::op(c, blot_backend_runtime_ir::OP_i32_eqz);
        blot_emitter::value(c, bytes); blot_emitter::value(c, 3);
        blot_emitter::op(c, blot_backend_runtime_ir::OP_i32_and);
        blot_emitter::op(c, blot_backend_runtime_ir::OP_i32_or); blot_emitter::trap(c);
        blot_emitter::value(c, bytes); blot_emitter::globalGet(c, end); blot_emitter::globalGet(c, top);
        blot_emitter::op(c, blot_backend_runtime_ir::OP_i32_sub);
        blot_emitter::op(c, blot_backend_runtime_ir::OP_i32_gt_u); blot_emitter::trap(c);
        blot_emitter::globalGet(c, top); blot_emitter::set(c, address);
        blot_emitter::value(c, address); blot_emitter::value(c, 0); blot_emitter::value(c, bytes);
        blot_emitter::zero(c);
        blot_emitter::value(c, address); blot_emitter::value(c, bytes);
        blot_emitter::op(c, blot_backend_runtime_ir::OP_i32_add); blot_emitter::globalSet(c, top);
        blot_emitter::value(c, address);
        if c.failure != Error.none { return default<Runtime>(), c.failure; }
    }
    {
        var c = blot_emitter::init(module, reset);
        blot_emitter::globalGet(c, base); blot_emitter::globalSet(c, top); blot_emitter::value(c, 0);
        if c.failure != Error.none { return default<Runtime>(), c.failure; }
    }
    {
        var c = blot_emitter::init(module, length);
        let address = Local { 0 }; let count = blot_emitter::temp(c);
        blot_emitter::value(c, address); blot_emitter::globalGet(c, base);
        blot_emitter::op(c, blot_backend_runtime_ir::OP_i32_lt_u);
        blot_emitter::value(c, address); blot_emitter::value(c, 3);
        blot_emitter::op(c, blot_backend_runtime_ir::OP_i32_and);
        blot_emitter::op(c, blot_backend_runtime_ir::OP_i32_or); blot_emitter::trap(c);
        blot_emitter::value(c, address); blot_emitter::globalGet(c, top);
        blot_emitter::op(c, blot_backend_runtime_ir::OP_i32_gt_u); blot_emitter::trap(c);
        blot_emitter::globalGet(c, top); blot_emitter::value(c, address);
        blot_emitter::op(c, blot_backend_runtime_ir::OP_i32_sub); blot_emitter::value(c, 4);
        blot_emitter::op(c, blot_backend_runtime_ir::OP_i32_lt_u); blot_emitter::trap(c);
        blot_emitter::value(c, address); blot_emitter::load(c, 0); blot_emitter::set(c, count);
        blot_emitter::value(c, count); blot_emitter::globalGet(c, top); blot_emitter::value(c, address);
        blot_emitter::op(c, blot_backend_runtime_ir::OP_i32_sub); blot_emitter::value(c, 4);
        blot_emitter::op(c, blot_backend_runtime_ir::OP_i32_sub); blot_emitter::value(c, 4);
        blot_emitter::op(c, blot_backend_runtime_ir::OP_i32_div_u);
        blot_emitter::op(c, blot_backend_runtime_ir::OP_i32_gt_u); blot_emitter::trap(c);
        blot_emitter::value(c, count);
        if c.failure != Error.none { return default<Runtime>(), c.failure; }
    }
    module.array_transport = blot_support::some(blot_backend_wasm::ArrayTransport { allocate, reset });
    return runtime, Error.none;
}
