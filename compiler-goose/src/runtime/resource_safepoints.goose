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
fn run(module: const Module&, function: Function) -> blot_support::Option<blot_backend_runtime_ir::DetachedBody>, Error {
    let drain, has_drain = module.resourceDrainImport();
    if !has_drain { return blot_support::none<blot_backend_runtime_ir::DetachedBody>(), blot_error::Error.none; }
    var locals: blot_backend_runtime_ir::ValueType[>..<] = [];
    var code: IR[>..<] = [];
    locals.append(module.locals(function));
    let source = blot_backend_wasm::instructions(module,function);
    for inst in source {
        if before(module, inst) { code.push(IR { op:blot_backend_runtime_ir::OP_call_import,operand:drain,..}); }
        code.push(inst);
        if after(module, inst) { code.push(IR { op:blot_backend_runtime_ir::OP_call_import,operand:drain,..}); }
    }
    if source.len == 0 || source[source.len - 1].op != blot_backend_runtime_ir::OP_return_ {
        code.push(IR { op:blot_backend_runtime_ir::OP_call_import,operand:drain,..});
    }
    let result,error=blot_backend_runtime_ir::cloneBody(locals[..],code[..]);if error!=blot_error::Error.none {return blot_support::none<blot_backend_runtime_ir::DetachedBody>(),error;}return blot_support::some(result),blot_error::Error.none;
}
