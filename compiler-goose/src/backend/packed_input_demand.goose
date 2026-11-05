// Packed logical words load before the complete unchanged callee suffix.
namespace blot_backend_packed_input_demand;
import .runtime_ir;
import .wasm;
import support.error;
type Error = blot_error::Error;
struct Result { used: bool[:],omitted: i64 }
reusable[] var used_runs: bool[>..] = [];
reusable[] var code_runs: blot_backend_runtime_ir::Instruction[>..] = [];
fn deinit(result: Result&) { if result.used.len != 0 { used_runs.free_slice(result.used); } result.used = []; }
fn materialize(module: blot_backend_wasm::Module&,id: u32,words: i64) -> Result,Error {
    assert(module.parameters(id).len == 1 && module.locals(id).len >= words); let code = module.instructions(id); let used = used_runs.alloc_slice(words); for &read in used { read = false; } for instruction in code { if instruction.op == blot_backend_runtime_ir::OP_local_get && instruction.operand > 0 && instruction.operand <= words { used[instruction.operand - 1] = true; } } var omitted: i64 = 0; var demanded: i64 = 0; for read in used { if read { demanded++; } else { omitted++; } }
    let lowered = code_runs.alloc_slice(demanded * 3 + code.len); var next: i64 = 0; for read,index in used { if !read { continue; } lowered[next] = blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,0); lowered[next + 1] = blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,(index * 4) as u32); lowered[next + 2] = blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,(index + 1) as u32); next += 3; } for instruction in code { lowered[next] = instruction; next++; }
    let error = module.publishInstructions(id,lowered); if lowered.len != 0 { code_runs.free_slice(lowered); } if error != Error.none { if used.len != 0 { used_runs.free_slice(used); } return Result { used: [],omitted: 0 },error; } return Result { used,omitted },Error.none;
}
