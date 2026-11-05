// Cleanup drains only between complete ownership transactions.
namespace blot_runtime_resource_safepoints;
import backend.runtime_ir;
import backend.wasm;
import support.error;
import support.option;
type IR = blot_backend_runtime_ir::Instruction;
type Module = blot_backend_wasm::Module;
type Function = blot_backend_runtime_ir::Function;
type Error = blot_error::Error;
fn before(module: const Module&, inst: IR) -> bool {
    return inst.op == blot_backend_runtime_ir::OP_return_ ||
        inst.op == blot_backend_runtime_ir::OP_call_import && module.hostCallbackImport(inst.operand).present;
}
fn after(module: const Module&, inst: IR) -> bool {
    if inst.op == blot_backend_runtime_ir::OP_call_import && module.resourceImport(inst.operand) {
        return module.importName(inst.operand) == "release";
    }
    if inst.op != blot_backend_runtime_ir::OP_call || !module.arena.present { return false; }
    let arena = module.arena.value;
    return inst.operand == arena.recycle || inst.operand == arena.release ||
        inst.operand == arena.release_lease || inst.operand == arena.cycle_collect ||
        inst.operand == arena.root_pop || inst.operand == arena.root_close || inst.operand == arena.root_leave;
}
fn run(module: Module&, function: Function) -> blot_support::Option<blot_backend_runtime_ir::Body>, Error {
    let drain, has_drain = module.resourceDrainImport();
    if !has_drain { return blot_support::none<blot_backend_runtime_ir::Body>(), Error.none; }
    // Snapshot the source before publishing grows Module's instruction table.
    var locals: blot_backend_runtime_ir::ValueType[>..<] = [];
    var code: IR[>..<] = [];
    locals.append(module.locals(function));
    let source = module.instructions(function);
    for inst in source {
        if before(module, inst) { code.push(IR { blot_backend_runtime_ir::OP_call_import, drain , ..}); }
        code.push(inst);
        if after(module, inst) { code.push(IR { blot_backend_runtime_ir::OP_call_import, drain , ..}); }
    }
    if source.len == 0 || source[source.len - 1].op != blot_backend_runtime_ir::OP_return_ {
        code.push(IR { blot_backend_runtime_ir::OP_call_import, drain , ..});
    }
    return blot_support::some(module.publishBody(locals, code)), Error.none;
}
