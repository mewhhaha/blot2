namespace blot_backend_provider_chain;
import dictionary;
import check.effect_evidence;
import check.effect_authority;
import runtime.runtime_layout;
import support.error;
import support.option;
import support.native;
import support.pooled_buffer;
import support.pooled_map;

type Operation = blot_check_effect_evidence::Label;
type Authority = blot_check_effect_authority::Handle;
type Value = u32;
type Head = u32;
type CellId = u32;
let empty: Head = 0;
type Kind = blot_runtime_runtime_layout::ProviderKind;
type Frame = blot_runtime_runtime_layout::ProviderFrame;
type Cell = blot_runtime_runtime_layout::StateCell;
type Provider = blot_runtime_runtime_layout::Provider;
type StateProvider = blot_runtime_runtime_layout::StateProvider;
struct Key { operation: Operation = 0, owner: Authority = 0 }
fn same(left: Key, right: Key) -> bool { left.operation == right.operation && left.owner == right.owner }
struct Installation { head: Head = 0, cell: CellId = 0 }
struct Match { frame: Frame }
struct Mark { frames: i64, cells: i64 }
struct Frames { storage: Frame[:] = default<Frame[:]>(),items: Frame[:] = default<Frame[:]>(),len: i64 = 0 }
struct Cells { storage: Cell[:] = default<Cell[:]>(),items: Cell[:] = default<Cell[:]>(),len: i64 = 0 }
struct Scopes { storage: Authority[:] = default<Authority[:]>(),items: Authority[:] = default<Authority[:]>(),len: i64 = 0 }
reusable[] var frame_runs: Frame[>..] = [];
reusable[] var cell_runs: Cell[>..] = [];
reusable[] var scope_runs: Authority[>..] = [];
fn ensure(buffer: Frames&,minimum: i64) -> blot_error::Error { blot_support_pooled_buffer::ensure(buffer,minimum,frame_runs) }
fn ensure(buffer: Cells&,minimum: i64) -> blot_error::Error { blot_support_pooled_buffer::ensure(buffer,minimum,cell_runs) }
fn ensure(buffer: Scopes&,minimum: i64) -> blot_error::Error { blot_support_pooled_buffer::ensure(buffer,minimum,scope_runs) }
fn appendAssumeCapacity(buffer: Frames&,frame: Frame) { assert(buffer.len < buffer.storage.len); buffer.storage[buffer.len] = frame; buffer.len++; buffer.items = buffer.storage[..buffer.len]; }
fn appendAssumeCapacity(buffer: Cells&,cell: Cell) { assert(buffer.len < buffer.storage.len); buffer.storage[buffer.len] = cell; buffer.len++; buffer.items = buffer.storage[..buffer.len]; }
fn appendAssumeCapacity(buffer: Scopes&,scope: Authority) { assert(buffer.len < buffer.storage.len); buffer.storage[buffer.len] = scope; buffer.len++; buffer.items = buffer.storage[..buffer.len]; }
fn pop(buffer: Scopes&) -> Authority { assert(buffer.len != 0); let value = buffer.items[buffer.len - 1]; buffer.len--; buffer.items = buffer.storage[..buffer.len]; return value; }
fn resize(buffer: Frames&,length: i64) { blot_support_pooled_buffer::resize(buffer,length); buffer.len = length; }
fn resize(buffer: Cells&,length: i64) { blot_support_pooled_buffer::resize(buffer,length); buffer.len = length; }
fn clear(buffer: Frames&) { blot_support_pooled_buffer::clear(buffer); buffer.len = 0; }
fn clear(buffer: Cells&) { blot_support_pooled_buffer::clear(buffer); buffer.len = 0; }
fn clear(buffer: Scopes&) { blot_support_pooled_buffer::clear(buffer); buffer.len = 0; }
fn deinit(buffer: Frames&) { blot_support_pooled_buffer::deinit(buffer,frame_runs); buffer.len = 0; }
fn deinit(buffer: Cells&) { blot_support_pooled_buffer::deinit(buffer,cell_runs); buffer.len = 0; }
fn deinit(buffer: Scopes&) { blot_support_pooled_buffer::deinit(buffer,scope_runs); buffer.len = 0; }
struct FrameOwners { count: i64 = 0,slots: dictionary_slot<Head,Authority>[:] = default<dictionary_slot<Head,Authority>[:]>() }
reusable[] var frame_owner_slots: dictionary_slot<Head,Authority>[>..] = [];
fn get(map: const FrameOwners&,key: Head) -> Authority? { let view = blot_support_pooled_map::Map<Head,Authority> { map.count,map.slots , ..}; return blot_support_pooled_map::get(view,key); }
fn reserve(map: FrameOwners&,extra: i64) -> blot_error::Error { if extra < 0 || map.count > 1537228672809129301 - extra { return blot_error::Error.out_of_memory; } var capacity = max(8,map.slots.len); while (map.count + extra) * 3 > capacity * 2 { capacity *= 2; } if capacity != map.slots.len { var view = blot_support_pooled_map::Map<Head,Authority> { map.count,map.slots , ..}; blot_support_pooled_map::grow(view,capacity,frame_owner_slots); map.count = view.count; map.slots = view.slots; } return blot_error::Error.none; }
fn insert(map: FrameOwners&,key: Head,value: Authority) { var view = blot_support_pooled_map::Map<Head,Authority> { map.count,map.slots , ..}; blot_support_pooled_map::insert(view,key,value,frame_owner_slots); map.count = view.count; map.slots = view.slots; }
fn remove(map: FrameOwners&,key: Head) -> bool { var view = blot_support_pooled_map::Map<Head,Authority> { map.count,map.slots , ..}; let removed = blot_support_pooled_map::remove(view,key); map.count = view.count; map.slots = view.slots; return removed; }
fn clear(map: FrameOwners&) { for &slot in map.slots { slot.tag = 0; } map.count = 0; }
fn deinit(map: FrameOwners&) { if map.slots.len != 0 { frame_owner_slots.free_slice(map.slots); } map.slots = []; map.count = 0; }
struct Activation { scopes: Scopes }
struct State { owner_id: u64,generation: u64,frames: Frames,cells: Cells,authorities: blot_check_effect_authority::Store,frame_owners: FrameOwners }
reusable var states: State[>..] = [];
var next_generation: u64 = 1;
var inactive_frames = Frames {..};
var inactive_cells = Cells {..};
var inactive_authorities = blot_check_effect_authority::Store {..};
var inactive_owners = FrameOwners {..};
struct Store { owner_id: u64 = 0,lease: u32 = 0,generation: u64 = 0,reference_lease: u32 = 0,frames: Frames& = inactive_frames,cells: Cells& = inactive_cells,authorities: blot_check_effect_authority::Store& = inactive_authorities,frame_owners: FrameOwners& = inactive_owners }
struct Reference { value: Store }
reusable var references: Reference[>..] = [];
fn valid(store: const Store&) -> bool { return store.lease != 0 && store.lease - 1 < states.len && store.owner_id != 0 && states[store.lease - 1].owner_id == store.owner_id && states[store.lease - 1].generation == store.generation; }
fn initPooled() -> Store,blot_error::Error {
    if next_generation == 18446744073709551615 || states.len >= 4294967295 { return Store {..},blot_error::Error.out_of_memory; } let authorities,error = blot_check_effect_authority::initPooled(); if error != blot_error::Error.none { return Store {..},error; } let generation = next_generation; next_generation++; let owner_id = blot_native::fresh_owner_id(); let index = states.alloc_index(State { owner_id: owner_id,generation: generation,frames: Frames {..},cells: Cells {..},authorities: authorities,frame_owners: FrameOwners {..} , ..}); let state: State& = states[index]; return Store { owner_id: owner_id,lease: (index + 1) as u32,generation: generation,frames: state.frames,cells: state.cells,authorities: state.authorities,frame_owners: state.frame_owners , ..},blot_error::Error.none;
}
fn init() -> Store,blot_error::Error { return initPooled(); }
fn initPooledRef() -> Store?,blot_error::Error { let initialized,error = initPooled(); if error != blot_error::Error.none { return null,error; } if references.len >= 4294967295 { var unused = initialized; unused.deinit(); return null,blot_error::Error.out_of_memory; } let index = references.alloc_index(Reference { initialized , ..}); references[index].value.reference_lease = (index + 1) as u32; return references[index].value,blot_error::Error.none; }
fn end(activation: Activation&, store: Store&) {
    while activation.scopes.len != 0 { let owner = activation.scopes.pop(); let error = store.authorities.end(owner); assert(error == blot_error::Error.none); }
}
fn mark(store: Store&) -> Mark { assert(valid(store)); return Mark { frames: store.frames.len, cells: store.cells.len , ..}; }
fn releaseFrame(store: Store&, head: Head) {
    var owner: Authority = 0; var found = false;
    block { let entry = store.frame_owners.get(head); if entry { owner = entry; found = true; } }
    if found { store.frame_owners.remove(head); let error = store.authorities.release(owner); assert(error == blot_error::Error.none); }
}
fn rewind(store: Store&, point: Mark) {
    assert(valid(store)); assert(point.frames <= store.frames.len && point.cells <= store.cells.len);
    if store.frame_owners.count != 0 { var head = store.frames.len; while head > point.frames { releaseFrame(store, head as u32); head--; } }
    store.frames.resize(point.frames); store.cells.resize(point.cells);
}
fn beginScope(store: Store&, activation: Activation&) -> Authority, blot_error::Error {
    assert(valid(store));
    let reserved = activation.scopes.ensure(activation.scopes.len + 1); if reserved != blot_error::Error.none { return 0,reserved; }
    let owner, error = store.authorities.begin(); if error != blot_error::Error.none { return 0, error; }
    activation.scopes.appendAssumeCapacity(owner); return owner, blot_error::Error.none;
}
fn endScope(store: Store&, activation: Activation&, owner: Authority) -> blot_error::Error {
    assert(valid(store));
    if activation.scopes.len == 0 || activation.scopes.items[activation.scopes.len - 1] != owner { return blot_error::Error.invalid_scope; }
    let error = store.authorities.end(owner); if error != blot_error::Error.none { return error; } activation.scopes.pop(); return blot_error::Error.none;
}
fn retainAuthority(store: Store&, owner: Authority) -> blot_error::Error { store.authorities.retain(owner) }
fn releaseAuthority(store: Store&, owner: Authority) -> blot_error::Error { store.authorities.release(owner) }
fn validateHead(store: Store&, head: Head) -> blot_error::Error { assert(valid(store)); if head > store.frames.len { return blot_error::Error.invalid_scope; } return blot_error::Error.none; }
fn validateOperation(catalog: blot_check_effect_evidence::View, operation: Operation) -> blot_error::Error {
    if operation == 0 || operation >= catalog.operations.len { return blot_error::Error.invalid_operation; }
    let identity = catalog.operation(operation).identity; if identity.decl == 0 { return blot_error::Error.invalid_operation; }
    if identity.unit == 0 && identity.decl == 1 { return blot_error::Error.sealed_operation; } return blot_error::Error.none;
}
fn retainFrame(store: Store&, head: Head, owner: Authority) -> blot_error::Error {
    if owner == 0 { return blot_error::Error.none; }
    let reserved = store.frame_owners.reserve(1); if reserved != blot_error::Error.none { return reserved; }
    let error = store.authorities.retain(owner); if error != blot_error::Error.none { return error; }
    store.frame_owners.insert(head, owner); return blot_error::Error.none;
}
fn installProvider(store: Store&, catalog: blot_check_effect_evidence::View, outer: Head, provider: Provider) -> Head, blot_error::Error { return installProviderKey(store, catalog, outer, Key { operation: provider.operation , ..}, provider.implementation); }
fn installProviderKey(store: Store&, catalog: blot_check_effect_evidence::View, outer: Head, key: Key, implementation: Value) -> Head, blot_error::Error {
    let head, error = installFrame(store, catalog, outer, key, implementation, blot_runtime_runtime_layout::ProviderKind_callback); return head, error;
}
fn installRequest(store: Store&, catalog: blot_check_effect_evidence::View, outer: Head, operation: Operation, handler: u32) -> Head, blot_error::Error { return installRequestKey(store, catalog, outer, Key { operation: operation , ..}, handler); }
fn installRequestKey(store: Store&, catalog: blot_check_effect_evidence::View, outer: Head, key: Key, handler: u32) -> Head, blot_error::Error { return installFrame(store, catalog, outer, key, handler, blot_runtime_runtime_layout::ProviderKind_request); }
fn installFrame(store: Store&, catalog: blot_check_effect_evidence::View, outer: Head, key: Key, target: Value, kind: Kind) -> Head, blot_error::Error {
    var error = validateHead(store, outer); if error != blot_error::Error.none { return 0, error; }
    error = validateOperation(catalog, key.operation); if error != blot_error::Error.none { return 0, error; }
    error = store.authorities.requireActive(key.owner); if error != blot_error::Error.none { return 0, error; }
    if store.frames.len == 4294967295 { return 0, blot_error::Error.provider_limit; }
    error = store.frames.ensure(store.frames.len + 1); if error != blot_error::Error.none { return 0,error; }
    let head = (store.frames.len + 1) as u32; error = retainFrame(store, head, key.owner); if error != blot_error::Error.none { return 0, error; }
    store.frames.appendAssumeCapacity(Frame { operation: key.operation, target: target, outer: outer, kind: kind , ..}); return head, blot_error::Error.none;
}
fn installState(store: Store&, catalog: blot_check_effect_evidence::View, outer: Head, provider: StateProvider) -> Installation, blot_error::Error { return installStateKeys(store, catalog, outer, Key { operation: provider.read , ..}, Key { operation: provider.write , ..}, provider.initial); }
fn installStateKeys(store: Store&, catalog: blot_check_effect_evidence::View, outer: Head, read_key: Key, write_key: Key, initial: Value) -> Installation, blot_error::Error {
    var error = validateHead(store, outer); if error != blot_error::Error.none { return Installation {..}, error; }
    error = validateOperation(catalog, read_key.operation); if error != blot_error::Error.none { return Installation {..}, error; }
    error = validateOperation(catalog, write_key.operation); if error != blot_error::Error.none { return Installation {..}, error; }
    error = store.authorities.requireActive(read_key.owner); if error != blot_error::Error.none { return Installation {..}, error; }
    error = store.authorities.requireActive(write_key.owner); if error != blot_error::Error.none { return Installation {..}, error; }
    if same(read_key, write_key) || read_key.owner != write_key.owner { return Installation {..}, blot_error::Error.invalid_state_operations; }
    if store.frames.len > 4294967293 || store.cells.len == 4294967295 { return Installation {..}, blot_error::Error.provider_limit; }
    error = store.frames.ensure(store.frames.len + 2); if error != blot_error::Error.none { return Installation {..},error; }
    error = store.cells.ensure(store.cells.len + 1); if error != blot_error::Error.none { return Installation {..},error; }
    let write_head = (store.frames.len + 1) as u32;
    error = retainFrame(store, write_head, write_key.owner); if error != blot_error::Error.none { return Installation {..}, error; }
    error = retainFrame(store, write_head + 1, read_key.owner); if error != blot_error::Error.none { releaseFrame(store, write_head); return Installation {..}, error; }
    let cell = (store.cells.len + 1) as u32; store.cells.appendAssumeCapacity(Cell { value: initial , ..});
    store.frames.appendAssumeCapacity(Frame { operation: write_key.operation, target: cell, outer: outer, kind: blot_runtime_runtime_layout::ProviderKind_state_write , ..});
    store.frames.appendAssumeCapacity(Frame { operation: read_key.operation, target: cell, outer: write_head, kind: blot_runtime_runtime_layout::ProviderKind_state_read , ..});
    return Installation { head: store.frames.len as u32, cell: cell , ..}, blot_error::Error.none;
}
fn lookup(store: Store&, head: Head, operation: Operation) -> blot_support::Option<Match>, blot_error::Error { return lookupKey(store, head, Key { operation: operation , ..}); }
fn lookupKey(store: Store&, head: Head, key: Key) -> blot_support::Option<Match>, blot_error::Error {
    var error = store.authorities.requireActive(key.owner); if error != blot_error::Error.none { return blot_support::none<Match>(), error; }
    error = validateHead(store, head); if error != blot_error::Error.none { return blot_support::none<Match>(), error; }
    var cursor = head;
    while cursor != empty {
        let frame = store.frames.items[cursor - 1];
        if frame.operation == key.operation {
            var owner: Authority = 0;
            block { let entry = store.frame_owners.get(cursor); if entry { owner = entry; } }
            if owner == key.owner { return blot_support::some(Match { frame: frame , ..}), blot_error::Error.none; }
        }
        cursor = frame.outer;
    }
    return blot_support::none<Match>(), blot_error::Error.none;
}
fn read(store: Store&, cell: CellId) -> Value, blot_error::Error { assert(valid(store)); if cell == 0 || cell > store.cells.len { return 0, blot_error::Error.invalid_scope; } return store.cells.items[cell - 1].value, blot_error::Error.none; }
fn write(store: Store&, cell: CellId, value: Value) -> blot_error::Error { assert(valid(store)); if cell == 0 || cell > store.cells.len { return blot_error::Error.invalid_scope; } store.cells.items[cell - 1].value = value; return blot_error::Error.none; }
fn deinit(activation: Activation&, store: Store&) { end(activation, store); activation.scopes.deinit(); }
fn deinit(store: Store&) {
    if store.lease == 0 { return; } assert(valid(store)); store.frames.deinit(); store.cells.deinit(); store.frame_owners.deinit(); store.authorities.deinit(); let index = store.lease - 1; let reference = store.reference_lease; states[index].owner_id = 0; states.free(index); store = Store {..}; if reference != 0 { references.free(reference - 1); }
}
fn reset(store: Store&) -> blot_error::Error {
    assert(valid(store)); rewind(store,Mark { frames: 0,cells: 0 , ..}); store.frame_owners.clear(); store.frames.clear(); store.cells.clear(); let error = store.authorities.reset(); if error != blot_error::Error.none { return error; } let identity = blot_native::fresh_owner_id(); states[store.lease - 1].owner_id = identity; store.owner_id = identity; return blot_error::Error.none;
}
