namespace blot_backend_collector_contract;
import .wasm;
import .runtime_ir;
import support.option;

enum Reason { proven, unchecked_module, host_import, incoming_reference, public_arena, mutable_static, indirect_call, owning_allocation, unknown_runtime_helper, invalid_call, work_limit }
struct Certificate {
    version: u32 = 1, certified: bool = false, scope: const u8[:] = "complete_module_arena",
    proof: const u8[:] = "no_owning_user_heap_fields_v1", reason: Reason = Reason.proven,
    function: blot_support::Option<u32>, instruction: blot_support::Option<u32>, covered_functions: i64 = 0,
    assumption: const u8[:] = "Call source exports through the ownership ABI; do not mutate raw memory, tables or runtime globals or invoke private helpers.",
}
fn helper(arena: blot_backend_wasm::Arena, id: u32) -> bool {
    for function in [arena.allocate_scalar, arena.retain, arena.release, arena.release_lease, arena.retire, arena.free, arena.store_word, arena.copy_words, arena.decrement, arena.recycle, arena.reset, arena.root_reserve, arena.root_pop, arena.root_open, arena.root_close, arena.root_enter, arena.root_leave, arena.root_store, arena.root_authority, arena.cycle_safe, arena.cycle_collect, arena.mark_acyclic] { if function == id { return true; } }
    return false;
}
fn scanCode(module: const blot_backend_wasm::Module&, code: const blot_backend_runtime_ir::Instruction[:], result: Certificate&, remaining: i64&) -> bool {
    for at in 0..code.len {
        let inst = code[at]; result.instruction = blot_support::some(at as u32);
        if remaining == 0 { result.reason = Reason.work_limit; return false; } remaining--;
        if inst.op == blot_backend_runtime_ir::OP_call_indirect || inst.op == blot_backend_runtime_ir::OP_call_import { result.reason = Reason.indirect_call; return false; }
        if inst.op != blot_backend_runtime_ir::OP_call { continue; }
        if inst.operand >= module.functions.len { result.reason = Reason.invalid_call; return false; }
        if !blot_backend_wasm::runtimeHelper(module, inst.operand) { continue; }
        if module.arena.present {
            let arena = module.arena.value;
            if inst.operand == arena.allocate_typed || inst.operand == arena.root_allocate {
                if at != 0 { let before = code[at - 1]; if before.op == blot_backend_runtime_ir::OP_i32_const && before.operand == 0 { continue; } }
                result.reason = Reason.owning_allocation; return false;
            }
            if inst.operand == arena.allocate || inst.operand == arena.allocate_shaped || inst.operand == arena.root_allocate_shaped { result.reason = Reason.owning_allocation; return false; }
            if helper(arena, inst.operand) { continue; }
        }
        result.reason = Reason.unknown_runtime_helper; return false;
    }
    return true;
}
fn analyze<P>(module: const blot_backend_wasm::Module&, bodies: const P[:]) -> Certificate {
    var result = Certificate {..};
    if module.public_arena { result.reason = Reason.public_arena; return result; }
    if module.imports.len != 0 || module.host_references.present { result.reason = Reason.host_import; return result; }
    if module.mutable_static { result.reason = Reason.mutable_static; return result; }
    var remaining: i64 = 4000000;
    for function, id in module.functions {
        if blot_backend_wasm::runtimeHelper(module, id) { continue; }
        result.function = blot_support::some(id as u32);
        if function.entry {
            for parameter in 0..function.parameters.len { if blot_backend_runtime_ir::parameterRole(function, parameter) != blot_backend_runtime_ir::ROLE_scalar { result.reason = Reason.incoming_reference; return result; } }
        }
        result.covered_functions++;
        if bodies[id].body.present {
            if !scanCode(module,bodies[id].body.value.instructions,result,remaining) { return result; }
        } else {
            if !scanCode(module,blot_backend_wasm::instructions(module,function),result,remaining) { return result; }
        }
    }
    result.function = blot_support::none<u32>(); result.instruction = blot_support::none<u32>(); result.certified = true; return result;
}
fn reasonName(reason: Reason) -> const u8[:] { match reason { proven=>"proven",unchecked_module=>"unchecked_module",host_import=>"host_import",incoming_reference=>"incoming_reference",public_arena=>"public_arena",mutable_static=>"mutable_static",indirect_call=>"indirect_call",owning_allocation=>"owning_allocation",unknown_runtime_helper=>"unknown_runtime_helper",invalid_call=>"invalid_call",work_limit=>"work_limit" } }
