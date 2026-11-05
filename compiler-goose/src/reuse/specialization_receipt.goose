// Exact-query observations refer to one retained immutable evaluator owner.
namespace blot_reuse_specialization_receipt;
import check.core;
import eval.core_eval;
import backend.core_backend;
import support.error;
import support.host_layout;
import support.option;
type Error = blot_error::Error;
struct ViewEffect { value: u32, evidence: u32, selected: u32, existed: bool }
struct CallRead { unit: u32, binding: u32, evidence: u32, present: bool }
struct ScalarRead { target: blot_check_core::BindingRef, evidence: u32 }
struct PlainFact { key: u64, plain: bool, read: bool = true, present: bool = true }
struct ReadyRead { target: blot_check_core::BindingRef, value: u32 }
enum PrincipalOutcome { missing, declined, graph }
struct PrincipalRead {
    target: blot_check_core::BindingRef, open: bool, source_interface: bool,
    deferred_member: bool, outcome: PrincipalOutcome,
}
struct MemberTrace {
    entries: PrincipalRead[64], ready: ReadyRead[64], ready_len: i64 = 0,
    len: i64 = 0, complete: bool = true,
}
fn readyRead(self: MemberTrace&, read: ReadyRead, was_ready: bool) {
    if !was_ready || self.ready_len == 64 { self.complete = false; return; }
    self.ready[self.ready_len] = read; self.ready_len++;
}
fn append(self: MemberTrace&, read: PrincipalRead) {
    if self.len == 64 { self.complete = false; return; }
    self.entries[self.len] = read; self.len++;
}
struct Member {
    ready: ReadyRead[:] = [], principals: PrincipalRead[:] = [],
    principal_graphs: bool, target: blot_check_core::BindingRef, function: u32,
    query_budgets: i64[8], principal_nodes: i64, principal_edges: i64,
    summary_work: i64, transitions: i64, exhausted: bool,
}
// Only Generator supplies these production hooks. Their typed borrow stays
// inside the owning generation; no function value or solver handle escapes.
struct Provider { context: blot_backend_core_backend::Generator&, member_enabled: bool = false }
fn lookup(self: Provider, session: blot_eval_core_eval::Session&, value: u32, expected: u32) -> blot_support::Option<u32>, Error {
    return self.context.lookupSpecialization(session, value, expected);
}
fn member(self: Provider, session: blot_eval_core_eval::Session&, target: blot_check_core::BindingRef,
    value: u32, expected: u32) -> blot_support::Option<u32>, Error {
    if !self.member_enabled { return blot_support::none<u32>(), Error.none; }
    return self.context.lookupMemberSpecialization(session, target, value, expected);
}
struct Record {
    member: blot_support::Option<Member>, completed_closures: u32[:] = [],
    input: u32, expected: u32, selected: u32, options: blot_eval_core_eval::Options,
    depth: i64, values_before: i64, children_before: i64, values_added: i64,
    children_added: i64, steps: i64, collected: i64, source_scopes: i64,
    solver_nodes: i64, complete: bool, sources: blot_check_core::BindingRef[:],
    scalar_reads: ScalarRead[:], call_reads: CallRead[:], call_publications: CallRead[:],
    views: ViewEffect[:], plain_facts: PlainFact[:],
}
reusable[] var owned_closures: u32[>..] = [];
fn copyOwned(source: const u32[:]) -> u32[:] {
    if source.len == 0 { return []; } let out = owned_closures.alloc_slice(source.len);
    for value, index in source { out[index] = value; } return out;
}
fn releaseOwned(source: const u32[:]) {
    if source.len == 0 { return; } let first: const u32& = source[0];
    let at = owned_closures.index_of(first); assert(at >= 0); owned_closures.free_slice(owned_closures[at..at + source.len]);
}
reusable[] var owned_sources: blot_check_core::BindingRef[>..] = [];
fn copyOwned(source: const blot_check_core::BindingRef[:]) -> blot_check_core::BindingRef[:] {
    if source.len == 0 { return []; } let out = owned_sources.alloc_slice(source.len);
    for value, index in source { out[index] = value; } return out;
}
fn releaseOwned(source: const blot_check_core::BindingRef[:]) {
    if source.len == 0 { return; } let first: const blot_check_core::BindingRef& = source[0];
    let at = owned_sources.index_of(first); assert(at >= 0); owned_sources.free_slice(owned_sources[at..at + source.len]);
}
reusable[] var owned_scalars: ScalarRead[>..] = [];
fn copyOwned(source: const ScalarRead[:]) -> ScalarRead[:] {
    if source.len == 0 { return []; } let out = owned_scalars.alloc_slice(source.len);
    for value, index in source { out[index] = value; } return out;
}
fn releaseOwned(source: const ScalarRead[:]) {
    if source.len == 0 { return; } let first: const ScalarRead& = source[0];
    let at = owned_scalars.index_of(first); assert(at >= 0); owned_scalars.free_slice(owned_scalars[at..at + source.len]);
}
reusable[] var owned_calls: CallRead[>..] = [];
fn copyOwned(source: const CallRead[:]) -> CallRead[:] {
    if source.len == 0 { return []; } let out = owned_calls.alloc_slice(source.len);
    for value, index in source { out[index] = value; } return out;
}
fn releaseOwned(source: const CallRead[:]) {
    if source.len == 0 { return; } let first: const CallRead& = source[0];
    let at = owned_calls.index_of(first); assert(at >= 0); owned_calls.free_slice(owned_calls[at..at + source.len]);
}
reusable[] var owned_views: ViewEffect[>..] = [];
fn copyOwned(source: const ViewEffect[:]) -> ViewEffect[:] {
    if source.len == 0 { return []; } let out = owned_views.alloc_slice(source.len);
    for value, index in source { out[index] = value; } return out;
}
fn releaseOwned(source: const ViewEffect[:]) {
    if source.len == 0 { return; } let first: const ViewEffect& = source[0];
    let at = owned_views.index_of(first); assert(at >= 0); owned_views.free_slice(owned_views[at..at + source.len]);
}
reusable[] var owned_plains: PlainFact[>..] = [];
fn copyOwned(source: const PlainFact[:]) -> PlainFact[:] {
    if source.len == 0 { return []; } let out = owned_plains.alloc_slice(source.len);
    for value, index in source { out[index] = value; } return out;
}
fn releaseOwned(source: const PlainFact[:]) {
    if source.len == 0 { return; } let first: const PlainFact& = source[0];
    let at = owned_plains.index_of(first); assert(at >= 0); owned_plains.free_slice(owned_plains[at..at + source.len]);
}
reusable[] var owned_ready: ReadyRead[>..] = [];
fn copyOwned(source: const ReadyRead[:]) -> ReadyRead[:] {
    if source.len == 0 { return []; } let out = owned_ready.alloc_slice(source.len);
    for value, index in source { out[index] = value; } return out;
}
fn releaseOwned(source: const ReadyRead[:]) {
    if source.len == 0 { return; } let first: const ReadyRead& = source[0];
    let at = owned_ready.index_of(first); assert(at >= 0); owned_ready.free_slice(owned_ready[at..at + source.len]);
}
reusable[] var owned_principals: PrincipalRead[>..] = [];
fn copyOwned(source: const PrincipalRead[:]) -> PrincipalRead[:] {
    if source.len == 0 { return []; } let out = owned_principals.alloc_slice(source.len);
    for value, index in source { out[index] = value; } return out;
}
fn releaseOwned(source: const PrincipalRead[:]) {
    if source.len == 0 { return; } let first: const PrincipalRead& = source[0];
    let at = owned_principals.index_of(first); assert(at >= 0); owned_principals.free_slice(owned_principals[at..at + source.len]);
}
fn deinit(self: Record&) {
    releaseOwned(self.completed_closures);
    if self.member.present { releaseOwned(self.member.value.principals); releaseOwned(self.member.value.ready); }
    releaseOwned(self.sources); releaseOwned(self.scalar_reads); releaseOwned(self.call_reads);
    releaseOwned(self.call_publications); releaseOwned(self.views); releaseOwned(self.plain_facts);
    self = default<Record>();
}
fn clone(self: Record) -> Record, Error {
    var result = self;
    if self.member.present {
        var member = self.member.value; member.principals = copyOwned(member.principals); member.ready = copyOwned(member.ready);
        result.member = blot_support::some(member);
    }
    result.sources = copyOwned(self.sources); result.scalar_reads = copyOwned(self.scalar_reads);
    result.call_reads = copyOwned(self.call_reads); result.call_publications = copyOwned(self.call_publications);
    result.views = copyOwned(self.views); result.plain_facts = copyOwned(self.plain_facts);
    result.completed_closures = copyOwned(self.completed_closures); return result, Error.none;
}
fn addBytes(total: i64&, amount: i64) {
    if amount > 9223372036854775807 - total { total = 9223372036854775807; } else { total += amount; }
}
fn ownedBytes(record: Record) -> i64 {
    var total: i64 = 0;
    if record.member.present {
        addBytes(total, blot_host_layout::specialization_member); addBytes(total, bytes_of(record.member.value.principals).len);
        addBytes(total, bytes_of(record.member.value.ready).len);
    }
    addBytes(total, bytes_of(record.sources).len); addBytes(total, bytes_of(record.scalar_reads).len);
    addBytes(total, bytes_of(record.call_reads).len); addBytes(total, bytes_of(record.call_publications).len);
    addBytes(total, bytes_of(record.views).len); addBytes(total, bytes_of(record.plain_facts).len);
    addBytes(total, bytes_of(record.completed_closures).len); return total;
}
struct SourceBuffer { storage: blot_check_core::BindingRef[:] = [], items: blot_check_core::BindingRef[:] = [], len: i64 = 0, failure: Error = Error.none }
reusable[] var tape_sources: blot_check_core::BindingRef[>..] = [];
fn push(self: SourceBuffer&, value: blot_check_core::BindingRef) -> Error {
    if self.failure != Error.none { return self.failure; }
    if self.len == self.storage.len {
        if self.len > 0x5555555555555540 { self.failure = Error.out_of_memory; return self.failure; }
        let minimum = self.len + 1; let capacity = max(8, minimum + minimum / 2);
        let run = tape_sources.alloc_slice(capacity); for item, index in self.items { run[index] = item; }
        if self.storage.len != 0 { tape_sources.free_slice(self.storage); } self.storage = run;
    }
    self.storage[self.len] = value; self.len++; self.items = self.storage[..self.len]; return Error.none;
}
fn clear(self: SourceBuffer&) { self.len = 0; self.items = self.storage[..0]; self.failure = Error.none; }
fn deinit(self: SourceBuffer&) { if self.storage.len != 0 { tape_sources.free_slice(self.storage); } self = SourceBuffer {..}; }
struct ScalarBuffer { storage: ScalarRead[:] = [], items: ScalarRead[:] = [], len: i64 = 0, failure: Error = Error.none }
reusable[] var tape_scalars: ScalarRead[>..] = [];
fn push(self: ScalarBuffer&, value: ScalarRead) -> Error {
    if self.failure != Error.none { return self.failure; }
    if self.len == self.storage.len {
        if self.len > 0x5555555555555540 { self.failure = Error.out_of_memory; return self.failure; }
        let minimum = self.len + 1; let capacity = max(8, minimum + minimum / 2);
        let run = tape_scalars.alloc_slice(capacity); for item, index in self.items { run[index] = item; }
        if self.storage.len != 0 { tape_scalars.free_slice(self.storage); } self.storage = run;
    }
    self.storage[self.len] = value; self.len++; self.items = self.storage[..self.len]; return Error.none;
}
fn clear(self: ScalarBuffer&) { self.len = 0; self.items = self.storage[..0]; self.failure = Error.none; }
fn deinit(self: ScalarBuffer&) { if self.storage.len != 0 { tape_scalars.free_slice(self.storage); } self = ScalarBuffer {..}; }
struct CallBuffer { storage: CallRead[:] = [], items: CallRead[:] = [], len: i64 = 0, failure: Error = Error.none }
reusable[] var tape_calls: CallRead[>..] = [];
fn push(self: CallBuffer&, value: CallRead) -> Error {
    if self.failure != Error.none { return self.failure; }
    if self.len == self.storage.len {
        if self.len > 0x5555555555555540 { self.failure = Error.out_of_memory; return self.failure; }
        let minimum = self.len + 1; let capacity = max(8, minimum + minimum / 2);
        let run = tape_calls.alloc_slice(capacity); for item, index in self.items { run[index] = item; }
        if self.storage.len != 0 { tape_calls.free_slice(self.storage); } self.storage = run;
    }
    self.storage[self.len] = value; self.len++; self.items = self.storage[..self.len]; return Error.none;
}
fn clear(self: CallBuffer&) { self.len = 0; self.items = self.storage[..0]; self.failure = Error.none; }
fn deinit(self: CallBuffer&) { if self.storage.len != 0 { tape_calls.free_slice(self.storage); } self = CallBuffer {..}; }
struct ViewBuffer { storage: ViewEffect[:] = [], items: ViewEffect[:] = [], len: i64 = 0, failure: Error = Error.none }
reusable[] var tape_views: ViewEffect[>..] = [];
fn push(self: ViewBuffer&, value: ViewEffect) -> Error {
    if self.failure != Error.none { return self.failure; }
    if self.len == self.storage.len {
        if self.len > 0x5555555555555540 { self.failure = Error.out_of_memory; return self.failure; }
        let minimum = self.len + 1; let capacity = max(8, minimum + minimum / 2);
        let run = tape_views.alloc_slice(capacity); for item, index in self.items { run[index] = item; }
        if self.storage.len != 0 { tape_views.free_slice(self.storage); } self.storage = run;
    }
    self.storage[self.len] = value; self.len++; self.items = self.storage[..self.len]; return Error.none;
}
fn clear(self: ViewBuffer&) { self.len = 0; self.items = self.storage[..0]; self.failure = Error.none; }
fn deinit(self: ViewBuffer&) { if self.storage.len != 0 { tape_views.free_slice(self.storage); } self = ViewBuffer {..}; }
struct PlainBuffer { storage: PlainFact[:] = [], items: PlainFact[:] = [], len: i64 = 0, failure: Error = Error.none }
reusable[] var tape_plains: PlainFact[>..] = [];
fn push(self: PlainBuffer&, value: PlainFact) -> Error {
    if self.failure != Error.none { return self.failure; }
    if self.len == self.storage.len {
        if self.len > 0x5555555555555540 { self.failure = Error.out_of_memory; return self.failure; }
        let minimum = self.len + 1; let capacity = max(8, minimum + minimum / 2);
        let run = tape_plains.alloc_slice(capacity); for item, index in self.items { run[index] = item; }
        if self.storage.len != 0 { tape_plains.free_slice(self.storage); } self.storage = run;
    }
    self.storage[self.len] = value; self.len++; self.items = self.storage[..self.len]; return Error.none;
}
fn clear(self: PlainBuffer&) { self.len = 0; self.items = self.storage[..0]; self.failure = Error.none; }
fn deinit(self: PlainBuffer&) { if self.storage.len != 0 { tape_plains.free_slice(self.storage); } self = PlainBuffer {..}; }
struct Tape {
    sources: SourceBuffer = SourceBuffer {..}, scalar_reads: ScalarBuffer = ScalarBuffer {..},
    call_reads: CallBuffer = CallBuffer {..}, call_publications: CallBuffer = CallBuffer {..},
    views: ViewBuffer = ViewBuffer {..}, plain_facts: PlainBuffer = PlainBuffer {..},
    nested: bool = false, unknown: bool = false, collected: i64 = 0,
}
fn initPooled() -> Tape, Error { return Tape {..}, Error.none; }
fn deinit(self: Tape&) {
    self.sources.deinit(); self.scalar_reads.deinit(); self.call_reads.deinit();
    self.call_publications.deinit(); self.views.deinit(); self.plain_facts.deinit();
}
fn finish(self: Tape&, base: Record) -> Record, Error {
    let failures = [self.sources.failure, self.scalar_reads.failure, self.call_reads.failure,
        self.call_publications.failure, self.views.failure, self.plain_facts.failure];
    for failure in failures { if failure != Error.none { self.deinit(); return default<Record>(), failure; } }
    var result = base;
    result.sources = copyOwned(self.sources.items); result.scalar_reads = copyOwned(self.scalar_reads.items);
    result.call_reads = copyOwned(self.call_reads.items); result.call_publications = copyOwned(self.call_publications.items);
    result.views = copyOwned(self.views.items); result.plain_facts = copyOwned(self.plain_facts.items);
    result.complete = result.complete && !self.nested && !self.unknown;
    self.deinit(); return result, Error.none;
}
fn withTape<C,F>(context: C&) -> Error { var owner,error=initTapeOwner(); if error!=Error.none { return error; } let tape=owner.borrow(); assert(tape); let result=F(context,tape); owner.deinit(); return result; }

