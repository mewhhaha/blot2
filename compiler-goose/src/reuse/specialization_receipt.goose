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
fn readyRead(self_: MemberTrace&, read: ReadyRead, was_ready: bool) {
    if !was_ready || self_.ready_len == 64 { self_.complete = false; return; }
    self_.ready[self_.ready_len] = read; self_.ready_len++;
}
fn append(self_: MemberTrace&, read: PrincipalRead) {
    if self_.len == 64 { self_.complete = false; return; }
    self_.entries[self_.len] = read; self_.len++;
}
struct Member {
    ready: ReadyRead[:] = default<ReadyRead[:]>(), principals: PrincipalRead[:] = default<PrincipalRead[:]>(),
    principal_graphs: bool, target: blot_check_core::BindingRef, function: u32,
    query_budgets: i64[8], principal_nodes: i64, principal_edges: i64,
    summary_work: i64, transitions: i64, exhausted: bool,
}
// Only Generator supplies these production hooks. Their typed borrow stays
// inside the owning generation; no function value or solver handle escapes.
struct Provider { context: blot_backend_core_backend::Generator&, member_enabled: bool = false }
fn lookup(self_: Provider, session: blot_eval_core_eval::Session&, value: u32, expected: u32) -> blot_support::Option<u32>, Error {
    return self_.context.lookupSpecialization(session, value, expected);
}
fn member(self_: Provider, session: blot_eval_core_eval::Session&, target: blot_check_core::BindingRef,
    value: u32, expected: u32) -> blot_support::Option<u32>, Error {
    if !self_.member_enabled { return blot_support::none<u32>(), blot_error::Error.none; }
    return self_.context.lookupMemberSpecialization(session, target, value, expected);
}
struct Record {
    member: blot_support::Option<Member>, completed_closures: u32[:] = default<u32[:]>(),
    input: u32, expected: u32, selected: u32, options: blot_eval_core_eval::Options,
    depth: i64, values_before: i64, children_before: i64, values_added: i64,
    children_added: i64, steps: i64, collected: i64, source_scopes: i64,
    solver_nodes: i64, complete: bool, sources: blot_check_core::BindingRef[:],
    scalar_reads: ScalarRead[:], call_reads: CallRead[:], call_publications: CallRead[:],
    views: ViewEffect[:], plain_facts: PlainFact[:],
}
reusable[] var owned_closures: u32[>..] = [];
fn copyOwned(source: const u32[:]) -> u32[:] {
    if source.len == 0 { return default<u32[:]>(); } let out = owned_closures.alloc_slice(source.len);
    for value, index in source { out[index] = value; } return out;
}
fn releaseOwned(source: const u32[:]) {
    if source.len == 0 { return; } owned_closures.free_slice(source);
}
reusable[] var owned_sources: blot_check_core::BindingRef[>..] = [];
fn copyOwned(source: const blot_check_core::BindingRef[:]) -> blot_check_core::BindingRef[:] {
    if source.len == 0 { return default<blot_check_core::BindingRef[:]>(); } let out = owned_sources.alloc_slice(source.len);
    for value, index in source { out[index] = value; } return out;
}
fn releaseOwned(source: const blot_check_core::BindingRef[:]) {
    if source.len == 0 { return; } owned_sources.free_slice(source);
}
reusable[] var owned_scalars: ScalarRead[>..] = [];
fn copyOwned(source: const ScalarRead[:]) -> ScalarRead[:] {
    if source.len == 0 { return default<ScalarRead[:]>(); } let out = owned_scalars.alloc_slice(source.len);
    for value, index in source { out[index] = value; } return out;
}
fn releaseOwned(source: const ScalarRead[:]) {
    if source.len == 0 { return; } owned_scalars.free_slice(source);
}
reusable[] var owned_calls: CallRead[>..] = [];
fn copyOwned(source: const CallRead[:]) -> CallRead[:] {
    if source.len == 0 { return default<CallRead[:]>(); } let out = owned_calls.alloc_slice(source.len);
    for value, index in source { out[index] = value; } return out;
}
fn releaseOwned(source: const CallRead[:]) {
    if source.len == 0 { return; } owned_calls.free_slice(source);
}
reusable[] var owned_views: ViewEffect[>..] = [];
fn copyOwned(source: const ViewEffect[:]) -> ViewEffect[:] {
    if source.len == 0 { return default<ViewEffect[:]>(); } let out = owned_views.alloc_slice(source.len);
    for value, index in source { out[index] = value; } return out;
}
fn releaseOwned(source: const ViewEffect[:]) {
    if source.len == 0 { return; } owned_views.free_slice(source);
}
reusable[] var owned_plains: PlainFact[>..] = [];
fn copyOwned(source: const PlainFact[:]) -> PlainFact[:] {
    if source.len == 0 { return default<PlainFact[:]>(); } let out = owned_plains.alloc_slice(source.len);
    for value, index in source { out[index] = value; } return out;
}
fn releaseOwned(source: const PlainFact[:]) {
    if source.len == 0 { return; } owned_plains.free_slice(source);
}
reusable[] var owned_ready: ReadyRead[>..] = [];
fn copyOwned(source: const ReadyRead[:]) -> ReadyRead[:] {
    if source.len == 0 { return default<ReadyRead[:]>(); } let out = owned_ready.alloc_slice(source.len);
    for value, index in source { out[index] = value; } return out;
}
fn releaseOwned(source: const ReadyRead[:]) {
    if source.len == 0 { return; } owned_ready.free_slice(source);
}
reusable[] var owned_principals: PrincipalRead[>..] = [];
fn copyOwned(source: const PrincipalRead[:]) -> PrincipalRead[:] {
    if source.len == 0 { return default<PrincipalRead[:]>(); } let out = owned_principals.alloc_slice(source.len);
    for value, index in source { out[index] = value; } return out;
}
fn releaseOwned(source: const PrincipalRead[:]) {
    if source.len == 0 { return; } owned_principals.free_slice(source);
}
fn deinit(self_: Record&) {
    releaseOwned(self_.completed_closures);
    if self_.member.present { releaseOwned(self_.member.value.principals); releaseOwned(self_.member.value.ready); }
    releaseOwned(self_.sources); releaseOwned(self_.scalar_reads); releaseOwned(self_.call_reads);
    releaseOwned(self_.call_publications); releaseOwned(self_.views); releaseOwned(self_.plain_facts);
    self_ = default<Record>();
}
fn clone(self_: Record) -> Record, Error {
    var result = self_;
    if self_.member.present {
        var member = self_.member.value; member.principals = copyOwned(member.principals); member.ready = copyOwned(member.ready);
        result.member = blot_support::some(member);
    }
    result.sources = copyOwned(self_.sources); result.scalar_reads = copyOwned(self_.scalar_reads);
    result.call_reads = copyOwned(self_.call_reads); result.call_publications = copyOwned(self_.call_publications);
    result.views = copyOwned(self_.views); result.plain_facts = copyOwned(self_.plain_facts);
    result.completed_closures = copyOwned(self_.completed_closures); return result, blot_error::Error.none;
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
struct SourceBuffer { storage: blot_check_core::BindingRef[:] = default<blot_check_core::BindingRef[:]>(), items: blot_check_core::BindingRef[:] = default<blot_check_core::BindingRef[:]>(), len: i64 = 0, failure: Error = blot_error::Error.none }
reusable[] var tape_sources: blot_check_core::BindingRef[>..] = [];
fn push(self_: SourceBuffer&, value: blot_check_core::BindingRef) -> Error {
    if self_.failure != blot_error::Error.none { return self_.failure; }
    if self_.len == self_.storage.len {
        if self_.len > 0x5555555555555540 { self_.failure = blot_error::Error.out_of_memory; return self_.failure; }
        let minimum = self_.len + 1; let capacity = max(8, minimum + minimum / 2);
        let run = tape_sources.alloc_slice(capacity); for item, index in self_.items { run[index] = item; }
        if self_.storage.len != 0 { tape_sources.free_slice(self_.storage); } self_.storage = run;
    }
    self_.storage[self_.len] = value; self_.len++; self_.items = self_.storage[..self_.len]; return blot_error::Error.none;
}
fn clear(self_: SourceBuffer&) { self_.len = 0; self_.items = self_.storage[..0]; self_.failure = blot_error::Error.none; }
fn deinit(self_: SourceBuffer&) { if self_.storage.len != 0 { tape_sources.free_slice(self_.storage); } self_ = SourceBuffer {..}; }
struct ScalarBuffer { storage: ScalarRead[:] = default<ScalarRead[:]>(), items: ScalarRead[:] = default<ScalarRead[:]>(), len: i64 = 0, failure: Error = blot_error::Error.none }
reusable[] var tape_scalars: ScalarRead[>..] = [];
fn push(self_: ScalarBuffer&, value: ScalarRead) -> Error {
    if self_.failure != blot_error::Error.none { return self_.failure; }
    if self_.len == self_.storage.len {
        if self_.len > 0x5555555555555540 { self_.failure = blot_error::Error.out_of_memory; return self_.failure; }
        let minimum = self_.len + 1; let capacity = max(8, minimum + minimum / 2);
        let run = tape_scalars.alloc_slice(capacity); for item, index in self_.items { run[index] = item; }
        if self_.storage.len != 0 { tape_scalars.free_slice(self_.storage); } self_.storage = run;
    }
    self_.storage[self_.len] = value; self_.len++; self_.items = self_.storage[..self_.len]; return blot_error::Error.none;
}
fn clear(self_: ScalarBuffer&) { self_.len = 0; self_.items = self_.storage[..0]; self_.failure = blot_error::Error.none; }
fn deinit(self_: ScalarBuffer&) { if self_.storage.len != 0 { tape_scalars.free_slice(self_.storage); } self_ = ScalarBuffer {..}; }
struct CallBuffer { storage: CallRead[:] = default<CallRead[:]>(), items: CallRead[:] = default<CallRead[:]>(), len: i64 = 0, failure: Error = blot_error::Error.none }
reusable[] var tape_calls: CallRead[>..] = [];
fn push(self_: CallBuffer&, value: CallRead) -> Error {
    if self_.failure != blot_error::Error.none { return self_.failure; }
    if self_.len == self_.storage.len {
        if self_.len > 0x5555555555555540 { self_.failure = blot_error::Error.out_of_memory; return self_.failure; }
        let minimum = self_.len + 1; let capacity = max(8, minimum + minimum / 2);
        let run = tape_calls.alloc_slice(capacity); for item, index in self_.items { run[index] = item; }
        if self_.storage.len != 0 { tape_calls.free_slice(self_.storage); } self_.storage = run;
    }
    self_.storage[self_.len] = value; self_.len++; self_.items = self_.storage[..self_.len]; return blot_error::Error.none;
}
fn clear(self_: CallBuffer&) { self_.len = 0; self_.items = self_.storage[..0]; self_.failure = blot_error::Error.none; }
fn deinit(self_: CallBuffer&) { if self_.storage.len != 0 { tape_calls.free_slice(self_.storage); } self_ = CallBuffer {..}; }
struct ViewBuffer { storage: ViewEffect[:] = default<ViewEffect[:]>(), items: ViewEffect[:] = default<ViewEffect[:]>(), len: i64 = 0, failure: Error = blot_error::Error.none }
reusable[] var tape_views: ViewEffect[>..] = [];
fn push(self_: ViewBuffer&, value: ViewEffect) -> Error {
    if self_.failure != blot_error::Error.none { return self_.failure; }
    if self_.len == self_.storage.len {
        if self_.len > 0x5555555555555540 { self_.failure = blot_error::Error.out_of_memory; return self_.failure; }
        let minimum = self_.len + 1; let capacity = max(8, minimum + minimum / 2);
        let run = tape_views.alloc_slice(capacity); for item, index in self_.items { run[index] = item; }
        if self_.storage.len != 0 { tape_views.free_slice(self_.storage); } self_.storage = run;
    }
    self_.storage[self_.len] = value; self_.len++; self_.items = self_.storage[..self_.len]; return blot_error::Error.none;
}
fn clear(self_: ViewBuffer&) { self_.len = 0; self_.items = self_.storage[..0]; self_.failure = blot_error::Error.none; }
fn deinit(self_: ViewBuffer&) { if self_.storage.len != 0 { tape_views.free_slice(self_.storage); } self_ = ViewBuffer {..}; }
struct PlainBuffer { storage: PlainFact[:] = default<PlainFact[:]>(), items: PlainFact[:] = default<PlainFact[:]>(), len: i64 = 0, failure: Error = blot_error::Error.none }
reusable[] var tape_plains: PlainFact[>..] = [];
fn push(self_: PlainBuffer&, value: PlainFact) -> Error {
    if self_.failure != blot_error::Error.none { return self_.failure; }
    if self_.len == self_.storage.len {
        if self_.len > 0x5555555555555540 { self_.failure = blot_error::Error.out_of_memory; return self_.failure; }
        let minimum = self_.len + 1; let capacity = max(8, minimum + minimum / 2);
        let run = tape_plains.alloc_slice(capacity); for item, index in self_.items { run[index] = item; }
        if self_.storage.len != 0 { tape_plains.free_slice(self_.storage); } self_.storage = run;
    }
    self_.storage[self_.len] = value; self_.len++; self_.items = self_.storage[..self_.len]; return blot_error::Error.none;
}
fn clear(self_: PlainBuffer&) { self_.len = 0; self_.items = self_.storage[..0]; self_.failure = blot_error::Error.none; }
fn deinit(self_: PlainBuffer&) { if self_.storage.len != 0 { tape_plains.free_slice(self_.storage); } self_ = PlainBuffer {..}; }
struct Tape {
    sources: SourceBuffer = SourceBuffer {..}, scalar_reads: ScalarBuffer = ScalarBuffer {..},
    call_reads: CallBuffer = CallBuffer {..}, call_publications: CallBuffer = CallBuffer {..},
    views: ViewBuffer = ViewBuffer {..}, plain_facts: PlainBuffer = PlainBuffer {..},
    nested: bool = false, unknown: bool = false, collected: i64 = 0,
}
fn initPooled() -> Tape, Error { return Tape {..}, blot_error::Error.none; }
fn deinit(self_: Tape&) {
    self_.sources.deinit(); self_.scalar_reads.deinit(); self_.call_reads.deinit();
    self_.call_publications.deinit(); self_.views.deinit(); self_.plain_facts.deinit();
}
fn finish(self_: Tape&, base: Record) -> Record, Error {
    let failures = [self_.sources.failure, self_.scalar_reads.failure, self_.call_reads.failure,
        self_.call_publications.failure, self_.views.failure, self_.plain_facts.failure];
    for failure in failures { if failure != blot_error::Error.none { self_.deinit(); return default<Record>(), failure; } }
    var result = base;
    result.sources = copyOwned(self_.sources.items); result.scalar_reads = copyOwned(self_.scalar_reads.items);
    result.call_reads = copyOwned(self_.call_reads.items); result.call_publications = copyOwned(self_.call_publications.items);
    result.views = copyOwned(self_.views.items); result.plain_facts = copyOwned(self_.plain_facts.items);
    result.complete = result.complete && !self_.nested && !self_.unknown;
    self_.deinit(); return result, blot_error::Error.none;
}
fn withTape<C,F>(context: C&) -> Error { var owner,error=initTapeOwner(); if error!=blot_error::Error.none { return error; } let tape=owner.borrow(); assert(tape); let result=F(context,tape); owner.deinit(); return result; }

fn principalOutcomeCode(value: PrincipalOutcome) -> u8 {
    match value { missing => 0, declined => 1, graph => 2 }
}

fn append(self_: SourceBuffer&, values: const blot_check_core::BindingRef[:]) -> Error { for value in values { let error = self_.push(value); if error != blot_error::Error.none { return error; } } return self_.failure; }
fn resize(self_: SourceBuffer&, length: i64) { assert(length >= 0 && length <= self_.len); self_.len = length; self_.items = self_.storage[..length]; }

fn append(self_: ScalarBuffer&, values: const ScalarRead[:]) -> Error { for value in values { let error = self_.push(value); if error != blot_error::Error.none { return error; } } return self_.failure; }
fn resize(self_: ScalarBuffer&, length: i64) { assert(length >= 0 && length <= self_.len); self_.len = length; self_.items = self_.storage[..length]; }

fn append(self_: CallBuffer&, values: const CallRead[:]) -> Error { for value in values { let error = self_.push(value); if error != blot_error::Error.none { return error; } } return self_.failure; }
fn resize(self_: CallBuffer&, length: i64) { assert(length >= 0 && length <= self_.len); self_.len = length; self_.items = self_.storage[..length]; }

fn append(self_: ViewBuffer&, values: const ViewEffect[:]) -> Error { for value in values { let error = self_.push(value); if error != blot_error::Error.none { return error; } } return self_.failure; }
fn resize(self_: ViewBuffer&, length: i64) { assert(length >= 0 && length <= self_.len); self_.len = length; self_.items = self_.storage[..length]; }

fn append(self_: PlainBuffer&, values: const PlainFact[:]) -> Error { for value in values { let error = self_.push(value); if error != blot_error::Error.none { return error; } } return self_.failure; }
fn resize(self_: PlainBuffer&, length: i64) { assert(length >= 0 && length <= self_.len); self_.len = length; self_.items = self_.storage[..length]; }

struct TapeOwner { lease: u32=0,generation: u64=0 }
struct TapeOwnerState { value: Tape,generation: u64,live: bool=true }
reusable var tape_owner_slots: TapeOwnerState[>..]=[];
var next_tape_owner_slots_generation: u64=1;
fn initTapeOwner() -> TapeOwner,Error { if next_tape_owner_slots_generation==0xffffffffffffffff||tape_owner_slots.len>=0xffffffff { return TapeOwner {..},blot_error::Error.out_of_memory; } let value,error=initPooled(); if error!=blot_error::Error.none { return TapeOwner {..},error; } let generation=next_tape_owner_slots_generation; next_tape_owner_slots_generation++; let at=tape_owner_slots.alloc_index(TapeOwnerState {value,generation,true, ..}); return TapeOwner {(at+1) as u32,generation, ..},blot_error::Error.none; }
fn borrow(self_: TapeOwner) -> Tape? { if self_.lease==0||self_.lease-1>=tape_owner_slots.len { return null; } let slot: TapeOwnerState& =tape_owner_slots[self_.lease-1]; if !slot.live||slot.generation!=self_.generation { return null; } return slot.value; }
fn deinit(self_: TapeOwner&) { if self_.lease==0 { return; } let at=self_.lease-1; assert(at<tape_owner_slots.len&&tape_owner_slots[at].live&&tape_owner_slots[at].generation==self_.generation); let slot: TapeOwnerState& =tape_owner_slots[at]; slot.value.deinit(); slot.live=false; tape_owner_slots.free(at); self_=TapeOwner {..}; }
