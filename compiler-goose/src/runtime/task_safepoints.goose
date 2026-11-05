// Each JSPI continuation restores its invocation's journal before resuming.
namespace blot_runtime_task_safepoints;
import backend.runtime_ir;
import backend.wasm;
import support.error;
import support.option;
type Module = blot_backend_wasm::Module;
type Function = blot_backend_runtime_ir::Function;
type Instruction = blot_backend_runtime_ir::Instruction;
type Error = blot_error::Error;
fn suspends(module: const Module&, inst: Instruction) -> bool {
    if inst.op != blot_backend_runtime_ir::OP_call_import { return false; }
    let callback = module.hostCallbackImport(inst.operand);
    if callback.present { return !callback.value.cleanup; }
    if !module.taskImport(inst.operand) { return false; }
    let name = module.importName(inst.operand);
    return name == "close" || name == "join" || name == "cancel" || name == "drop" || name == "drain";
}
fn run(module: const Module&, function: Function) -> blot_support::Option<blot_backend_runtime_ir::DetachedBody>, Error {
    let current, has_current = module.taskImportNamed("current");
    if !has_current { return blot_support::none<blot_backend_runtime_ir::DetachedBody>(), Error.none; }
    let resume_, has_resume = module.taskImportNamed("resume");
    let checkpoint, has_checkpoint = module.taskImportNamed("checkpoint");
    assert(has_resume && has_checkpoint);
    var locals: blot_backend_runtime_ir::ValueType[>..<] = [];
    var code: Instruction[>..<] = [];
    locals.append(module.locals(function));
    let context = function.parameters.len + locals.len;
    locals.push(blot_backend_runtime_ir::VT_i32);
    let source = module.instructions(function);
    for inst, index in source {
        let indirect_annotation = inst.op == blot_backend_runtime_ir::OP_ownership && index + 1 < source.len &&
            blot_backend_runtime_ir::indirectResult(source, index + 1) != blot_backend_runtime_ir::ROLE_unknown;
        let annotated_indirect = inst.op == blot_backend_runtime_ir::OP_call_indirect &&
            blot_backend_runtime_ir::indirectResult(source, index) != blot_backend_runtime_ir::ROLE_unknown;
        let source_call = indirect_annotation ||
            inst.op == blot_backend_runtime_ir::OP_call_indirect && !annotated_indirect ||
            inst.op == blot_backend_runtime_ir::OP_call && !module.runtimeHelper(inst.operand);
        var publication = false;
        if inst.op == blot_backend_runtime_ir::OP_call_import && module.taskImport(inst.operand) {
            let name = module.importName(inst.operand);
            publication = name == "open" || name == "spawn";
        }
        if source_call || publication { code.push(Instruction { op:blot_backend_runtime_ir::OP_call_import,operand:checkpoint,..}); }
        let suspend = suspends(module, inst);
        if suspend {
            code.push(Instruction { op:blot_backend_runtime_ir::OP_call_import,operand:checkpoint,..});
            code.push(Instruction { op:blot_backend_runtime_ir::OP_call_import,operand:current,..});
            code.push(Instruction { op:blot_backend_runtime_ir::OP_local_set,operand:context as u32,..});
        }
        if inst.op == blot_backend_runtime_ir::OP_br || inst.op == blot_backend_runtime_ir::OP_br_if {
            code.push(Instruction { op:blot_backend_runtime_ir::OP_call_import,operand:checkpoint,..});
        }
        code.push(inst);
        if suspend {
            code.push(Instruction { op:blot_backend_runtime_ir::OP_local_get,operand:context as u32,..});
            code.push(Instruction { op:blot_backend_runtime_ir::OP_call_import,operand:resume_,..});
            code.push(Instruction { op:blot_backend_runtime_ir::OP_call_import,operand:checkpoint,..});
        }
    }
    let result,error=blot_backend_runtime_ir::cloneBody(locals[:],code[:]);if error!=Error.none {return blot_support::none<blot_backend_runtime_ir::DetachedBody>(),error;}return blot_support::some(result),Error.none;
}