fn principalOutcomeCode(value: PrincipalOutcome) -> u8 {
    match value { PrincipalOutcome.missing => 0, PrincipalOutcome.declined => 1, PrincipalOutcome.graph => 2 }
}

fn append(self: SourceBuffer&, values: const blot_check_core::BindingRef[:]) -> Error { for value in values { let error = self.push(value); if error != Error.none { return error; } } return self.failure; }
fn resize(self: SourceBuffer&, length: i64) { assert(length >= 0 && length <= self.len); self.len = length; self.items = self.storage[..length]; }

fn append(self: ScalarBuffer&, values: const ScalarRead[:]) -> Error { for value in values { let error = self.push(value); if error != Error.none { return error; } } return self.failure; }
fn resize(self: ScalarBuffer&, length: i64) { assert(length >= 0 && length <= self.len); self.len = length; self.items = self.storage[..length]; }

fn append(self: CallBuffer&, values: const CallRead[:]) -> Error { for value in values { let error = self.push(value); if error != Error.none { return error; } } return self.failure; }
fn resize(self: CallBuffer&, length: i64) { assert(length >= 0 && length <= self.len); self.len = length; self.items = self.storage[..length]; }

fn append(self: ViewBuffer&, values: const ViewEffect[:]) -> Error { for value in values { let error = self.push(value); if error != Error.none { return error; } } return self.failure; }
fn resize(self: ViewBuffer&, length: i64) { assert(length >= 0 && length <= self.len); self.len = length; self.items = self.storage[..length]; }

