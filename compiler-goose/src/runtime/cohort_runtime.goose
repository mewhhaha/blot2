// Bounded activation cohorts retire only through their ordinary leased owner.
namespace blot_runtime_cohort_runtime;
import backend.wasm;
import backend.runtime_ir;
import backend.runtime_code;
import runtime.runtime_layout;
import runtime.shared_rc;
import runtime.cycles_runtime;
import runtime.root_runtime;
import support.emitter;
import support.error;
import support.option;
type Error = blot_error::Error;
type Module = blot_backend_wasm::Module;
type Arena = blot_backend_wasm::Arena;
type Local = blot_backend_runtime_code::Local;
type Code = blot_emitter::Emitter<Module>;
struct Runtime { begin: u32, allocate: u32, retire_members: u32 }
let member: u32 = 4096; let owner: u32 = 8192; let capacity: u32 = 64;
let header: u32 = blot_runtime_runtime_layout::ArenaHeader_bytes;
let flags: u32 = blot_runtime_runtime_layout::ArenaHeader_flags;
let strong: u32 = blot_runtime_runtime_layout::ArenaHeader_strong;
let next: u32 = blot_runtime_runtime_layout::ArenaHeader_candidate_next;
fn complete(c: Code&, arena: Arena) {
    c.globalGet(arena.rc_enabled); c.op(blot_backend_runtime_ir::OP_i32_eqz); c.trap();
    c.globalGet(arena.root_enabled); c.value(blot_runtime_root_runtime::enabled | blot_runtime_root_runtime::complete); c.op(blot_backend_runtime_ir::OP_i32_ne); c.trap();
}
fn checked(c: Code&, arena: Arena, pointer: Local) -> Local {
    c.value(pointer); c.globalGet(arena.static_end); c.op(blot_backend_runtime_ir::OP_i32_lt_u); c.trap();
    if c.failure != Error.none { return Local {..}; }
    let head, error = blot_runtime_shared_rc::checkedHead(c.code, pointer);
    c.failure = error; return head;
}
fn excluded() -> u32 { return blot_runtime_cycles_runtime::queued | blot_runtime_shared_rc::dead | blot_runtime_shared_rc::resource_owner; }
fn begin(c: Code&, arena: Arena) -> Error {
    let pointer = Local { 0 , ..}; complete(c, arena); let head = checked(c, arena, pointer);
    c.value(head); c.load(flags); c.value(excluded() | member | owner); c.op(blot_backend_runtime_ir::OP_i32_and); c.trap();
    c.value(head); c.load(flags); c.value(blot_runtime_shared_rc::lease); c.op(blot_backend_runtime_ir::OP_i32_and); c.op(blot_backend_runtime_ir::OP_i32_eqz); c.trap();
    c.value(head); c.load(strong); c.value(1); c.op(blot_backend_runtime_ir::OP_i32_ne); c.trap();
    c.value(head); c.load(next); c.trap();
    c.value(head); c.value(head); c.load(flags); c.value(owner); c.op(blot_backend_runtime_ir::OP_i32_or); c.store(flags);
    return c.failure;
}
fn allocate(c: Code&, arena: Arena) -> Error {
    let bytes = Local { 0 , ..}; let mask = Local { 1 , ..}; let parent = Local { 2 , ..};
    complete(c, arena); let head = checked(c, arena, parent);
    c.value(bytes); c.op(blot_backend_runtime_ir::OP_i32_eqz); c.trap();
    c.value(head); c.load(flags); c.value(excluded() | member); c.op(blot_backend_runtime_ir::OP_i32_and); c.trap();
    c.value(head); c.load(flags); c.value(owner | blot_runtime_shared_rc::lease); c.op(blot_backend_runtime_ir::OP_i32_and); c.value(owner | blot_runtime_shared_rc::lease); c.op(blot_backend_runtime_ir::OP_i32_ne); c.trap();
    let current = c.temp(); let count = c.temp();
    c.value(head); c.load(next); c.set(current);
    c.loopStart(); c.value(current); c.loopTest();
    c.value(count); c.value(capacity); c.op(blot_backend_runtime_ir::OP_i32_ge_u); c.trap();
    let item = checked(c, arena, current);
    c.value(item); c.load(flags); c.value(member); c.op(blot_backend_runtime_ir::OP_i32_and); c.op(blot_backend_runtime_ir::OP_i32_eqz); c.trap();
    c.value(item); c.load(next); c.set(current); c.next(count); c.again();
    c.value(count); c.value(capacity); c.op(blot_backend_runtime_ir::OP_i32_ge_u); c.trap();
    let value = c.temp(); c.value(bytes); c.value(mask); c.call(arena.allocate_typed); c.set(value);
    let allocated = c.temp(); c.value(value); c.value(header); c.op(blot_backend_runtime_ir::OP_i32_sub); c.set(allocated);
    c.value(allocated); c.value(allocated); c.load(flags); c.value(~blot_runtime_shared_rc::lease); c.op(blot_backend_runtime_ir::OP_i32_and); c.value(member); c.op(blot_backend_runtime_ir::OP_i32_or); c.store(flags);
    c.globalGet(arena.rc_leases); c.value(1); c.op(blot_backend_runtime_ir::OP_i32_sub); c.globalSet(arena.rc_leases);
    c.value(allocated); c.value(head); c.load(next); c.store(next); c.value(head); c.value(value); c.store(next);
    c.value(value); return c.failure;
}
fn retire(c: Code&, arena: Arena) -> Error {
    let pointer = Local { 0 , ..};
    c.value(pointer); c.globalGet(arena.static_end); c.op(blot_backend_runtime_ir::OP_i32_lt_u); c.when(); c.ret(); c.end();
    let head = checked(c, arena, pointer);
    c.value(head); c.load(flags); c.value(member); c.op(blot_backend_runtime_ir::OP_i32_and); c.when();
    c.value(head); c.load(flags); c.value(blot_runtime_shared_rc::dead); c.op(blot_backend_runtime_ir::OP_i32_and); c.op(blot_backend_runtime_ir::OP_i32_eqz); c.trap(); c.end();
    c.value(head); c.load(flags); c.value(owner); c.op(blot_backend_runtime_ir::OP_i32_and); c.op(blot_backend_runtime_ir::OP_i32_eqz); c.when(); c.ret(); c.end();
    complete(c, arena);
    c.value(head); c.load(flags); c.value(excluded() | member | blot_runtime_shared_rc::lease); c.op(blot_backend_runtime_ir::OP_i32_and); c.trap();
    c.value(head); c.load(flags); c.value(owner); c.op(blot_backend_runtime_ir::OP_i32_and); c.op(blot_backend_runtime_ir::OP_i32_eqz); c.trap();
    c.value(head); c.load(strong); c.trap();
    let current = c.temp(); let count = c.temp(); c.value(head); c.load(next); c.set(current);
    c.loopStart(); c.value(current); c.loopTest(); c.value(count); c.value(capacity); c.op(blot_backend_runtime_ir::OP_i32_ge_u); c.trap();
    let item = checked(c, arena, current);
    c.value(item); c.load(flags); c.value(excluded() | owner | blot_runtime_shared_rc::lease); c.op(blot_backend_runtime_ir::OP_i32_and); c.trap();
    c.value(item); c.load(flags); c.value(member); c.op(blot_backend_runtime_ir::OP_i32_and); c.op(blot_backend_runtime_ir::OP_i32_eqz); c.trap();
    c.value(item); c.load(strong); c.value(1); c.op(blot_backend_runtime_ir::OP_i32_ne); c.trap();
    c.value(item); c.load(next); c.set(current); c.next(count); c.again();
    c.value(head); c.value(head); c.load(flags); c.value(blot_runtime_shared_rc::dead); c.op(blot_backend_runtime_ir::OP_i32_or); c.store(flags);
    c.value(head); c.load(next); c.set(current); c.loopStart(); c.value(current); c.loopTest();
    let classified = c.temp(); c.value(current); c.value(header); c.op(blot_backend_runtime_ir::OP_i32_sub); c.set(classified);
    c.value(classified); c.value(classified); c.load(flags); c.value(blot_runtime_shared_rc::dead); c.op(blot_backend_runtime_ir::OP_i32_or); c.store(flags);
    c.value(classified); c.value(0); c.store(strong);
    c.globalGet(arena.rc_releases); c.value(1); c.op(blot_backend_runtime_ir::OP_i32_add); c.globalSet(arena.rc_releases);
    c.value(classified); c.load(next); c.set(current); c.again();
    c.value(head); c.load(next); c.set(current); c.value(head); c.value(0); c.store(next);
    c.loopStart(); c.value(current); c.loopTest(); let next_member = c.temp();
    c.value(current); c.value(header); c.op(blot_backend_runtime_ir::OP_i32_sub); c.load(next); c.set(next_member);
    c.value(current); c.call(arena.retire); c.set(current, next_member); c.again();
    return c.failure;
}
fn install(module: Module&) -> Runtime, Error {
    if module.cohorts.present { return module.cohorts.value, Error.none; }
    if !module.arena.present { return default<Runtime>(), Error.missing_arena; }
    let arena = module.arena.value;
    let begin_id, begin_error = module.addTypedFunction([blot_backend_runtime_ir::VT_i32], blot_backend_runtime_ir::VT_none, blot_backend_runtime_ir::ROLE_scalar);
    if begin_error != Error.none { return default<Runtime>(), begin_error; }
    let allocate_id, allocate_error = module.addTypedFunction([blot_backend_runtime_ir::VT_i32, blot_backend_runtime_ir::VT_i32, blot_backend_runtime_ir::VT_i32], blot_backend_runtime_ir::VT_i32, blot_backend_runtime_ir::ROLE_reference);
    if allocate_error != Error.none { return default<Runtime>(), allocate_error; }
    let retire_id, retire_error = module.addTypedFunction([blot_backend_runtime_ir::VT_i32], blot_backend_runtime_ir::VT_none, blot_backend_runtime_ir::ROLE_scalar);
    if retire_error != Error.none { return default<Runtime>(), retire_error; }
    let runtime = Runtime { begin_id, allocate_id, retire_id , ..};
    let reference = blot_backend_runtime_ir::ROLE_reference;
    let scalar = blot_backend_runtime_ir::ROLE_scalar;
    { let propagated_error = module.setParameterRoles(runtime.begin, blot_backend_runtime_ir::packParameterRoles([reference])); if propagated_error != Error.none { return default<Runtime>(), propagated_error; } }
    { let propagated_error = module.setParameterRoles(runtime.allocate, blot_backend_runtime_ir::packParameterRoles([scalar, scalar, reference])); if propagated_error != Error.none { return default<Runtime>(), propagated_error; } }
    { let propagated_error = module.setParameterRoles(runtime.retire_members, blot_backend_runtime_ir::packParameterRoles([reference])); if propagated_error != Error.none { return default<Runtime>(), propagated_error; } }
    var begin_code = blot_emitter::init(module, runtime.begin); { let propagated_error = begin(begin_code, arena); if propagated_error != Error.none { return default<Runtime>(), propagated_error; } }
    var allocation_code = blot_emitter::init(module, runtime.allocate); { let propagated_error = allocate(allocation_code, arena); if propagated_error != Error.none { return default<Runtime>(), propagated_error; } }
    var retirement_code = blot_emitter::init(module, runtime.retire_members); { let propagated_error = retire(retirement_code, arena); if propagated_error != Error.none { return default<Runtime>(), propagated_error; } }
    module.cohorts = blot_support::some(runtime); return runtime, Error.none;
}
