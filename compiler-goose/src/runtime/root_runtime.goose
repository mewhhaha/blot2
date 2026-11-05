// Every private journal slot owns one counted reference. Journal pages are
// allocator storage and never source objects.
namespace blot_runtime_root_runtime;
import backend.wasm;
import backend.runtime_ir;
import backend.runtime_code;
import runtime.runtime_layout;
import runtime.shared_rc;
import support.emitter;
import support.error;
type Error = blot_error::Error;
type Module = blot_backend_wasm::Module;
type Arena = blot_backend_wasm::Arena;
type Local = blot_backend_runtime_code::Local;
type Code = blot_emitter::Emitter<Module>;
let head_bytes: u32 = blot_runtime_runtime_layout::ArenaHeader_bytes;
let page_bytes: u32 = 4096 - head_bytes; let first_slot: u32 = 8; let slot_bytes: u32 = 8;
let slots_per_page: u32 = (page_bytes - first_slot) / slot_bytes;
let enabled: u32 = 1; let complete: u32 = 2;
let owner_slot: u32 = blot_runtime_runtime_layout::ArenaHeader_candidate_prev;
let flags: u32 = blot_runtime_runtime_layout::ArenaHeader_flags;
fn count(c: Code&, arena: Arena, add: bool) {
    if add { c.globalGet(arena.root_count); c.value(1); c.op(blot_backend_runtime_ir::OP_i32_add); }
    else { c.globalGet(arena.root_count); c.value(1); c.op(blot_backend_runtime_ir::OP_i32_sub); }
    c.globalSet(arena.root_count);
}
fn emitOne<F>(module: Module&, function: u32, arena: Arena) -> Error { var code = blot_emitter::init(module, function); F(code, arena); return code.failure; }
fn emit(module: Module&, arena: Arena) -> Error {
    { let propagated_error = emitOne(module, arena.root_reserve, arena, reserve); if propagated_error != blot_error::Error.none { return propagated_error; } }
    var ordinary = blot_emitter::init(module, arena.root_allocate); allocate(ordinary, arena, arena.allocate_typed); { let propagated_error = ordinary.failure; if propagated_error != blot_error::Error.none { return propagated_error; } }
    var shaped = blot_emitter::init(module, arena.root_allocate_shaped); allocate(shaped, arena, arena.allocate_shaped); { let propagated_error = shaped.failure; if propagated_error != blot_error::Error.none { return propagated_error; } }
    { let propagated_error = emitOne(module, arena.root_pop, arena, pop); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = emitOne(module, arena.root_open, arena, open); if propagated_error != blot_error::Error.none { return propagated_error; } }
    { let propagated_error = emitOne(module, arena.root_close, arena, close); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = emitOne(module, arena.root_enter, arena, enter); if propagated_error != blot_error::Error.none { return propagated_error; } }
    { let propagated_error = emitOne(module, arena.root_leave, arena, leave); if propagated_error != blot_error::Error.none { return propagated_error; } }
    if module.host_references.present { { let propagated_error = hostCleanup(module, arena); if propagated_error != blot_error::Error.none { return propagated_error; } } }
    { let propagated_error = emitOne(module, arena.root_store, arena, store); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = emitOne(module, arena.root_public_allocate, arena, publicAllocate); if propagated_error != blot_error::Error.none { return propagated_error; } }
    { let propagated_error = emitOne(module, arena.root_public_reset, arena, publicReset); if propagated_error != blot_error::Error.none { return propagated_error; } } { let propagated_error = emitOne(module, arena.root_authority, arena, authority); if propagated_error != blot_error::Error.none { return propagated_error; } }
    return blot_error::Error.none;
}
fn reserve(c: Code&, arena: Arena) {
    let page = c.temp(); let slot = c.temp();
    c.globalGet(arena.root_page); c.op(blot_backend_runtime_ir::OP_i32_eqz); c.globalGet(arena.root_top); c.value(page_bytes); c.op(blot_backend_runtime_ir::OP_i32_eq); c.op(blot_backend_runtime_ir::OP_i32_or); c.when();
    c.value(page_bytes); c.call(arena.allocate); c.set(page); c.value(page); c.globalGet(arena.root_page); c.store(0);
    c.value(page); c.value(head_bytes); c.op(blot_backend_runtime_ir::OP_i32_sub); c.value(2); c.store(flags); c.value(page); c.globalSet(arena.root_page);
    c.value(first_slot); c.globalSet(arena.root_top); c.end();
    c.globalGet(arena.root_page); c.globalGet(arena.root_top); c.op(blot_backend_runtime_ir::OP_i32_add); c.set(slot);
    c.value(slot); c.value(0); c.store(0); c.value(slot); c.globalGet(arena.root_frame); c.store(4);
    c.globalGet(arena.root_top); c.value(slot_bytes); c.op(blot_backend_runtime_ir::OP_i32_add); c.globalSet(arena.root_top); c.value(slot);
}
fn allocate(c: Code&, arena: Arena, allocator: u32) {
    let bytes = Local { 0 , ..}; let mask = Local { 1 , ..}; let slot = c.temp(); let value = c.temp();
    c.globalGet(arena.root_enabled); c.op(blot_backend_runtime_ir::OP_i32_eqz); c.when(); c.value(bytes); c.value(mask); c.call(allocator); c.ret(); c.end();
    c.call(arena.root_reserve); c.set(slot); c.value(bytes); c.value(mask); c.call(allocator); c.set(value);
    c.value(value); c.when(); c.value(slot); c.value(value); c.store(0); c.value(value); c.value(head_bytes); c.op(blot_backend_runtime_ir::OP_i32_sub); c.value(slot); c.store(owner_slot);
    count(c, arena, true); c.end(); c.value(value);
}
fn pop(c: Code&, arena: Arena) {
    let page = c.temp(); let slot = c.temp(); let value = c.temp();
    c.globalGet(arena.root_page); c.op(blot_backend_runtime_ir::OP_i32_eqz); c.trap(); c.globalGet(arena.root_top); c.value(first_slot); c.op(blot_backend_runtime_ir::OP_i32_eq); c.when();
    c.globalGet(arena.root_page); c.set(page); c.value(page); c.load(0); c.globalSet(arena.root_page);
    c.value(page_bytes); c.globalSet(arena.root_top); c.value(page); c.call(arena.free);
    c.globalGet(arena.root_page); c.op(blot_backend_runtime_ir::OP_i32_eqz); c.trap(); c.value(0 as u32); c.ret(); c.end();
    c.globalGet(arena.root_top); c.value(slot_bytes); c.op(blot_backend_runtime_ir::OP_i32_sub); c.globalSet(arena.root_top);
    c.globalGet(arena.root_page); c.globalGet(arena.root_top); c.op(blot_backend_runtime_ir::OP_i32_add); c.set(slot); c.value(slot); c.load(0); c.set(value);
    c.value(value); c.op(blot_backend_runtime_ir::OP_i32_eqz); c.when(); c.value(slot); c.ret(); c.end(); c.value(slot); c.value(0); c.store(0);
    c.value(value); c.globalGet(arena.static_end); c.op(blot_backend_runtime_ir::OP_i32_ge_u); c.when(); count(c, arena, false);
    let head = blot_runtime_shared_rc::checkedHead(c, value);
    c.value(head); c.load(flags); c.value(blot_runtime_shared_rc::lease); c.op(blot_backend_runtime_ir::OP_i32_and); c.value(0); c.op(blot_backend_runtime_ir::OP_i32_ne); c.value(head); c.load(owner_slot); c.value(slot); c.op(blot_backend_runtime_ir::OP_i32_eq); c.op(blot_backend_runtime_ir::OP_i32_and); c.when();
    c.value(head); c.value(0); c.store(owner_slot); c.value(head); c.value(head); c.load(flags); c.value(~blot_runtime_shared_rc::lease); c.op(blot_backend_runtime_ir::OP_i32_and); c.store(flags);
    c.globalGet(arena.rc_leases); c.value(1); c.op(blot_backend_runtime_ir::OP_i32_sub); c.globalSet(arena.rc_leases); c.end();
    blot_runtime_shared_rc::releaseKnown(c, arena, value, head); c.end(); c.value(slot);
}
fn open(c: Code&, arena: Arena) { let frame = c.temp(); c.call(arena.root_reserve); c.set(frame); c.value(frame); c.globalSet(arena.root_frame); c.value(frame); }
fn close(c: Code&, arena: Arena) {
    let value = Local { 0 , ..}; let frame = c.temp(); let parent = c.temp(); let owner = c.temp(); let slot = c.temp();
    c.globalGet(arena.root_frame); c.set(frame); c.value(frame); c.op(blot_backend_runtime_ir::OP_i32_eqz); c.trap(); c.value(frame); c.load(4); c.set(parent);
    c.value(value); c.globalGet(arena.static_end); c.op(blot_backend_runtime_ir::OP_i32_ge_u); c.when();
    c.value(value); c.value(head_bytes); c.op(blot_backend_runtime_ir::OP_i32_sub); c.load(flags); c.value(blot_runtime_shared_rc::lease); c.op(blot_backend_runtime_ir::OP_i32_and); c.when();
    c.value(value); c.value(head_bytes); c.op(blot_backend_runtime_ir::OP_i32_sub); c.load(owner_slot); c.set(owner); c.end();
    c.value(owner); c.when(); c.value(owner); c.load(4); c.set(slot); c.end(); let last = c.temp();
    c.value(slot); c.value(frame); c.op(blot_backend_runtime_ir::OP_i32_ne); c.globalGet(arena.root_top); c.value(first_slot); c.op(blot_backend_runtime_ir::OP_i32_gt_u); c.op(blot_backend_runtime_ir::OP_i32_and); c.when();
    c.globalGet(arena.root_page); c.globalGet(arena.root_top); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(slot_bytes); c.op(blot_backend_runtime_ir::OP_i32_sub); c.set(last);
    c.value(last); c.load(0); c.value(value); c.op(blot_backend_runtime_ir::OP_i32_eq); c.value(last); c.load(4); c.value(frame); c.op(blot_backend_runtime_ir::OP_i32_eq); c.op(blot_backend_runtime_ir::OP_i32_and); c.when();
    c.set(owner, last); c.set(slot, frame); c.end(); c.end();
    c.value(slot); c.value(frame); c.op(blot_backend_runtime_ir::OP_i32_eq); c.when(); c.value(owner); c.value(0); c.store(0);
    c.value(value); c.value(head_bytes); c.op(blot_backend_runtime_ir::OP_i32_sub); c.load(flags); c.value(blot_runtime_shared_rc::lease); c.op(blot_backend_runtime_ir::OP_i32_and); c.value(0); c.op(blot_backend_runtime_ir::OP_i32_ne); c.value(value); c.value(head_bytes); c.op(blot_backend_runtime_ir::OP_i32_sub); c.load(owner_slot); c.value(owner); c.op(blot_backend_runtime_ir::OP_i32_eq); c.op(blot_backend_runtime_ir::OP_i32_and); c.when();
    c.value(value); c.value(head_bytes); c.op(blot_backend_runtime_ir::OP_i32_sub); c.value(frame); c.store(owner_slot); c.end(); c.op(blot_backend_runtime_ir::OP_else_);
    c.value(value); c.call(arena.retain); count(c, arena, true); c.end(); c.value(frame); c.value(value); c.store(0); c.end();
    c.loopStart(); c.value(1); c.loopTest();
    c.globalGet(arena.root_page); c.globalGet(arena.root_top); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(slot_bytes); c.op(blot_backend_runtime_ir::OP_i32_sub); c.value(frame); c.op(blot_backend_runtime_ir::OP_i32_eq); c.when();
    c.value(frame); c.load(0); c.op(blot_backend_runtime_ir::OP_i32_eqz); c.when();
    c.globalGet(arena.root_top); c.value(slot_bytes); c.op(blot_backend_runtime_ir::OP_i32_sub); c.globalSet(arena.root_top); c.end();
    c.op(blot_backend_runtime_ir::OP_br, 2); c.end();
    c.globalGet(arena.root_top); c.value(first_slot); c.op(blot_backend_runtime_ir::OP_i32_gt_u); c.when();
    c.globalGet(arena.root_page); c.globalGet(arena.root_top); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(slot_bytes); c.op(blot_backend_runtime_ir::OP_i32_sub); c.load(0); c.op(blot_backend_runtime_ir::OP_i32_eqz); c.when();
    c.globalGet(arena.root_top); c.value(slot_bytes); c.op(blot_backend_runtime_ir::OP_i32_sub); c.globalSet(arena.root_top); c.op(blot_backend_runtime_ir::OP_br, 2);
    c.end(); c.end(); c.call(arena.root_pop); c.op(blot_backend_runtime_ir::OP_drop); c.again();
    c.value(parent); c.globalSet(arena.root_frame); c.globalGet(arena.cycle_head); c.when(); c.value(0); c.call(arena.cycle_safe); c.end();
}
fn enter(c: Code&, arena: Arena) {
    c.globalGet(arena.root_active); c.globalGet(arena.root_frame); c.op(blot_backend_runtime_ir::OP_i32_or); c.trap();
    c.value(1 as u32); c.globalSet(arena.root_active); c.call(arena.root_open); c.globalSet(arena.root_active);
    c.value(1 as u32); c.globalSet(arena.root_external); c.value(0 as u32); c.globalSet(arena.root_started);
}
fn leave(c: Code&, arena: Arena) {
    let outcome = Local { 0 , ..}; c.value(outcome); c.value(2); c.op(blot_backend_runtime_ir::OP_i32_gt_u); c.trap(); c.value(outcome); c.value(2); c.op(blot_backend_runtime_ir::OP_i32_eq); c.when();
    c.globalGet(arena.root_active); c.globalGet(arena.root_frame); c.op(blot_backend_runtime_ir::OP_i32_or); c.trap(); let page = c.temp();
    c.loopStart(); c.globalGet(arena.root_page); c.loopTest(); c.globalGet(arena.root_top); c.value(first_slot); c.op(blot_backend_runtime_ir::OP_i32_eq); c.when();
    c.globalGet(arena.root_page); c.set(page); c.value(page); c.load(0); c.globalSet(arena.root_page);
    c.value(page_bytes); c.globalSet(arena.root_top); c.value(page); c.call(arena.free);
    c.op(blot_backend_runtime_ir::OP_else_); c.call(arena.root_pop); c.op(blot_backend_runtime_ir::OP_drop); c.end(); c.again();
    c.value(0 as u32); c.globalSet(arena.root_top); c.value(0 as u32); c.globalSet(arena.root_globals);
    c.op(blot_backend_runtime_ir::OP_else_); c.globalGet(arena.root_active); c.op(blot_backend_runtime_ir::OP_i32_eqz); c.trap();
    c.value(outcome); c.value(1); c.op(blot_backend_runtime_ir::OP_i32_eq); c.when(); c.globalGet(arena.root_active); c.value(1); c.op(blot_backend_runtime_ir::OP_i32_or); c.globalSet(arena.root_active); c.end();
    c.globalGet(arena.root_active); c.value(2); c.op(blot_backend_runtime_ir::OP_i32_and); c.when(); revokeAuthorities(c, arena); c.end();
    c.loopStart(); c.globalGet(arena.root_frame); c.loopTest(); c.value(0); c.call(arena.root_close); c.again();
    let last = c.temp(); c.loopStart(); c.globalGet(arena.root_page); c.value(0); c.op(blot_backend_runtime_ir::OP_i32_ne); c.globalGet(arena.root_top); c.value(first_slot); c.op(blot_backend_runtime_ir::OP_i32_gt_u); c.op(blot_backend_runtime_ir::OP_i32_and); c.loopTest();
    c.globalGet(arena.root_page); c.globalGet(arena.root_top); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(slot_bytes); c.op(blot_backend_runtime_ir::OP_i32_sub); c.set(last);
    c.value(last); c.load(0); c.when(); c.op(blot_backend_runtime_ir::OP_br, 2); c.end();
    c.globalGet(arena.root_top); c.value(slot_bytes); c.op(blot_backend_runtime_ir::OP_i32_sub); c.globalSet(arena.root_top); c.again();
    c.value(0 as u32); c.globalSet(arena.root_active); c.value(0 as u32); c.globalSet(arena.root_external); c.value(0 as u32); c.globalSet(arena.root_started); c.end();
    c.globalGet(arena.cycle_head); c.when(); c.value(1); c.call(arena.cycle_safe); c.end();
}
fn detach(c: Code&, arena: Arena, head: Local) {
    let slot = c.temp(); c.globalGet(arena.root_enabled); c.when(); c.value(head); c.load(owner_slot); c.set(slot);
    c.value(slot); c.when(); c.value(slot); c.value(0); c.store(0); c.value(head); c.value(0); c.store(owner_slot); count(c, arena, false); c.end(); c.end();
}
fn retainBorrow(c: Code&, arena: Arena, value: Local) {
    c.globalGet(arena.root_enabled); c.when(); c.value(value); c.globalGet(arena.static_end); c.op(blot_backend_runtime_ir::OP_i32_ge_u); c.when();
    c.value(value); c.value(head_bytes); c.op(blot_backend_runtime_ir::OP_i32_sub); c.load(flags); c.value(blot_runtime_shared_rc::lease); c.op(blot_backend_runtime_ir::OP_i32_and); c.op(blot_backend_runtime_ir::OP_i32_eqz); c.when();
    c.call(arena.root_reserve); c.value(value); c.call(arena.root_store); c.end(); c.end(); c.end();
}
fn store(c: Code&, arena: Arena) {
    let slot = Local { 0 , ..}; let value = Local { 1 , ..}; let old = c.temp(); c.value(slot); c.load(0); c.set(old);
    c.value(value); c.globalGet(arena.static_end); c.op(blot_backend_runtime_ir::OP_i32_ge_u); c.when(); c.value(old); c.value(value); c.op(blot_backend_runtime_ir::OP_i32_eq); c.when(); c.ret(); c.end();
    c.value(value); c.call(arena.retain); c.value(slot); c.value(value); c.store(0); count(c, arena, true); c.op(blot_backend_runtime_ir::OP_else_);
    c.value(slot); c.value(0); c.store(0); c.end(); c.value(old); c.when(); count(c, arena, false); c.value(old); c.call(arena.release); c.end();
}
fn publicAllocate(c: Code&, arena: Arena) {
    let bytes = Local { 0 , ..}; c.globalGet(arena.root_enabled); c.when(); c.globalGet(arena.root_active); c.op(blot_backend_runtime_ir::OP_i32_eqz); c.when();
    c.call(arena.root_enter); c.value(0 as u32); c.globalSet(arena.root_external); c.end();
    c.value(bytes); c.value(0); c.call(arena.root_allocate); c.ret(); c.end(); c.value(bytes); c.call(arena.allocate);
}
fn publicReset(c: Code&, arena: Arena) {
    c.globalGet(arena.root_enabled); c.globalGet(arena.root_external); c.op(blot_backend_runtime_ir::OP_i32_eqz); c.op(blot_backend_runtime_ir::OP_i32_and); c.when();
    c.globalGet(arena.root_active); c.when(); c.value(1); c.call(arena.root_leave); c.end(); c.end();
    c.value(0); c.call(arena.reset);
}
fn hostCleanup(module: Module&, arena: Arena) -> Error {
    assert(module.host_references.present); let references = module.host_references.value;
    var entry = blot_emitter::init(module, arena.root_enter); entry.globalGet(references.cursor); entry.globalSet(arena.root_host_cursor);
    entry.globalGet(references.active); entry.globalSet(arena.root_host_active); { let propagated_error = entry.failure; if propagated_error != blot_error::Error.none { return propagated_error; } }
    var exit = blot_emitter::init(module, arena.root_leave); exit.globalGet(arena.root_host_cursor); exit.call(references.release);
    exit.globalGet(arena.root_host_active); exit.globalSet(references.active); return exit.failure;
}
fn authority(c: Code&, arena: Arena) {
    let value = Local { 0 , ..}; let slot = c.temp(); c.globalGet(arena.root_enabled); c.op(blot_backend_runtime_ir::OP_i32_eqz); c.when(); c.ret(); c.end();
    c.call(arena.root_reserve); c.set(slot); c.value(slot); c.value(value); c.call(arena.root_store);
    c.value(slot); c.value(slot); c.load(4); c.value(2); c.op(blot_backend_runtime_ir::OP_i32_or); c.store(4);
    c.globalGet(arena.root_active); c.value(2); c.op(blot_backend_runtime_ir::OP_i32_or); c.globalSet(arena.root_active);
}
fn revokeAuthorities(c: Code&, arena: Arena) {
    let page = c.temp(); let top = c.temp(); let slot = c.temp(); let owner = c.temp();
    c.globalGet(arena.root_page); c.set(page); c.globalGet(arena.root_top); c.set(top);
    c.loopStart(); c.value(page); c.loopTest(); c.loopStart(); c.value(top); c.value(first_slot); c.op(blot_backend_runtime_ir::OP_i32_gt_u); c.loopTest(); c.value(top); c.value(slot_bytes); c.op(blot_backend_runtime_ir::OP_i32_sub); c.set(top);
    c.value(page); c.value(top); c.op(blot_backend_runtime_ir::OP_i32_add); c.set(slot); c.value(slot); c.load(0); c.set(owner);
    c.value(owner); c.value(0); c.op(blot_backend_runtime_ir::OP_i32_ne); c.value(slot); c.load(4); c.value(2); c.op(blot_backend_runtime_ir::OP_i32_and); c.value(0); c.op(blot_backend_runtime_ir::OP_i32_ne); c.op(blot_backend_runtime_ir::OP_i32_and); c.when();
    c.value(owner); c.value(0); c.store(blot_runtime_runtime_layout::EffectAuthority_active); c.end(); c.again();
    c.value(page); c.load(0); c.set(page); c.set(top, page_bytes); c.again();
}
