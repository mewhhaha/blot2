namespace blot_backend_provider_chain;
import dictionary;
import check.effect_evidence;
import check.effect_authority;
import runtime.runtime_layout;
import support.error;
import support.option;

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
struct Activation { scopes: Authority[>..<]& }
struct Store { frames: Frame[>..<]&, cells: Cell[>..<]&, authorities: blot_check_effect_authority::Store&, frame_owners: dictionary<Head, Authority>& }
fn init(frames: Frame[>..<]&, cells: Cell[>..<]&, authorities: blot_check_effect_authority::Store&, frame_owners: dictionary<Head, Authority>&) -> Store { Store { frames: frames, cells: cells, authorities: authorities, frame_owners: frame_owners } }
fn end(activation: Activation&, store: Store&) {
    while activation.scopes.len != 0 { let owner = activation.scopes.pop(); let error = store.authorities.end(owner); assert(error == blot_error::Error.none); }
}
fn mark(store: Store&) -> Mark { Mark { frames: store.frames.len, cells: store.cells.len } }
fn releaseFrame(store: Store&, head: Head) {
    var owner: Authority = 0; var found = false;
    block { let entry = store.frame_owners.get(head); if entry { owner = entry; found = true; } }
    if found { store.frame_owners.remove(head); let error = store.authorities.release(owner); assert(error == blot_error::Error.none); }
}
fn rewind(store: Store&, point: Mark) {
    assert(point.frames <= store.frames.len && point.cells <= store.cells.len);
    if store.frame_owners.count != 0 { var head = store.frames.len; while head > point.frames { releaseFrame(store, head as u32); head--; } }
    store.frames.resize(point.frames); store.cells.resize(point.cells);
}
fn beginScope(store: Store&, activation: Activation&) -> Authority, blot_error::Error {
    let owner, error = store.authorities.begin(); if error != blot_error::Error.none { return 0, error; }
    activation.scopes.push(owner); return owner, blot_error::Error.none;
}
fn endScope(store: Store&, activation: Activation&, owner: Authority) -> blot_error::Error {
    if activation.scopes.len == 0 || activation.scopes[activation.scopes.len - 1] != owner { return blot_error::Error.invalid_scope; }
    let error = store.authorities.end(owner); if error != blot_error::Error.none { return error; } activation.scopes.pop(); return blot_error::Error.none;
}
fn retainAuthority(store: Store&, owner: Authority) -> blot_error::Error { store.authorities.retain(owner) }
fn releaseAuthority(store: Store&, owner: Authority) -> blot_error::Error { store.authorities.release(owner) }
fn validateHead(store: Store&, head: Head) -> blot_error::Error { if head > store.frames.len { return blot_error::Error.invalid_scope; } return blot_error::Error.none; }
fn validateOperation(catalog: blot_check_effect_evidence::View, operation: Operation) -> blot_error::Error {
    if operation == 0 || operation >= catalog.operations.len { return blot_error::Error.invalid_operation; }
    let identity = catalog.operation(operation).identity; if identity.decl == 0 { return blot_error::Error.invalid_operation; }
    if identity.unit == 0 && identity.decl == 1 { return blot_error::Error.sealed_operation; } return blot_error::Error.none;
}
fn retainFrame(store: Store&, head: Head, owner: Authority) -> blot_error::Error {
    if owner == 0 { return blot_error::Error.none; }
    let error = store.authorities.retain(owner); if error != blot_error::Error.none { return error; }
    store.frame_owners.insert(head, owner); return blot_error::Error.none;
}
fn installProvider(store: Store&, catalog: blot_check_effect_evidence::View, outer: Head, provider: Provider) -> Head, blot_error::Error { installProviderKey(store, catalog, outer, Key { operation: provider.operation }, provider.implementation) }
fn installProviderKey(store: Store&, catalog: blot_check_effect_evidence::View, outer: Head, key: Key, implementation: Value) -> Head, blot_error::Error {
    let head, error = installFrame(store, catalog, outer, key, implementation, blot_runtime_runtime_layout::ProviderKind_callback); return head, error;
}
fn installRequest(store: Store&, catalog: blot_check_effect_evidence::View, outer: Head, operation: Operation, handler: u32) -> Head, blot_error::Error { installRequestKey(store, catalog, outer, Key { operation: operation }, handler) }
fn installRequestKey(store: Store&, catalog: blot_check_effect_evidence::View, outer: Head, key: Key, handler: u32) -> Head, blot_error::Error { installFrame(store, catalog, outer, key, handler, blot_runtime_runtime_layout::ProviderKind_request) }
fn installFrame(store: Store&, catalog: blot_check_effect_evidence::View, outer: Head, key: Key, target: Value, kind: Kind) -> Head, blot_error::Error {
    var error = validateHead(store, outer); if error != blot_error::Error.none { return 0, error; }
    error = validateOperation(catalog, key.operation); if error != blot_error::Error.none { return 0, error; }
    error = store.authorities.requireActive(key.owner); if error != blot_error::Error.none { return 0, error; }
    if store.frames.len == 4294967295 { return 0, blot_error::Error.provider_limit; }
    let head = (store.frames.len + 1) as u32; error = retainFrame(store, head, key.owner); if error != blot_error::Error.none { return 0, error; }
    store.frames.push(Frame { operation: key.operation, target: target, outer: outer, kind: kind }); return head, blot_error::Error.none;
}
fn installState(store: Store&, catalog: blot_check_effect_evidence::View, outer: Head, provider: StateProvider) -> Installation, blot_error::Error { installStateKeys(store, catalog, outer, Key { operation: provider.read }, Key { operation: provider.write }, provider.initial) }
fn installStateKeys(store: Store&, catalog: blot_check_effect_evidence::View, outer: Head, read_key: Key, write_key: Key, initial: Value) -> Installation, blot_error::Error {
    var error = validateHead(store, outer); if error != blot_error::Error.none { return Installation {}, error; }
    error = validateOperation(catalog, read_key.operation); if error != blot_error::Error.none { return Installation {}, error; }
    error = validateOperation(catalog, write_key.operation); if error != blot_error::Error.none { return Installation {}, error; }
    error = store.authorities.requireActive(read_key.owner); if error != blot_error::Error.none { return Installation {}, error; }
    error = store.authorities.requireActive(write_key.owner); if error != blot_error::Error.none { return Installation {}, error; }
    if same(read_key, write_key) || read_key.owner != write_key.owner { return Installation {}, blot_error::Error.invalid_state_operations; }
    if store.frames.len > 4294967293 || store.cells.len == 4294967295 { return Installation {}, blot_error::Error.provider_limit; }
    let write_head = (store.frames.len + 1) as u32;
    error = retainFrame(store, write_head, write_key.owner); if error != blot_error::Error.none { return Installation {}, error; }
    error = retainFrame(store, write_head + 1, read_key.owner); if error != blot_error::Error.none { releaseFrame(store, write_head); return Installation {}, error; }
    let cell = (store.cells.len + 1) as u32; store.cells.push(Cell { value: initial });
    store.frames.push(Frame { operation: write_key.operation, target: cell, outer: outer, kind: blot_runtime_runtime_layout::ProviderKind_state_write });
    store.frames.push(Frame { operation: read_key.operation, target: cell, outer: write_head, kind: blot_runtime_runtime_layout::ProviderKind_state_read });
    return Installation { head: store.frames.len as u32, cell: cell }, blot_error::Error.none;
}
fn lookup(store: Store&, head: Head, operation: Operation) -> blot_support::Option<Match>, blot_error::Error { lookupKey(store, head, Key { operation: operation }) }
fn lookupKey(store: Store&, head: Head, key: Key) -> blot_support::Option<Match>, blot_error::Error {
    var error = store.authorities.requireActive(key.owner); if error != blot_error::Error.none { return blot_support::none<Match>(), error; }
    error = validateHead(store, head); if error != blot_error::Error.none { return blot_support::none<Match>(), error; }
    var cursor = head;
    while cursor != empty {
        let frame = store.frames[cursor - 1];
        if frame.operation == key.operation {
            var owner: Authority = 0;
            block { let entry = store.frame_owners.get(cursor); if entry { owner = entry; } }
            if owner == key.owner { return blot_support::some(Match { frame: frame }), blot_error::Error.none; }
        }
        cursor = frame.outer;
    }
    return blot_support::none<Match>(), blot_error::Error.none;
}
fn read(store: Store&, cell: CellId) -> Value, blot_error::Error { if cell == 0 || cell > store.cells.len { return 0, blot_error::Error.invalid_scope; } return store.cells[cell - 1].value, blot_error::Error.none; }
fn write(store: Store&, cell: CellId, value: Value) -> blot_error::Error { if cell == 0 || cell > store.cells.len { return blot_error::Error.invalid_scope; } store.cells[cell - 1].value = value; return blot_error::Error.none; }
fn deinit(activation: Activation&, store: Store&) { end(activation, store); activation.scopes.clear(); }
fn deinit(store: Store&) { rewind(store, Mark { frames: 0, cells: 0 }); store.frame_owners.clear(); store.frames.clear(); store.cells.clear(); }
