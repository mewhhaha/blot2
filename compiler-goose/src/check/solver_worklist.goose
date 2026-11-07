// Ordered solver work with reverse watches on exact unresolved frontiers.
namespace blot_check_solver_worklist;
import check.types;
import support.error;
import support.option;
import support.pooled_buffer;
import support.pooled_map;

import std;
import dictionary;
let none: u32 = 0xffffffff;
let any_write: u64 = 0xffffffffffffffff;
let future_clock: u64 = 0xfffffffffffffffe;
let external: u64 = 0xfffffffffffffffd;
struct Entry { head: u32 = none, done: bool = false, required: bool, waiting: bool = false }
struct Link { key: u64, item: u32, previous: u32 = none, next: u32 = none, owner_next: u32 = none }
type Error=blot_error::Error;
struct EntryBuffer { storage: Entry[:]=default<Entry[:]>(),items: Entry[:]=default<Entry[:]>(),len: i64=0,failure: Error=blot_error::Error.none }
reusable[] var pool_EntryBuffer: Entry[>..]=[];
fn ensure(self_: EntryBuffer&,minimum: i64) -> Error { if self_.failure!=blot_error::Error.none { return self_.failure; } let error=blot_support_pooled_buffer::ensure(self_,minimum,pool_EntryBuffer); if error!=blot_error::Error.none { self_.failure=error; } return error; }
fn push(self_: EntryBuffer&,value: Entry) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::push(self_,value,pool_EntryBuffer); self_.len=self_.items.len; }
fn append(self_: EntryBuffer&,values: const Entry[:]) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::append(self_,values,pool_EntryBuffer); self_.len=self_.items.len; }
fn resize(self_: EntryBuffer&,length: i64) { blot_support_pooled_buffer::resize(self_,length); self_.len=length; }
fn resize(self_: EntryBuffer&,length: i64,value: Entry) { if length<=self_.len { resize(self_,length); return; } let error=ensure(self_,length); if error!=blot_error::Error.none { return; } for index in self_.len..length { self_.storage[index]=value; } self_.items=self_.storage[..length]; self_.len=length; }
fn clear(self_: EntryBuffer&) { blot_support_pooled_buffer::clear(self_); self_.len=0; self_.failure=blot_error::Error.none; }
fn deinit(self_: EntryBuffer&) { blot_support_pooled_buffer::deinit(self_,pool_EntryBuffer); self_.len=0; self_.failure=blot_error::Error.none; }
struct WordBuffer { storage: u64[:]=default<u64[:]>(),items: u64[:]=default<u64[:]>(),len: i64=0,failure: Error=blot_error::Error.none }
reusable[] var pool_WordBuffer: u64[>..]=[];
fn ensure(self_: WordBuffer&,minimum: i64) -> Error { if self_.failure!=blot_error::Error.none { return self_.failure; } let error=blot_support_pooled_buffer::ensure(self_,minimum,pool_WordBuffer); if error!=blot_error::Error.none { self_.failure=error; } return error; }
fn push(self_: WordBuffer&,value: u64) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::push(self_,value,pool_WordBuffer); self_.len=self_.items.len; }
fn append(self_: WordBuffer&,values: const u64[:]) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::append(self_,values,pool_WordBuffer); self_.len=self_.items.len; }
fn resize(self_: WordBuffer&,length: i64) { blot_support_pooled_buffer::resize(self_,length); self_.len=length; }
fn resize(self_: WordBuffer&,length: i64,value: u64) { if length<=self_.len { resize(self_,length); return; } let error=ensure(self_,length); if error!=blot_error::Error.none { return; } for index in self_.len..length { self_.storage[index]=value; } self_.items=self_.storage[..length]; self_.len=length; }
fn clear(self_: WordBuffer&) { blot_support_pooled_buffer::clear(self_); self_.len=0; self_.failure=blot_error::Error.none; }
fn deinit(self_: WordBuffer&) { blot_support_pooled_buffer::deinit(self_,pool_WordBuffer); self_.len=0; self_.failure=blot_error::Error.none; }
struct LinkBuffer { storage: Link[:]=default<Link[:]>(),items: Link[:]=default<Link[:]>(),len: i64=0,failure: Error=blot_error::Error.none }
reusable[] var pool_LinkBuffer: Link[>..]=[];
fn ensure(self_: LinkBuffer&,minimum: i64) -> Error { if self_.failure!=blot_error::Error.none { return self_.failure; } let error=blot_support_pooled_buffer::ensure(self_,minimum,pool_LinkBuffer); if error!=blot_error::Error.none { self_.failure=error; } return error; }
fn push(self_: LinkBuffer&,value: Link) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::push(self_,value,pool_LinkBuffer); self_.len=self_.items.len; }
fn append(self_: LinkBuffer&,values: const Link[:]) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::append(self_,values,pool_LinkBuffer); self_.len=self_.items.len; }
fn resize(self_: LinkBuffer&,length: i64) { blot_support_pooled_buffer::resize(self_,length); self_.len=length; }
fn resize(self_: LinkBuffer&,length: i64,value: Link) { if length<=self_.len { resize(self_,length); return; } let error=ensure(self_,length); if error!=blot_error::Error.none { return; } for index in self_.len..length { self_.storage[index]=value; } self_.items=self_.storage[..length]; self_.len=length; }
fn clear(self_: LinkBuffer&) { blot_support_pooled_buffer::clear(self_); self_.len=0; self_.failure=blot_error::Error.none; }
fn deinit(self_: LinkBuffer&) { blot_support_pooled_buffer::deinit(self_,pool_LinkBuffer); self_.len=0; self_.failure=blot_error::Error.none; }
struct Heads { count: i64=0,slots: dictionary_slot<u64,u32>[:]=default<dictionary_slot<u64,u32>[:]>() }
reusable[] var head_slots: dictionary_slot<u64,u32>[>..]=[];
fn get(self_: const Heads&,key: u64) -> u32? { let view=blot_support_pooled_map::Map<u64,u32> {count:self_.count,slots:self_.slots}; return blot_support_pooled_map::get(view,key); }
fn insert(self_: Heads&,key: u64,value: u32) { var view=blot_support_pooled_map::Map<u64,u32> {count:self_.count,slots:self_.slots}; blot_support_pooled_map::insert(view,key,value,head_slots); self_.count=view.count; self_.slots=view.slots; }
fn remove(self_: Heads&,key: u64) -> bool { var view=blot_support_pooled_map::Map<u64,u32> {count:self_.count,slots:self_.slots}; let removed=blot_support_pooled_map::remove(view,key); self_.count=view.count; self_.slots=view.slots; return removed; }
fn clear(self_: Heads&) { for &slot in self_.slots { slot.tag=0; } self_.count=0; }
fn release(self_: Heads&) { if self_.slots.len!=0 { head_slots.free_slice(self_.slots); } self_.slots=default<dictionary_slot<u64,u32>[:]>(); self_.count=0; }
fn restore(self_: Heads&,slots: const dictionary_slot<u64,u32>[:],count: i64) { release(self_); self_.count=count; if slots.len!=0 { self_.slots=head_slots.alloc_slice(slots.len); for slot,index in slots { self_.slots[index]=slot; } } }
struct State { entries: EntryBuffer=EntryBuffer {},ready: WordBuffer=WordBuffer {},pending: WordBuffer=WordBuffer {},links: LinkBuffer=LinkBuffer {},heads: Heads=Heads {},free: u32=none,remaining: i64=0,required: i64=0,waiting: i64=0,type_versions: i64=0,row_versions: i64=0,type_generation: u16=0,row_generation: u64=0,clock: blot_check_types::Cursor=0,subscriber_visits: u64=0,retained_watches: u64=0,refreshed_watches: u64=0,ready_word_scans: u64=0,lease_generation: u64=0,live: bool=false }
reusable var states: State[>..]=[];
var inactive: State=State {};
var next_generation: u64=1;
struct Queue { entries: EntryBuffer& =inactive.entries,ready: WordBuffer& =inactive.ready,pending: WordBuffer& =inactive.pending,links: LinkBuffer& =inactive.links,heads: Heads& =inactive.heads,free: u32& =inactive.free,remaining: i64& =inactive.remaining,required: i64& =inactive.required,waiting: i64& =inactive.waiting,type_versions: i64& =inactive.type_versions,row_versions: i64& =inactive.row_versions,type_generation: u16& =inactive.type_generation,row_generation: u64& =inactive.row_generation,clock: blot_check_types::Cursor& =inactive.clock,subscriber_visits: u64& =inactive.subscriber_visits,retained_watches: u64& =inactive.retained_watches,refreshed_watches: u64& =inactive.refreshed_watches,ready_word_scans: u64& =inactive.ready_word_scans,lease: u32=0,lease_generation: u64=0 }
fn initPooled() -> Queue,Error { if next_generation==0xffffffffffffffff||states.len>=0xffffffff { return Queue {},blot_error::Error.out_of_memory; } let generation=next_generation; next_generation++; let index=states.alloc_index(State {lease_generation:generation,live:true}); let state: State& =states[index]; return Queue {entries:state.entries,ready:state.ready,pending:state.pending,links:state.links,heads:state.heads,free:state.free,remaining:state.remaining,required:state.required,waiting:state.waiting,type_versions:state.type_versions,row_versions:state.row_versions,type_generation:state.type_generation,row_generation:state.row_generation,clock:state.clock,subscriber_visits:state.subscriber_visits,retained_watches:state.retained_watches,refreshed_watches:state.refreshed_watches,ready_word_scans:state.ready_word_scans,lease:(index+1) as u32,lease_generation:generation},blot_error::Error.none; }
fn valid(self_: Queue) -> bool { return self_.lease!=0&&self_.lease-1<states.len&&states[self_.lease-1].live&&states[self_.lease-1].lease_generation==self_.lease_generation; }
fn deinit(self_: Queue&) { if self_.lease==0 { return; } assert(valid(self_)); self_.entries.deinit(); self_.ready.deinit(); self_.pending.deinit(); self_.links.deinit(); release(self_.heads); let index=self_.lease-1; states[index].live=false; states.free(index); self_=Queue {}; }
fn add(self_: Queue, required: bool) -> blot_error::Error {
    let index = self_.entries.len; self_.entries.push(Entry { required: required });
    if index / 64 == self_.ready.len { self_.ready.push(0); } if index / 64 == self_.pending.len { self_.pending.push(0); }
    self_.pending.items[index / 64] |= (1 as u64) << (index % 64); self_.remaining += 1; if required { self_.required += 1; } enqueue(self_, index); return blot_error::Error.none;
}
fn enqueue(self_: Queue, index: i64) { if !self_.entries.items[index].done { self_.ready.items[index / 64] |= (1 as u64) << (index % 64); } }
fn requeue(self_: Queue, index: i64) { enqueue(self_, index); }
fn takeIndex(self_: Queue, index: i64) -> bool { let mask = (1 as u64) << (index % 64); let dirty = self_.ready.items[index / 64] & mask != 0; self_.ready.items[index / 64] &= ~mask; return dirty; }
fn truncate(self_: Queue, len: i64) {
    if len >= self_.entries.len { return; }
    for index in len..self_.entries.len {
        clearWatches(self_, index); let entry = self_.entries.items[index];
        if !entry.done { self_.remaining -= 1; if entry.required { self_.required -= 1; } }
        if entry.waiting { self_.waiting -= 1; }
        self_.ready.items[index / 64] &= ~((1 as u64) << (index % 64)); self_.pending.items[index / 64] &= ~((1 as u64) << (index % 64));
    }
    self_.entries.resize(len);
}
fn wakeAll(self_: Queue) { for index in self_.ready.len { self_.ready.items[index] |= self_.pending.items[index]; } }
fn take(self_: Queue, start: i64) -> blot_support::Option<i64> {
    var word = start / 64; if word >= self_.ready.len { return blot_support::Option<i64> { false, 0 }; }
    var bits = self_.ready.items[word] & (any_write << (start % 64));
    while bits == 0 { self_.ready_word_scans += 1; word += 1; if word >= self_.ready.len { return blot_support::Option<i64> { false, 0 }; } bits = self_.ready.items[word]; }
    let offset = ctz(bits); self_.ready.items[word] &= ~((1 as u64) << offset); return blot_support::Option<i64> { true, word * 64 + offset };
}
fn setWaiting(self_: Queue, index: i64, waiting: bool) {
    if self_.entries.items[index].waiting == waiting { return; } if waiting { self_.waiting += 1; } else { self_.waiting -= 1; } self_.entries.items[index].waiting = waiting;
}
fn complete(self_: Queue, index: i64) {
    if self_.entries.items[index].done { return; } setWaiting(self_, index, false); clearWatches(self_, index); self_.entries.items[index].done = true;
    self_.pending.items[index / 64] &= ~((1 as u64) << (index % 64)); self_.remaining -= 1; if self_.entries.items[index].required { self_.required -= 1; } self_.ready.items[index / 64] &= ~((1 as u64) << (index % 64));
}
fn wake(self_: Queue, key: u64) {
    var cursor = none; block { let head = self_.heads.get(key); if head { cursor = head; } }
    while cursor != none { self_.subscriber_visits += 1; let link = self_.links.items[cursor]; enqueue(self_, link.item); cursor = link.next; }
}
fn wakeExternal(self_: Queue) { wake(self_, external); }
fn observe(self_: Queue, store: const blot_check_types::Store&) {
    let physical = self_.type_generation != store.closed_generation || self_.row_generation != store.effects.physical_epoch || store.closed_generation == 0xffff || store.effects.physical_epoch == any_write || self_.type_versions > store.versions.len || self_.row_versions > store.effects.versions.len;
    if physical { wakeAll(self_); }
    else { for write in store.versions.items[self_.type_versions..] { wake(self_, (write.variable as u64) * 2); } for write in store.effects.versions.items[self_.row_versions..] { wake(self_, (write.variable as u64) * 2 + 1); } }
    if physical || self_.type_versions != store.versions.len || self_.row_versions != store.effects.versions.len { wake(self_, any_write); }
    if self_.clock != store.cursor() { wake(self_, future_clock); }
    self_.type_versions = store.versions.len; self_.row_versions = store.effects.versions.len; self_.type_generation = store.closed_generation; self_.row_generation = store.effects.physical_epoch; self_.clock = store.cursor();
}
fn clearWatches(self_: Queue, index: i64) {
    var cursor = self_.entries.items[index].head; self_.entries.items[index].head = none;
    while cursor != none {
        let link = self_.links.items[cursor];
        if link.previous == none {
            if link.next == none { self_.heads.remove(link.key); } else { let head .= self_.heads.get(link.key); assert(head); head = link.next; }
        } else { self_.links.items[link.previous].next = link.next; }
        if link.next != none { self_.links.items[link.next].previous = link.previous; }
        self_.links.items[cursor].next = self_.free; self_.free = cursor; cursor = link.owner_next;
    }
}
fn watchKey(self_: Queue, index: i64, key: u64) -> blot_error::Error {
    var prior = none; block { let head = self_.heads.get(key); if head { prior = head; } }
    var link: u32 = 0;
    if self_.free != none { link = self_.free; self_.free = self_.links.items[link].next; }
    else { link = self_.links.len as u32; self_.links.push(default<Link>()); }
    self_.links.items[link] = Link { key: key, item: index as u32, next: prior, owner_next: self_.entries.items[index].head };
    if prior != none { self_.links.items[prior].previous = link; } self_.heads.insert(key, link); self_.entries.items[index].head = link; return blot_error::Error.none;
}
fn watch(self_: Queue, store: blot_check_types::Store&, index: i64, roots: const blot_check_types::Id[:], external_input: bool, broad: bool) -> blot_error::Error {
    var frontier = Frontier {};
    if !broad { let error = collect(frontier, store, roots); if error != blot_error::Error.none { if error == blot_error::Error.out_of_memory { return error; } frontier.overflow = true; } }
    self_.refreshed_watches += 1; let fallback = broad || frontier.overflow;
    if sameWatches(self_, index, frontier, external_input, fallback) { self_.retained_watches += 1; return blot_error::Error.none; }
    clearWatches(self_, index);
    if fallback { let error = watchKey(self_, index, any_write); if error != blot_error::Error.none { return error; } }
    else { for key in frontier.keys[..frontier.len] { let error = watchKey(self_, index, key); if error != blot_error::Error.none { return error; } } }
    if external_input { return watchKey(self_, index, external); } return blot_error::Error.none;
}
fn sameWatches(self_: Queue, index: i64, frontier: const Frontier&, external_input: bool, broad: bool) -> bool {
    var cursor = self_.entries.items[index].head;
    if external_input { if cursor == none || self_.links.items[cursor].key != external { return false; } cursor = self_.links.items[cursor].owner_next; }
    if broad { if cursor == none || self_.links.items[cursor].key != any_write { return false; } cursor = self_.links.items[cursor].owner_next; }
    else { var remaining = frontier.len; while remaining != 0 { remaining -= 1; if cursor == none || self_.links.items[cursor].key != frontier.keys[remaining] { return false; } cursor = self_.links.items[cursor].owner_next; } }
    return cursor == none;
}
struct Frontier { keys: u64[64] = [0; 64], len: i64 = 0, overflow: bool = false }
fn add(self_: Frontier&, key: u64) { for old in self_.keys[..self_.len] { if old == key { return; } } if self_.len == self_.keys.len { self_.overflow = true; return; } self_.keys[self_.len] = key; self_.len += 1; }
fn collect(self_: Frontier&, store: blot_check_types::Store&, roots: const blot_check_types::Id[:]) -> blot_error::Error {
    var stack: blot_check_types::Id[256] = [0; 256]; var seen: blot_check_types::Id[64] = [0; 64];
    if roots.len > stack.len { self_.overflow = true; return blot_error::Error.none; }
    for root, index in roots { stack[index] = root; } var len = roots.len; var visited: i64 = 0;
    while len != 0 && !self_.overflow {
        len -= 1; let root = stack[len]; if root == 0 { continue; }
        if !store.has_projections { let slot = (root * (0x9e3779b9 as u32)) >> 26; if seen[slot] == root { continue; } seen[slot] = root; }
        if visited == 1024 { self_.overflow = true; return blot_error::Error.none; } visited += 1;
        let resolved, error = store.resolve(root, 0); if error != blot_error::Error.none { return error; } let node = store.node(resolved);
        if node.tag == blot_check_types::Tag.variable { add(self_, (node.a as u64) * 2); if node.b > store.cursor() { add(self_, future_clock); } continue; }
        if node.tag == blot_check_types::Tag.function || node.tag == blot_check_types::Tag.provider {
            let row_id, error = store.resolveEffects(node.c, 0); if error != blot_error::Error.none { return error; } let row = store.row(row_id);
            match row.tail { variable v => { add(self_, (v.value as u64) * 2 + 1); }, _ => {}, }
            for label in store.effects.list(row.labels) {
                let arguments = store.operationArguments(label); if arguments.len > stack.len - len { self_.overflow = true; return blot_error::Error.none; }
                for argument in arguments { stack[len] = argument; len += 1; }
                let instance = store.operation(label).instance; if instance.unit == 0 && instance.decl != 0 { if len == stack.len { self_.overflow = true; return blot_error::Error.none; } stack[len] = instance.decl; len += 1; }
            }
        }
        var local: blot_check_types::Id[3] = [0; 3]; var local_count: i64 = 0;
        match node.tag {
            function => { local = [node.a, node.b, 0]; local_count = 2; }, state_provider => { local = [node.a, node.b, node.c]; local_count = 3; },
            usage => { local = [node.a, node.c, 0]; local_count = 1; if node.c != 0 { local_count = 2; } },
            scoped => { local = [node.a, node.c, 0]; local_count = 1; if node.b == 0 { local_count = 2; } },
            forall, existential => {
                if len == stack.len { self_.overflow = true; return blot_error::Error.none; } stack[len] = node.a; len += 1;
                let selected, error = store.resolve(root, 0); if error != blot_error::Error.none { return error; }
                for goal in store.quantifierGoals(selected) { for child in [goal.ty, goal.other, goal.result, goal.signature] { if child != 0 { if len == stack.len { self_.overflow = true; return blot_error::Error.none; } stack[len] = child; len += 1; } } }
            },
            array, list, cursor, resolver, provider => { local[0] = node.a; local_count = 1; },
            product, nominal, projection, instance_selection => {},
            record => { if node.b > stack.len - len { self_.overflow = true; return blot_error::Error.none; } for field in node.b { stack[len] = store.recordField(node, field).ty; len += 1; } }, _ => {},
        }
        let children=selectedFrontierChildren(store,node);if local_count + children.len > stack.len - len { self_.overflow = true; return blot_error::Error.none; }
        for child in local[..local_count] { stack[len] = child; len += 1; } for child in children { stack[len] = child; len += 1; }
    }
    return blot_error::Error.none;
}

fn selectedFrontierChildren(store:const blot_check_types::Store&,node:blot_check_types::Node)->const blot_check_types::Id[:] {match node.tag {product=>{return store.list(blot_check_types::List{node.a,node.b});},nominal,projection,instance_selection=>{return store.nominalArguments(node);},_=>{return default<const blot_check_types::Id[:]>();},}}
