// Scalar coordinates for one synchronous function-planning attempt.
namespace blot_backend_storage_function_plan_input;
import check.core;
import .runtime_ir;
import .storage_calls;
import .storage_type_key;
import .storage_owner_graph;
import .storage_recursive_admission;
import support.option;
struct FunctionPlanKey {
    unit: u32,binding: u32,context: u32,context_free: bool,evidence: blot_backend_storage_type_key::WordRun,
}
fn functionPlanKey(key: blot_backend_storage_calls::Key,evidence: const blot_backend_storage_type_key::Words&) -> FunctionPlanKey {
    assert(blot_support::same_slice_identity(key.evidence,evidence.items));
    return FunctionPlanKey { unit: key.unit,binding: key.binding,context: key.context,context_free: key.context_free,evidence: blot_backend_storage_type_key::wordRun(evidence) };
}
fn borrowPlanKey(key: FunctionPlanKey) -> blot_backend_storage_calls::Key {
    return blot_backend_storage_calls::Key { unit: key.unit,binding: key.binding,context: key.context,context_free: key.context_free,evidence: key.evidence.view() };
}
fn planUnit(units: const blot_check_core::Module[:],module: const blot_check_core::Module&) -> u32 {
    assert(module.unit != 0 && module.unit <= units.len);
    let registered: const blot_check_core::Module& = units[module.unit - 1];
    assert(module .== registered); return module.unit;
}
// Planning requests retain scalar coordinates; caller-owned runs outlive the synchronous attempt.
struct Input<V> {
    module: u32,target: blot_check_core::BindingRef,arguments: blot_backend_runtime_ir::Range,owners: blot_backend_runtime_ir::Range,graph: blot_support::Option<blot_backend_storage_owner_graph::OrdinalRun>,words: i64,input_aliases: blot_backend_runtime_ir::Range,
    rejection_slot: i64 = -1,addressed: bool = true,borrowed_inputs: bool = false,recursive_: blot_support::Option<blot_backend_storage_recursive_admission::AccessRun>,created_receipts: blot_backend_runtime_ir::Range,capture_globals: bool,unit_result: bool,result_shape: V,shared: bool,key: FunctionPlanKey,
}
struct Rejections { alias: bool = false,addressed: bool = false }
reusable var rejections: Rejections[>..] = [];
