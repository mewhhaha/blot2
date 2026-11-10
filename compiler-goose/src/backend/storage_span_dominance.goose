// Scope identities survive suffix scans and are invalidated by explicit reset.
namespace blot_backend_storage_span_dominance;
import .runtime_ir;
import support.option;
import support.pooled_buffer;
import support.error;
struct Active { storage: bool[:] = default<bool[:]>(),items: bool[:] = default<bool[:]>() }
struct Stack { storage: i64[:] = default<i64[:]>(),items: i64[:] = default<i64[:]>() }
reusable[] var active_runs: bool[>..] = [];
reusable[] var stack_runs: i64[>..] = [];
struct Scopes { cursor: i64 = 0,function: blot_support::Option<u32>,active: Active,stack: Stack,reset_pending: bool = true }
fn reset(scopes: Scopes&) { scopes.reset_pending = true; }
fn deinit(scopes: Scopes&) { blot_support_pooled_buffer::deinit(scopes.active,active_runs); blot_support_pooled_buffer::deinit(scopes.stack,stack_runs); scopes.reset_pending = true; scopes.cursor = 0; scopes.function = blot_support::none<u32>(); }
fn enter(scopes: Scopes&) -> blot_error::Error { let error = blot_support_pooled_buffer::ensure(scopes.active,scopes.active.items.len + 1,active_runs); if error != blot_error::Error.none { return error; } let stack_error = blot_support_pooled_buffer::ensure(scopes.stack,scopes.stack.items.len + 1,stack_runs); if stack_error != blot_error::Error.none { return stack_error; } let index = scopes.active.items.len; let active=active_runs.realloc_slice(scopes.active.storage,scopes.active.storage.len);active[index]=true;scopes.active.items=active[..index+1]; let position = scopes.stack.items.len; let stack=stack_runs.realloc_slice(scopes.stack.storage,scopes.stack.storage.len);stack[position]=index;scopes.stack.items=stack[..position+1]; return blot_error::Error.none; }
fn leave(scopes: Scopes&) { if scopes.stack.items.len != 0 { let scope = scopes.stack.items[scopes.stack.items.len - 1]; blot_support_pooled_buffer::resize(scopes.stack,scopes.stack.items.len - 1); scopes.active.items[scope] = false; } }
fn scan(scopes: Scopes&,function: u32,code: const blot_backend_runtime_ir::Instruction[:]) -> blot_error::Error {
    if scopes.reset_pending || !scopes.function.present || scopes.function.value != function || scopes.cursor > code.len {
        for &active in scopes.active.items { active = false; } blot_support_pooled_buffer::clear(scopes.stack); scopes.cursor = 0; scopes.function = blot_support::some(function); scopes.reset_pending = false; let error = enter(scopes); if error != blot_error::Error.none { return error; }
    }
    for inst in code[scopes.cursor..] {
        if inst.op == blot_backend_runtime_ir::OP_block || inst.op == blot_backend_runtime_ir::OP_loop || inst.op == blot_backend_runtime_ir::OP_if_ { let error = enter(scopes); if error != blot_error::Error.none { return error; } }
        else if inst.op == blot_backend_runtime_ir::OP_else_ { leave(scopes); let error = enter(scopes); if error != blot_error::Error.none { return error; } }
        else if inst.op == blot_backend_runtime_ir::OP_end { leave(scopes); }
    }
    scopes.cursor = code.len; return blot_error::Error.none;
}
fn current(scopes: Scopes&) -> blot_support::Option<i64> { if scopes.reset_pending || scopes.stack.items.len == 0 { return blot_support::none<i64>(); } return blot_support::some(scopes.stack.items[scopes.stack.items.len - 1]); }
fn contains(scopes: Scopes&,scope: blot_support::Option<i64>) -> bool { if scopes.reset_pending || !scope.present { return false; } return scope.value < scopes.active.items.len && scopes.active.items[scope.value]; }
