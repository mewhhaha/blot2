// Installation describes storage only; source rewrite authority remains separate.
namespace blot_runtime_region_runtime;
import backend.wasm;
import backend.runtime_ir;
import backend.runtime_code;
import runtime.runtime_layout;
import runtime.shared_rc;
import runtime.root_runtime;
import support.emitter;
import support.error;
import support.option;
type Error = blot_error::Error;
type Module = blot_backend_wasm::Module;
type Arena = blot_backend_wasm::Arena;
type Local = blot_backend_runtime_code::Local;
type Code = blot_emitter::Emitter<Module>;
let flag: u32 = 16384;
struct Member { offset: u32, bytes: u32 }
struct Plan { frame_bytes: u32, bytes: u32, mask: u32, members: const Member[:] }
fn valid(self: Plan) -> bool {
    if self.frame_bytes == 0 || self.frame_bytes % 4 != 0 || self.bytes % 4 != 0 || self.bytes > 124 || self.members.len == 0 || self.members.len > 32 { return false; }
    var end = self.frame_bytes;
    for member in self.members {
        if member.offset < end || member.offset % 4 != 0 || member.bytes == 0 || member.bytes % 4 != 0 || member.offset > self.bytes || member.bytes > self.bytes - member.offset { return false; }
        end = member.offset + member.bytes;
        for word in member.offset / 4..end / 4 { if self.mask & ((1 as u32) << (word as u32)) != 0 { return false; } }
    }
    return end == self.bytes && self.mask >> (self.frame_bytes / 4) == 0;
}
struct Runtime { allocate: u32, project: u32, store: u32, close: u32, frame_allocate: u32, member_at: u32 }
fn contains(self: Runtime, id: i64) -> bool { const for <N,A> in fields<Runtime> { if id == self.A { return true; } } return false; }
struct Scope { function: u32, parameter: u32 }
struct Prepared { runtime: Runtime, plan: Plan, scopes: const Scope[:] }
struct Contract { id: u32, parameters: const blot_backend_runtime_ir::ValueType[:], result: blot_backend_runtime_ir::ValueType, result_role: blot_backend_runtime_ir::Role, roles: u64 }
fn valid(self: Prepared, module: const Module&) -> bool {
    if !self.plan.valid() { return false; }
    let i32 = blot_backend_runtime_ir::VT_i32; let none = blot_backend_runtime_ir::VT_none;
    let reference = blot_backend_runtime_ir::ROLE_reference; let scalar = blot_backend_runtime_ir::ROLE_scalar;
    let reference_pair = blot_backend_runtime_ir::packParameterRoles([reference, reference]);
    let contracts = [
        Contract { self.runtime.allocate, [], i32, reference, 0 },
        Contract { self.runtime.project, [i32, i32], i32, reference, reference_pair },
        Contract { self.runtime.store, [i32, i32, i32], none, scalar, blot_backend_runtime_ir::packParameterRoles([scalar, reference, reference]) },
        Contract { self.runtime.close, [i32, i32], none, scalar, reference_pair },
        Contract { self.runtime.frame_allocate, [i32], i32, reference, blot_backend_runtime_ir::packParameterRoles([scalar]) },
        Contract { self.runtime.member_at, [i32, i32], i32, reference, blot_backend_runtime_ir::packParameterRoles([reference, scalar]) },
    ];
    for contract, at in contracts {
        if contract.id >= module.functions.len { return false; }
        for previous in contracts[..at] { if previous.id == contract.id { return false; } }
        let body = module.functions[contract.id];
        let parameters = module.types[body.parameters.start..body.parameters.start + body.parameters.len];
        if body.entry || body.result != contract.result || body.result_role != contract.result_role || body.parameter_roles != contract.roles || parameters != contract.parameters { return false; }
    }
    for entry, at in self.scopes {
        if entry.function >= module.functions.len || self.runtime.contains(entry.function) { return false; }
        for previous in self.scopes[..at] { if previous.function == entry.function { return false; } }
        let body = module.functions[entry.function];
        if body.entry || entry.parameter != body.provider_parameter || entry.parameter >= body.parameters.len || body.parameterRole(entry.parameter) != reference || module.types[body.parameters.start + entry.parameter] != i32 { return false; }
    }
    return true;
}
fn scope(module: const Module&, function: i64) -> blot_support::Option<Scope> {
    if !module.regions.present { return blot_support::none<Scope>(); }
    for entry in module.regions.value.scopes { if entry.function == function { return blot_support::some(entry); } }
    return blot_support::none<Scope>();
}
fn complete(c: Code&, arena: Arena) {
    c.globalGet(arena.rc_enabled); c.op(blot_backend_runtime_ir::OP_i32_eqz); c.trap();
    c.globalGet(arena.root_enabled); c.value(blot_runtime_root_runtime::enabled | blot_runtime_root_runtime::complete); c.op(blot_backend_runtime_ir::OP_i32_ne); c.trap();
}
fn owner(c: Code&, arena: Arena, plan: Plan, value: Local) -> Local {
    complete(c, arena); c.value(value); c.globalGet(arena.static_end); c.op(blot_backend_runtime_ir::OP_i32_lt_u); c.trap();
    if c.failure != Error.none { return Local {}; }
    let head, error = blot_runtime_shared_rc::checkedHead(c.code, value); c.failure = error;
    c.value(head); c.load(blot_runtime_runtime_layout::ArenaHeader_flags); c.value(flag); c.op(blot_backend_runtime_ir::OP_i32_and); c.op(blot_backend_runtime_ir::OP_i32_eqz); c.trap();
    c.value(head); c.load(blot_runtime_runtime_layout::ArenaHeader_flags); c.value(blot_runtime_shared_rc::dead | blot_runtime_shared_rc::resource_owner); c.op(blot_backend_runtime_ir::OP_i32_and); c.trap();
    c.value(head); c.load(blot_runtime_runtime_layout::ArenaHeader_requested); c.value(plan.bytes); c.op(blot_backend_runtime_ir::OP_i32_ne); c.trap();
    c.value(head); c.load(blot_runtime_runtime_layout::ArenaHeader_strong); c.op(blot_backend_runtime_ir::OP_i32_eqz); c.trap();
    return head;
}
fn emitAllocate(c: Code&, arena: Arena, plan: Plan) -> Error {
    complete(c, arena); let value = c.temp(); c.value(plan.bytes); c.value(plan.mask); c.call(arena.root_allocate); c.set(value);
    if plan.mask == 0 { c.value(value); c.value(0); c.value(plan.bytes); c.zero(); }
    let head = c.temp(); c.value(value); c.value(blot_runtime_runtime_layout::ArenaHeader_bytes); c.op(blot_backend_runtime_ir::OP_i32_sub); c.set(head);
    c.value(head); c.value(head); c.load(blot_runtime_runtime_layout::ArenaHeader_flags); c.value(flag); c.op(blot_backend_runtime_ir::OP_i32_or); c.store(blot_runtime_runtime_layout::ArenaHeader_flags);
    c.value(value); return c.failure;
}
fn emitProject(c: Code&, arena: Arena, plan: Plan) -> Error {
    let value = Local { 0 }; let parent = Local { 1 }; let checked = owner(c, arena, plan, parent);
    for member in plan.members { c.value(value); c.value(parent); c.value(member.offset); c.op(blot_backend_runtime_ir::OP_i32_add); c.op(blot_backend_runtime_ir::OP_i32_eq); c.when(); c.value(parent); c.ret(); c.end(); }
    c.value(value); c.value(parent); c.value(plan.frame_bytes); c.op(blot_backend_runtime_ir::OP_i32_add); c.op(blot_backend_runtime_ir::OP_i32_ge_u); c.value(value); c.value(parent); c.value(plan.bytes); c.op(blot_backend_runtime_ir::OP_i32_add); c.op(blot_backend_runtime_ir::OP_i32_lt_u); c.op(blot_backend_runtime_ir::OP_i32_and); c.trap();
    c.value(value); return c.failure;
}
fn allocateFunctions(module: Module&) -> Runtime, Error {
    let i32 = blot_backend_runtime_ir::VT_i32; let none = blot_backend_runtime_ir::VT_none;
    let reference = blot_backend_runtime_ir::ROLE_reference; let scalar = blot_backend_runtime_ir::ROLE_scalar;
    var ids: u32[6]; let counts: i64[6] = [0, 2, 3, 2, 1, 2]; let results = [i32, i32, none, none, i32, i32];
    let roles = [reference, reference, scalar, scalar, reference, reference]; let parameters = [i32, i32, i32];
    for index in 0..6 {
        let id, error = module.addTypedFunction(parameters[..counts[index]], results[index], roles[index]);
        if error != Error.none { return default<Runtime>(), error; } ids[index] = id;
    }
    return Runtime { ids[0], ids[1], ids[2], ids[3], ids[4], ids[5] }, Error.none;
}
fn install(module: Module&, plan: Plan) -> Runtime, Error {
    if !plan.valid() { return default<Runtime>(), Error.invalid_region; }
    if !module.arena.present { return default<Runtime>(), Error.missing_arena; }
    let arena = module.arena.value;
    let result, error = allocateFunctions(module); if error != Error.none { return default<Runtime>(), error; }
    let reference = blot_backend_runtime_ir::ROLE_reference; let scalar = blot_backend_runtime_ir::ROLE_scalar;
    { let propagated_error = module.setParameterRoles(result.project, blot_backend_runtime_ir::packParameterRoles([reference, reference])); if propagated_error != Error.none { return default<Runtime>(), propagated_error; } }
    { let propagated_error = module.setParameterRoles(result.store, blot_backend_runtime_ir::packParameterRoles([scalar, reference, reference])); if propagated_error != Error.none { return default<Runtime>(), propagated_error; } }
    { let propagated_error = module.setParameterRoles(result.close, blot_backend_runtime_ir::packParameterRoles([reference, reference])); if propagated_error != Error.none { return default<Runtime>(), propagated_error; } }
    { let propagated_error = module.setParameterRoles(result.frame_allocate, blot_backend_runtime_ir::packParameterRoles([scalar])); if propagated_error != Error.none { return default<Runtime>(), propagated_error; } }
    { let propagated_error = module.setParameterRoles(result.member_at, blot_backend_runtime_ir::packParameterRoles([reference, scalar])); if propagated_error != Error.none { return default<Runtime>(), propagated_error; } }
    var frame = blot_emitter::init(module, result.frame_allocate); let frame_bytes = Local { 0 };
    frame.value(frame_bytes); frame.value(plan.frame_bytes); frame.op(blot_backend_runtime_ir::OP_i32_ne); frame.trap(); frame.call(result.allocate);
    { let propagated_error = frame.failure; if propagated_error != Error.none { return default<Runtime>(), propagated_error; } }
    var member = blot_emitter::init(module, result.member_at); let parent = Local { 0 }; let offset = Local { 1 };
    let checked = owner(member, arena, plan, parent); let matched = member.temp();
    for entry in plan.members { member.value(matched); member.value(offset); member.value(entry.offset); member.op(blot_backend_runtime_ir::OP_i32_eq); member.op(blot_backend_runtime_ir::OP_i32_or); member.set(matched); }
    member.value(matched); member.op(blot_backend_runtime_ir::OP_i32_eqz); member.trap(); member.value(parent); member.value(offset); member.op(blot_backend_runtime_ir::OP_i32_add);
    { let propagated_error = member.failure; if propagated_error != Error.none { return default<Runtime>(), propagated_error; } }
    var allocation = blot_emitter::init(module, result.allocate); { let propagated_error = emitAllocate(allocation, arena, plan); if propagated_error != Error.none { return default<Runtime>(), propagated_error; } }
    var projection = blot_emitter::init(module, result.project); { let propagated_error = emitProject(projection, arena, plan); if propagated_error != Error.none { return default<Runtime>(), propagated_error; } }
    var store = blot_emitter::init(module, result.store); let target = Local { 0 }; let value = Local { 1 }; let value_owner = Local { 2 };
    store.value(target); store.value(value); store.value(value_owner); store.call(result.project); store.call(arena.root_store); { let propagated_error = store.failure; if propagated_error != Error.none { return default<Runtime>(), propagated_error; } }
    var close = blot_emitter::init(module, result.close);
    close.value(target); close.value(value); close.call(result.project); close.call(arena.root_close); { let propagated_error = close.failure; if propagated_error != Error.none { return default<Runtime>(), propagated_error; } }
    return result, Error.none;
}
