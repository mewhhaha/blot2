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
struct Tape {
    sources: blot_check_core::BindingRef[>..<]&, scalar_reads: ScalarRead[>..<]&,
    call_reads: CallRead[>..<]&, call_publications: CallRead[>..<]&,
    views: ViewEffect[>..<]&, plain_facts: PlainFact[>..<]&,
    nested: bool = false, unknown: bool = false, collected: i64 = 0,
}
fn init(sources: blot_check_core::BindingRef[>..<]&, scalars: ScalarRead[>..<]&,
    calls: CallRead[>..<]&, publications: CallRead[>..<]&, views: ViewEffect[>..<]&,
    plains: PlainFact[>..<]&) -> Tape { Tape { sources, scalars, calls, publications, views, plains } }
fn deinit(self: Tape&) {
    self.sources.clear(); self.scalar_reads.clear(); self.call_reads.clear(); self.call_publications.clear();
    self.views.clear(); self.plain_facts.clear();
}
fn finish(self: Tape&, base: Record) -> Record, Error {
    var result = base;
    result.sources = copyOwned(self.sources); result.scalar_reads = copyOwned(self.scalar_reads);
    result.call_reads = copyOwned(self.call_reads); result.call_publications = copyOwned(self.call_publications);
    result.views = copyOwned(self.views); result.plain_facts = copyOwned(self.plain_facts);
    result.complete = result.complete && !self.nested && !self.unknown;
    self.deinit(); return result, Error.none;
}
fn withTape<C,F>(context: C&) -> Error {
    var sources: blot_check_core::BindingRef[>..<] = []; var scalars: ScalarRead[>..<] = [];
    var calls: CallRead[>..<] = []; var publications: CallRead[>..<] = [];
    var views: ViewEffect[>..<] = []; var plains: PlainFact[>..<] = [];
    var tape = init(sources, scalars, calls, publications, views, plains);
    return F(context, tape);
}
fn principalOutcomeCode(value: PrincipalOutcome) -> u8 {
    match value { PrincipalOutcome.missing => 0, PrincipalOutcome.declined => 1, PrincipalOutcome.graph => 2 }
}
