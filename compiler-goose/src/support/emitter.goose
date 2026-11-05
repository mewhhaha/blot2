// Runtime recipes have finite host control flow. After the first failed
// append all further recipe operations are inert; the caller returns failure
// before publishing its runtime descriptor or journal event.
namespace blot_emitter;
import backend.runtime_code;
import backend.runtime_ir;
import backend.wasm;
import support.error;

type Error = blot_error::Error;
type Local = blot_backend_runtime_code::Local;
struct Emitter<M> { code: blot_backend_runtime_code::Code<M>, failure: Error = Error.none }
fn init<M>(module: M&, function: u32) -> Emitter<M> {
    Emitter<M> { blot_backend_runtime_code::Code<M> { module, function } }
}
fn op<M>(emitter: Emitter<M>&, opcode: blot_backend_runtime_ir::Op, operand: u32 = 0) {
    if emitter.failure != Error.none { return; }
    emitter.failure = blot_backend_runtime_code::op(emitter.code, opcode, operand);
}
fn value<M>(emitter: Emitter<M>&, number: u32) {
    op(emitter, blot_backend_runtime_ir::OP_i32_const, number);
}
fn value<M>(emitter: Emitter<M>&, local: Local) {
    op(emitter, blot_backend_runtime_ir::OP_local_get, local.id);
}
fn temp<M>(emitter: Emitter<M>&) -> Local {
    if emitter.failure != Error.none { return Local {}; }
    let local, error = blot_backend_runtime_code::temp(emitter.code);
    emitter.failure = error;
    return local;
}
fn set<M>(emitter: Emitter<M>&, local: Local) { op(emitter, blot_backend_runtime_ir::OP_local_set, local.id); }
fn set<M>(emitter: Emitter<M>&, local: Local, number: u32) { value(emitter, number); set(emitter, local); }
fn set<M>(emitter: Emitter<M>&, local: Local, other: Local) { value(emitter, other); set(emitter, local); }
fn store<M>(emitter: Emitter<M>&, offset: u32 = 0) { op(emitter, blot_backend_runtime_ir::OP_i32_store, offset); }
fn load<M>(emitter: Emitter<M>&, offset: u32 = 0) { op(emitter, blot_backend_runtime_ir::OP_i32_load, offset); }
fn when<M>(emitter: Emitter<M>&) { op(emitter, blot_backend_runtime_ir::OP_if_); }
fn end<M>(emitter: Emitter<M>&) { op(emitter, blot_backend_runtime_ir::OP_end); }
fn ret<M>(emitter: Emitter<M>&) { op(emitter, blot_backend_runtime_ir::OP_return_); }
fn trap<M>(emitter: Emitter<M>&) {
    when(emitter); op(emitter, blot_backend_runtime_ir::OP_unreachable_); end(emitter);
}
fn zero<M>(emitter: Emitter<M>&) { op(emitter, blot_backend_runtime_ir::OP_memory_fill); }
fn copy<M>(emitter: Emitter<M>&) { op(emitter, blot_backend_runtime_ir::OP_memory_copy); }
fn loopStart<M>(emitter: Emitter<M>&) {
    op(emitter, blot_backend_runtime_ir::OP_block); op(emitter, blot_backend_runtime_ir::OP_loop);
}
fn loopTest<M>(emitter: Emitter<M>&) {
    op(emitter, blot_backend_runtime_ir::OP_i32_eqz); op(emitter, blot_backend_runtime_ir::OP_br_if, 1);
}
fn again<M>(emitter: Emitter<M>&) {
    op(emitter, blot_backend_runtime_ir::OP_br); end(emitter); end(emitter);
}
fn next<M>(emitter: Emitter<M>&, local: Local) {
    value(emitter, local); value(emitter, 1); op(emitter, blot_backend_runtime_ir::OP_i32_add); set(emitter, local);
}
fn globalGet<M>(emitter: Emitter<M>&, index: u32) { op(emitter, blot_backend_runtime_ir::OP_global_get, index); }
fn globalSet<M>(emitter: Emitter<M>&, index: u32) { op(emitter, blot_backend_runtime_ir::OP_global_set, index); }
fn call<M>(emitter: Emitter<M>&, function: u32) { op(emitter, blot_backend_runtime_ir::OP_call, function); }
fn annotation<M>(emitter: Emitter<M>&, item: blot_backend_runtime_ir::Instruction) {
    if emitter.failure != Error.none { return; }
    emitter.failure = blot_backend_wasm::emit(emitter.code.module, emitter.code.function, item);
}
fn value<M>(emitter: Emitter<M>&, instructions: const blot_backend_runtime_ir::Instruction[:]) {
    if emitter.failure != Error.none { return; }
    emitter.failure = blot_backend_runtime_code::value(emitter.code, instructions);
}
