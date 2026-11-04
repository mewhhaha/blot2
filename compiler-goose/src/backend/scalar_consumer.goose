namespace blot_backend_scalar_consumer;
import .runtime_ir;
import .wasm;

fn check(module: blot_backend_wasm::Module&, body: blot_backend_runtime_ir::Function) -> bool {
    let length = blot_backend_runtime_ir::codeLength(body);
    if body.result_role != blot_backend_runtime_ir::ROLE_scalar || length == 0 || length > 96 || body.parameters.len > 4 || body.locals.len > 64 - body.parameters.len { return false; }
    let count = body.parameters.len + body.locals.len;
    for parameter in 0..body.parameters.len { if blot_backend_runtime_ir::parameterRole(body, parameter) == blot_backend_runtime_ir::ROLE_unknown { return false; } }
    for ty in blot_backend_wasm::locals(module, body) { if ty != blot_backend_runtime_ir::VT_i32 && ty != blot_backend_runtime_ir::VT_f32 { return false; } }
    var depth = 0;
    for inst in blot_backend_wasm::instructions(module, body) {
        if inst.op == blot_backend_runtime_ir::OP_block || inst.op == blot_backend_runtime_ir::OP_if_ { depth++; }
        else if inst.op == blot_backend_runtime_ir::OP_end { if depth == 0 { return false; } depth--; }
        else if inst.op == blot_backend_runtime_ir::OP_else_ { if depth == 0 { return false; } }
        else if inst.op == blot_backend_runtime_ir::OP_br || inst.op == blot_backend_runtime_ir::OP_br_if { if inst.operand >= depth { return false; } }
        else if inst.op == blot_backend_runtime_ir::OP_unreachable_ {}
        else if inst.op == blot_backend_runtime_ir::OP_local_get || inst.op == blot_backend_runtime_ir::OP_local_set || inst.op == blot_backend_runtime_ir::OP_local_tee { if inst.operand >= count { return false; } }
        else if inst.op == blot_backend_runtime_ir::OP_ownership { if blot_backend_runtime_ir::ownership(inst.operand).kind == blot_backend_runtime_ir::OWN_scope { return false; } }
        else if inst.op == blot_backend_runtime_ir::OP_i32_load || inst.op == blot_backend_runtime_ir::OP_f32_load {}
        else if blot_backend_runtime_ir::fixed(inst.op).effect != blot_backend_runtime_ir::EFFECT_pure { return false; }
    }
    return depth == 0;
}
struct Frame { entry: u64 = 0, conditional: bool = false, alternate: u64 = 0, has_alternate: bool = false }
fn zeroes(module: blot_backend_wasm::Module&, body: blot_backend_runtime_ir::Function) -> u64 {
    var frames: Frame[96] = [Frame {}; 96]; var depth = 0; var defined: u64 = 0;
    for index in 0..body.parameters.len { defined |= 1 as u64 << index; }
    let parameters = defined; var required: u64 = 0;
    for inst in blot_backend_wasm::instructions(module, body) {
        if inst.op == blot_backend_runtime_ir::OP_local_get { let bit = 1 as u64 << inst.operand; if (defined & bit) == 0 { required |= bit; } }
        else if inst.op == blot_backend_runtime_ir::OP_local_set || inst.op == blot_backend_runtime_ir::OP_local_tee { defined |= 1 as u64 << inst.operand; }
        else if inst.op == blot_backend_runtime_ir::OP_block || inst.op == blot_backend_runtime_ir::OP_if_ { frames[depth] = Frame { entry: defined, conditional: inst.op == blot_backend_runtime_ir::OP_if_ }; depth++; }
        else if inst.op == blot_backend_runtime_ir::OP_else_ { frames[depth - 1].alternate = defined; frames[depth - 1].has_alternate = true; defined = frames[depth - 1].entry; }
        else if inst.op == blot_backend_runtime_ir::OP_end { depth--; let frame = frames[depth]; var both: u64 = 0; if frame.conditional && frame.has_alternate { both = defined & frame.alternate; } defined = frame.entry | both; }
        else if inst.op == blot_backend_runtime_ir::OP_br || inst.op == blot_backend_runtime_ir::OP_br_if || inst.op == blot_backend_runtime_ir::OP_unreachable_ { defined = parameters; }
    }
    return required;
}
