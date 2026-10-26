// Private, job-local scoped inventory of active proof facts and evidence edges.
// Handles are bookkeeping only: they do not authenticate proof terms, sources,
// other jobs, or artifacts. Do not copy a job or use handles across jobs.
// All failed operations poison the job; discard it without publishing evidence.
// Only open/add/close are supported operations; the arena and helper functions
// are trusted compiler internals, not an interface for untrusted callers.
// The accounting schedule charges proof records, scope-parent/ownership links,
// and evidence prerequisite links. Scope head, fact previous, slot generation,
// free-list and dependent counters are private inventory bookkeeping, not proof
// graph edges; inspecting them does not add a semantic visit. Event 22 counts
// only active facts and evidence prerequisite edges, not lexical scope links.
// This experimental schedule is not yet the project's frozen C09 schedule.
namespace proof_scopes;
import work;

struct Handle { index: u32 = 0, generation: u32 = 0 }
struct Scope {
    generation: u32 = 0, live: bool = false, has_parent: bool = false, parent: Handle = Handle {},
    children: u32 = 0, head: Handle = Handle {}, next_free: u32 = 0
}
struct Fact {
    generation: u32 = 0, live: bool = false, scope: Handle = Handle {},
    previous: Handle = Handle {}, first: Handle = Handle {}, second: Handle = Handle {},
    dependents: u32 = 0, links: u8 = 0, next_free: u32 = 0
}
struct Entry {
    generation: u32 = 0, kind: u32 = 0, next_free: u32 = 0,
    scope: Scope = Scope {}, fact: Fact = Fact {}
}
struct Job {
    meter: work::Meter = work::Meter {}, failed: bool = false, free: u32 = 0,
    entries: Entry[>..] = []
}
// status: 0 success, 1 invalid handle/order or internal bound, 2 meter failure.
// For status 2 the unmodified work receipt specifies the precise limit/category.
struct Result { status: u32 = 0, receipt: work::Receipt = work::Receipt {}, handle: Handle = Handle {} }
fn same(a: Handle, b: Handle) -> bool { return a.index == b.index && a.generation == b.generation; }
fn none(h: Handle) -> bool { return h.index == 0 && h.generation == 0; }
fn scope_valid(job: Job&, h: Handle) -> bool {
    return h.index > 0 && h.index <= job.entries.len &&
        job.entries[h.index - 1].scope.live && job.entries[h.index - 1].scope.generation == h.generation;
}
fn fact_valid(job: Job&, h: Handle) -> bool {
    return h.index > 0 && h.index <= job.entries.len &&
        job.entries[h.index - 1].fact.live && job.entries[h.index - 1].fact.generation == h.generation;
}
fn invalid(job: Job&) -> Result { job.failed = true; return Result { status: 1 }; }
fn meter_failed(job: Job&, r: work::Receipt) -> Result {
    job.failed = true; return Result { status: 2, receipt: r };
}
// One reusable arena keeps allocations bounded by the proof-visit ceiling.
fn allocate(job: Job&) -> Result {
    if job.failed { return Result { status: 1 }; }
    var index: u32 = 0;
    var generation: u32 = 1;
    if job.free != 0 {
        index = job.free;
        if index > job.entries.len { return invalid(job); }
        let old = job.entries[index - 1];
        if old.kind != 0 || old.generation == ~(0 as u32) { return invalid(job); }
        generation = old.generation + 1;
        job.free = old.next_free;
        job.entries[index - 1] = Entry { generation: generation };
    } else {
        if job.entries.len >= 65536 { return invalid(job); }
        job.entries.push(Entry { generation: generation });
        index = job.entries.len as u32;
    }
    return Result { handle: Handle { index: index, generation: generation } };
}
// Opening an empty scope does not itself create a fact/evidence edge.
fn open(job: Job&, parent: Handle) -> Result {
    if job.failed { return Result { status: 1 }; }
    var r = work::Receipt {};
    if !none(parent) {
        r = work::charge(job.meter, 4, 20);
        if r.status != 0 { return meter_failed(job, r); }
        if !scope_valid(job, parent) { return invalid(job); }
        if job.entries[parent.index - 1].scope.children == 65536 { return invalid(job); }
    }
    r = work::charge(job.meter, 4, 20);
    if r.status != 0 { return meter_failed(job, r); }
    var scratch = Scope { live: true };
    if !none(parent) {
        r = work::charge(job.meter, 4, 20);
        if r.status != 0 { return meter_failed(job, r); }
        scratch.has_parent = true;
        scratch.parent = parent;
    }
    let allocated = allocate(job);
    if allocated.status != 0 { return allocated; }
    let index = allocated.handle.index;
    let generation = allocated.handle.generation;
    scratch.generation = generation;
    job.entries[index - 1].kind = 1;
    job.entries[index - 1].scope = scratch;
    if !none(parent) { job.entries[parent.index - 1].scope.children += 1; }
    return Result { handle: Handle { index: index, generation: generation } };
}
// A prerequisite is available only within its own or a descendant scope.
// Charge every scope examined while walking to the root.
fn ancestor(job: Job&, candidate: Handle, scope: Handle) -> Result {
    if job.failed { return Result { status: 1 }; }
    var cursor = scope;
    while !none(cursor) {
        let r = work::charge(job.meter, 4, 20);
        if r.status != 0 { return meter_failed(job, r); }
        if !scope_valid(job, cursor) { return invalid(job); }
        if same(cursor, candidate) { return Result {}; }
        if !job.entries[cursor.index - 1].scope.has_parent { return invalid(job); }
        let edge = work::charge(job.meter, 4, 20);
        if edge.status != 0 { return meter_failed(job, edge); }
        cursor = job.entries[cursor.index - 1].scope.parent;
    }
    return invalid(job);
}
// Creates one fact and zero, one or two distinct prerequisite links. It does
// not validate the proof rule: the caller must do so before publication.
fn add(job: Job&, scope: Handle, first: Handle, second: Handle) -> Result {
    if job.failed { return Result { status: 1 }; }
    var r = work::charge(job.meter, 4, 20);
    if r.status != 0 { return meter_failed(job, r); }
    if !scope_valid(job, scope) || (!none(first) && same(first, second)) ||
       (first.index == 0 && !none(first)) || (second.index == 0 && !none(second)) { return invalid(job); }
    for prior in [first, second] {
        if none(prior) { continue; }
        r = work::charge(job.meter, 4, 20);
        if r.status != 0 { return meter_failed(job, r); }
        if !fact_valid(job, prior) || job.entries[prior.index - 1].fact.dependents == 65536 { return invalid(job); }
        r = work::charge(job.meter, 4, 20);
        if r.status != 0 { return meter_failed(job, r); }
        let a = ancestor(job, job.entries[prior.index - 1].fact.scope, scope);
        if a.status != 0 { return a; }
    }
    // Materialize a private scratch fact immediately after its charge, then
    // each private prerequisite link immediately after its own charge. A
    // later failure poisons the job and never publishes this scratch record.
    r = work::charge(job.meter, 4, 22); if r.status != 0 { return meter_failed(job, r); }
    let previous = job.entries[scope.index - 1].scope.head;
    var scratch = Fact { live: true, previous: previous };
    r = work::charge(job.meter, 4, 20); if r.status != 0 { return meter_failed(job, r); }
    scratch.scope = scope;
    if !none(first) {
        r = work::charge(job.meter, 4, 22); if r.status != 0 { return meter_failed(job, r); }
        scratch.first = first; scratch.links += 1;
    }
    if !none(second) {
        r = work::charge(job.meter, 4, 22); if r.status != 0 { return meter_failed(job, r); }
        scratch.second = second; scratch.links += 2;
    }
    let allocated = allocate(job);
    if allocated.status != 0 { return allocated; }
    let index = allocated.handle.index;
    let generation = allocated.handle.generation;
    scratch.generation = generation;
    job.entries[index - 1].kind = 2;
    job.entries[index - 1].fact = scratch;
    let h = Handle { index: index, generation: generation };
    job.entries[scope.index - 1].scope.head = h;
    if !none(first) { job.entries[first.index - 1].fact.dependents += 1; }
    if !none(second) { job.entries[second.index - 1].fact.dependents += 1; }
    return Result { handle: h };
}
// Scope closure discharges facts newest-first, after all child scopes close.
// A failure is terminal even if earlier discharges already changed the meter.
fn close(job: Job&, scope: Handle) -> Result {
    if job.failed { return Result { status: 1 }; }
    var r = work::charge(job.meter, 4, 20);
    if r.status != 0 { return meter_failed(job, r); }
    if !scope_valid(job, scope) || job.entries[scope.index - 1].scope.children != 0 { return invalid(job); }
    var head = job.entries[scope.index - 1].scope.head;
    while !none(head) {
        r = work::charge(job.meter, 4, 20);
        if r.status != 0 { return meter_failed(job, r); }
        if !fact_valid(job, head) { return invalid(job); }
        if job.entries[head.index - 1].fact.dependents != 0 { return invalid(job); }
        r = work::charge(job.meter, 4, 20); if r.status != 0 { return meter_failed(job, r); }
        if !same(job.entries[head.index - 1].fact.scope, scope) { return invalid(job); }
        let links = job.entries[head.index - 1].fact.links;
        if links > 3 { return invalid(job); }
        for slot in 2 {
            if slot == 0 && (links & 1) == 0 { continue; }
            if slot == 1 && (links & 2) == 0 { continue; }
            // Charge the edge before reading its handle, then the referenced
            // proof record before inspecting it. Zero slots are not edges.
            r = work::charge(job.meter, 4, 20); if r.status != 0 { return meter_failed(job, r); }
            let prior = if slot == 0 { job.entries[head.index - 1].fact.first } else { job.entries[head.index - 1].fact.second };
            r = work::charge(job.meter, 4, 20); if r.status != 0 { return meter_failed(job, r); }
            if !fact_valid(job, prior) || job.entries[prior.index - 1].fact.dependents == 0 || job.meter.proof_edges == 0 { return invalid(job); }
            job.entries[prior.index - 1].fact.dependents -= 1;
            job.meter.proof_edges -= 1;
        }
        let previous = job.entries[head.index - 1].fact.previous;
        if job.meter.proof_edges == 0 { return invalid(job); }
        job.meter.proof_edges -= 1;
        job.entries[head.index - 1].fact.live = false;
        job.entries[head.index - 1].kind = 0;
        job.entries[head.index - 1].next_free = job.free;
        job.free = head.index;
        head = previous;
        job.entries[scope.index - 1].scope.head = head;
    }
    if job.entries[scope.index - 1].scope.has_parent {
        r = work::charge(job.meter, 4, 20); if r.status != 0 { return meter_failed(job, r); }
        let parent = job.entries[scope.index - 1].scope.parent;
        r = work::charge(job.meter, 4, 20); if r.status != 0 { return meter_failed(job, r); }
        if !scope_valid(job, parent) || job.entries[parent.index - 1].scope.children == 0 { return invalid(job); }
        job.entries[parent.index - 1].scope.children -= 1;
    }
    job.entries[scope.index - 1].scope.live = false;
    job.entries[scope.index - 1].kind = 0;
    job.entries[scope.index - 1].next_free = job.free;
    job.free = scope.index;
    return Result {};
}
