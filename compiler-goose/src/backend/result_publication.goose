// Publication owns immutable input journals while the driver owns the workspace.
namespace blot_backend_result_publication;
import check.core;
import reuse.dependency_payload;
import reuse.code_artifacts;
import support.error;
import support.native;
type Error = blot_error::Error;
type InputOwner = blot_reuse_dependency_payload::Owner;
struct Owner { slot: u32 = 0,generation: u64 = 0 }
struct Pins { journals: InputOwner[:] = default<InputOwner[:]>(),units: blot_check_core::Module[:] = default<blot_check_core::Module[:]>() }
struct State { generation: u64,driver_owner: u64,allocation_owner: u64,live: bool = true,epoch: u64 = 0,compiling: bool = false,result_live: bool = false,published: bool = false,leased: bool = false,inputs_staged: bool = false,pins: Pins }
reusable var states: State[>..] = [];
reusable[] var journal_runs: InputOwner[>..] = [];
reusable[] var module_runs: blot_check_core::Module[>..] = [];
fn valid(owner: Owner) -> bool { return owner.slot != 0 && owner.slot - 1 < states.len && states[owner.slot - 1].live && states[owner.slot - 1].generation == owner.generation; }
fn init(driver_owner: u64,allocation_owner: u64) -> Owner,Error {
    if driver_owner == 0 || allocation_owner == 0 { return Owner {..},blot_error::Error.invalid_artifact; } if states.len >= 4294967295 { return Owner {..},blot_error::Error.out_of_memory; } let generation = blot_native::fresh_owner_id(); let at = states.alloc_index(State { generation,driver_owner,allocation_owner , ..}); return Owner { slot: (at + 1) as u32,generation: generation , ..},blot_error::Error.none;
}
fn allocation(owner: Owner) -> u64 { assert(valid(owner)); return states[owner.slot - 1].allocation_owner; }
fn driver(owner: Owner) -> u64 { assert(valid(owner)); return states[owner.slot - 1].driver_owner; }
fn canMutate(owner: Owner) -> bool { if owner.slot == 0 { return true; } if !valid(owner) { return false; } let state = states[owner.slot - 1]; return !state.leased && !state.published && !state.result_live; }
fn canCompile(owner: Owner) -> bool { if owner.slot == 0 { return true; } if !valid(owner) { return false; } let state = states[owner.slot - 1]; return state.inputs_staged && state.epoch == 0 && !state.compiling && !state.result_live && !state.published && !state.leased; }
fn beginCompile(owner: Owner) -> u64,Error {
    if owner.slot == 0 { return 0,blot_error::Error.none; } if !canCompile(owner) { return 0,blot_error::Error.invalid_artifact; } let state: State& = states[owner.slot - 1]; if state.epoch == 18446744073709551615 { return 0,blot_error::Error.out_of_memory; } state.epoch++; state.compiling = true; return state.epoch,blot_error::Error.none;
}
fn finishCompile(owner: Owner,epoch: u64) { if owner.slot == 0 { assert(epoch == 0); return; } assert(valid(owner)); let state: State& = states[owner.slot - 1]; assert(state.compiling && state.epoch == epoch && !state.result_live && !state.leased); state.compiling = false; state.result_live = true; }
fn resultValid(owner: Owner,epoch: u64,pinned: bool) -> bool { if owner.slot == 0 { return epoch == 0 && !pinned; } if !valid(owner) { return false; } let state = states[owner.slot - 1]; return !state.compiling && state.result_live && state.epoch == epoch && state.leased == pinned; }
fn deinit(pins: Pins&) { for &owner in pins.journals { owner.release(); } if pins.journals.len != 0 { journal_runs.free_slice(pins.journals); } if pins.units.len != 0 { module_runs.free_slice(pins.units); } pins = Pins {..}; }
fn inputsMatch(pins: Pins,catalog: InputOwner,unit_owners: const InputOwner[:],seed_owners: const InputOwner[:]) -> bool {
    var at: i64 = 0;
    if catalog.lease != 0 { if at >= pins.journals.len || pins.journals[at] != catalog { return false; } at++; }
    for input in unit_owners { if input.lease == 0 { continue; } if at >= pins.journals.len || pins.journals[at] != input { return false; } at++; }
    for input in seed_owners { if at >= pins.journals.len || pins.journals[at] != input { return false; } at++; }
    return at == pins.journals.len;
}
fn sameUnits(left: const blot_check_core::Module[:],right: const blot_check_core::Module[:]) -> bool {
    if left.len != right.len { return false; } for module,index in left { if blot_check_core::stampView(module) != blot_check_core::stampView(right[index]) { return false; } } return true;
}
// Called before any workspace context receives a module or payload reference.
fn stageInputs(owner: Owner,units: const blot_check_core::Module[:],catalog: InputOwner,unit_owners: const InputOwner[:],seed_owners: const InputOwner[:]) -> Error {
    if !valid(owner) || unit_owners.len != units.len { return blot_error::Error.invalid_artifact; } let state: State& = states[owner.slot - 1];
    if state.inputs_staged || state.epoch != 0 || state.compiling || state.result_live || state.published || state.leased { return blot_error::Error.invalid_artifact; }
    if units.len != 0 && catalog.lease == 0 { return blot_error::Error.invalid_artifact; }
    var count: i64 = 0; if catalog.lease != 0 { count++; } for input in unit_owners { if input.lease == 0 { if seed_owners.len == 0 { return blot_error::Error.invalid_artifact; } } else { count++; } } for input in seed_owners { if input.lease == 0 { return blot_error::Error.invalid_artifact; } count++; }
    var pins = Pins {..}; pins.journals = journal_runs.alloc_slice(count); for &input in pins.journals { input = InputOwner {..}; } var next: i64 = 0;
    fn retainInputs() -> Error {
        if catalog.lease != 0 { let held,error = catalog.retain(); if error != blot_error::Error.none { return error; } pins.journals[next] = held; next++; }
        for input in unit_owners { if input.lease == 0 { continue; } let held,error = input.retain(); if error != blot_error::Error.none { return error; } pins.journals[next] = held; next++; }
        for input in seed_owners { let held,error = input.retain(); if error != blot_error::Error.none { return error; } pins.journals[next] = held; next++; }
        pins.units = module_runs.alloc_slice(units.len);
        // Catalogs own registered header ranges; retained journals keep
        // every payload alive. Reborrow that run without moving or copying it.
        let source = blot_reuse_dependency_payload::pool_header_module.realloc_slice(units,units.len);
        for module,index in source { pins.units[index] = module; } return blot_error::Error.none;
    }
    let error = retainInputs(); if error != blot_error::Error.none { pins.deinit(); return error; } assert(next == count); state.pins = pins; state.inputs_staged = true; return blot_error::Error.none;
}
fn registeredInputUnits(owner:Owner)->const blot_check_core::Module[:],Error {
    if !valid(owner) || !states[owner.slot-1].inputs_staged {return default<const blot_check_core::Module[:]>(),blot_error::Error.invalid_artifact;}
    let registered=states[owner.slot-1].pins.units;if registered.len==0 {return default<const blot_check_core::Module[:]>(),blot_error::Error.none;}
    let owned=module_runs.realloc_slice(registered,registered.len);assert(blot_support::same_slice_identity(owned,registered));let start=module_runs.index_of(owned[0]);return module_runs[start..start+owned.len],blot_error::Error.none;
}
fn inputUnits(owner: Owner,source: const blot_check_core::Module[:]) -> const blot_check_core::Module[:],Error {
    let held,error=registeredInputUnits(owner);if error!=blot_error::Error.none || !sameUnits(held,source) {return default<const blot_check_core::Module[:]>(),blot_error::Error.invalid_artifact;}return held,blot_error::Error.none;
}
// Validates a result's pins against its staged inputs. Capture module pins are
// made one per registered unit and rebind to those registered units directly.
fn checkPins(owner: Owner,epoch: u64,units: const blot_check_core::Module[:],catalog: InputOwner,unit_owners: const InputOwner[:],seed_owners: const InputOwner[:],module_pins: const blot_reuse_code_artifacts::ModulePin[:]) -> Error {
    if !valid(owner) || !resultValid(owner,epoch,false) { return blot_error::Error.invalid_artifact; } let state = states[owner.slot - 1];
    if !state.inputs_staged || state.published || unit_owners.len != units.len || !sameUnits(state.pins.units,units) || !inputsMatch(state.pins,catalog,unit_owners,seed_owners) { return blot_error::Error.invalid_artifact; }
    if module_pins.len != 0 && module_pins.len != state.pins.units.len { return blot_error::Error.invalid_artifact; } return blot_error::Error.none;
}
fn commit(owner: Owner,epoch: u64) {
    assert(valid(owner) && resultValid(owner,epoch,false)); let state: State& = states[owner.slot - 1]; assert(state.inputs_staged && !state.published); state.published = true; state.leased = true;
}
fn units(owner: Owner,epoch: u64) -> const blot_check_core::Module[:] { assert(resultValid(owner,epoch,true));let held,error=registeredInputUnits(owner);assert(error==blot_error::Error.none);return held; }
fn releaseResult(owner: Owner,epoch: u64,pinned: bool) {
    if owner.slot == 0 { assert(epoch == 0 && !pinned); return; } assert(resultValid(owner,epoch,pinned)); let state: State& = states[owner.slot - 1]; state.result_live = false; state.leased = false;
    // Input journals and header copies remain alive during workspace teardown.
}
fn canReclaim(owner: Owner) -> bool { if !valid(owner) { return false; } let state = states[owner.slot - 1]; return !state.compiling && !state.result_live && !state.leased; }
// The canonical driver calls this after destroying every workspace context.
fn destroy(owner: Owner&) -> Error { if owner.slot == 0 { return blot_error::Error.none; } if !canReclaim(owner) { return blot_error::Error.invalid_artifact; } let at = owner.slot - 1; states[at].pins.deinit(); states[at].live = false; states.free(at); owner = Owner {..}; return blot_error::Error.none; }

// Failed error-union calls publish no Result lease; staged inputs stay pinned
// until the ordinary workspace destruction boundary.
fn abortCompile(owner: Owner,epoch: u64) { if owner.slot == 0 { assert(epoch == 0); return; } assert(valid(owner)); let state: State& = states[owner.slot - 1]; assert(state.compiling && state.epoch == epoch && !state.result_live && !state.leased); state.compiling = false; }
