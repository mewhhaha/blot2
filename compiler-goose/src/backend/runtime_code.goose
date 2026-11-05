// Postfix recipes emit directly into the symbolic body, without expression nodes.
namespace blot_backend_runtime_code;
import .runtime_ir;
import .wasm;
import support.error;

struct Local { id: u32 = 0 }
struct Code<M> { module: M&, function: u32 }
fn op<M>(c: Code<M>&, opcode: blot_backend_runtime_ir::Op, operand: u32 = 0) -> blot_error::Error {
    return blot_backend_wasm::emit(c.module, c.function, blot_backend_runtime_ir::instruction(opcode, operand));
}
fn emit<M>(c: Code<M>&, opcode: blot_backend_runtime_ir::Op, operand: u32 = 0) -> blot_error::Error { op(c, opcode, operand) }
fn value<M>(c: Code<M>&, local: Local) -> blot_error::Error { op(c, blot_backend_runtime_ir::OP_local_get, local.id) }
fn value<M>(c: Code<M>&, number: u32) -> blot_error::Error { op(c, blot_backend_runtime_ir::OP_i32_const, number) }
fn value<M>(c: Code<M>&, code: const blot_backend_runtime_ir::Instruction[:]) -> blot_error::Error {
    for instruction in code {
        let error = blot_backend_wasm::emit(c.module, c.function, instruction);
        if error != blot_error::Error.none { return error; }
    }
    return blot_error::Error.none;
}
fn temp<M>(c: Code<M>&) -> Local, blot_error::Error {
    let id, error = blot_backend_wasm::addLocal(c.module, c.function, blot_backend_runtime_ir::VT_i32);
    return Local { id: id , ..}, error;
}
fn set<M>(c: Code<M>&, local: Local) -> blot_error::Error { op(c, blot_backend_runtime_ir::OP_local_set, local.id) }
fn set<M>(c: Code<M>&, local: Local, number: u32) -> blot_error::Error {
    let error = value(c, number); if error != blot_error::Error.none { return error; } return set(c, local);
}
fn set<M>(c: Code<M>&, local: Local, other: Local) -> blot_error::Error {
    let error = value(c, other); if error != blot_error::Error.none { return error; } return set(c, local);
}
fn store<M>(c: Code<M>&, offset: u32 = 0) -> blot_error::Error { op(c, blot_backend_runtime_ir::OP_i32_store, offset) }
fn copy<M>(c: Code<M>&) -> blot_error::Error { op(c, blot_backend_runtime_ir::OP_memory_copy) }
fn zero<M>(c: Code<M>&) -> blot_error::Error { op(c, blot_backend_runtime_ir::OP_memory_fill) }
fn when<M>(c: Code<M>&) -> blot_error::Error { op(c, blot_backend_runtime_ir::OP_if_) }
fn end<M>(c: Code<M>&) -> blot_error::Error { op(c, blot_backend_runtime_ir::OP_end) }
fn ret<M>(c: Code<M>&) -> blot_error::Error { op(c, blot_backend_runtime_ir::OP_return_) }
fn trap<M>(c: Code<M>&) -> blot_error::Error {
    var error = when(c); if error != blot_error::Error.none { return error; }
    error = op(c, blot_backend_runtime_ir::OP_unreachable_); if error != blot_error::Error.none { return error; }
    return end(c);
}
// Emit block+loop before computing the condition; loopTest consumes it. Keeping
// these separate ensures conditions are evaluated at the loop header each trip.
fn loopStart<M>(c: Code<M>&) -> blot_error::Error {
    let error = op(c, blot_backend_runtime_ir::OP_block); if error != blot_error::Error.none { return error; }
    return op(c, blot_backend_runtime_ir::OP_loop);
}
fn loopTest<M>(c: Code<M>&) -> blot_error::Error {
    let error = op(c, blot_backend_runtime_ir::OP_i32_eqz); if error != blot_error::Error.none { return error; }
    return op(c, blot_backend_runtime_ir::OP_br_if, 1);
}
fn again<M>(c: Code<M>&) -> blot_error::Error {
    var error = op(c, blot_backend_runtime_ir::OP_br); if error != blot_error::Error.none { return error; }
    error = end(c); if error != blot_error::Error.none { return error; }
    return end(c);
}
fn next<M>(c: Code<M>&, local: Local) -> blot_error::Error {
    var error = value(c, local); if error != blot_error::Error.none { return error; }
    error = value(c, 1); if error != blot_error::Error.none { return error; }
    error = op(c, blot_backend_runtime_ir::OP_i32_add); if error != blot_error::Error.none { return error; }
    return set(c, local);
}