fn append(self: PlainBuffer&, values: const PlainFact[:]) -> Error { for value in values { let error = self.push(value); if error != Error.none { return error; } } return self.failure; }
fn resize(self: PlainBuffer&, length: i64) { assert(length >= 0 && length <= self.len); self.len = length; self.items = self.storage[..length]; }

struct TapeOwner { lease: u32=0,generation: u64=0 }
struct TapeOwnerState { value: Tape,generation: u64,live: bool=true }
reusable var tape_owner_slots: TapeOwnerState[>..]=[];
var next_tape_owner_slots_generation: u64=1;
fn initTapeOwner() -> TapeOwner,Error { if next_tape_owner_slots_generation==0xffffffffffffffff||tape_owner_slots.len>=0xffffffff { return TapeOwner {..},Error.out_of_memory; } let value,error=initPooled(); if error!=Error.none { return TapeOwner {..},error; } let generation=next_tape_owner_slots_generation; next_tape_owner_slots_generation++; let at=tape_owner_slots.alloc_index(TapeOwnerState {value,generation,true, ..}); return TapeOwner {(at+1) as u32,generation, ..},Error.none; }
fn borrow(self: TapeOwner) -> Tape? { if self.lease==0||self.lease-1>=tape_owner_slots.len { return null; } let slot: TapeOwnerState&=tape_owner_slots[self.lease-1]; if !slot.live||slot.generation!=self.generation { return null; } return slot.value; }
fn deinit(self: TapeOwner&) { if self.lease==0 { return; } let at=self.lease-1; assert(at<tape_owner_slots.len&&tape_owner_slots[at].live&&tape_owner_slots[at].generation==self.generation); let slot: TapeOwnerState&=tape_owner_slots[at]; slot.value.deinit(); slot.live=false; tape_owner_slots.free(at); self=TapeOwner {..}; }
