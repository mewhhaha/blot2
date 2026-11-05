// Alias recipes contain logical input ordinals, never child local identities.
namespace blot_backend_storage_result_alias;
import .runtime_ir;
import .runtime_code;
import .wasm;
import support.error;
let absent: u32 = 4294967295;
reusable[] var written_runs: bool[>..] = [];
reusable[] var alias_runs: u32[>..] = [];
fn release(aliases: const u32[:]) { if aliases.len != 0 { alias_runs.free_slice(aliases); } }
fn analyze(module: const blot_backend_wasm::Module&,function: u32,first: u32,words: i64,output: const blot_backend_runtime_code::Local[:]) -> const u32[:],blot_error::Error {
    if words > 9223372036854775807 - first as i64 { return [],blot_error::Error.none; } let end = first as i64 + words; let parameters = module.parameters(function).len; let locals = module.locals(function).len; if locals > 9223372036854775807 - parameters { return [],blot_error::Error.none; } if end > 4294967295 || end > parameters + locals { return [],blot_error::Error.none; }
    var candidate = false; for word in output { if word.id >= first && word.id < end { candidate = true; break; } } if !candidate { return [],blot_error::Error.none; } let code = blot_backend_wasm::instructions(module,function); for instruction in code { if instruction.op == blot_backend_runtime_ir::OP_ownership || instruction.op == blot_backend_runtime_ir::OP_resource_retire { return [],blot_error::Error.none; } }
    let written = written_runs.alloc_slice(words); for &value in written { value = false; } for instruction in code { if (instruction.op == blot_backend_runtime_ir::OP_local_set || instruction.op == blot_backend_runtime_ir::OP_local_tee) && instruction.operand >= first && instruction.operand < end { written[instruction.operand - first] = true; } } var count: i64 = 0; for word in output { if word.id >= first && word.id < end && !written[word.id - first] { count++; } }
    if count == 0 { written_runs.free_slice(written); return [],blot_error::Error.none; } let result = alias_runs.alloc_slice(output.len); for word,index in output { result[index] = absent; if word.id >= first && word.id < end && !written[word.id - first] { result[index] = word.id - first; } } written_runs.free_slice(written); return result,blot_error::Error.none;
}
