namespace blot_backend_storage_input_alias;
import dictionary;
import .runtime_code;
import .runtime_ir;
import .wasm;

fn partition(aliases: u32[>..<]&, words: const blot_backend_runtime_code::Local[:]) {
    aliases.clear(); var positions = dictionary<u32, u32> {}; var repeated = false;
    for word, ordinal in words {
        var first = ordinal as u32; block { let known = positions.get(word.id); if known { first = known; repeated = true; } }
        if first == ordinal { positions.insert(word.id, first); } aliases.push(first);
    }
    if !repeated { aliases.clear(); }
}
fn readOnly(module: blot_backend_wasm::Module&, function: blot_backend_runtime_ir::Function, first: u32, aliases: const u32[:]) -> bool {
    if aliases.len == 0 { return true; }
    let code = blot_backend_wasm::instructions(module, function);
    for inst in code { if inst.op == blot_backend_runtime_ir::OP_ownership || inst.op == blot_backend_runtime_ir::OP_resource_retire || inst.table_reference || inst.table_kind != blot_backend_runtime_ir::TABLE_unknown { return false; } }
    var shared: bool[>..<] = []; for index in 0..aliases.len { shared.push(false); }
    for alias, ordinal in aliases { assert(alias <= ordinal && aliases[alias] == alias); if alias != ordinal { shared[alias] = true; } }
    for inst in code { if inst.op != blot_backend_runtime_ir::OP_local_set && inst.op != blot_backend_runtime_ir::OP_local_tee { continue; } if inst.operand >= first && inst.operand - first < shared.len && shared[inst.operand - first] { return false; } }
    return true;
}
