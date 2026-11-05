// Ordered solver work with reverse watches on exact unresolved frontiers.
namespace blot_check_solver_worklist;
import std;
import dictionary;
import check.types;
import support.pooled_buffer;
import support.pooled_map;
import support.error;
import support.option;
let none: u32 = 0xffffffff;
let any_write: u64 = 0xffffffffffffffff;
let future_clock: u64 = 0xfffffffffffffffe;
let external: u64 = 0xfffffffffffffffd;
struct Entry { head: u32 = none, done: bool = false, required: bool, waiting: bool = false }
struct Link { key: u64, item: u32, previous: u32 = none, next: u32 = none, owner_next: u32 = none }
type Error=blot_error::Error;
struct EntryBuffer { storage: Entry[:]=[],items: Entry[:]=[],len: i64=0,failure: Error=Error.none }
reusable[] var pool_EntryBuffer: Entry[>..]=[];
fn ensure(self: EntryBuffer&,minimum: i64) -> Error { if self.failure!=Error.none { return self.failure; } let error=blot_support_pooled_buffer::ensure(self,minimum,pool_EntryBuffer); if error!=Error.none { self.failure=error; } return error; }
fn push(self: EntryBuffer&,value: Entry) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::push(self,value,pool_EntryBuffer); self.len=self.items.len; }
fn append(self: EntryBuffer&,values: const Entry[:]) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::append(self,values,pool_EntryBuffer); self.len=self.items.len; }
fn resize(self: EntryBuffer&,length: i64) { blot_support_pooled_buffer::resize(self,length); self.len=length; }
fn resize(self: EntryBuffer&,length: i64,value: Entry) { if length<=self.len { resize(self,length); return; } let error=ensure(self,length); if error!=Error.none { return; } for index in self.len..length { self.storage[index]=value; } self.items=self.storage[..length]; self.len=length; }
fn clear(self: EntryBuffer&) { blot_support_pooled_buffer::clear(self); self.len=0; self.failure=Error.none; }
fn deinit(self: EntryBuffer&) { blot_support_pooled_buffer::deinit(self,pool_EntryBuffer); self.len=0; self.failure=Error.none; }
struct WordBuffer { storage: u64[:]=[],items: u64[:]=[],len: i64=0,failure: Error=Error.none }
reusable[] var pool_WordBuffer: u64[>..]=[];
fn ensure(self: WordBuffer&,minimum: i64) -> Error { if self.failure!=Error.none { return self.failure; } let error=blot_support_pooled_buffer::ensure(self,minimum,pool_WordBuffer); if error!=Error.none { self.failure=error; } return error; }
fn push(self: WordBuffer&,value: u64) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::push(self,value,pool_WordBuffer); self.len=self.items.len; }
fn append(self: WordBuffer&,values: const u64[:]) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::append(self,values,pool_WordBuffer); self.len=self.items.len; }
fn resize(self: WordBuffer&,length: i64) { blot_support_pooled_buffer::resize(self,length); self.len=length; }
fn resize(self: WordBuffer&,length: i64,value: u64) { if length<=self.len { resize(self,length); return; } let error=ensure(self,length); if error!=Error.none { return; } for index in self.len..length { self.storage[index]=value; } self.items=self.storage[..length]; self.len=length; }
fn clear(self: WordBuffer&) { blot_support_pooled_buffer::clear(self); self.len=0; self.failure=Error.none; }
fn deinit(self: WordBuffer&) { blot_support_pooled_buffer::deinit(self,pool_WordBuffer); self.len=0; self.failure=Error.none; }
struct LinkBuffer { storage: Link[:]=[],items: Link[:]=[],len: i64=0,failure: Error=Error.none }
reusable[] var pool_LinkBuffer: Link[>..]=[];
fn ensure(self: LinkBuffer&,minimum: i64) -> Error { if self.failure!=Error.none { return self.failure; } let error=blot_support_pooled_buffer::ensure(self,minimum,pool_LinkBuffer); if error!=Error.none { self.failure=error; } return error; }
fn push(self: LinkBuffer&,value: Link) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::push(self,value,pool_LinkBuffer); self.len=self.items.len; }
fn append(self: LinkBuffer&,values: const Link[:]) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::append(self,values,pool_LinkBuffer); self.len=self.items.len; }
fn resize(self: LinkBuffer&,length: i64) { blot_support_pooled_buffer::resize(self,length); self.len=length; }
fn resize(self: LinkBuffer&,length: i64,value: Link) { if length<=self.len { resize(self,length); return; } let error=ensure(self,length); if error!=Error.none { return; } for index in self.len..length { self.storage[index]=value; } self.items=self.storage[..length]; self.len=length; }
fn clear(self: LinkBuffer&) { blot_support_pooled_buffer::clear(self); self.len=0; self.failure=Error.none; }
fn deinit(self: LinkBuffer&) { blot_support_pooled_buffer::deinit(self,pool_LinkBuffer); self.len=0; self.failure=Error.none; }
type Heads=blot_support_pooled_map::Map<u64,u32>;
reusable[] var head_slots: dictionary_slot<u64,u32>[>..]=[];
fn get(self: const Heads&,key: u64) -> u32? { return blot_support_pooled_map::get(self,key); }
fn insert(self: Heads&,key: u64,value: u32) { blot_support_pooled_map::insert(self,key,value,head_slots); }
fn remove(self: Heads&,key: u64) -> bool { return blot_support_pooled_map::remove(self,key); }
fn clear(self: Heads&) { blot_support_pooled_map::clear(self); }
fn release(self: Heads&) { blot_support_pooled_map::deinit(self,head_slots); }
fn restore(self: Heads&,slots: const dictionary_slot<u64,u32>[:],count: i64) { release(self); self.count=count; if slots.len!=0 { self.slots=head_slots.alloc_slice(slots.len); for slot,index in slots { self.slots[index]=slot; } } }
struct State { entries: EntryBuffer=EntryBuffer {},ready: WordBuffer=WordBuffer {},pending: WordBuffer=WordBuffer {},links: LinkBuffer=LinkBuffer {},heads: Heads=Heads {},free: u32=none,remaining: i64=0,required: i64=0,waiting: i64=0,type_versions: i64=0,row_versions: i64=0,type_generation: u16=0,row_generation: u64=0,clock: blot_check_types::Cursor=0,subscriber_visits: u64=0,retained_watches: u64=0,refreshed_watches: u64=0,ready_word_scans: u64=0,lease_generation: u64=0,live: bool=false }
reusable var states: State[>..]=[];
var inactive: State=State {};
var next_generation: u64=1;
struct Queue { entries: EntryBuffer&=inactive.entries,ready: WordBuffer&=inactive.ready,pending: WordBuffer&=inactive.pending,links: LinkBuffer&=inactive.links,heads: Heads&=inactive.heads,free: u32&=inactive.free,remaining: i64&=inactive.remaining,required: i64&=inactive.required,waiting: i64&=inactive.waiting,type_versions: i64&=inactive.type_versions,row_versions: i64&=inactive.row_versions,type_generation: u16&=inactive.type_generation,row_generation: u64&=inactive.row_generation,clock: blot_check_types::Cursor&=inactive.clock,subscriber_visits: u64&=inactive.subscriber_visits,retained_watches: u64&=inactive.retained_watches,refreshed_watches: u64&=inactive.refreshed_watches,ready_word_scans: u64&=inactive.ready_word_scans,lease: u32=0,lease_generation: u64=0 }
fn initPooled() -> Queue,Error { if next_generation==0xffffffffffffffff||states.len>=0xffffffff { return Queue {},Error.out_of_memory; } let generation=next_generation; next_generation++; let index=states.alloc_index(State {lease_generation:generation,live:true}); let state: State&=states[index]; return Queue {entries:state.entries,ready:state.ready,pending:state.pending,links:state.links,heads:state.heads,free:state.free,remaining:state.remaining,required:state.required,waiting:state.waiting,type_versions:state.type_versions,row_versions:state.row_versions,type_generation:state.type_generation,row_generation:state.row_generation,clock:state.clock,subscriber_visits:state.subscriber_visits,retained_watches:state.retained_watches,refreshed_watches:state.refreshed_watches,ready_word_scans:state.ready_word_scans,lease:(index+1) as u32,lease_generation:generation},Error.none; }
fn valid(self: Queue) -> bool { return self.lease!=0&&self.lease-1<states.len&&states[self.lease-1].live&&states[self.lease-1].lease_generation==self.lease_generation; }
fn deinit(self: Queue&) { if self.lease==0 { return; } assert(valid(self)); self.entries.deinit(); self.ready.deinit(); self.pending.deinit(); self.links.deinit(); release(self.heads); let index=self.lease-1; states[index].live=false; states.free(index); self=Queue {}; }
fn add(self: Queue, required: bool) -> blot_error::Error {
    let index = self.entries.len; self.entries.push(Entry { required: required });
    if index / 64 == self.ready.len { self.ready.push(0); } if index / 64 == self.pending.len { self.pending.push(0); }
    self.pending.items[index / 64] |= (1 as u64) << (index % 64); self.remaining += 1; if required { self.required += 1; } enqueue(self, index); return blot_error::Error.none;
}
fn enqueue(self: Queue, index: i64) { if !self.entries.items[index].done { self.ready.items[index / 64] |= (1 as u64) << (index % 64); } }
fn requeue(self: Queue, index: i64) { enqueue(self, index); }
fn takeIndex(self: Queue, index: i64) -> bool { let mask = (1 as u64) << (index % 64); let dirty = self.ready.items[index / 64] & mask != 0; self.ready.items[index / 64] &= ~mask; return dirty; }
fn truncate(self: Queue, len: i64) {
    if len >= self.entries.len { return; }
    for index in len..self.entries.len {
        clearWatches(self, index); let entry = self.entries.items[index];
        if !entry.done { self.remaining -= 1; if entry.required { self.required -= 1; } }
        if entry.waiting { self.waiting -= 1; }
        self.ready.items[index / 64] &= ~((1 as u64) << (index % 64)); self.pending.items[index / 64] &= ~((1 as u64) << (index % 64));
    }
    self.entries.resize(len);
}
fn wakeAll(self: Queue) { for index in self.ready.len { self.ready.items[index] |= self.pending.items[index]; } }
fn take(self: Queue, start: i64) -> blot_support::Option<i64> {
    var word = start / 64; if word >= self.ready.len { return blot_support::Option<i64> { false, 0 }; }
    var bits = self.ready.items[word] & (any_write << (start % 64));
    while bits == 0 { self.ready_word_scans += 1; word += 1; if word >= self.ready.len { return blot_support::Option<i64> { false, 0 }; } bits = self.ready.items[word]; }
    let offset = ctz(bits); self.ready.items[word] &= ~((1 as u64) << offset); return blot_support::Option<i64> { true, word * 64 + offset };
}
fn setWaiting(self: Queue, index: i64, waiting: bool) {
    if self.entries.items[index].waiting == waiting { return; } if waiting { self.waiting += 1; } else { self.waiting -= 1; } self.entries.items[index].waiting = waiting;
}
fn complete(self: Queue, index: i64) {
    if self.entries.items[index].done { return; } setWaiting(self, index, false); clearWatches(self, index); self.entries.items[index].done = true;
    self.pending.items[index / 64] &= ~((1 as u64) << (index % 64)); self.remaining -= 1; if self.entries.items[index].required { self.required -= 1; } self.ready.items[index / 64] &= ~((1 as u64) << (index % 64));
}
fn wake(self: Queue, key: u64) {
    var cursor = none; block { let head = self.heads.get(key); if head { cursor = head; } }
    while cursor != none { self.subscriber_visits += 1; let link = self.links.items[cursor]; enqueue(self, link.item); cursor = link.next; }
}
fn wakeExternal(self: Queue) { wake(self, external); }
fn observe(self: Queue, store: const blot_check_types::Store&) {
    let physical = self.type_generation != store.closed_generation || self.row_generation != store.effects.physical_epoch || store.closed_generation == 0xffff || store.effects.physical_epoch == any_write || self.type_versions > store.versions.len || self.row_versions > store.effects.versions.len;
    if physical { wakeAll(self); }
    else { for write in store.versions[self.type_versions..] { wake(self, (write.variable as u64) * 2); } for write in store.effects.versions[self.row_versions..] { wake(self, (write.variable as u64) * 2 + 1); } }
    if physical || self.type_versions != store.versions.len || self.row_versions != store.effects.versions.len { wake(self, any_write); }
    if self.clock != store.cursor() { wake(self, future_clock); }
    self.type_versions = store.versions.len; self.row_versions = store.effects.versions.len; self.type_generation = store.closed_generation; self.row_generation = store.effects.physical_epoch; self.clock = store.cursor();
}
fn clearWatches(self: Queue, index: i64) {
    var cursor = self.entries.items[index].head; self.entries.items[index].head = none;
    while cursor != none {
        let link = self.links.items[cursor];
        if link.previous == none {
            if link.next == none { self.heads.remove(link.key); } else { let head .= self.heads.get(link.key); assert(head); head = link.next; }
        } else { self.links.items[link.previous].next = link.next; }
        if link.next != none { self.links.items[link.next].previous = link.previous; }
        self.links.items[cursor].next = self.free; self.free = cursor; cursor = link.owner_next;
    }
}
fn watchKey(self: Queue, index: i64, key: u64) -> blot_error::Error {
    var prior = none; block { let head = self.heads.get(key); if head { prior = head; } }
    var link: u32 = 0;
    if self.free != none { link = self.free; self.free = self.links.items[link].next; }
    else { link = self.links.len as u32; self.links.push(default<Link>()); }
    self.links.items[link] = Link { key, index as u32, next: prior, owner_next: self.entries.items[index].head };
    if prior != none { self.links.items[prior].previous = link; } self.heads.insert(key, link); self.entries.items[index].head = link; return blot_error::Error.none;
}
fn watch(self: Queue, store: blot_check_types::Store&, index: i64, roots: const blot_check_types::Id[:], external_input: bool, broad: bool) -> blot_error::Error {
    var frontier = Frontier {};
    if !broad { let error = collect(frontier, store, roots); if error != blot_error::Error.none { if error == blot_error::Error.out_of_memory { return error; } frontier.overflow = true; } }
    self.refreshed_watches += 1; let fallback = broad || frontier.overflow;
    if sameWatches(self, index, frontier, external_input, fallback) { self.retained_watches += 1; return blot_error::Error.none; }
    clearWatches(self, index);
    if fallback { let error = watchKey(self, index, any_write); if error != blot_error::Error.none { return error; } }
    else { for key in frontier.keys[..frontier.len] { let error = watchKey(self, index, key); if error != blot_error::Error.none { return error; } } }
    if external_input { return watchKey(self, index, external); } return blot_error::Error.none;
}
fn sameWatches(self: Queue, index: i64, frontier: const Frontier&, external_input: bool, broad: bool) -> bool {
    var cursor = self.entries.items[index].head;
    if external_input { if cursor == none || self.links.items[cursor].key != external { return false; } cursor = self.links.items[cursor].owner_next; }
    if broad { if cursor == none || self.links.items[cursor].key != any_write { return false; } cursor = self.links.items[cursor].owner_next; }
    else { var remaining = frontier.len; while remaining != 0 { remaining -= 1; if cursor == none || self.links.items[cursor].key != frontier.keys[remaining] { return false; } cursor = self.links.items[cursor].owner_next; } }
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
