// Addressed words load at their use, or once at entry after three reads.
namespace blot_backend_addressed_input_demand;
import .runtime_ir;
import .wasm;
import support.option;
import support.error;
type Error = blot_error::Error;
struct Bundle { parameter: u32,first: u32,words: i64 }
struct Result { used: bool[:],omitted: i64,loads: i64 }
reusable[] var used_runs: bool[>..] = [];
reusable[] var read_runs: u8[>..] = [];
reusable[] var code_runs: blot_backend_runtime_ir::Instruction[>..] = [];
fn deinit(result: Result&) { if result.used.len != 0 { used_runs.free_slice(result.used); } result.used = []; }
fn wordOffset(word: i64) -> blot_support::Option<u32> { if word > 1073741823 { return blot_support::none<u32>(); } return blot_support::some((word * 4) as u32); }
fn contains(bundle: Bundle,local: u32) -> bool { if local < bundle.first { return false; } return local - bundle.first < bundle.words; }
fn materialize(module: blot_backend_wasm::Module&,function: u32,bundles: const Bundle[:]) -> blot_support::Option<Result>,Error {
    let parameters = module.parameters(function); let locals = module.locals(function); let code = module.instructions(function); if locals.len > 9223372036854775807 - parameters.len { return blot_support::none<Result>(),Error.none; } let local_count = parameters.len + locals.len; var words: i64 = 0;
    for bundle,index in bundles { if bundle.parameter >= parameters.len || parameters[bundle.parameter] != blot_backend_runtime_ir::VT_i32 { return blot_support::none<Result>(),Error.none; } if bundle.words == 0 || !wordOffset(bundle.words - 1).present || bundle.first < parameters.len || bundle.first > local_count || bundle.words > local_count - bundle.first || bundle.words - 1 > 4294967295 - bundle.first { return blot_support::none<Result>(),Error.none; }
        let start = bundle.first - parameters.len; for ty in locals[start..start + bundle.words] { if ty != blot_backend_runtime_ir::VT_i32 { return blot_support::none<Result>(),Error.none; } } for previous in bundles[..index] { if contains(previous,bundle.first) || contains(bundle,previous.first) { return blot_support::none<Result>(),Error.none; } } if bundle.words > 9223372036854775807 - words { return blot_support::none<Result>(),Error.none; } words += bundle.words;
    }
    for instruction in code { if instruction.op == blot_backend_runtime_ir::OP_ownership || instruction.op == blot_backend_runtime_ir::OP_resource_retire || instruction.table_reference || instruction.table_kind != blot_backend_runtime_ir::TABLE_unknown { return blot_support::none<Result>(),Error.none; } if instruction.op != blot_backend_runtime_ir::OP_local_get && instruction.op != blot_backend_runtime_ir::OP_local_set && instruction.op != blot_backend_runtime_ir::OP_local_tee { continue; } if instruction.operand >= local_count { return blot_support::none<Result>(),Error.none; } for bundle in bundles { if instruction.op != blot_backend_runtime_ir::OP_local_get && (contains(bundle,instruction.operand) || instruction.operand == bundle.parameter) { return blot_support::none<Result>(),Error.none; } } }
    let used = used_runs.alloc_slice(words); for &value in used { value = false; } let reads = read_runs.alloc_slice(words); for &value in reads { value = 0; }
    for instruction in code { if instruction.op != blot_backend_runtime_ir::OP_local_get { continue; } var first: i64 = 0; for bundle in bundles { if contains(bundle,instruction.operand) { let index = first + instruction.operand - bundle.first; used[index] = true; if reads[index] < 3 { reads[index]++; } break; } first += bundle.words; } }
    var loads: i64 = 0; var added: i64 = 0; var omitted: i64 = 0;
    for count in reads { if count == 0 { omitted++; continue; } var growth = count as i64; var generated = count as i64; if count == 3 { growth = 3; generated = 1; } if growth > 9223372036854775807 - added { if reads.len != 0 { read_runs.free_slice(reads); } if used.len != 0 { used_runs.free_slice(used); } return blot_support::none<Result>(),Error.none; } added += growth; loads += generated; }
    if added > 9223372036854775807 - code.len { if reads.len != 0 { read_runs.free_slice(reads); } if used.len != 0 { used_runs.free_slice(used); } return blot_support::none<Result>(),Error.none; } let length = code.len + added;
    if loads == 0 { if reads.len != 0 { read_runs.free_slice(reads); } return blot_support::some(Result { used,omitted,loads: 0 , ..}),Error.none; }
    let lowered = code_runs.alloc_slice(length); var next: i64 = 0; var first_word: i64 = 0;
    for bundle in bundles { for count,word in reads[first_word..first_word + bundle.words] { if count != 3 { continue; } let offset = wordOffset(word); assert(offset.present); lowered[next] = blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,bundle.parameter); lowered[next + 1] = blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,offset.value); lowered[next + 2] = blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,bundle.first + word as u32); next += 3; } first_word += bundle.words; }
    for instruction in code { var first: i64 = 0; var replaced = false; if instruction.op == blot_backend_runtime_ir::OP_local_get { for bundle in bundles { if contains(bundle,instruction.operand) { let word = instruction.operand - bundle.first; if reads[first + word] == 3 { break; } let offset = wordOffset(word); assert(offset.present); var pointer = blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,bundle.parameter); pointer.origin = instruction.origin; lowered[next] = pointer; var load = blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,offset.value); load.origin = instruction.origin; lowered[next + 1] = load; next += 2; replaced = true; break; } first += bundle.words; } } if !replaced { lowered[next] = instruction; next++; } }
    assert(next == length); let error = module.publishInstructions(function,lowered); code_runs.free_slice(lowered); if reads.len != 0 { read_runs.free_slice(reads); } if error != Error.none { if used.len != 0 { used_runs.free_slice(used); } return blot_support::none<Result>(),error; } return blot_support::some(Result { used,omitted,loads , ..}),Error.none;
}
