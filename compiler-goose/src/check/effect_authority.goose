// Activation authority stays in a durable owner and never enters archives.
namespace blot_check_effect_authority;
import support.error;
import support.native;
import support.pooled_buffer;
type Handle = u32;
type Error = blot_error::Error;
let static: Handle = 0;
struct Owner { references: u32 = 1,active: bool = true }
struct Owners { storage: Owner[:] = [],items: Owner[:] = [],len: i64 = 0 }
reusable[] var owner_runs: Owner[>..] = [];
fn push(owners: Owners&,owner: Owner) -> Error { let error = blot_support_pooled_buffer::push(owners,owner,owner_runs); owners.len = owners.items.len; return error; }
fn clear(owners: Owners&) { blot_support_pooled_buffer::clear(owners); owners.len = 0; }
fn deinit(owners: Owners&) { blot_support_pooled_buffer::deinit(owners,owner_runs); owners.len = 0; }
struct State { owner_id: u64,generation: u64,owners: Owners,live: i64 = 0,active: i64 = 0,max_owners: u32 = 4294967295 }
reusable var states: State[>..] = [];
var next_generation: u64 = 1;
var inactive_owners = Owners {..};
var inactive_count: i64 = 0;
var inactive_maximum: u32 = 4294967295;
struct Store {
    owner_id: u64 = 0,lease: u32 = 0,generation: u64 = 0,reference_lease: u32 = 0,
    owners: Owners& = inactive_owners,live: i64& = inactive_count,active: i64& = inactive_count,max_owners: u32& = inactive_maximum,
}
struct Reference { value: Store }
reusable var references: Reference[>..] = [];
fn valid(store: const Store&) -> bool { return store.lease != 0 && store.lease - 1 < states.len && store.owner_id != 0 && states[store.lease - 1].owner_id == store.owner_id && states[store.lease - 1].generation == store.generation; }
fn initPooled() -> Store,Error {
    if next_generation == 18446744073709551615 || states.len >= 4294967295 { return Store {..},Error.out_of_memory; } let generation = next_generation; next_generation++; let owner_id = blot_native::fresh_owner_id(); let index = states.alloc_index(State { owner_id,generation,owners: Owners {..} , ..}); let state: State& = states[index]; return Store { owner_id,lease: (index + 1) as u32,generation,owners: state.owners,live: state.live,active: state.active,max_owners: state.max_owners , ..},Error.none;
}
fn init() -> Store,Error { initPooled() }
fn initPooledRef() -> Store?,Error {
    let initialized,error = initPooled(); if error != Error.none { return null,error; } if references.len >= 4294967295 { var unused = initialized; unused.deinit(); return null,Error.out_of_memory; } let index = references.alloc_index(Reference { value: initialized , ..}); references[index].value.reference_lease = (index + 1) as u32; return references[index].value,Error.none;
}
fn deinit(store: Store&) {
    if store.lease == 0 { return; } assert(valid(store)); store.owners.deinit(); let index = store.lease - 1; let reference = store.reference_lease; states[index].owner_id = 0; states.free(index); store = Store {..}; if reference != 0 { references.free(reference - 1); }
}
fn reset(store: Store&) -> Error {
    assert(valid(store)); store.owners.clear(); store.live = 0; store.active = 0; store.max_owners = 4294967295; let identity = blot_native::fresh_owner_id(); states[store.lease - 1].owner_id = identity; store.owner_id = identity; return Error.none;
}
fn begin(store: Store&) -> Handle,Error { assert(valid(store)); if store.owners.len >= store.max_owners { return 0,Error.authority_limit; } let error = store.owners.push(Owner {..}); if error != Error.none { return 0,error; } store.live++; store.active++; return store.owners.len as u32,Error.none; }
fn ownerIndex(store: const Store&,handle: Handle) -> i64,Error { assert(valid(store)); if handle == 0 || handle > store.owners.len || store.owners.items[handle - 1].references == 0 { return 0,Error.invalid_authority; } return (handle - 1) as i64,Error.none; }
fn requireActive(store: const Store&,handle: Handle) -> Error { if handle == static { return Error.none; } let index,error = ownerIndex(store,handle); if error != Error.none { return error; } if !store.owners.items[index].active { return Error.inactive_authority; } return Error.none; }
fn retain(store: Store&,handle: Handle) -> Error { if handle == static { return Error.none; } let index,error = ownerIndex(store,handle); if error != Error.none { return error; } if store.owners.items[index].references == 4294967295 { return Error.authority_limit; } store.owners.items[index].references++; return Error.none; }
fn release(store: Store&,handle: Handle) -> Error { if handle == static { return Error.none; } let index,error = ownerIndex(store,handle); if error != Error.none { return error; } if store.owners.items[index].references == 1 && store.owners.items[index].active { return Error.invalid_authority; } store.owners.items[index].references--; if store.owners.items[index].references == 0 { store.live--; } return Error.none; }
fn revoke(store: Store&,handle: Handle) -> Error { if handle == static { return Error.invalid_authority; } let index,error = ownerIndex(store,handle); if error != Error.none { return error; } if store.owners.items[index].active { store.owners.items[index].active = false; store.active--; } return Error.none; }
fn end(store: Store&,handle: Handle) -> Error { let error = revoke(store,handle); if error != Error.none { return error; } return release(store,handle); }
