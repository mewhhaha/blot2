// Pending-requirement dependencies own reusable snapshots, private to a checker.
namespace blot_check_scheme_dependencies;
import std;
import support.error;
struct LeaseRef { index: u32 = 0, generation: u64 = 0 }
struct LeaseMeta { start: i64 = 0, len: i64 = 0, generation: u64 = 0, live: bool = false }
reusable var lease_meta: LeaseMeta[>..] = [];
reusable[] var snapshot_values: u32[>..] = [];
var next_generation: u64 = 1;
struct Entry {
    roots: const u32[:] = [], variables: const u32[:] = [], rows: const u32[:] = [], valid: bool = false,
    root_lease: LeaseRef = LeaseRef {}, variable_lease: LeaseRef = LeaseRef {}, row_lease: LeaseRef = LeaseRef {},
}
fn copySnapshot(source: const u32[:]) -> const u32[:], LeaseRef, blot_error::Error {
    if source.len == 0 { return [], LeaseRef {}, blot_error::Error.none; }
    if next_generation == 0xffffffffffffffff { return [], LeaseRef {}, blot_error::Error.type_limit; }
    let generation = next_generation; next_generation += 1;
    let values = snapshot_values.alloc_slice(source.len);
    for value, index in source { values[index] = value; }
    let first: const u32& = values[0]; let start = snapshot_values.index_of(first);
    let index = lease_meta.alloc_index(LeaseMeta { start, values.len, generation, true });
    return values, LeaseRef { (index + 1) as u32, generation }, blot_error::Error.none;
}
fn releaseSnapshot(ref: LeaseRef) -> blot_error::Error {
    if ref.index == 0 { return blot_error::Error.none; }
    if ref.index > lease_meta.len { return blot_error::Error.invalid_artifact; }
    let index = ref.index - 1; let meta = lease_meta[index];
    if !meta.live || meta.generation != ref.generation { return blot_error::Error.invalid_artifact; }
    lease_meta[index].live = false;
    snapshot_values.free_slice(snapshot_values[meta.start..meta.start + meta.len]);
    lease_meta.free(index); return blot_error::Error.none;
}
fn deinit(self: Entry&) {
    // Leases are internal linear owners; stale handles indicate a compiler bug.
    assert(releaseSnapshot(self.root_lease) == blot_error::Error.none);
    assert(releaseSnapshot(self.variable_lease) == blot_error::Error.none);
    assert(releaseSnapshot(self.row_lease) == blot_error::Error.none);
    self = Entry {};
}
struct Cache { entries: Entry[>..<]&, watches: blot_check_solver_worklist::Queue, hits: u64 = 0, recomputations: u64 = 0 }
fn init(entries: Entry[>..<]&, watches: blot_check_solver_worklist::Queue) -> Cache { return Cache { entries, watches }; }
fn deinit(self: Cache&) { for &entry in self.entries { deinit(entry); } self.entries.clear(); self.watches.deinit(); }
fn truncate(self: Cache&, len: i64) {
    if len >= self.entries.len { return; }
    for &entry in self.entries[len..] { deinit(entry); }
    self.entries.pop_n(self.entries.len - len); self.watches.truncate(len);
}
fn query(self: Cache&, store: blot_check_types::Store&, index: i64, roots: const blot_check_types::Id[:]) -> const Entry?, blot_error::Error {
    while self.entries.len <= index { let error = self.watches.add(false); if error != blot_error::Error.none { return null, error; } self.entries.push(Entry {}); }
    self.watches.observe(store); let dirty = self.watches.takeIndex(index);
    if !store.has_projections && !dirty && self.entries[index].valid && self.entries[index].roots == roots { self.hits += 1; return self.entries[index], blot_error::Error.none; }
    self.recomputations += 1;
    var next = Entry {};
    let error = recompute(self, store, index, roots, next);
    if error != blot_error::Error.none { deinit(next); self.watches.requeue(index); return null, error; }
    deinit(self.entries[index]); self.entries[index] = next;
    return self.entries[index], blot_error::Error.none;
}
fn recompute(self: Cache&, store: blot_check_types::Store&, index: i64, roots: const u32[:], next: Entry&) -> blot_error::Error {
    let copied_roots, root_lease, root_error = copySnapshot(roots); if root_error != blot_error::Error.none { return root_error; }
    next.roots = copied_roots; next.root_lease = root_lease;
    var variables: u32[>..] = []; var rows: u32[>..] = [];
    for root in roots {
        let free, error = store.freeVariables(root); if error != blot_error::Error.none { return error; }
        for id in free { if !::contains(variables, id) { variables.push(id); } }
    }
    for root in roots {
        let free, error = store.freeRowVariables(root); if error != blot_error::Error.none { return error; }
        for id in free { if !::contains(rows, id) { rows.push(id); } }
    }
    let copied_variables, variable_lease, variable_error = copySnapshot(variables); if variable_error != blot_error::Error.none { return variable_error; }
    next.variables = copied_variables; next.variable_lease = variable_lease;
    let copied_rows, row_lease, row_error = copySnapshot(rows); if row_error != blot_error::Error.none { return row_error; }
    next.rows = copied_rows; next.row_lease = row_lease;
    if !store.has_projections { let error = self.watches.watch(store, index, roots, false, false); if error != blot_error::Error.none { return error; } }
    next.valid = true; return blot_error::Error.none;
}
