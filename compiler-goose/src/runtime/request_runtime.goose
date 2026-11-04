// Request cancellation carries an owning cell; typed payload dispatch stays local.
namespace blot_runtime_request_runtime;
import backend.wasm;
import backend.runtime_ir;
import runtime.runtime_cleanup;
import runtime.runtime_layout;
import support.emitter;
import support.error;
type Status = blot_runtime_runtime_layout::RequestStatus;
type Cell = blot_runtime_runtime_layout::RequestCell;
type Frame = blot_runtime_runtime_layout::RequestFrame;
type Module = blot_backend_wasm::Module;
type Stack = blot_runtime_runtime_cleanup::Stack;
type Error = blot_error::Error;
let request_kind: u32 = blot_runtime_runtime_layout::ProviderKind_request;
fn dummy(module: Module&, function: u32, cleanups: const Stack&) -> Error {
    let error = cleanups.emitAll(module, function); if error != Error.none { return error; }
    var c = blot_emitter::init(module, function);
    let result = module.functions[function].result;
    if result != blot_backend_runtime_ir::VT_none {
        if result == blot_backend_runtime_ir::VT_f32 { c.op(blot_backend_runtime_ir::OP_f32_const); }
        else { c.op(blot_backend_runtime_ir::OP_i32_const); }
    }
    c.ret(); return c.failure;
}
fn guard(module: Module&, function: u32, owner: u32, cleanups: const Stack&) -> Error {
    var c = blot_emitter::init(module, function); c.globalGet(owner); c.when();
    if c.failure != Error.none { return c.failure; }
    let error = dummy(module, function, cleanups); if error != Error.none { return error; }
    c.end(); return c.failure;
}
fn runner(module: Module&, function: u32, owner: u32, cell: u32, cleanups: const Stack&) -> Error {
    var c = blot_emitter::init(module, function);
    c.globalGet(owner); c.when(); c.globalGet(owner);
    c.op(blot_backend_runtime_ir::OP_local_get, cell); c.op(blot_backend_runtime_ir::OP_i32_ne); c.when();
    if c.failure != Error.none { return c.failure; }
    let error = dummy(module, function, cleanups); if error != Error.none { return error; }
    c.end(); c.value(0); c.globalSet(owner); c.end(); return c.failure;
}
fn cancel(module: Module&, function: u32, owner: u32, cell: u32, status: Status, cleanups: const Stack&) -> Error {
    assert(module.arena.present);
    var c = blot_emitter::init(module, function);
    c.op(blot_backend_runtime_ir::OP_local_get, cell); c.op(blot_backend_runtime_ir::OP_local_get, cell);
    c.value(blot_runtime_runtime_layout::RequestCell_status); c.op(blot_backend_runtime_ir::OP_i32_add);
    c.value(status); c.call(module.arena.value.store_word);
    c.op(blot_backend_runtime_ir::OP_local_get, cell); c.globalSet(owner);
    if c.failure != Error.none { return c.failure; }
    return dummy(module, function, cleanups);
}
