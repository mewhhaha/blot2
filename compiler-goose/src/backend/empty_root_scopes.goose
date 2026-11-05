namespace blot_backend_empty_root_scopes;
import .runtime_ir;
import .wasm;
import .wasm_simd_ops;
import .wasm_control_flow;

enum Action { keep, open, close }
fn scalar(inst: blot_backend_runtime_ir::Instruction, module: const blot_backend_wasm::Module&) -> bool {
    let op = inst.op;
    if op == blot_backend_runtime_ir::OP_local_get || op == blot_backend_runtime_ir::OP_local_set || op == blot_backend_runtime_ir::OP_local_tee || op == blot_backend_runtime_ir::OP_drop || op == blot_backend_runtime_ir::OP_nop || op == blot_backend_runtime_ir::OP_i32_const || op == blot_backend_runtime_ir::OP_f32_const || op == blot_backend_runtime_ir::OP_i32_load || op == blot_backend_runtime_ir::OP_f32_load ||
       op == blot_backend_runtime_ir::OP_block || op == blot_backend_runtime_ir::OP_loop || op == blot_backend_runtime_ir::OP_if_ || op == blot_backend_runtime_ir::OP_else_ || op == blot_backend_runtime_ir::OP_end || op == blot_backend_runtime_ir::OP_br || op == blot_backend_runtime_ir::OP_br_if { return true; }
    if op == blot_backend_runtime_ir::OP_global_get { return inst.operand < module.globals.len && blot_backend_runtime_ir::role(module.globals[inst.operand].scalar) == blot_backend_runtime_ir::ROLE_scalar; }
    if op == blot_backend_runtime_ir::OP_v128_store { return false; }
    let simd, is_simd = blot_backend_wasm_simd_ops::code(op); if is_simd { return true; }
    return op == blot_backend_runtime_ir::OP_i32_eqz || op == blot_backend_runtime_ir::OP_i32_select || op == blot_backend_runtime_ir::OP_i32_eq || op == blot_backend_runtime_ir::OP_i32_ne || op == blot_backend_runtime_ir::OP_i32_lt_u || op == blot_backend_runtime_ir::OP_i32_gt_u || op == blot_backend_runtime_ir::OP_i32_le_u || op == blot_backend_runtime_ir::OP_i32_ge_u ||
        op == blot_backend_runtime_ir::OP_i32_add || op == blot_backend_runtime_ir::OP_i32_sub || op == blot_backend_runtime_ir::OP_i32_mul || op == blot_backend_runtime_ir::OP_i32_div_u || op == blot_backend_runtime_ir::OP_i32_rem_u || op == blot_backend_runtime_ir::OP_i32_and || op == blot_backend_runtime_ir::OP_i32_or || op == blot_backend_runtime_ir::OP_i32_xor || op == blot_backend_runtime_ir::OP_i32_shl || op == blot_backend_runtime_ir::OP_i32_shr_u || op == blot_backend_runtime_ir::OP_i32_clz || op == blot_backend_runtime_ir::OP_i32_ctz ||
        op == blot_backend_runtime_ir::OP_f32_eq || op == blot_backend_runtime_ir::OP_f32_ne || op == blot_backend_runtime_ir::OP_f32_lt || op == blot_backend_runtime_ir::OP_f32_gt || op == blot_backend_runtime_ir::OP_f32_le || op == blot_backend_runtime_ir::OP_f32_ge || op == blot_backend_runtime_ir::OP_f32_abs || op == blot_backend_runtime_ir::OP_f32_neg || op == blot_backend_runtime_ir::OP_f32_ceil || op == blot_backend_runtime_ir::OP_f32_floor || op == blot_backend_runtime_ir::OP_f32_trunc || op == blot_backend_runtime_ir::OP_f32_sqrt ||
        op == blot_backend_runtime_ir::OP_f32_add || op == blot_backend_runtime_ir::OP_f32_sub || op == blot_backend_runtime_ir::OP_f32_mul || op == blot_backend_runtime_ir::OP_f32_div || op == blot_backend_runtime_ir::OP_f32_min || op == blot_backend_runtime_ir::OP_f32_max || op == blot_backend_runtime_ir::OP_i32_trunc_sat_f32_u || op == blot_backend_runtime_ir::OP_f32_convert_i32_u || op == blot_backend_runtime_ir::OP_i32_reinterpret_f32 || op == blot_backend_runtime_ir::OP_f32_reinterpret_i32;
}
fn marker(inst: blot_backend_runtime_ir::Instruction, chunk: u8) -> bool {
    if inst.op != blot_backend_runtime_ir::OP_ownership { return false; } let fact = blot_backend_runtime_ir::ownership(inst.operand); return fact.kind == blot_backend_runtime_ir::OWN_scope && fact.chunk == chunk && fact.roles == 0;
}
fn neutralCall(module: const blot_backend_wasm::Module&, id: u32) -> bool {
    if id >= module.functions.len || module.runtimeHelper(id) { return false; } let callee = module.functions[id];
    if callee.entry || callee.result_role != blot_backend_runtime_ir::ROLE_scalar || (module.start.present && module.start.value == id) { return false; }
    let code = blot_backend_wasm::instructions(module, callee);
    for inst, at in code {
        let op = inst.op;
        if op == blot_backend_runtime_ir::OP_call || op == blot_backend_runtime_ir::OP_call_import || op == blot_backend_runtime_ir::OP_call_indirect || op == blot_backend_runtime_ir::OP_global_set || op == blot_backend_runtime_ir::OP_memory_copy || op == blot_backend_runtime_ir::OP_memory_fill || op == blot_backend_runtime_ir::OP_memory_grow || op == blot_backend_runtime_ir::OP_resource_retire || op == blot_backend_runtime_ir::OP_wide_layouts || op == blot_backend_runtime_ir::OP_host_ref_get || op == blot_backend_runtime_ir::OP_host_ref_set || op == blot_backend_runtime_ir::OP_host_ref_size || op == blot_backend_runtime_ir::OP_host_ref_grow { return false; }
        if (op == blot_backend_runtime_ir::OP_i32_store || op == blot_backend_runtime_ir::OP_f32_store || op == blot_backend_runtime_ir::OP_v128_store) && !blot_backend_runtime_ir::hasScalarStore(code, at) { return false; }
        if op == blot_backend_runtime_ir::OP_ownership { let fact = blot_backend_runtime_ir::ownership(inst.operand); if fact.kind == blot_backend_runtime_ir::OWN_call_result { return false; } if fact.kind == blot_backend_runtime_ir::OWN_scope && fact.chunk != 14 && (fact.chunk > 1 || fact.roles != 0) { return false; } }
    }
    return true;
}
fn empty(code: const blot_backend_runtime_ir::Instruction[:], at: i64, module: const blot_backend_wasm::Module&, actions: const Action[:]) -> bool {
    let inst = code[at]; if scalar(inst, module) || inst.op == blot_backend_runtime_ir::OP_unreachable_ { return true; }
    if inst.op == blot_backend_runtime_ir::OP_i32_store || inst.op == blot_backend_runtime_ir::OP_f32_store || inst.op == blot_backend_runtime_ir::OP_v128_store { return blot_backend_runtime_ir::hasScalarStore(code, at); }
    if inst.op == blot_backend_runtime_ir::OP_call { return neutralCall(module, inst.operand); }
    if inst.op == blot_backend_runtime_ir::OP_ownership { return actions[at] != Action.keep || blot_backend_runtime_ir::hasScalarStore(code, at + 1) || blot_backend_runtime_ir::hasNonzeroRead(code, at + 1); }
    return false;
}
fn prove(module: const blot_backend_wasm::Module&, source: blot_backend_runtime_ir::Function, actions: Action[>..<]&) -> bool {
    let drain, has_drain = module.resourceDrainImport(); if has_drain { return false; }
    let code = blot_backend_wasm::instructions(module, source); if code.len > 16384 { return false; }
    var any_open = false; for inst in code { if marker(inst, 0) { any_open = true; break; } } if !any_open { return false; }
    var nodes: blot_backend_wasm_control_flow::Node[>..] = []; var predecessors: blot_backend_wasm_control_flow::Predecessor[>..] = [];
    let graph = blot_backend_wasm_control_flow::init(nodes, predecessors, code); if !graph.valid { return false; }
    var marks: u32[>..<] = []; var reachable: bool[>..<] = []; var pending: u32[>..<] = [];
    for node in graph.nodes { marks.push(0); reachable.push(false); }
    actions.clear(); for inst in code { actions.push(Action.keep); }
    reachable[0] = true; pending.push(0); var reach_cursor = 0;
    while reach_cursor < pending.len {
        let at = pending[reach_cursor]; reach_cursor++;
        for next in graph.nodes[at].next { if next == blot_backend_wasm_control_flow::absent || reachable[next] { continue; } reachable[next] = true; pending.push(next); }
    }
    var work: i64 = 1048576; var found = false; var start = code.len;
    while start != 0 {
        start--; if !marker(code[start], 0) { continue; } let stamp = (start + 1) as u32;
        pending.clear(); marks[start] = stamp; pending.push((start + 1) as u32); marks[start + 1] = stamp;
        var cursor = 0; var valid = true; var closed = false;
        while cursor < pending.len {
            if work == 0 { valid = false; break; } work--; let at = pending[cursor]; cursor++;
            if at == code.len { valid = false; break; }
            if marker(code[at], 1) && actions[at] == Action.keep { closed = true; continue; }
            if !empty(code, at, module, actions) { valid = false; break; }
            if code[at].op == blot_backend_runtime_ir::OP_unreachable_ { continue; }
            for next in graph.nodes[at].next { if next == blot_backend_wasm_control_flow::absent || marks[next] == stamp { continue; } marks[next] = stamp; pending.push(next); }
        }
        if !valid || !closed { continue; }
        for at in pending {
            var edge = graph.nodes[at].first;
            while edge != blot_backend_wasm_control_flow::absent { let previous = graph.predecessors[edge]; if reachable[previous.from] && marks[previous.from] != stamp { valid = false; } edge = previous.next; }
        }
        if !valid { continue; }
        actions[start] = Action.open; for at in pending { if marker(code[at], 1) && actions[at] == Action.keep { actions[at] = Action.close; } } found = true;
    }
    if !found { actions.clear(); } return found;
}
