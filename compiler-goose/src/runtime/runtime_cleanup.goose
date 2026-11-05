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
enum Backing { empty, lexical { value: Action[>..<]& }, pooled { run: Action[:], len: i64 } }
struct Stack { parent: const Stack? = null, actions: Backing = Backing.empty }
reusable[] var action_runs: Action[>..] = [];
fn init(actions: Action[>..<]&, parent: const Stack? = null) -> Stack { Stack { parent, Backing.lexical { actions } } }
// Recursive emitters carry only fixed descriptors. The run is an actual typed
// allocation, released when this lexical owner leaves, including error paths.
fn initPooled(parent: const Stack? = null) -> Stack, Error { return Stack { parent, Backing.pooled { [], 0 } }, Error.none; }
fn release(run: const Action[:]) { if run.len != 0 { let first: const Action& = run[0]; let at = action_runs.index_of(first); assert(at >= 0); action_runs.free_slice(action_runs[at..at + run.len]); } }
fn items(self: const Stack&) -> const Action[:] {
    match self.actions { Backing.empty => { return []; }, Backing.lexical backing => { return backing.value[..]; }, Backing.pooled backing => { return backing.run[..backing.len]; } }
}
fn deinit(self: Stack&) { match self.actions { Backing.empty => {}, Backing.lexical backing => { backing.value.clear(); }, Backing.pooled backing => { release(backing.run); } } self.actions = Backing.empty; self.parent .= null; }
fn mark(self: const Stack&) -> Mark { return self.items().len; }
fn restore(self: Stack&, checkpoint: Mark) {
    assert(checkpoint >= 0 && checkpoint <= self.mark());
    match self.actions { Backing.empty => {}, Backing.lexical backing => { backing.value.resize(checkpoint); }, Backing.pooled backing => { self.actions = Backing.pooled { backing.run, checkpoint }; } }
}
fn since(self: const Stack&, checkpoint: Mark) -> const Action[:] { return self.items()[checkpoint..]; }
fn append(self: Stack&, action: Action) -> Error {
    match self.actions {
        Backing.empty => { return Error.invalid_artifact; },
        Backing.lexical backing => { backing.value.push(action); },
        Backing.pooled backing => {
            var run = backing.run;
            if backing.len == run.len {
                if backing.len > 0x5555555555555540 { return Error.out_of_memory; }
                let minimum = backing.len + 1; let next = minimum + minimum / 2 + 7;
                let replacement = action_runs.alloc_slice(next); for index in backing.len { replacement[index] = run[index]; }
                release(run); run = replacement;
            }
            run[backing.len] = action; self.actions = Backing.pooled { run, backing.len + 1 };
        },
    } return Error.none;
}
fn emitTo(self: const Stack&, module: Module&, function: u32, checkpoint: Mark) -> Error {
    return emitToResult(self, module, function, checkpoint, blot_support::none<u32>());
}
fn emitToResult(self: const Stack&, module: Module&, function: u32, checkpoint: Mark,
    result: blot_support::Option<u32>) -> Error {
    let actions = self.items(); assert(checkpoint >= 0 && checkpoint <= actions.len);
    var index = actions.len;
    while index > checkpoint {
        index--;
        match actions[index] {
            Action.task_group => { let error = emit(actions[index], module, function, result); if error != Error.none { return error; } },
            _ => {},
        }
    }
    for action in actions[checkpoint..] {
        match action {
            Action.revoke_effect => { let error = emit(action, module, function, result); if error != Error.none { return error; } },
            _ => {},
        }
    }
    index = actions.len;
    while index > checkpoint {
        index--;
        match actions[index] {
            Action.revoke_effect, Action.task_group => {},
            _ => { let error = emit(actions[index], module, function, result); if error != Error.none { return error; } },
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
