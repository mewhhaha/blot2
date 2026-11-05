// Lexical cleanup order: task groups, effect revocation, then storage unwinding.
namespace blot_runtime_runtime_cleanup;
import backend.runtime_ir;
import backend.wasm;
import runtime.runtime_layout;
import support.error;
import support.option;
type Error = blot_error::Error;
type Mark = i64;
type Module = blot_backend_wasm::Module;
type Local = blot_backend_runtime_ir::LocalId;
enum Action {
    task_group { owner: Local, close: u32 }, resource { token: Local, release: u32 },
    release { local: Local }, release_if_nonzero { local: Local }, root_scope,
    revoke_effect { local: Local },
}
struct Stack { parent: const Stack? = null, actions: Action[>..<]& }
fn init(actions: Action[>..<]&, parent: const Stack? = null) -> Stack { Stack { parent, actions } }
fn deinit(self: Stack&) { self.actions.clear(); }
fn mark(self: const Stack&) -> Mark { self.actions.len }
fn restore(self: Stack&, checkpoint: Mark) { self.actions.resize(checkpoint); }
fn since(self: const Stack&, checkpoint: Mark) -> const Action[:] { self.actions[checkpoint..] }
fn append(self: Stack&, action: Action) -> Error { self.actions.push(action); return Error.none; }
fn emitTo(self: const Stack&, module: Module&, function: u32, checkpoint: Mark) -> Error {
    return emitToResult(self, module, function, checkpoint, blot_support::none<u32>());
}
fn emitToResult(self: const Stack&, module: Module&, function: u32, checkpoint: Mark,
    result: blot_support::Option<u32>) -> Error {
    assert(checkpoint >= 0 && checkpoint <= self.actions.len);
    var index = self.actions.len;
    while index > checkpoint {
        index--;
        match self.actions[index] {
            Action.task_group => { let error = emit(self.actions[index], module, function, result); if error != Error.none { return error; } },
            _ => {},
        }
    }
    for action in self.actions[checkpoint..] {
        match action {
            Action.revoke_effect => { let error = emit(action, module, function, result); if error != Error.none { return error; } },
            _ => {},
        }
    }
    index = self.actions.len;
    while index > checkpoint {
        index--;
        match self.actions[index] {
            Action.revoke_effect, Action.task_group => {},
            _ => { let error = emit(self.actions[index], module, function, result); if error != Error.none { return error; } },
        }
    }
    return Error.none;
}
recursive fn emitAll(self: const Stack&, module: Module&, function: u32) -> Error {
    let error = emitTo(self, module, function, 0); if error != Error.none { return error; }
    { let optional_source_59 .= self.parent; if optional_source_59 { let parent .= optional_source_59; return parent.emitAll(module, function);  } }
    return Error.none;
}
fn emit(action: Action, module: Module&, function: u32, result: blot_support::Option<u32>) -> Error {
    var code: blot_backend_runtime_ir::Instruction[>..<] = [];
    match action {
        Action.task_group group => {
            code.push(blot_backend_runtime_ir::Instruction { blot_backend_runtime_ir::OP_local_get, group.owner });
            code.push(blot_backend_runtime_ir::Instruction { blot_backend_runtime_ir::OP_i32_load, blot_runtime_runtime_layout::EffectAuthority_active });
            code.push(blot_backend_runtime_ir::Instruction { blot_backend_runtime_ir::OP_call_import, group.close });
        },
        Action.resource journal => {
            let drain, has_drain = module.taskImportNamed("drain");
            if has_drain { code.push(blot_backend_runtime_ir::Instruction { blot_backend_runtime_ir::OP_call_import, drain }); }
            code.push(blot_backend_runtime_ir::Instruction { blot_backend_runtime_ir::OP_local_get, journal.token });
            code.push(blot_backend_runtime_ir::Instruction { blot_backend_runtime_ir::OP_call_import, journal.release });
        },
        Action.revoke_effect local => {
            code.push(blot_backend_runtime_ir::Instruction { blot_backend_runtime_ir::OP_local_get, local.local });
            code.push(blot_backend_runtime_ir::Instruction { blot_backend_runtime_ir::OP_i32_const, 0 });
            code.push(blot_backend_runtime_ir::Instruction { blot_backend_runtime_ir::OP_i32_store, blot_runtime_runtime_layout::EffectAuthority_active });
        },
        Action.root_scope => {
            var chunk: u32 = 1; var roles: u32 = 0;
            if result.present { chunk = 2; roles = result.value; }
            let scope = blot_backend_runtime_ir::Ownership {
                kind: blot_backend_runtime_ir::OWN_scope, chunk: chunk as u8, roles: roles,
            };
            code.push(blot_backend_runtime_ir::Instruction { blot_backend_runtime_ir::OP_ownership, blot_backend_runtime_ir::pack(scope) });
        },
        Action.release local => {
            assert(module.arena.present);
            code.push(blot_backend_runtime_ir::Instruction { blot_backend_runtime_ir::OP_local_get, local.local });
            code.push(blot_backend_runtime_ir::Instruction { blot_backend_runtime_ir::OP_call, module.arena.value.recycle });
        },
        Action.release_if_nonzero local => {
            assert(module.arena.present);
            code.push(blot_backend_runtime_ir::Instruction { blot_backend_runtime_ir::OP_local_get, local.local });
            code.push(blot_backend_runtime_ir::Instruction { blot_backend_runtime_ir::OP_if_, 0 });
            code.push(blot_backend_runtime_ir::Instruction { blot_backend_runtime_ir::OP_local_get, local.local });
            code.push(blot_backend_runtime_ir::Instruction { blot_backend_runtime_ir::OP_call, module.arena.value.recycle });
            code.push(blot_backend_runtime_ir::Instruction { blot_backend_runtime_ir::OP_end, 0 });
        },
    }
    for inst in code { let error = module.emit(function, inst); if error != Error.none { return error; } }
    return Error.none;
}
