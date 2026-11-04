namespace blot_backend_storage_span_dominance;
import .runtime_ir;
import support.option;

struct Scopes { cursor: i64 = 0, function: blot_support::Option<u32>, active: bool[>..<]&, stack: i64[>..<]&, reset_pending: bool = true }
fn reset(scopes: Scopes&) { scopes.reset_pending = true; }
fn enter(scopes: Scopes&) { scopes.active.push(true); scopes.stack.push(scopes.active.len - 1); }
fn leave(scopes: Scopes&) { if scopes.stack.len != 0 { let scope = scopes.stack.pop(); scopes.active[scope] = false; } }
fn scan(scopes: Scopes&, function: u32, code: const blot_backend_runtime_ir::Instruction[:]) {
    if scopes.reset_pending || !scopes.function.present || scopes.function.value != function || scopes.cursor > code.len {
        let count = scopes.active.len; for index in 0..count { scopes.active[index] = false; }
        scopes.stack.clear(); scopes.cursor = 0; scopes.function = blot_support::some(function); scopes.reset_pending = false; enter(scopes);
    }
    for inst in code[scopes.cursor..] {
        if inst.op == blot_backend_runtime_ir::OP_block || inst.op == blot_backend_runtime_ir::OP_loop || inst.op == blot_backend_runtime_ir::OP_if_ { enter(scopes); }
        else if inst.op == blot_backend_runtime_ir::OP_else_ { leave(scopes); enter(scopes); }
        else if inst.op == blot_backend_runtime_ir::OP_end { leave(scopes); }
    }
    scopes.cursor = code.len;
}
fn current(scopes: Scopes&) -> blot_support::Option<i64> {
    if scopes.reset_pending || scopes.stack.len == 0 { return blot_support::none<i64>(); }
    return blot_support::some(scopes.stack[scopes.stack.len - 1]);
}
fn contains(scopes: Scopes&, scope: blot_support::Option<i64>) -> bool {
    if scopes.reset_pending || !scope.present { return false; } return scope.value < scopes.active.len && scopes.active[scope.value];
}
