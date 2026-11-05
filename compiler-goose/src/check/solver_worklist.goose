// Ordered solver work with reverse watches on exact unresolved frontiers.
namespace blot_check_solver_worklist;
import std;
import dictionary;
import support.error;
import support.option;
let none: u32 = 0xffffffff;
let any_write: u64 = 0xffffffffffffffff;
let future_clock: u64 = 0xfffffffffffffffe;
let external: u64 = 0xfffffffffffffffd;
struct Entry { head: u32 = none, done: bool = false, required: bool, waiting: bool = false }
struct Link { key: u64, item: u32, previous: u32 = none, next: u32 = none, owner_next: u32 = none }
struct Tables { entries: Entry[>..<]&, ready: u64[>..<]&, pending: u64[>..<]&, links: Link[>..<]&, heads: dictionary<u64, u32>& }
struct Queue {
    entries: Entry[>..<]&, ready: u64[>..<]&, pending: u64[>..<]&, links: Link[>..<]&, heads: dictionary<u64, u32>&,
    free: u32 = none, remaining: i64 = 0, required: i64 = 0, waiting: i64 = 0,
    type_versions: i64 = 0, row_versions: i64 = 0, type_generation: u16 = 0,
    row_generation: u64 = 0, clock: blot_check_types::Cursor = 0,
    subscriber_visits: u64 = 0, retained_watches: u64 = 0, refreshed_watches: u64 = 0, ready_word_scans: u64 = 0,
}
fn init(t: Tables) -> Queue { return Queue { t.entries, t.ready, t.pending, t.links, t.heads }; }
fn deinit(self: Queue&) { self.entries.clear(); self.ready.clear(); self.pending.clear(); self.links.clear(); self.heads.clear(); }
fn add(self: Queue&, required: bool) -> blot_error::Error {
    let index = self.entries.len; self.entries.push(Entry { required: required });
    if index / 64 == self.ready.len { self.ready.push(0); } if index / 64 == self.pending.len { self.pending.push(0); }
    self.pending[index / 64] |= (1 as u64) << (index % 64); self.remaining += 1; if required { self.required += 1; } enqueue(self, index); return blot_error::Error.none;
}
fn enqueue(self: Queue&, index: i64) { if !self.entries[index].done { self.ready[index / 64] |= (1 as u64) << (index % 64); } }
fn requeue(self: Queue&, index: i64) { enqueue(self, index); }
fn takeIndex(self: Queue&, index: i64) -> bool { let mask = (1 as u64) << (index % 64); let dirty = self.ready[index / 64] & mask != 0; self.ready[index / 64] &= ~mask; return dirty; }
fn truncate(self: Queue&, len: i64) {
    if len >= self.entries.len { return; }
    for index in len..self.entries.len {
        clearWatches(self, index); let entry = self.entries[index];
        if !entry.done { self.remaining -= 1; if entry.required { self.required -= 1; } }
        if entry.waiting { self.waiting -= 1; }
        self.ready[index / 64] &= ~((1 as u64) << (index % 64)); self.pending[index / 64] &= ~((1 as u64) << (index % 64));
    }
    self.entries.pop_n(self.entries.len - len);
}
fn wakeAll(self: Queue&) { for index in self.ready.len { self.ready[index] |= self.pending[index]; } }
fn take(self: Queue&, start: i64) -> blot_support::Option<i64> {
    var word = start / 64; if word >= self.ready.len { return blot_support::Option<i64> { false, 0 }; }
    var bits = self.ready[word] & (any_write << (start % 64));
    while bits == 0 { self.ready_word_scans += 1; word += 1; if word >= self.ready.len { return blot_support::Option<i64> { false, 0 }; } bits = self.ready[word]; }
    let offset = ctz(bits); self.ready[word] &= ~((1 as u64) << offset); return blot_support::Option<i64> { true, word * 64 + offset };
}
fn setWaiting(self: Queue&, index: i64, waiting: bool) {
    if self.entries[index].waiting == waiting { return; } if waiting { self.waiting += 1; } else { self.waiting -= 1; } self.entries[index].waiting = waiting;
}
fn complete(self: Queue&, index: i64) {
    if self.entries[index].done { return; } setWaiting(self, index, false); clearWatches(self, index); self.entries[index].done = true;
    self.pending[index / 64] &= ~((1 as u64) << (index % 64)); self.remaining -= 1; if self.entries[index].required { self.required -= 1; } self.ready[index / 64] &= ~((1 as u64) << (index % 64));
}
fn wake(self: Queue&, key: u64) {
    var cursor = none; block { let head = self.heads.get(key); if head { cursor = head; } }
    while cursor != none { self.subscriber_visits += 1; let link = self.links[cursor]; enqueue(self, link.item); cursor = link.next; }
}
fn wakeExternal(self: Queue&) { wake(self, external); }
fn observe(self: Queue&, store: const blot_check_types::Store&) {
    let physical = self.type_generation != store.closed_generation || self.row_generation != store.effects.physical_epoch || store.closed_generation == 0xffff || store.effects.physical_epoch == any_write || self.type_versions > store.versions.len || self.row_versions > store.effects.versions.len;
    if physical { wakeAll(self); }
    else { for write in store.versions[self.type_versions..] { wake(self, (write.variable as u64) * 2); } for write in store.effects.versions[self.row_versions..] { wake(self, (write.variable as u64) * 2 + 1); } }
    if physical || self.type_versions != store.versions.len || self.row_versions != store.effects.versions.len { wake(self, any_write); }
    if self.clock != store.cursor() { wake(self, future_clock); }
    self.type_versions = store.versions.len; self.row_versions = store.effects.versions.len; self.type_generation = store.closed_generation; self.row_generation = store.effects.physical_epoch; self.clock = store.cursor();
}
fn clearWatches(self: Queue&, index: i64) {
    var cursor = self.entries[index].head; self.entries[index].head = none;
    while cursor != none {
        let link = self.links[cursor];
        if link.previous == none {
            if link.next == none { self.heads.remove(link.key); } else { let head = self.heads.get(link.key); assert(head); head = link.next; }
        } else { self.links[link.previous].next = link.next; }
        if link.next != none { self.links[link.next].previous = link.previous; }
        self.links[cursor].next = self.free; self.free = cursor; cursor = link.owner_next;
    }
}
fn watchKey(self: Queue&, index: i64, key: u64) -> blot_error::Error {
    var prior = none; block { let head = self.heads.get(key); if head { prior = head; } }
    var link: u32 = 0;
    if self.free != none { link = self.free; self.free = self.links[link].next; }
    else { link = self.links.len as u32; self.links.push(default<Link>()); }
    self.links[link] = Link { key, index as u32, next: prior, owner_next: self.entries[index].head };
    if prior != none { self.links[prior].previous = link; } self.heads.insert(key, link); self.entries[index].head = link; return blot_error::Error.none;
}
fn watch(self: Queue&, store: blot_check_types::Store&, index: i64, roots: const blot_check_types::Id[:], external_input: bool, broad: bool) -> blot_error::Error {
    var frontier = Frontier {};
    if !broad { let error = collect(frontier, store, roots); if error != blot_error::Error.none { if error == blot_error::Error.out_of_memory { return error; } frontier.overflow = true; } }
    self.refreshed_watches += 1; let fallback = broad || frontier.overflow;
    if sameWatches(self, index, frontier, external_input, fallback) { self.retained_watches += 1; return blot_error::Error.none; }
    clearWatches(self, index);
    if fallback { let error = watchKey(self, index, any_write); if error != blot_error::Error.none { return error; } }
    else { for key in frontier.keys[..frontier.len] { let error = watchKey(self, index, key); if error != blot_error::Error.none { return error; } } }
    if external_input { return watchKey(self, index, external); } return blot_error::Error.none;
}
fn sameWatches(self: const Queue&, index: i64, frontier: const Frontier&, external_input: bool, broad: bool) -> bool {
    var cursor = self.entries[index].head;
    if external_input { if cursor == none || self.links[cursor].key != external { return false; } cursor = self.links[cursor].owner_next; }
    if broad { if cursor == none || self.links[cursor].key != any_write { return false; } cursor = self.links[cursor].owner_next; }
    else { var remaining = frontier.len; while remaining != 0 { remaining -= 1; if cursor == none || self.links[cursor].key != frontier.keys[remaining] { return false; } cursor = self.links[cursor].owner_next; } }
    return cursor == none;
}
struct Frontier { keys: u64[64] = [0; 64], len: i64 = 0, overflow: bool = false }
fn add(self: Frontier&, key: u64) { for old in self.keys[..self.len] { if old == key { return; } } if self.len == self.keys.len { self.overflow = true; return; } self.keys[self.len] = key; self.len += 1; }
fn collect(self: Frontier&, store: blot_check_types::Store&, roots: const blot_check_types::Id[:]) -> blot_error::Error {
    var stack: blot_check_types::Id[256] = [0; 256]; var seen: blot_check_types::Id[64] = [0; 64];
    if roots.len > stack.len { self.overflow = true; return blot_error::Error.none; }
    for root, index in roots { stack[index] = root; } var len = roots.len; var visited: i64 = 0;
    while len != 0 && !self.overflow {
        len -= 1; let root = stack[len]; if root == 0 { continue; }
        if !store.has_projections { let slot = (root * (0x9e3779b9 as u32)) >> 26; if seen[slot] == root { continue; } seen[slot] = root; }
        if visited == 1024 { self.overflow = true; return blot_error::Error.none; } visited += 1;
        let resolved, error = store.resolve(root, 0); if error != blot_error::Error.none { return error; } let node = store.node(resolved);
        if node.tag == blot_check_types::Tag.variable { add(self, (node.a as u64) * 2); if node.b > store.cursor() { add(self, future_clock); } continue; }
        if node.tag == blot_check_types::Tag.function || node.tag == blot_check_types::Tag.provider {
            let row_id, error = store.resolveEffects(node.c, 0); if error != blot_error::Error.none { return error; } let row = store.row(row_id);
            match row.tail { variable v => { add(self, (v.value as u64) * 2 + 1); }, _ => {}, }
            for label in store.effects.list(row.labels) {
                let arguments = store.operationArguments(label); if arguments.len > stack.len - len { self.overflow = true; return blot_error::Error.none; }
                for argument in arguments { stack[len] = argument; len += 1; }
                let instance = store.operation(label).instance; if instance.unit == 0 && instance.decl != 0 { if len == stack.len { self.overflow = true; return blot_error::Error.none; } stack[len] = instance.decl; len += 1; }
            }
        }
        var local: blot_check_types::Id[3] = [0; 3]; var local_count: i64 = 0; var children: const blot_check_types::Id[:] = [];
        match node.tag {
            function => { local = [node.a, node.b, 0]; local_count = 2; }, state_provider => { local = [node.a, node.b, node.c]; local_count = 3; },
            usage => { local = [node.a, node.c, 0]; local_count = 1; if node.c != 0 { local_count = 2; } },
            scoped => { local = [node.a, node.c, 0]; local_count = 1; if node.b == 0 { local_count = 2; } },
            forall, existential => {
                if len == stack.len { self.overflow = true; return blot_error::Error.none; } stack[len] = node.a; len += 1;
                let selected, error = store.resolve(root, 0); if error != blot_error::Error.none { return error; }
                for goal in store.quantifierGoals(selected) { for child in [goal.ty, goal.other, goal.result, goal.signature] { if child != 0 { if len == stack.len { self.overflow = true; return blot_error::Error.none; } stack[len] = child; len += 1; } } }
            },
            array, list, cursor, resolver, provider => { local[0] = node.a; local_count = 1; },
            product => { children = store.list(blot_check_types::List { node.a, node.b }); },
            nominal, projection, instance_selection => { children = store.nominalArguments(node); },
            record => { if node.b > stack.len - len { self.overflow = true; return blot_error::Error.none; } for field in node.b { stack[len] = store.recordField(node, field).ty; len += 1; } }, _ => {},
        }
        if local_count + children.len > stack.len - len { self.overflow = true; return blot_error::Error.none; }
        for child in local[..local_count] { stack[len] = child; len += 1; } for child in children { stack[len] = child; len += 1; }
    }
    return blot_error::Error.none;
}
