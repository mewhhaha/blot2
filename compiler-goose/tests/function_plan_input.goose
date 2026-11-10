import bootstrap_globals;
import std;
import backend.storage_function_plan_input;
reusable[] var module_runs: blot_check_core::Module[>..] = [];
struct MiniValue { word: u32,flags: u32 }
type Request = blot_backend_storage_function_plan_input::Input<MiniValue>;
recursive fn inspect(request: Request,depth: i64) {
    assert(request.module == 17 && request.words == 3 && request.shared);
    assert(request.result_shape.word == 23 && request.result_shape.flags == 9);
    assert(request.key.unit == 17 && request.key.binding == 8 && request.key.context == 41 && !request.key.context_free);
    let key = blot_backend_storage_function_plan_input::borrowPlanKey(request.key);
    assert(key.evidence == [7 as u32,11,13]);
    let first,error = request.graph.value.ordinal(91);
    assert(error == blot_error::Error.none && first == 0);
    let second,error2 = request.graph.value.ordinal(12);
    assert(error2 == blot_error::Error.none && second == 1);
    let missing,missing_error = request.graph.value.ordinal(99);
    assert(missing_error == blot_error::Error.declined);
    let a = blot_backend_storage_recursive_admission::accessAt(request.recursive_.value,0);
    let b = blot_backend_storage_recursive_admission::accessAt(request.recursive_.value,1);
    assert(a.read && !a.write && !b.read && b.write);
    if depth == 0 {
        blot_backend_storage_function_plan_input::rejections[request.rejection_slot].alias = true;
        blot_backend_storage_function_plan_input::rejections[request.rejection_slot].addressed = true;
        return;
    }
    var other = blot_backend_storage_type_key::Words {..};
    assert(other.push(depth as u32) == blot_error::Error.none);
    inspect(request,depth - 1);
    other.deinit();
}
fn main() {
    var empty = blot_backend_storage_type_key::Words {..};
    let empty_span = empty.wordRun();
    assert(empty_span.len == 0 && empty_span.capacity == 0 && empty_span.view().len == 0);
    assert(empty.push(9 as u32) == blot_error::Error.none); empty.clear();
    let retained_empty = empty.wordRun(); assert(retained_empty.len == 0 && retained_empty.capacity > 0 && retained_empty.view().len == 0);
    var graph = blot_backend_storage_owner_graph::Graph<u32> {..};
    let empty_graph = graph.ordinalRun();
    let missing,error = empty_graph.ordinal(1);
    assert(error == blot_error::Error.declined);
    let empty_access = blot_backend_storage_recursive_admission::accessRun(blot_backend_storage_recursive_admission::Contract {..});
    assert(empty_access.len == 0);
    assert(graph.add(91,100) == blot_error::Error.none);
    assert(graph.add(12,100) == blot_error::Error.none);
    assert(graph.add(91,100) == blot_error::Error.none);
    assert(graph.owners.items == [91 as i64,12]);
    var evidence = blot_backend_storage_type_key::Words {..};
    assert(evidence.append([7 as u32,11,13]) == blot_error::Error.none);
    let key = blot_backend_storage_calls::Key { unit:17,binding:8,context:41,evidence:evidence.items,..};
    let accesses = blot_backend_storage_recursive_admission::access_pool.alloc_slice(2);
    accesses[0] = blot_backend_storage_recursive_admission::Access {read:true,..};
    accesses[1] = blot_backend_storage_recursive_admission::Access {write:true,..};
    let contract = blot_backend_storage_recursive_admission::Contract {parameter_access:accesses,self_recursive:true,work:19,backedges:2};
    let slot = blot_backend_storage_function_plan_input::rejections.alloc_index(blot_backend_storage_function_plan_input::Rejections {..});
    let request = Request {module:17,graph:blot_support::Option<blot_backend_storage_owner_graph::OrdinalRun> {true,graph.ordinalRun()},words:3,rejection_slot:slot,recursive_:blot_support::Option<blot_backend_storage_recursive_admission::AccessRun> {true,contract.accessRun()},result_shape:MiniValue {23,9},shared:true,key:blot_backend_storage_function_plan_input::functionPlanKey(key,evidence),..};
    assert(blot_support::same_slice_identity(request.key.evidence.view(),evidence.items));
    assert(blot_support::same_slice_identity(blot_backend_storage_owner_graph::ordinal_slots[request.graph.value.start..request.graph.value.start+request.graph.value.len],graph.ordinals.slots));
    assert(blot_support::same_slice_identity(blot_backend_storage_recursive_admission::access_pool[request.recursive_.value.start..request.recursive_.value.start+request.recursive_.value.len],accesses));
    let original_flags: blot_backend_storage_function_plan_input::Rejections& = blot_backend_storage_function_plan_input::rejections[slot];
    inspect(request,3);
    assert(original_flags.alias && original_flags.addressed);
    assert(contract.work == 19 && contract.backedges == 2 && contract.self_recursive);
    assert(blot_backend_storage_function_plan_input::rejections[slot].alias && blot_backend_storage_function_plan_input::rejections[slot].addressed);
    assert(graph.owners.items == [91 as i64,12] && evidence.items == [7 as u32,11,13]);
    blot_backend_storage_function_plan_input::rejections.free(slot);
    blot_backend_storage_recursive_admission::access_pool.free_slice(accesses);
    evidence.deinit(); graph.deinit(); empty.deinit();
    let modules = module_runs.alloc_slice(1);
    modules[0] = blot_check_core::Module {unit:1,..};
    let module: const blot_check_core::Module& = modules[0];
    assert(module .== modules[0]);
    assert(blot_backend_storage_function_plan_input::planUnit(modules,module) == 1);
    module_runs.free_slice(modules);
}
