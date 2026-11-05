// Pending-requirement dependencies own reusable snapshots, private to a checker.
namespace blot_check_scheme_dependencies;
import check.solver_worklist;
import check.types;
import support.error;

import std;
struct LeaseRef { index: u32 = 0, generation: u64 = 0 }
struct LeaseMeta { start: i64 = 0, len: i64 = 0, generation: u64 = 0, live: bool = false }
reusable var lease_meta: LeaseMeta[>..] = [];
reusable[] var snapshot_values: u32[>..] = [];
var next_generation: u64 = 1;
struct Entry {
    roots: const u32[:] = default<const u32[:]>(), variables: const u32[:] = default<const u32[:]>(), rows: const u32[:] = default<const u32[:]>(), valid: bool = false,
    root_lease: LeaseRef = LeaseRef {..}, variable_lease: LeaseRef = LeaseRef {..}, row_lease: LeaseRef = LeaseRef {..},
}
fn copySnapshot(source: const u32[:]) -> const u32[:], LeaseRef, blot_error::Error {
    if source.len == 0 { return [], LeaseRef {..}, blot_error::Error.none; }
    if next_generation == 0xffffffffffffffff { return [], LeaseRef {..}, blot_error::Error.type_limit; }
    let generation = next_generation; next_generation += 1;
    let values = snapshot_values.alloc_slice(source.len);
    for value, index in source { values[index] = value; }
    let first: const u32&  = values[0]; let start = snapshot_values.index_of(first);
    let index = lease_meta.alloc_index(LeaseMeta { start, values.len, generation, true , ..});
    return values, LeaseRef { (index + 1) as u32, generation , ..}, blot_error::Error.none;
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
fn deinit(self_: Entry&) {
    // Leases are internal linear owners; stale handles indicate a compiler bug.
    let root_release = releaseSnapshot(self_.root_lease); assert(root_release == blot_error::Error.none);
    let variable_release = releaseSnapshot(self_.variable_lease); assert(variable_release == blot_error::Error.none);
    let row_release = releaseSnapshot(self_.row_lease); assert(row_release == blot_error::Error.none);
    self_ = Entry {..};
}
struct Cache { entries: Entry[>..<]&, watches: blot_check_solver_worklist::Queue, hits: u64 = 0, recomputations: u64 = 0 }
fn init(entries: Entry[>..<]&, watches: blot_check_solver_worklist::Queue) -> Cache { return Cache { entries, watches , ..}; }
fn deinit(self_: Cache&) { for &entry in self_.entries { deinit(entry); } self_.entries.clear(); self_.watches.deinit(); }
fn truncate(self_: Cache&, len: i64) {
    if len >= self_.entries.len { return; }
    for &entry in self_.entries[len..] { deinit(entry); }
    self_.entries.pop_n(self_.entries.len - len); self_.watches.truncate(len);
}
fn query(self_: Cache&, store: blot_check_types::Store&, index: i64, roots: const blot_check_types::Id[:]) -> const Entry?, blot_error::Error {
    while self_.entries.len <= index { let error = self_.watches.add(false); if error != blot_error::Error.none { return null, error; } self_.entries.push(Entry {..}); }
    self_.watches.observe(store); let dirty = self_.watches.takeIndex(index);
    if !store.has_projections && !dirty && self_.entries[index].valid && self_.entries[index].roots == roots { self_.hits += 1; return self_.entries[index], blot_error::Error.none; }
    self_.recomputations += 1;
    var next = Entry {..};
    let error = recompute(self_, store, index, roots, next);
    if error != blot_error::Error.none { deinit(next); self_.watches.requeue(index); return null, error; }
    deinit(self_.entries[index]); self_.entries[index] = next;
    return self_.entries[index], blot_error::Error.none;
}
fn recompute(self_: Cache&, store: blot_check_types::Store&, index: i64, roots: const u32[:], next: Entry&) -> blot_error::Error {
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
    if !store.has_projections { let error = self_.watches.watch(store, index, roots, false, false); if error != blot_error::Error.none { return error; } }
    next.valid = true; return blot_error::Error.none;
}
