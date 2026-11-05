// Trial deletion uses phase-exclusive weak scratch links and allocates no guest
// storage. Journal leases stay outside subtraction.
namespace blot_runtime_cycles_runtime;
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
let queued: u32 = 32; let gray: u32 = 64; let black: u32 = 128; let deferred: u32 = 256; let no_cycle: u32 = 512;
let enqueue_guard: u32 = blot_runtime_shared_rc::lease | blot_runtime_shared_rc::dead | no_cycle;
let visit_guard: u32 = blot_runtime_shared_rc::lease | gray | no_cycle;
let minimum_traffic: u32 = 65536; let collector_object_local: u32 = 0;
let traffic_per_vertex_shift: u32 = 6; let traffic_vertex_cap: u32 = 1 << 18;
let header: u32 = blot_runtime_runtime_layout::ArenaHeader_bytes;
let flags: u32 = blot_runtime_runtime_layout::ArenaHeader_flags; let next: u32 = blot_runtime_runtime_layout::ArenaHeader_next;
let trial: u32 = blot_runtime_runtime_layout::ArenaHeader_candidate_prev; let member: u32 = blot_runtime_runtime_layout::ArenaHeader_candidate_next;
let strong: u32 = blot_runtime_runtime_layout::ArenaHeader_strong; let layout: u32 = blot_runtime_runtime_layout::ArenaHeader_layout;
let requested: u32 = blot_runtime_runtime_layout::ArenaHeader_requested;
enum Phase { discover, live }
fn head(c: Code&, value: Local) -> Local { let result = c.temp(); c.value(value); c.value(header); c.op(blot_backend_runtime_ir::OP_i32_sub); c.set(result); return result; }
fn emitOne<F>(module: Module&, function: u32, arena: Arena) -> Error { var code = blot_emitter::init(module, function); F(code, arena); return code.failure; }
fn emit(module: Module&, arena: Arena) -> Error {
    { let propagated_error = emitOne(module, arena.cycle_unlink, arena, unlink); if propagated_error != Error.none { return propagated_error; } } { let propagated_error = emitOne(module, arena.cycle_enqueue, arena, enqueue); if propagated_error != Error.none { return propagated_error; } }
    { let propagated_error = emitOne(module, arena.cycle_visit, arena, visit); if propagated_error != Error.none { return propagated_error; } } { let propagated_error = emitOne(module, arena.cycle_collect, arena, collect); if propagated_error != Error.none { return propagated_error; } } { let propagated_error = emitOne(module, arena.cycle_safe, arena, safe); if propagated_error != Error.none { return propagated_error; } }
    return Error.none;
}
fn unlink(c: Code&, arena: Arena) {
    let pointer = Local { 0 }; let block = head(c, pointer); let previous = c.temp(); let following = c.temp();
    c.value(block); c.load(flags); c.value(queued); c.op(blot_backend_runtime_ir::OP_i32_and); c.op(blot_backend_runtime_ir::OP_i32_eqz); c.when(); c.ret(); c.end();
    c.value(block); c.load(trial); c.set(previous); c.value(block); c.load(member); c.set(following);
    c.value(previous); c.when(); c.value(previous); c.value(header); c.op(blot_backend_runtime_ir::OP_i32_sub); c.value(following); c.store(member);
    c.op(blot_backend_runtime_ir::OP_else_); c.value(following); c.globalSet(arena.cycle_head); c.end();
    c.value(following); c.when(); c.value(following); c.value(header); c.op(blot_backend_runtime_ir::OP_i32_sub); c.value(previous); c.store(trial); c.end();
    c.value(block); c.value(0); c.store(trial); c.value(block); c.value(0); c.store(member);
    c.value(block); c.value(block); c.load(flags); c.value(~queued); c.op(blot_backend_runtime_ir::OP_i32_and); c.store(flags);
}
fn enqueue(c: Code&, arena: Arena) {
    let pointer = Local { 0 }; let block = head(c, pointer);
    c.value(block); c.load(layout); c.op(blot_backend_runtime_ir::OP_i32_eqz); c.value(block); c.load(flags); c.value(enqueue_guard); c.op(blot_backend_runtime_ir::OP_i32_and); c.op(blot_backend_runtime_ir::OP_i32_or); c.when(); c.ret(); c.end();
    c.value(block); c.load(flags); c.value(queued); c.op(blot_backend_runtime_ir::OP_i32_and); c.when(); c.ret(); c.end();
    c.globalGet(arena.cycle_removed); c.globalGet(arena.cycle_threshold); c.op(blot_backend_runtime_ir::OP_i32_lt_u); c.when();
    c.value(block); c.load(requested); c.globalGet(arena.cycle_threshold); c.globalGet(arena.cycle_removed); c.op(blot_backend_runtime_ir::OP_i32_sub); c.op(blot_backend_runtime_ir::OP_i32_ge_u); c.when();
    c.globalGet(arena.cycle_threshold); c.globalSet(arena.cycle_removed); c.op(blot_backend_runtime_ir::OP_else_);
    c.globalGet(arena.cycle_removed); c.value(block); c.load(requested); c.op(blot_backend_runtime_ir::OP_i32_add); c.globalSet(arena.cycle_removed); c.end(); c.end();
    c.value(block); c.load(flags); c.value(gray); c.op(blot_backend_runtime_ir::OP_i32_and); c.when();
    c.value(block); c.value(block); c.load(flags); c.value(deferred); c.op(blot_backend_runtime_ir::OP_i32_or); c.store(flags); c.ret(); c.end();
    c.value(block); c.value(0); c.store(trial); c.value(block); c.globalGet(arena.cycle_head); c.store(member);
    c.globalGet(arena.cycle_head); c.when(); c.globalGet(arena.cycle_head); c.value(header); c.op(blot_backend_runtime_ir::OP_i32_sub); c.value(pointer); c.store(trial); c.end();
    c.value(pointer); c.globalSet(arena.cycle_head); c.value(block); c.value(block); c.load(flags); c.value(queued); c.op(blot_backend_runtime_ir::OP_i32_or); c.store(flags);
}
fn visit(c: Code&, arena: Arena) {
    let pointer = Local { 0 }; c.value(pointer); c.globalGet(arena.static_end); c.op(blot_backend_runtime_ir::OP_i32_lt_u); c.when(); c.ret(); c.end();
    let block = head(c, pointer); c.value(block); c.load(flags); c.value(visit_guard); c.op(blot_backend_runtime_ir::OP_i32_and); c.when(); c.ret(); c.end();
    c.value(block); c.load(requested); c.op(blot_backend_runtime_ir::OP_i32_eqz); c.trap();
    c.value(block); c.load(flags); c.value(blot_runtime_shared_rc::counted); c.op(blot_backend_runtime_ir::OP_i32_and); c.op(blot_backend_runtime_ir::OP_i32_eqz); c.trap();
    c.value(pointer); c.call(arena.cycle_unlink);
    c.value(block); c.value(block); c.load(flags); c.value(gray); c.op(blot_backend_runtime_ir::OP_i32_or); c.store(flags); c.value(block); c.value(block); c.load(strong); c.store(trial);
    c.value(block); c.globalGet(arena.cycle_members); c.store(member); c.value(pointer); c.globalSet(arena.cycle_members);
    c.value(block); c.globalGet(arena.cycle_work); c.store(next); c.value(pointer); c.globalSet(arena.cycle_work);
    c.globalGet(arena.cycle_vertices); c.value(1); c.op(blot_backend_runtime_ir::OP_i32_add); c.globalSet(arena.cycle_vertices);
}
fn edges(c: Code&, arena: Arena, pointer: Local, phase: Phase) {
    let block = head(c, pointer); let offset = c.temp(); let child = c.temp(); let child_block = c.temp();
    c.set(offset, 0 as u32); c.value(block); c.load(layout); c.when(); let end = blot_runtime_shared_rc::referenceEnd(c, block);
    c.loopStart(); c.value(offset); c.value(end); c.op(blot_backend_runtime_ir::OP_i32_lt_u); c.loopTest(); blot_runtime_shared_rc::referenceSlot(c, block, offset); c.when();
    c.value(pointer); c.value(offset); c.op(blot_backend_runtime_ir::OP_i32_add); c.load(0); c.set(child);
    c.value(child); c.globalGet(arena.static_end); c.op(blot_backend_runtime_ir::OP_i32_ge_u); c.when();
    if phase == Phase.discover {
        c.globalGet(arena.cycle_edges); c.value(1); c.op(blot_backend_runtime_ir::OP_i32_add); c.globalSet(arena.cycle_edges);
        c.value(child); c.call(arena.cycle_visit);
    }
    c.value(child); c.value(header); c.op(blot_backend_runtime_ir::OP_i32_sub); c.set(child_block); c.value(child_block); c.load(flags); c.value(gray); c.op(blot_backend_runtime_ir::OP_i32_and); c.when();
    if phase == Phase.discover {
        c.value(child_block); c.load(trial); c.op(blot_backend_runtime_ir::OP_i32_eqz); c.trap(); c.value(child_block); c.value(child_block); c.load(trial); c.value(1); c.op(blot_backend_runtime_ir::OP_i32_sub); c.store(trial);
    } else {
        c.value(child_block); c.load(flags); c.value(black); c.op(blot_backend_runtime_ir::OP_i32_and); c.op(blot_backend_runtime_ir::OP_i32_eqz); c.when();
        c.value(child_block); c.value(child_block); c.load(flags); c.value(black); c.op(blot_backend_runtime_ir::OP_i32_or); c.store(flags);
        c.value(child_block); c.globalGet(arena.cycle_work); c.store(next); c.value(child); c.globalSet(arena.cycle_work); c.end();
    }
    c.end(); c.end(); c.end(); c.value(offset); c.value(4); c.op(blot_backend_runtime_ir::OP_i32_add); c.set(offset); c.again(); c.end();
}
fn work(c: Code&, arena: Arena, pointer: Local, phase: Phase) {
    c.loopStart(); c.globalGet(arena.cycle_work); c.loopTest(); c.globalGet(arena.cycle_work); c.set(pointer);
    c.value(pointer); c.value(header); c.op(blot_backend_runtime_ir::OP_i32_sub); c.load(next); c.globalSet(arena.cycle_work);
    c.value(pointer); c.value(header); c.op(blot_backend_runtime_ir::OP_i32_sub); c.value(0); c.store(next); edges(c, arena, pointer, phase); c.again();
}
fn collect(c: Code&, arena: Arena) {
    let pointer = c.temp(); if c.failure == Error.none { assert(pointer.id == collector_object_local); }
    let block = c.temp(); let following = c.temp(); let pending = c.temp(); let scanned = c.temp();
    c.globalGet(arena.cycle_phase); c.globalGet(arena.cycle_head); c.op(blot_backend_runtime_ir::OP_i32_eqz); c.op(blot_backend_runtime_ir::OP_i32_or); c.when(); c.ret(); c.end();
    c.value(1 as u32); c.globalSet(arena.cycle_phase); c.value(0 as u32); c.globalSet(arena.cycle_removed);
    c.globalGet(arena.allocated); c.globalSet(arena.cycle_cadence);
    c.globalGet(arena.cycle_passes); c.value(1); c.op(blot_backend_runtime_ir::OP_i32_add); c.globalSet(arena.cycle_passes);
    c.globalGet(arena.cycle_vertices); c.set(scanned); c.loopStart(); c.globalGet(arena.cycle_head); c.loopTest();
    c.globalGet(arena.cycle_head); c.call(arena.cycle_visit); work(c, arena, pointer, Phase.discover); c.again();
    c.globalGet(arena.cycle_vertices); c.value(scanned); c.op(blot_backend_runtime_ir::OP_i32_sub); c.set(scanned);
    c.globalGet(arena.cycle_members); c.set(pointer); c.loopStart(); c.value(pointer); c.loopTest();
    c.value(pointer); c.value(header); c.op(blot_backend_runtime_ir::OP_i32_sub); c.set(block); c.value(block); c.load(trial); c.when();
    c.value(block); c.value(block); c.load(flags); c.value(black); c.op(blot_backend_runtime_ir::OP_i32_or); c.store(flags); c.value(block); c.globalGet(arena.cycle_work); c.store(next);
    c.value(pointer); c.globalSet(arena.cycle_work); c.end(); c.value(block); c.load(member); c.set(pointer); c.again();
    work(c, arena, pointer, Phase.live);
    c.globalGet(arena.cycle_members); c.set(pointer); c.loopStart(); c.value(pointer); c.loopTest(); c.value(pointer); c.value(header); c.op(blot_backend_runtime_ir::OP_i32_sub); c.set(block);
    c.value(block); c.load(flags); c.value(black); c.op(blot_backend_runtime_ir::OP_i32_and); c.op(blot_backend_runtime_ir::OP_i32_eqz); c.when();
    c.value(block); c.value(block); c.load(flags); c.value(blot_runtime_shared_rc::dead); c.op(blot_backend_runtime_ir::OP_i32_or); c.store(flags); c.end();
    c.value(block); c.load(member); c.set(pointer); c.again();
    c.globalGet(arena.cycle_members); c.set(pointer); c.value(0 as u32); c.globalSet(arena.cycle_members);
    c.loopStart(); c.value(pointer); c.loopTest(); c.value(pointer); c.value(header); c.op(blot_backend_runtime_ir::OP_i32_sub); c.set(block); c.value(block); c.load(member); c.set(following);
    c.value(block); c.load(flags); c.value(black); c.op(blot_backend_runtime_ir::OP_i32_and); c.when(); c.value(block); c.load(flags); c.value(deferred); c.op(blot_backend_runtime_ir::OP_i32_and); c.set(pending);
    c.value(block); c.value(0); c.store(trial); c.value(block); c.value(0); c.store(member);
    c.value(block); c.value(block); c.load(flags); c.value(~(gray | black | deferred)); c.op(blot_backend_runtime_ir::OP_i32_and); c.store(flags);
    c.value(pending); c.when(); c.value(pointer); c.call(arena.cycle_enqueue); c.end();
    c.op(blot_backend_runtime_ir::OP_else_); c.value(block); c.globalGet(arena.cycle_members); c.store(member); c.value(pointer); c.globalSet(arena.cycle_members); c.end();
    c.set(pointer, following); c.again();
    c.loopStart(); c.globalGet(arena.cycle_members); c.loopTest(); c.globalGet(arena.cycle_members); c.set(pointer);
    c.value(pointer); c.value(header); c.op(blot_backend_runtime_ir::OP_i32_sub); c.set(block); c.value(block); c.load(member); c.globalSet(arena.cycle_members);
    c.globalGet(arena.cycle_bytes); c.value(block); c.load(requested); c.op(blot_backend_runtime_ir::OP_i32_add); c.globalSet(arena.cycle_bytes);
    c.value(scanned); c.value(1); c.op(blot_backend_runtime_ir::OP_i32_sub); c.set(scanned); c.value(pointer); c.call(arena.retire); c.again();
    c.value(scanned); c.value(traffic_vertex_cap); c.op(blot_backend_runtime_ir::OP_i32_gt_u); c.when(); c.set(scanned, traffic_vertex_cap); c.end();
    c.value(minimum_traffic); c.value(scanned); c.value(traffic_per_vertex_shift); c.op(blot_backend_runtime_ir::OP_i32_shl); c.op(blot_backend_runtime_ir::OP_i32_add); c.globalSet(arena.cycle_threshold);
    c.value(0 as u32); c.globalSet(arena.cycle_phase); blot_runtime_shared_rc::drain(c, arena);
}
fn safe(c: Code&, arena: Arena) {
    c.globalGet(arena.cycle_head); c.op(blot_backend_runtime_ir::OP_i32_eqz); c.when(); c.ret(); c.end(); let force = Local { 0 };
    c.value(force); c.globalGet(arena.cycle_removed); c.globalGet(arena.cycle_threshold); c.op(blot_backend_runtime_ir::OP_i32_ge_u); c.globalGet(arena.allocated); c.globalGet(arena.cycle_cadence); c.op(blot_backend_runtime_ir::OP_i32_sub); c.globalGet(arena.cycle_threshold); c.op(blot_backend_runtime_ir::OP_i32_ge_u); c.op(blot_backend_runtime_ir::OP_i32_or); c.op(blot_backend_runtime_ir::OP_i32_or); c.when();
    c.call(arena.cycle_collect); c.end();
}
