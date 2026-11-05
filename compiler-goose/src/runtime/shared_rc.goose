// Counted field ownership and tracer leases share an allocation-free retirement
// queue; every child decrement precedes the object's ordinary destructor.
namespace blot_runtime_shared_rc;
import backend.wasm;
import backend.runtime_ir;
import backend.runtime_code;
import runtime.runtime_layout;
import runtime.cycles_runtime;
import runtime.root_runtime;
import runtime.arena_runtime;
import support.emitter;
import support.error;
type Error = blot_error::Error;
type Module = blot_backend_wasm::Module;
type Arena = blot_backend_wasm::Arena;
type Local = blot_backend_runtime_code::Local;
type Code = blot_emitter::Emitter<Module>;
let counted: u32 = 4; let lease: u32 = 8; let dead: u32 = 16; let shaped: u32 = 1024;
let resource_owner: u32 = 2048; let shaped_mode: u32 = 2;
let queue: u32 = 16; let header: u32 = blot_runtime_runtime_layout::ArenaHeader_bytes;
let strong: u32 = blot_runtime_runtime_layout::ArenaHeader_strong;
let flags: u32 = blot_runtime_runtime_layout::ArenaHeader_flags;
let layout: u32 = blot_runtime_runtime_layout::ArenaHeader_layout;
let next: u32 = blot_runtime_runtime_layout::ArenaHeader_next;
let requested: u32 = blot_runtime_runtime_layout::ArenaHeader_requested;
fn bump(c: Code&, global: u32) { c.globalGet(global); c.value(1); c.op(blot_backend_runtime_ir::OP_i32_add); c.globalSet(global); }
fn dynamic(c: Code&, arena: Arena) -> Local {
    let pointer = Local { 0 }; c.value(pointer); c.globalGet(arena.static_end); c.op(blot_backend_runtime_ir::OP_i32_lt_u); c.when(); c.ret(); c.end();
    return checkedHead(c, pointer);
}
fn checkedHead(c: Code&, pointer: Local) -> Local {
    let head = c.temp(); c.value(pointer); c.value(header); c.op(blot_backend_runtime_ir::OP_i32_sub); c.set(head);
    c.value(pointer); c.value(3); c.op(blot_backend_runtime_ir::OP_i32_and); c.value(head); c.load(requested); c.op(blot_backend_runtime_ir::OP_i32_eqz); c.op(blot_backend_runtime_ir::OP_i32_or); c.trap();
    c.value(head); c.load(flags); c.value(counted); c.op(blot_backend_runtime_ir::OP_i32_and); c.op(blot_backend_runtime_ir::OP_i32_eqz); c.trap();
    return head;
}
fn checkedHead(c: blot_backend_runtime_code::Code<Module>&, pointer: Local) -> Local, Error {
    var emitter = Code { code: c }; let head = checkedHead(emitter, pointer); return head, emitter.failure;
}
fn narrowSlot(c: Code&, head: Local, word: Local) {
    c.value(word); c.value(31); c.op(blot_backend_runtime_ir::OP_i32_gt_u); c.when(); c.set(word, 31 as u32); c.end();
    c.value(head); c.load(layout); c.value(word); c.op(blot_backend_runtime_ir::OP_i32_shr_u); c.value(1); c.op(blot_backend_runtime_ir::OP_i32_and);
}
fn referenceSlot<O>(c: Code&, head: Local, offset: O) {
    let word = c.temp(); c.value(offset); c.value(4 as u32); c.op(blot_backend_runtime_ir::OP_i32_div_u); c.set(word);
    c.op(blot_backend_runtime_ir::OP_wide_layouts); c.op(blot_backend_runtime_ir::OP_if_, blot_backend_runtime_ir::VT_i32 as u32);
    c.value(head); c.load(flags); c.value(shaped); c.op(blot_backend_runtime_ir::OP_i32_and); c.op(blot_backend_runtime_ir::OP_if_, blot_backend_runtime_ir::VT_i32 as u32);
    c.value(head); c.load(layout); c.value(word); c.value(5); c.op(blot_backend_runtime_ir::OP_i32_shr_u); c.value(4); c.op(blot_backend_runtime_ir::OP_i32_mul); c.op(blot_backend_runtime_ir::OP_i32_add); c.load(4); c.value(word); c.value(31); c.op(blot_backend_runtime_ir::OP_i32_and); c.op(blot_backend_runtime_ir::OP_i32_shr_u); c.value(1); c.op(blot_backend_runtime_ir::OP_i32_and);
    c.op(blot_backend_runtime_ir::OP_else_); narrowSlot(c, head, word); c.end();
    c.op(blot_backend_runtime_ir::OP_else_); narrowSlot(c, head, word); c.end();
}
fn narrowEnd(c: Code&, end: Local, mask: Local) {
    c.value(mask); c.value(0x80000000); c.op(blot_backend_runtime_ir::OP_i32_and); c.op(blot_backend_runtime_ir::OP_i32_eqz); c.when();
    c.value(32); c.value(mask); c.op(blot_backend_runtime_ir::OP_i32_clz); c.op(blot_backend_runtime_ir::OP_i32_sub); c.value(4); c.op(blot_backend_runtime_ir::OP_i32_mul); c.set(mask);
    c.value(mask); c.value(end); c.op(blot_backend_runtime_ir::OP_i32_lt_u); c.when(); c.set(end, mask); c.end(); c.end();
}
fn referenceEnd(c: Code&, head: Local) -> Local {
    let end = c.temp(); let mask = c.temp(); c.value(head); c.load(requested); c.set(end); c.value(head); c.load(layout); c.set(mask);
    c.op(blot_backend_runtime_ir::OP_wide_layouts); c.when();
    c.value(head); c.load(flags); c.value(shaped); c.op(blot_backend_runtime_ir::OP_i32_and); c.when(); c.value(mask); c.load(0); c.value(4); c.op(blot_backend_runtime_ir::OP_i32_mul); c.set(end);
    c.op(blot_backend_runtime_ir::OP_else_); narrowEnd(c, end, mask); c.end();
    c.op(blot_backend_runtime_ir::OP_else_); narrowEnd(c, end, mask); c.end(); return end;
}
fn emitOne<F>(module: Module&, function: u32, arena: Arena) -> Error { var code = blot_emitter::init(module, function); F(code, arena); return code.failure; }
fn emit(module: Module&, arena: Arena) -> Error {
    { let propagated_error = emitOne(module, arena.allocate_typed, arena, allocate); if propagated_error != Error.none { return propagated_error; } } { let propagated_error = emitOne(module, arena.allocate_shaped, arena, allocateShaped); if propagated_error != Error.none { return propagated_error; } }
    var marker = blot_emitter::init(module, arena.mark_acyclic); marker.globalGet(arena.rc_enabled); marker.when();
    let marker_head = dynamic(marker, arena);
    marker.value(marker_head); marker.value(marker_head); marker.load(flags); marker.value(blot_runtime_cycles_runtime::no_cycle); marker.op(blot_backend_runtime_ir::OP_i32_or); marker.store(flags); marker.end(); { let propagated_error = marker.failure; if propagated_error != Error.none { return propagated_error; } }
    { let propagated_error = emitOne(module, arena.retain, arena, retain); if propagated_error != Error.none { return propagated_error; } } { let propagated_error = emitOne(module, arena.decrement, arena, decrement); if propagated_error != Error.none { return propagated_error; } }
    { let propagated_error = emitOne(module, arena.release, arena, release); if propagated_error != Error.none { return propagated_error; } } { let propagated_error = emitOne(module, arena.release_lease, arena, releaseLease); if propagated_error != Error.none { return propagated_error; } }
    { let propagated_error = emitOne(module, arena.retire, arena, retire); if propagated_error != Error.none { return propagated_error; } } { let propagated_error = emitOne(module, arena.store_word, arena, store); if propagated_error != Error.none { return propagated_error; } } { let propagated_error = emitOne(module, arena.copy_words, arena, copy); if propagated_error != Error.none { return propagated_error; } }
    var recycle = blot_emitter::init(module, arena.recycle); let pointer = Local { 0 };
    recycle.value(pointer); recycle.value(header); recycle.op(blot_backend_runtime_ir::OP_i32_sub); recycle.load(flags); recycle.value(counted); recycle.op(blot_backend_runtime_ir::OP_i32_and); recycle.when();
    recycle.value(pointer); recycle.call(arena.release_lease); recycle.op(blot_backend_runtime_ir::OP_else_);
    recycle.value(pointer); recycle.call(arena.free); recycle.end(); return recycle.failure;
}
fn allocate(c: Code&, arena: Arena) {
    let bytes = Local { 0 }; let mask = Local { 1 }; let pointer = c.temp(); let head = c.temp();
    c.value(bytes); c.op(blot_backend_runtime_ir::OP_i32_eqz); c.when(); c.value(0 as u32); c.ret(); c.end();
    c.globalGet(arena.rc_enabled); c.when(); c.value(bytes); c.value(3); c.op(blot_backend_runtime_ir::OP_i32_and); c.trap(); c.end();
    c.value(bytes); c.call(arena.allocate); c.set(pointer); c.value(pointer); c.value(header); c.op(blot_backend_runtime_ir::OP_i32_sub); c.set(head);
    c.value(mask); c.op(blot_backend_runtime_ir::OP_i32_eqz); c.when(); c.value(head); c.value(2); c.store(flags); c.end();
    c.globalGet(arena.rc_enabled); c.when();
    c.value(head); c.value(head); c.load(flags); c.value(counted | lease); c.op(blot_backend_runtime_ir::OP_i32_or); c.store(flags);
    c.value(head); c.value(mask); c.store(layout); c.value(head); c.value(1); c.store(strong); bump(c, arena.rc_leases); c.end();
    c.value(mask); c.when(); c.value(pointer); c.value(0); c.value(bytes); c.zero(); c.end(); c.value(pointer);
}
fn allocateShaped(c: Code&, arena: Arena) {
    let bytes = Local { 0 }; let shape = Local { 1 }; let pointer = c.temp(); let head = c.temp();
    c.value(shape); c.value(3); c.op(blot_backend_runtime_ir::OP_i32_and); c.value(shape); c.value(blot_runtime_arena_runtime::metadata_bytes); c.op(blot_backend_runtime_ir::OP_i32_lt_u); c.op(blot_backend_runtime_ir::OP_i32_or); c.trap();
    c.value(shape); c.globalGet(arena.static_end); c.value(4); c.op(blot_backend_runtime_ir::OP_i32_sub); c.op(blot_backend_runtime_ir::OP_i32_gt_u); c.trap();
    c.value(4); c.value(bytes); c.value(4); c.op(blot_backend_runtime_ir::OP_i32_div_u); c.value(31); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(32); c.op(blot_backend_runtime_ir::OP_i32_div_u); c.value(4); c.op(blot_backend_runtime_ir::OP_i32_mul); c.op(blot_backend_runtime_ir::OP_i32_add); c.globalGet(arena.static_end); c.value(shape); c.op(blot_backend_runtime_ir::OP_i32_sub); c.op(blot_backend_runtime_ir::OP_i32_gt_u); c.trap();
    c.value(shape); c.load(0); c.value(bytes); c.value(4); c.op(blot_backend_runtime_ir::OP_i32_div_u); c.op(blot_backend_runtime_ir::OP_i32_ne); c.trap();
    c.value(bytes); c.op(blot_backend_runtime_ir::OP_i32_eqz); c.value(bytes); c.value(3); c.op(blot_backend_runtime_ir::OP_i32_and); c.op(blot_backend_runtime_ir::OP_i32_or); c.trap();
    c.value(bytes); c.call(arena.allocate); c.set(pointer); c.value(pointer); c.value(header); c.op(blot_backend_runtime_ir::OP_i32_sub); c.set(head);
    c.globalGet(arena.rc_enabled); c.when(); c.value(head); c.value(counted | lease | shaped); c.store(flags);
    c.value(head); c.value(shape); c.store(layout); c.value(head); c.value(1); c.store(strong); bump(c, arena.rc_leases); c.end();
    c.value(pointer); c.value(0); c.value(bytes); c.zero(); c.value(pointer);
}
fn retain(c: Code&, arena: Arena) {
    let head = dynamic(c, arena);
    c.value(head); c.load(strong); c.op(blot_backend_runtime_ir::OP_i32_eqz); c.trap(); c.value(head); c.load(strong); c.value(0xffffffff); c.op(blot_backend_runtime_ir::OP_i32_eq); c.trap();
    c.value(head); c.value(head); c.load(strong); c.value(1); c.op(blot_backend_runtime_ir::OP_i32_add); c.store(strong); bump(c, arena.rc_retains);
}
fn decrement(c: Code&, arena: Arena) { let pointer = Local { 0 }; let head = dynamic(c, arena); decrementKnown(c, arena, pointer, head); }
fn decrementKnown(c: Code&, arena: Arena, pointer: Local, head: Local) { dropKnown(c, arena, pointer, head, false); }
fn releaseKnown(c: Code&, arena: Arena, pointer: Local, head: Local) { dropKnown(c, arena, pointer, head, true); drain(c, arena); }
fn dropKnown(c: Code&, arena: Arena, pointer: Local, head: Local, immediate: bool) {
    c.value(head); c.load(strong); c.op(blot_backend_runtime_ir::OP_i32_eqz); c.trap();
    c.value(head); c.value(head); c.load(strong); c.value(1); c.op(blot_backend_runtime_ir::OP_i32_sub); c.store(strong); bump(c, arena.rc_releases);
    c.value(head); c.load(strong); c.op(blot_backend_runtime_ir::OP_i32_eqz); c.when();
    c.value(head); c.load(flags); c.value(blot_runtime_cycles_runtime::queued); c.op(blot_backend_runtime_ir::OP_i32_and); c.when();
    c.value(pointer); c.call(arena.cycle_unlink); c.end();
    if immediate { c.value(head); c.value(0); c.store(next); c.value(pointer); c.call(arena.retire); }
    else { c.value(head); c.value(queue); c.load(0); c.store(next); c.value(queue); c.value(pointer); c.store(0); }
    c.op(blot_backend_runtime_ir::OP_else_); c.value(head); c.load(layout); c.when();
    c.value(pointer); c.call(arena.cycle_enqueue); c.end(); c.end();
}
fn release(c: Code&, arena: Arena) { let pointer = Local { 0 }; c.value(pointer); c.call(arena.decrement); drain(c, arena); }
fn drain(c: Code&, arena: Arena) {
    let pointer = c.temp(); c.loopStart(); c.value(queue); c.load(0); c.loopTest(); c.value(queue); c.load(0); c.set(pointer);
    c.value(queue); c.value(pointer); c.value(header); c.op(blot_backend_runtime_ir::OP_i32_sub); c.load(next); c.store(0);
    c.value(pointer); c.value(header); c.op(blot_backend_runtime_ir::OP_i32_sub); c.value(0); c.store(next); c.value(pointer); c.call(arena.retire); c.again();
}
fn releaseLease(c: Code&, arena: Arena) {
    let pointer = Local { 0 }; let head = dynamic(c, arena);
    c.value(head); c.load(flags); c.value(lease); c.op(blot_backend_runtime_ir::OP_i32_and); c.op(blot_backend_runtime_ir::OP_i32_eqz); c.trap();
    blot_runtime_root_runtime::detach(c, arena, head); consumeLease(c, arena, pointer, head); drain(c, arena);
}
fn consumeLease(c: Code&, arena: Arena, pointer: Local, head: Local) {
    c.value(head); c.value(head); c.load(flags); c.value(~lease); c.op(blot_backend_runtime_ir::OP_i32_and); c.store(flags);
    c.globalGet(arena.rc_leases); c.value(1); c.op(blot_backend_runtime_ir::OP_i32_sub); c.globalSet(arena.rc_leases); decrementKnown(c, arena, pointer, head);
}
fn retire(c: Code&, arena: Arena) {
    let pointer = Local { 0 }; let head = dynamic(c, arena); let is_dead = c.temp(); let offset = c.temp(); let child = c.temp();
    c.value(head); c.load(flags); c.value(dead); c.op(blot_backend_runtime_ir::OP_i32_and); c.set(is_dead);
    c.value(is_dead); c.op(blot_backend_runtime_ir::OP_i32_eqz); c.value(head); c.load(strong); c.op(blot_backend_runtime_ir::OP_i32_and); c.trap();
    c.value(head); c.load(flags); c.value(blot_runtime_cycles_runtime::queued); c.op(blot_backend_runtime_ir::OP_i32_and); c.when(); c.value(pointer); c.call(arena.cycle_unlink); c.end();
    c.value(head); c.load(flags); c.value(lease); c.op(blot_backend_runtime_ir::OP_i32_and); c.when(); c.value(is_dead); c.op(blot_backend_runtime_ir::OP_i32_eqz); c.trap();
    c.globalGet(arena.rc_leases); c.value(1); c.op(blot_backend_runtime_ir::OP_i32_sub); c.globalSet(arena.rc_leases); c.end();
    c.value(head); c.value(0); c.store(strong); c.value(head); c.load(layout); c.when();
    let end = referenceEnd(c, head); c.loopStart(); c.value(offset); c.value(end); c.op(blot_backend_runtime_ir::OP_i32_lt_u); c.loopTest(); referenceSlot(c, head, offset); c.when();
    c.value(pointer); c.value(offset); c.op(blot_backend_runtime_ir::OP_i32_add); c.load(0); c.set(child); c.value(pointer); c.value(offset); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(0); c.store(0);
    c.value(child); c.globalGet(arena.static_end); c.op(blot_backend_runtime_ir::OP_i32_ge_u); c.when(); c.value(is_dead); c.when();
    c.value(child); c.value(header); c.op(blot_backend_runtime_ir::OP_i32_sub); c.load(requested); c.value(0); c.op(blot_backend_runtime_ir::OP_i32_ne); c.value(child); c.value(header); c.op(blot_backend_runtime_ir::OP_i32_sub); c.load(flags); c.value(dead); c.op(blot_backend_runtime_ir::OP_i32_and); c.op(blot_backend_runtime_ir::OP_i32_eqz); c.op(blot_backend_runtime_ir::OP_i32_and); c.when();
    c.value(child); c.call(arena.decrement); c.end(); c.op(blot_backend_runtime_ir::OP_else_);
    c.value(child); c.call(arena.decrement); c.end(); c.end(); c.end();
    c.value(offset); c.value(4); c.op(blot_backend_runtime_ir::OP_i32_add); c.set(offset); c.again(); c.end(); bump(c, arena.rc_destroyed);
    c.op(blot_backend_runtime_ir::OP_resource_retire, pointer.id); c.value(pointer); c.call(arena.free);
}
fn store(c: Code&, arena: Arena) {
    let parent = Local { 0 }; let address = Local { 1 }; let value = Local { 2 };
    let head = c.temp(); let offset = c.temp(); let old = c.temp();
    c.globalGet(arena.rc_enabled); c.when(); c.value(parent); c.globalGet(arena.static_end); c.op(blot_backend_runtime_ir::OP_i32_lt_u); c.when();
    c.globalGet(arena.root_enabled); c.when(); let index = c.temp(); let field = c.temp(); let slot = c.temp(); c.set(index, 0 as u32);
    c.loopStart(); c.value(index); c.globalGet(arena.root_static_count); c.op(blot_backend_runtime_ir::OP_i32_lt_u); c.loopTest();
    c.globalGet(arena.root_static_map); c.value(index); c.value(4); c.op(blot_backend_runtime_ir::OP_i32_mul); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(0); c.op(blot_backend_runtime_ir::OP_i32_add); c.load(0); c.set(field);
    c.value(field); c.value(~(3 as u32)); c.op(blot_backend_runtime_ir::OP_i32_and); c.value(address); c.op(blot_backend_runtime_ir::OP_i32_eq); c.when();
    c.value(field); c.value(3); c.op(blot_backend_runtime_ir::OP_i32_and); c.value(blot_backend_runtime_ir::ROLE_reference as u32); c.op(blot_backend_runtime_ir::OP_i32_eq); c.when();
    c.globalGet(arena.root_globals); c.globalGet(arena.root_global_count); c.value(index); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(4); c.op(blot_backend_runtime_ir::OP_i32_mul); c.op(blot_backend_runtime_ir::OP_i32_add); c.value(0); c.op(blot_backend_runtime_ir::OP_i32_add); c.set(slot);
    c.globalGet(arena.root_globals); c.value(slot); c.value(value); c.call(arena.store_word); c.end();
    c.value(address); c.value(value); c.store(0); c.ret(); c.end(); c.value(index); c.value(1); c.op(blot_backend_runtime_ir::OP_i32_add); c.set(index); c.again(); c.end();
    c.value(address); c.load(0); c.value(value); c.op(blot_backend_runtime_ir::OP_i32_ne); c.trap(); c.ret(); c.end();
    c.value(parent); c.value(header); c.op(blot_backend_runtime_ir::OP_i32_sub); c.set(head); c.value(address); c.value(parent); c.op(blot_backend_runtime_ir::OP_i32_sub); c.set(offset);
    c.value(head); c.load(flags); c.value(counted); c.op(blot_backend_runtime_ir::OP_i32_and); c.op(blot_backend_runtime_ir::OP_i32_eqz); c.trap();
    c.value(offset); c.value(3); c.op(blot_backend_runtime_ir::OP_i32_and); c.value(offset); c.value(head); c.load(requested); c.op(blot_backend_runtime_ir::OP_i32_ge_u); c.op(blot_backend_runtime_ir::OP_i32_or); c.trap();
    c.value(head); c.load(requested); c.value(offset); c.op(blot_backend_runtime_ir::OP_i32_sub); c.value(4); c.op(blot_backend_runtime_ir::OP_i32_lt_u); c.trap(); referenceSlot(c, head, offset); c.when();
    c.value(address); c.load(0); c.set(old); c.value(value); c.call(arena.retain); c.value(address); c.value(value); c.store(0);
    c.value(old); c.call(arena.release); c.ret(); c.end(); c.end(); c.value(address); c.value(value); c.store(0);
}
fn copyWord<O,A,S>(c: Code&, arena: Arena, head: Local, offset: O, address: A, source: S) {
    let value = c.temp(); let old = c.temp();
    c.value(source); c.load(); c.set(value); referenceSlot(c, head, offset); c.when();
    c.value(address); c.load(); c.set(old); c.value(value); c.value(old); c.op(blot_backend_runtime_ir::OP_i32_ne); c.when();
    c.value(value); c.call(arena.retain); c.value(address); c.value(value); c.store();
    c.value(old); c.globalGet(arena.static_end); c.op(blot_backend_runtime_ir::OP_i32_ge_u); c.when(); c.value(old); c.call(arena.release); c.end(); c.end();
    c.op(blot_backend_runtime_ir::OP_else_); c.value(address); c.value(value); c.store(); c.end();
}
fn add(left: Local, right: Local) -> blot_backend_runtime_ir::Instruction[3] { return [blot_backend_runtime_ir::Instruction { blot_backend_runtime_ir::OP_local_get, left.id }, blot_backend_runtime_ir::Instruction { blot_backend_runtime_ir::OP_local_get, right.id }, blot_backend_runtime_ir::Instruction { blot_backend_runtime_ir::OP_i32_add }]; }
fn copy(c: Code&, arena: Arena) {
    let parent = Local { 0 }; let target = Local { 1 }; let source = Local { 2 }; let bytes = Local { 3 }; let index = c.temp();
    c.globalGet(arena.rc_enabled); c.op(blot_backend_runtime_ir::OP_i32_eqz); c.when(); c.value(target); c.value(source); c.value(bytes); c.copy(); c.ret(); c.end();
    c.value(bytes); c.value(3); c.op(blot_backend_runtime_ir::OP_i32_and); c.trap(); c.value(bytes); c.op(blot_backend_runtime_ir::OP_i32_eqz); c.when(); c.ret(); c.end();
    let head = c.temp(); let offset = c.temp(); c.value(parent); c.value(header); c.op(blot_backend_runtime_ir::OP_i32_sub); c.set(head); c.value(target); c.value(parent); c.op(blot_backend_runtime_ir::OP_i32_sub); c.set(offset);
    c.value(parent); c.globalGet(arena.static_end); c.op(blot_backend_runtime_ir::OP_i32_lt_u); c.trap();
    c.value(head); c.load(flags); c.value(counted); c.op(blot_backend_runtime_ir::OP_i32_and); c.op(blot_backend_runtime_ir::OP_i32_eqz); c.trap();
    c.value(offset); c.value(3); c.op(blot_backend_runtime_ir::OP_i32_and); c.value(offset); c.value(head); c.load(requested); c.op(blot_backend_runtime_ir::OP_i32_gt_u); c.op(blot_backend_runtime_ir::OP_i32_or); c.trap();
    c.value(bytes); c.value(head); c.load(requested); c.value(offset); c.op(blot_backend_runtime_ir::OP_i32_sub); c.op(blot_backend_runtime_ir::OP_i32_gt_u); c.trap();
    c.value(head); c.load(layout); c.op(blot_backend_runtime_ir::OP_i32_eqz); c.when(); c.value(target); c.value(source); c.value(bytes); c.copy(); c.ret(); c.end();
    c.value(target); c.value(source); c.op(blot_backend_runtime_ir::OP_i32_gt_u); c.when(); c.set(index, bytes); c.loopStart(); c.value(index); c.loopTest();
    c.value(index); c.value(4); c.op(blot_backend_runtime_ir::OP_i32_sub); c.set(index);
    copyWord(c, arena, head, add(offset, index), add(target, index), add(source, index)); c.again(); c.op(blot_backend_runtime_ir::OP_else_);
    c.loopStart(); c.value(index); c.value(bytes); c.op(blot_backend_runtime_ir::OP_i32_lt_u); c.loopTest(); copyWord(c, arena, head, add(offset, index), add(target, index), add(source, index));
    c.value(index); c.value(4); c.op(blot_backend_runtime_ir::OP_i32_add); c.set(index); c.again(); c.end();
}
