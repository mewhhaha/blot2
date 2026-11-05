// Lexical cleanup order: task groups, effect revocation, then storage unwinding.
namespace blot_runtime_runtime_cleanup;
import backend.runtime_ir;
import backend.wasm;
import runtime.runtime_layout;
import support.error;
import support.option;
import support.native;
type Error = blot_error::Error;
type Mark = i64;
type Module = blot_backend_wasm::Module;
type Local = blot_backend_runtime_ir::LocalId;
enum Action {
    task_group { owner: Local, close: u32 }, resource { token: Local, release: u32 },
    release { local: Local }, release_if_nonzero { local: Local }, root_scope,
    revoke_effect { local: Local },
}
struct FrameKey { id: u32 = 0, generation: u64 = 0 }
struct Frame { generation: u64 = 0, parent: FrameKey = FrameKey {..}, run: Action[:] = default<Action[:]>(), len: i64 = 0 }
enum Backing { empty, lexical { value: Action[>..<]& }, pooled { key: FrameKey } }
struct Stack { parent: const Stack? = null, actions: Backing = Backing.empty }
reusable[] var action_runs: Action[>..] = [];
reusable[] var frames: Frame[>..] = [];
fn init(actions: Action[>..<]&, parent: const Stack? = null) -> Stack { Stack { parent, Backing.lexical { actions , ..} } }
// Recursive emission links global typed frames by value. A child never retains
// a reference into the recursive caller's local Owner or cleanup descriptor.
fn initPooled(parent: const Stack? = null) -> Stack, Error {
    var parent_key = FrameKey {..};
    if parent {
        match parent.actions {
            empty => {}, pooled value => { parent_key = value.key; },
            lexical => { return Stack {..}, blot_error::Error.invalid_artifact; },
        }
    }
    let run = frames.alloc_slice(1); let exact = frames.realloc_slice(run,1); let first: const Frame& = exact[0]; let at = frames.index_of(first);
    if at >= 0xffffffff { frames.free_slice(run); return Stack {..}, blot_error::Error.out_of_memory; }
    let generation = blot_native::fresh_owner_id(); run[0] = Frame { generation: generation, parent: parent_key , ..};
    return Stack { actions: Backing.pooled { FrameKey { (at + 1) as u32, generation } , ..} , ..}, blot_error::Error.none;
}
fn frame(key: FrameKey) -> Frame& { assert(key.id != 0); let result: Frame& = frames[key.id - 1]; assert(result.generation == key.generation && key.generation != 0); return result; }
fn release(run: const Action[:]) { if run.len != 0 { action_runs.free_slice(run); } }
fn items(receiver: const Stack&) -> const Action[:] {
    match receiver.actions {
        empty => { return default<const Action[:]>(); }, lexical backing => { return backing.value[..]; },
        pooled backing => { let value .= frame(backing.key); return value.run[..value.len]; },
    }
}
fn deinit(receiver: Stack&) {
    match receiver.actions {
        empty => {}, lexical backing => { backing.value.clear(); },
        pooled backing => {
            let value .= frame(backing.key); release(value.run); value.generation = 0;
            frames.free_slice(frames[backing.key.id - 1..backing.key.id]);
        },
    }
    receiver.actions = Backing.empty; receiver.parent .= null;
}
fn mark(receiver: const Stack&) -> Mark { return receiver.items().len; }
fn restore(receiver: Stack&, checkpoint: Mark) {
    assert(checkpoint >= 0 && checkpoint <= receiver.mark());
    match receiver.actions { empty => {}, lexical backing => { backing.value.resize(checkpoint); }, pooled backing => { frame(backing.key).len = checkpoint; } }
}
fn since(receiver: const Stack&, checkpoint: Mark) -> const Action[:] { return receiver.items()[checkpoint..]; }
fn append(receiver: Stack&, action: Action) -> Error {
    match receiver.actions {
        empty => { return blot_error::Error.invalid_artifact; },
        lexical backing => { backing.value.push(action); },
        pooled backing => {
            let value .= frame(backing.key);
            if value.len == value.run.len {
                if value.len > 0x5555555555555540 { return blot_error::Error.out_of_memory; }
                let minimum = value.len + 1; let next = minimum + minimum / 2 + 7;
                let replacement = action_runs.alloc_slice(next); for index in 0..value.len { replacement[index] = value.run[index]; }
                release(value.run); value.run = replacement;
            }
            value.run[value.len] = action; value.len++;
        },
    }
    return blot_error::Error.none;
}
fn emitTo(receiver: const Stack&, module: Module&, function: u32, checkpoint: Mark) -> Error {
    return emitToResult(receiver, module, function, checkpoint, blot_support::none<u32>());
}
fn emitToResult(receiver: const Stack&, module: Module&, function: u32, checkpoint: Mark,
    result: blot_support::Option<u32>) -> Error {
    return emitActions(receiver.items(), module, function, checkpoint, result);
}
fn emitActions(actions: const Action[:], module: Module&, function: u32, checkpoint: Mark, result: blot_support::Option<u32>) -> Error {
    assert(checkpoint >= 0 && checkpoint <= actions.len);
    var index = actions.len;
    while index > checkpoint {
        index--;
        match actions[index] {
            task_group => { let error = emit(actions[index], module, function, result); if error != blot_error::Error.none { return error; } },
            _ => {},
        }
    }
    for action in actions[checkpoint..] {
        match action {
            revoke_effect => { let error = emit(action, module, function, result); if error != blot_error::Error.none { return error; } },
            _ => {},
        }
    }
    index = actions.len;
    while index > checkpoint {
        index--;
        match actions[index] {
            revoke_effect, task_group => {},
            _ => { let error = emit(actions[index], module, function, result); if error != blot_error::Error.none { return error; } },
        }
    }
    return blot_error::Error.none;
}
fn emitAll(receiver: const Stack&, module: Module&, function: u32) -> Error {
    var current: const Stack? = receiver;
    while current {
        let error = emitTo(current, module, function, 0); if error != blot_error::Error.none { return error; }
        match current.actions {
            pooled backing => { return emitParents(frame(backing.key).parent, module, function); },
            _ => { current .= current.parent; },
        }
    }
    return blot_error::Error.none;
}
fn emitParents(first: FrameKey, module: Module&, function: u32) -> Error {
    var key = first;
    while key.id != 0 {
        let value .= frame(key);
        let error = emitActions(value.run[..value.len], module, function, 0, blot_support::none<u32>());
        if error != blot_error::Error.none { return error; }
        key = value.parent;
    }
    return blot_error::Error.none;
}
fn emit(action: Action, module: Module&, function: u32, result: blot_support::Option<u32>) -> Error {
    var code: blot_backend_runtime_ir::Instruction[>..<] = [];
    match action {
        task_group group => {
            code.push(blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,group.owner));
            code.push(blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,blot_runtime_runtime_layout::EffectAuthority_active));
            code.push(blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_call_import,group.close));
        },
        resource journal => {
            let drain, has_drain = module.taskImportNamed("drain");
            if has_drain { code.push(blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_call_import,drain)); }
            code.push(blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,journal.token));
            code.push(blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_call_import,journal.release));
        },
        revoke_effect local => {
            code.push(blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,local.local));
            code.push(blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,0));
            code.push(blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_store,blot_runtime_runtime_layout::EffectAuthority_active));
        },
        root_scope => {
            var chunk: u32 = 1; var roles: u32 = 0;
            if result.present { chunk = 2; roles = result.value; }
            let scope = blot_backend_runtime_ir::Ownership {
                kind: blot_backend_runtime_ir::OWN_scope, chunk: chunk as u8, roles: roles,
             ..};
            code.push(blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_ownership,blot_backend_runtime_ir::pack(scope)));
        },
        release local => {
            assert(module.arena.present);
            code.push(blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,local.local));
            code.push(blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_call,module.arena.value.recycle));
        },
        release_if_nonzero local => {
            assert(module.arena.present);
            code.push(blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,local.local));
            code.push(blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_if_,0));
            code.push(blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,local.local));
            code.push(blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_call,module.arena.value.recycle));
            code.push(blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_end,0));
        },
    }
    for inst in code { let error = module.emit(function, inst); if error != blot_error::Error.none { return error; } }
    return blot_error::Error.none;
}
