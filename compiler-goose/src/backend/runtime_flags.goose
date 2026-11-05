namespace blot_backend_runtime_flags;
import .runtime_ir;
import .wasm;
import runtime.root_runtime;
import runtime.shared_rc;
import runtime.runtime_layout;

struct Facts { module: const blot_backend_wasm::Module&, root_mode: u32, rc_admitted: bool }
fn wide(facts: Facts&) -> bool {
    if !facts.module.arena.present { return false; }
    let arena = facts.module.arena.value;
    if (facts.module.globals[arena.rc_enabled].bits & blot_runtime_shared_rc::shaped_mode) != 0 { return true; }
    for item in facts.module.exports { if !item.global && (item.index == arena.allocate_shaped || item.index == arena.root_allocate_shaped) { return true; } }
    return false;
}
fn value(facts: Facts&, inst: blot_backend_runtime_ir::Instruction) -> u32, bool {
    if inst.op == blot_backend_runtime_ir::OP_wide_layouts { if wide(facts) { return 1, true; } return 0, true; }
    if inst.op != blot_backend_runtime_ir::OP_global_get || !facts.module.arena.present || inst.operand >= facts.module.globals.len { return 0, false; }
    let arena = facts.module.arena.value; let global = facts.module.globals[inst.operand];
    if global.mutable || global.scalar != blot_backend_runtime_ir::SC_u32 { return 0, false; }
    if inst.operand == arena.root_enabled { return facts.root_mode, true; }
    if inst.operand == arena.rc_enabled { if facts.rc_admitted { return 1, true; } return 0, true; }
    return 0, false;
}
fn complete(facts: Facts&) -> bool {
    if !facts.module.arena.present || !facts.rc_admitted || facts.root_mode != (blot_runtime_root_runtime::enabled | blot_runtime_root_runtime::complete) { return false; }
    let arena = facts.module.arena.value;
    let root, root_known = value(facts, blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_global_get, arena.root_enabled));
    let rc, rc_known = value(facts, blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_global_get, arena.rc_enabled));
    return root_known && rc_known;
}
struct Condition { after: i64 = 0, value: bool = false, result: u32 = 0 }
fn condition(facts: Facts&, instructions: const blot_backend_runtime_ir::Instruction[:], start: i64) -> Condition, bool {
    if start >= instructions.len { return Condition {..}, false; }
    let initial, known = value(facts, instructions[start]);
    if !known { return Condition {..}, false; }
    var bits = initial; var at = start + 1;
    if at + 1 < instructions.len && instructions[at].op == blot_backend_runtime_ir::OP_i32_const && instructions[at + 1].op == blot_backend_runtime_ir::OP_i32_and { bits &= instructions[at].operand; at += 2; }
    if at < instructions.len && instructions[at].op == blot_backend_runtime_ir::OP_i32_eqz { if bits == 0 { bits = 1; } else { bits = 0; } at++; }
    if at >= instructions.len || instructions[at].op != blot_backend_runtime_ir::OP_if_ { return Condition {..}, false; }
    return Condition { after: at + 1, value: bits != 0, result: instructions[at].operand , ..}, true;
}
fn boundary(instructions: const blot_backend_runtime_ir::Instruction[:], start: i64, alternate: bool) -> i64, bool {
    var depth = 0;
    for at in start..instructions.len {
        let op = instructions[at].op;
        if op == blot_backend_runtime_ir::OP_block || op == blot_backend_runtime_ir::OP_loop || op == blot_backend_runtime_ir::OP_if_ { depth++; }
        else if op == blot_backend_runtime_ir::OP_end { if depth == 0 { return at, true; } depth--; }
        else if op == blot_backend_runtime_ir::OP_else_ && alternate && depth == 0 { return at, true; }
    }
    return 0, false;
}
fn opening(instructions: const blot_backend_runtime_ir::Instruction[:], alternate: i64) -> i64, bool {
    var at = alternate; var depth = 0;
    while at != 0 {
        at--; let op = instructions[at].op;
        if op == blot_backend_runtime_ir::OP_end { depth++; }
        else if op == blot_backend_runtime_ir::OP_block || op == blot_backend_runtime_ir::OP_loop || op == blot_backend_runtime_ir::OP_if_ { if depth == 0 { return at, true; } depth--; }
    }
    return 0, false;
}
struct Iterator {
    facts: Facts, instructions: const blot_backend_runtime_ir::Instruction[:], at: i64 = 0,
    pending: blot_backend_runtime_ir::Instruction[18] = [blot_backend_runtime_ir::Instruction {..}; 18], pending_at: i64 = 18,
}
fn next(iterator: Iterator&) -> blot_backend_runtime_ir::Instruction, bool {
    if iterator.pending_at < 18 { let inst = iterator.pending[iterator.pending_at]; iterator.pending_at++; return inst, true; }
    while iterator.at < iterator.instructions.len {
        let at = iterator.at; var inst = iterator.instructions[at]; iterator.at++;
        if inst.op == blot_backend_runtime_ir::OP_resource_retire {
            let enqueue, found = iterator.facts.module.resourceRetireImport(); if !found { continue; }
            let local = inst.operand;
            iterator.pending = [
                blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get, local),
                blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const, blot_runtime_runtime_layout::ArenaHeader_bytes),
                blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_sub),
                blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load, blot_runtime_runtime_layout::ArenaHeader_flags),
                blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const, blot_runtime_shared_rc::resource_owner),
                blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_and),
                blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_if_),
                blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get, local),
                blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load, 4),
                blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_if_),
                blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get, local),
                blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load, 4),
                blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get, local),
                blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const),
                blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_store, 4),
                blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_call_import, enqueue),
                blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_end),
                blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_end),
            ];
            iterator.pending_at = 1; return iterator.pending[0], true;
        }
        let known, is_known = condition(iterator.facts, iterator.instructions, at);
        if is_known {
            let end, has_end = boundary(iterator.instructions, known.after, !known.value);
            if has_end {
                iterator.at = known.after;
                if !known.value { iterator.at = end; if iterator.instructions[end].op == blot_backend_runtime_ir::OP_else_ { iterator.at++; } }
                return blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_block, known.result), true;
            }
        }
        if inst.op == blot_backend_runtime_ir::OP_else_ {
            let begin, has_begin = opening(iterator.instructions, at);
            if has_begin {
                var start = begin - 4; if start < 0 { start = 0; }
                while start < begin {
                    let prior, prior_known = condition(iterator.facts, iterator.instructions, start); start++;
                    if !prior_known || prior.after != begin + 1 || !prior.value { continue; }
                    let end, has_end = boundary(iterator.instructions, at + 1, false);
                    if has_end { iterator.at = end; break; }
                }
                if iterator.at != at + 1 { continue; }
            }
        }
        let lowered, has_lowered = value(iterator.facts, inst);
        if has_lowered { inst = blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const, lowered); }
        return inst, true;
    }
    return blot_backend_runtime_ir::Instruction {..}, false;
}
