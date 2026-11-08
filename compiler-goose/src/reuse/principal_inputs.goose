// Dynamic observations qualify principal constraints, never evaluated values.
namespace blot_reuse_principal_inputs;
import std;
import dictionary;
import support.pooled_buffer;
import support.pooled_map;
import check.core;
import eval.core_eval;
import eval.type_evidence;
import support.error;
import support.option;
type Error = blot_error::Error;
type BindingRef = blot_check_core::BindingRef;
struct ScalarRead { target: BindingRef, evidence: u32 }
struct PlainRead { key: u64, value: blot_support::Option<bool> }
struct PlainPublication { key: u64, value: bool }
struct CallPublication { target: BindingRef, evidence: u32 }
struct CallRead { target: BindingRef, evidence: u32, present: bool }
struct SummaryKey { target: BindingRef, inputs: u32, deferred_member: bool = false }
struct Summary { key: SummaryKey, result: u32 }
struct Key {
    empty_call_inputs: bool = true, source_complete: bool = false,
    sources: const BindingRef[:] = default<const BindingRef[:]>(), interfaces: const BindingRef[:] = default<const BindingRef[:]>(),
    source_units: const u32[:] = default<const u32[:]>(), scalar_reads: const ScalarRead[:],
    plain_reads: const PlainRead[:] = default<const PlainRead[:]>(), plain_publications: const PlainPublication[:] = default<const PlainPublication[:]>(),
    call_publications: CallPublication[:] = default<CallPublication[:]>(), call_reads: CallRead[:] = default<CallRead[:]>(),
    summary_reads: Summary[:] = default<Summary[:]>(), summary_publications: Summary[:] = default<Summary[:]>(),
}
reusable[] var owned_binding: BindingRef[>..] = [];
fn copyOwned(source: const BindingRef[:]) -> BindingRef[:] {
    if source.len == 0 { return default<BindingRef[:]>(); } let out = owned_binding.alloc_slice(source.len);
    for value, index in source { out[index] = value; } return out;
}
fn releaseOwned(source: const BindingRef[:]) {
    if source.len == 0 { return; } owned_binding.free_slice(source);
}
reusable[] var owned_units: u32[>..] = [];
fn copyOwned(source: const u32[:]) -> u32[:] {
    if source.len == 0 { return default<u32[:]>(); } let out = owned_units.alloc_slice(source.len);
    for value, index in source { out[index] = value; } return out;
}
fn releaseOwned(source: const u32[:]) {
    if source.len == 0 { return; } owned_units.free_slice(source);
}
reusable[] var owned_scalar: ScalarRead[>..] = [];
fn copyOwned(source: const ScalarRead[:]) -> ScalarRead[:] {
    if source.len == 0 { return default<ScalarRead[:]>(); } let out = owned_scalar.alloc_slice(source.len);
    for value, index in source { out[index] = value; } return out;
}
fn releaseOwned(source: const ScalarRead[:]) {
    if source.len == 0 { return; } owned_scalar.free_slice(source);
}
reusable[] var owned_plain_reads: PlainRead[>..] = [];
fn copyOwned(source: const PlainRead[:]) -> PlainRead[:] {
    if source.len == 0 { return default<PlainRead[:]>(); } let out = owned_plain_reads.alloc_slice(source.len);
    for value, index in source { out[index] = value; } return out;
}
fn releaseOwned(source: const PlainRead[:]) {
    if source.len == 0 { return; } owned_plain_reads.free_slice(source);
}
reusable[] var owned_plain_publications: PlainPublication[>..] = [];
fn copyOwned(source: const PlainPublication[:]) -> PlainPublication[:] {
    if source.len == 0 { return default<PlainPublication[:]>(); } let out = owned_plain_publications.alloc_slice(source.len);
    for value, index in source { out[index] = value; } return out;
}
fn releaseOwned(source: const PlainPublication[:]) {
    if source.len == 0 { return; } owned_plain_publications.free_slice(source);
}
reusable[] var owned_call_publications: CallPublication[>..] = [];
fn copyOwned(source: const CallPublication[:]) -> CallPublication[:] {
    if source.len == 0 { return default<CallPublication[:]>(); } let out = owned_call_publications.alloc_slice(source.len);
    for value, index in source { out[index] = value; } return out;
}
fn releaseOwned(source: const CallPublication[:]) {
    if source.len == 0 { return; } owned_call_publications.free_slice(source);
}
reusable[] var owned_call_reads: CallRead[>..] = [];
fn copyOwned(source: const CallRead[:]) -> CallRead[:] {
    if source.len == 0 { return default<CallRead[:]>(); } let out = owned_call_reads.alloc_slice(source.len);
    for value, index in source { out[index] = value; } return out;
}
fn releaseOwned(source: const CallRead[:]) {
    if source.len == 0 { return; } owned_call_reads.free_slice(source);
}
reusable[] var owned_summaries: Summary[>..] = [];
fn copyOwned(source: const Summary[:]) -> Summary[:] {
    if source.len == 0 { return default<Summary[:]>(); } let out = owned_summaries.alloc_slice(source.len);
    for value, index in source { out[index] = value; } return out;
}
fn releaseOwned(source: const Summary[:]) {
    if source.len == 0 { return; } owned_summaries.free_slice(source);
}
// These receipts validate existing owned runs without moving or copying them.
fn canonicalOwned(source: Key) -> Key {
    return Key {
        empty_call_inputs: source.empty_call_inputs, source_complete: source.source_complete,
        sources: owned_binding.realloc_slice(source.sources, source.sources.len),
        interfaces: owned_binding.realloc_slice(source.interfaces, source.interfaces.len),
        source_units: owned_units.realloc_slice(source.source_units, source.source_units.len),
        scalar_reads: owned_scalar.realloc_slice(source.scalar_reads, source.scalar_reads.len),
        plain_reads: owned_plain_reads.realloc_slice(source.plain_reads, source.plain_reads.len),
        plain_publications: owned_plain_publications.realloc_slice(source.plain_publications, source.plain_publications.len),
        call_publications: owned_call_publications.realloc_slice(source.call_publications, source.call_publications.len),
        call_reads: owned_call_reads.realloc_slice(source.call_reads, source.call_reads.len),
        summary_reads: owned_summaries.realloc_slice(source.summary_reads, source.summary_reads.len),
        summary_publications: owned_summaries.realloc_slice(source.summary_publications, source.summary_publications.len),
    };
}
fn clone(self_: Key) -> Key, Error {
    var result = self_;
    result.sources = copyOwned(self_.sources);
    result.interfaces = copyOwned(self_.interfaces);
    result.source_units = copyOwned(self_.source_units);
    result.scalar_reads = copyOwned(self_.scalar_reads);
    result.plain_reads = copyOwned(self_.plain_reads);
    result.plain_publications = copyOwned(self_.plain_publications);
    result.call_publications = copyOwned(self_.call_publications);
    result.call_reads = copyOwned(self_.call_reads);
    result.summary_reads = copyOwned(self_.summary_reads);
    result.summary_publications = copyOwned(self_.summary_publications);
    return result, blot_error::Error.none;
}
fn deinit(self_: Key&) {
    releaseOwned(self_.sources); self_.sources = default<const BindingRef[:]>();
    releaseOwned(self_.interfaces); self_.interfaces = default<const BindingRef[:]>();
    releaseOwned(self_.source_units); self_.source_units = default<const u32[:]>();
    releaseOwned(self_.scalar_reads); self_.scalar_reads = default<const ScalarRead[:]>();
    releaseOwned(self_.plain_reads); self_.plain_reads = default<const PlainRead[:]>();
    releaseOwned(self_.plain_publications); self_.plain_publications = default<const PlainPublication[:]>();
    releaseOwned(self_.call_publications); self_.call_publications = default<CallPublication[:]>();
    releaseOwned(self_.call_reads); self_.call_reads = default<CallRead[:]>();
    releaseOwned(self_.summary_reads); self_.summary_reads = default<Summary[:]>();
    releaseOwned(self_.summary_publications); self_.summary_publications = default<Summary[:]>();
}
fn proofKey(target: BindingRef, evidence: u32) -> blot_eval_core_eval::CallProofKey {
    return blot_eval_core_eval::CallProofKey { target: blot_eval_core_eval::Target { (target.unit - 1) as i64, target.binding , ..}, evidence: evidence , ..};
}
fn matches<S>(self_: Key, session: const S&) -> bool {
    if !self_.matchesBase(session) { return false; }
    for read in self_.call_reads {
        if read.target.unit == 0 || read.target.unit > session.units.len || read.target.binding == 0 || read.target.binding >= session.units[read.target.unit - 1].bindings.len { return false; }
        if session.specializations.validated_calls.contains(proofKey(read.target, read.evidence)) != read.present { return false; }
    }
    for read in self_.summary_reads { if !session.principalSummaryMatches(read) { return false; } } return true;
}
fn matchesBase<S>(self_: Key, session: const S&) -> bool {
    if self_.empty_call_inputs && session.specializations.validated_calls.count != 0 { return false; }
    let tags = [blot_eval_type_evidence::Tag.absent, blot_eval_type_evidence::Tag.unit,
        blot_eval_type_evidence::Tag.boolean, blot_eval_type_evidence::Tag.unsigned32,
        blot_eval_type_evidence::Tag.floating32, blot_eval_type_evidence::Tag.never];
    if session.storage.evidence.nodes.len < tags.len { return false; }
    for tag, index in tags { if session.storage.evidence.nodes.items[index] != (blot_eval_type_evidence::Node { tag: tag , ..}) { return false; } }
    for read in self_.scalar_reads {
        if read.evidence > 5 || read.target.unit == 0 || read.target.unit > session.units.len { return false; }
        let module = session.units[read.target.unit - 1];
        if read.target.binding == 0 || read.target.binding >= module.bindings.len { return false; }
        let body = module.body(read.target.binding); if body == null { return false; }
        let slot = session.slots[session.binding_offsets[read.target.unit - 1] + read.target.binding];
        var actual: u32 = 0;
        if !body.runtime && slot.state == blot_eval_core_eval::State.complete && session.valueInfo(slot.value).kind == blot_eval_eval_values::ValueKind.scalar {
            actual = session.valueEvidence(slot.value);
        }
        if actual != read.evidence { return false; }
    }
    for read in self_.plain_reads {
        let actual = session.specializations.plain_nominals.get(read.key);
        if read.value.present { { let optional_source_41 .= actual; if optional_source_41 { let found .= optional_source_41; if found != read.value.value { return false; }  } else { return false; } } }
        else if actual != null { return false; }
    }
    return true;
}
fn publish<S>(self_: Key, session: S&) -> Error {
    session.specializations.plain_nominals.reserve(session.specializations.plain_nominals.count + self_.plain_publications.len);
    session.specializations.validated_calls.reserve(session.specializations.validated_calls.count + self_.call_publications.len);
    let error = session.reservePrincipalSummaries(self_.summary_publications.len); if error != blot_error::Error.none { return error; }
    for fact in self_.plain_publications { session.specializations.plain_nominals.insert(fact.key, fact.value); }
    for call in self_.call_publications {
        let key = proofKey(call.target, call.evidence);
        if !session.specializations.validated_calls.contains(key) { session.proofs.proof_published++; }
        session.specializations.validated_calls.insert(key, true);
    }
    for summary in self_.summary_publications { session.publishPrincipalSummary(summary); } return blot_error::Error.none;
}
enum Reason { unsupported, runtime_source, call_read, call_publication, evaluate, specialize, scalar_domain, changed_input, read_limit }
fn reasonCode(value: Reason) -> u32 {
    match value { unsupported => 0, runtime_source => 1, call_read => 2, call_publication => 3,
        evaluate => 4, specialize => 5, scalar_domain => 6, changed_input => 7, read_limit => 8 }
}
struct PlainSeen { initial: blot_support::Option<bool>, publication: blot_support::Option<i64> }
struct Recorder {
    rejected: u16 = 0, eligible: bool, empty_call_inputs: bool = true, source_complete: bool = true,
    root: BindingRef = BindingRef { 0, 0 , ..}, serial: u64 = 0, max_reads: i64,
    sources: RecorderSourcesBuffer&,
    sources_seen: RecorderSourcesSeenMap&,
    interfaces: RecorderInterfacesBuffer&,
    interfaces_seen: RecorderInterfacesSeenMap&,
    source_units: RecorderSourceUnitsBuffer&,
    source_units_seen: RecorderSourceUnitsSeenMap&,
    reads: RecorderReadsBuffer&,
    seen: RecorderSeenMap&,
    plain_reads: RecorderPlainReadsBuffer&,
    plain_publications: RecorderPlainPublicationsBuffer&,
    plain_seen: RecorderPlainSeenMap&,
    call_publications: RecorderCallPublicationsBuffer&,
    calls_seen: RecorderCallsSeenMap&,
    call_reads: RecorderCallReadsBuffer&,
    call_reads_seen: RecorderCallReadsSeenMap&,
    summary_reads: RecorderSummaryReadsBuffer&,
    summary_publications: RecorderSummaryPublicationsBuffer&,
    summaries_seen: RecorderSummariesSeenMap&,
    summary_reads_seen: RecorderSummaryReadsSeenMap&,
}
struct RecorderTables {
    sources: RecorderSourcesBuffer&,
    sources_seen: RecorderSourcesSeenMap&,
    interfaces: RecorderInterfacesBuffer&,
    interfaces_seen: RecorderInterfacesSeenMap&,
    source_units: RecorderSourceUnitsBuffer&,
    source_units_seen: RecorderSourceUnitsSeenMap&,
    reads: RecorderReadsBuffer&,
    seen: RecorderSeenMap&,
    plain_reads: RecorderPlainReadsBuffer&,
    plain_publications: RecorderPlainPublicationsBuffer&,
    plain_seen: RecorderPlainSeenMap&,
    call_publications: RecorderCallPublicationsBuffer&,
    calls_seen: RecorderCallsSeenMap&,
    call_reads: RecorderCallReadsBuffer&,
    call_reads_seen: RecorderCallReadsSeenMap&,
    summary_reads: RecorderSummaryReadsBuffer&,
    summary_publications: RecorderSummaryPublicationsBuffer&,
    summaries_seen: RecorderSummariesSeenMap&,
    summary_reads_seen: RecorderSummaryReadsSeenMap&,
}
fn init(t: RecorderTables, eligible: bool, max_reads: i64) -> Recorder {
    return Recorder { eligible: eligible, max_reads: max_reads,
        sources: t.sources,
        sources_seen: t.sources_seen,
        interfaces: t.interfaces,
        interfaces_seen: t.interfaces_seen,
        source_units: t.source_units,
        source_units_seen: t.source_units_seen,
        reads: t.reads,
        seen: t.seen,
        plain_reads: t.plain_reads,
        plain_publications: t.plain_publications,
        plain_seen: t.plain_seen,
        call_publications: t.call_publications,
        calls_seen: t.calls_seen,
        call_reads: t.call_reads,
        call_reads_seen: t.call_reads_seen,
        summary_reads: t.summary_reads,
        summary_publications: t.summary_publications,
        summaries_seen: t.summaries_seen,
        summary_reads_seen: t.summary_reads_seen,
     ..};
}
fn deinit(self_: Recorder&) {
    self_.sources.clear();
    self_.sources_seen.clear();
    self_.interfaces.clear();
    self_.interfaces_seen.clear();
    self_.source_units.clear();
    self_.source_units_seen.clear();
    self_.reads.clear();
    self_.seen.clear();
    self_.plain_reads.clear();
    self_.plain_publications.clear();
    self_.plain_seen.clear();
    self_.call_publications.clear();
    self_.calls_seen.clear();
    self_.call_reads.clear();
    self_.call_reads_seen.clear();
    self_.summary_reads.clear();
    self_.summary_publications.clear();
    self_.summaries_seen.clear();
    self_.summary_reads_seen.clear();
}
fn invalidate(self_: Recorder&, reason: Reason) { self_.eligible = false; self_.rejected |= (1 as u16) << reasonCode(reason); }
fn scalar(self_: Recorder&, target: BindingRef, actual: u32) -> Error {
    if !self_.eligible { return blot_error::Error.none; }
    let error = self_.source(target); if error != blot_error::Error.none { return error; }
    if actual > 5 || target.unit == 0 || target.binding == 0 { self_.invalidate(Reason.scalar_domain); return blot_error::Error.none; }
    let id = (target.unit as u64 << 32) | target.binding;
    { let optional_source_40 .= self_.seen.get(id); if optional_source_40 { let previous = optional_source_40; if previous != actual { self_.invalidate(Reason.changed_input); } return blot_error::Error.none;  } }
    if self_.plain_reads.len >= self_.max_reads || self_.reads.len >= self_.max_reads - self_.plain_reads.len { self_.invalidate(Reason.read_limit); return blot_error::Error.none; }
    self_.seen.insert(id, actual); self_.reads.push(ScalarRead { target, actual , ..}); return blot_error::Error.none;
}
fn plainRead(self_: Recorder&, key: u64, actual: blot_support::Option<bool>) -> Error {
    if !self_.eligible { return blot_error::Error.none; }
    { let optional_source_39 .= self_.plain_seen.get(key); if optional_source_39 { let previous .= optional_source_39;
        var expected = previous.initial;
        if previous.publication.present { expected = blot_support::some(self_.plain_publications.items[previous.publication.value].value); }
        if expected != actual { self_.invalidate(Reason.changed_input); } return blot_error::Error.none;
     } }
    if self_.plain_reads.len >= self_.max_reads || self_.reads.len >= self_.max_reads - self_.plain_reads.len { self_.invalidate(Reason.read_limit); return blot_error::Error.none; }
    self_.plain_seen.insert(key, PlainSeen { initial: actual , ..}); self_.plain_reads.push(PlainRead { key, actual , ..}); return blot_error::Error.none;
}
fn plainRead(self_: Recorder&, key: u64, actual: const bool?) -> Error {
    { let optional_source_38 .= actual; if optional_source_38 { let value: bool = optional_source_38; return self_.plainRead(key, blot_support::some(value));  } } return self_.plainRead(key, blot_support::none<bool>());
}
fn plainPublish(self_: Recorder&, key: u64, value: bool) -> Error {
    if !self_.eligible { return blot_error::Error.none; }
    { let optional_source_37 .= self_.plain_seen.get(key); if optional_source_37 { let observed .= optional_source_37;
        if observed.publication.present { self_.plain_publications.items[observed.publication.value].value = value; }
        else {
            let at = self_.plain_publications.len; self_.plain_publications.push(PlainPublication { key, value , ..});
            observed.publication = blot_support::some(at);
        }
     } else { self_.invalidate(Reason.changed_input); } }
    return blot_error::Error.none;
}
fn callPublish(self_: Recorder&, target: BindingRef, actual: u32) -> Error {
    if !self_.eligible { return blot_error::Error.none; } let call = CallPublication { target, actual , ..};
    if self_.calls_seen.contains(call) { return blot_error::Error.none; }
    if self_.call_publications.len >= self_.max_reads { self_.invalidate(Reason.read_limit); return blot_error::Error.none; }
    self_.calls_seen.insert(call, true); self_.call_publications.push(call); return blot_error::Error.none;
}
fn callRead(self_: Recorder&, target: BindingRef, actual: u32, present: bool) -> Error {
    if !self_.eligible { return blot_error::Error.none; } let call = CallPublication { target, actual , ..};
    if self_.calls_seen.contains(call) { if !present { self_.invalidate(Reason.changed_input); } return blot_error::Error.none; }
    if self_.empty_call_inputs { if present { self_.invalidate(Reason.call_read); } return blot_error::Error.none; }
    { let optional_source_36 .= self_.call_reads_seen.get(call); if optional_source_36 { let previous = optional_source_36; if previous != present { self_.invalidate(Reason.changed_input); } return blot_error::Error.none;  } }
    if self_.call_reads.len >= self_.max_reads { self_.invalidate(Reason.read_limit); return blot_error::Error.none; }
    self_.call_reads_seen.insert(call, present); self_.call_reads.push(CallRead { target, actual, present , ..}); return blot_error::Error.none;
}
fn summaryRead(self_: Recorder&, value: Summary) -> Error {
    if !self_.eligible { return blot_error::Error.none; }
    { let optional_source_35 .= self_.summaries_seen.get(value.key); if optional_source_35 { let previous = optional_source_35; if previous != value.result { self_.invalidate(Reason.changed_input); } return blot_error::Error.none;  } }
    { let optional_source_34 .= self_.summary_reads_seen.get(value.key); if optional_source_34 { let previous = optional_source_34; if previous != value.result { self_.invalidate(Reason.changed_input); } return blot_error::Error.none;  } }
    if self_.summary_reads.len >= self_.max_reads { self_.invalidate(Reason.read_limit); return blot_error::Error.none; }
    self_.summary_reads_seen.insert(value.key, value.result); self_.summary_reads.push(value); return blot_error::Error.none;
}
fn summaryPublish(self_: Recorder&, value: Summary) -> Error {
    if !self_.eligible { return blot_error::Error.none; }
    { let optional_source_33 .= self_.summaries_seen.get(value.key); if optional_source_33 { let previous = optional_source_33; if previous != value.result { self_.invalidate(Reason.changed_input); } return blot_error::Error.none;  } }
    if self_.summary_publications.len >= self_.max_reads { self_.invalidate(Reason.read_limit); return blot_error::Error.none; }
    self_.summaries_seen.insert(value.key, value.result); self_.summary_publications.push(value); return blot_error::Error.none;
}
fn sourceRoom(self_: const Recorder&) -> bool { return self_.sources.len + self_.source_units.len + self_.interfaces.len < self_.max_reads; }
fn source(self_: Recorder&, target: BindingRef) -> Error {
    if !self_.eligible || !self_.source_complete || self_.sources_seen.contains(target) { return blot_error::Error.none; }
    if target.unit == 0 || target.binding == 0 || !self_.sourceRoom() { self_.source_complete = false; return blot_error::Error.none; }
    self_.sources_seen.insert(target, true); self_.sources.push(target); return blot_error::Error.none;
}
fn interface(self_: Recorder&, target: BindingRef) -> Error {
    if !self_.eligible || !self_.source_complete || self_.interfaces_seen.contains(target) { return blot_error::Error.none; }
    if target.unit == 0 || target.binding == 0 || !self_.sourceRoom() { self_.source_complete = false; return blot_error::Error.none; }
    self_.interfaces_seen.insert(target, true); self_.interfaces.push(target); return blot_error::Error.none;
}
fn sourceUnit(self_: Recorder&, unit: u32) -> Error {
    if !self_.eligible || !self_.source_complete || self_.source_units_seen.contains(unit) { return blot_error::Error.none; }
    if unit == 0 || !self_.sourceRoom() { self_.source_complete = false; return blot_error::Error.none; }
    self_.source_units_seen.insert(unit, true); self_.source_units.push(unit); return blot_error::Error.none;
}
fn key(self_: const Recorder&) -> blot_support::Option<Key> { if self_.failure()!=blot_error::Error.none { return blot_support::none<Key>(); }
    if !self_.eligible { return blot_support::none<Key>(); }
    return blot_support::some(Key { self_.empty_call_inputs, self_.source_complete, self_.sources.items, self_.interfaces.items, self_.source_units.items,
        self_.reads.items, self_.plain_reads.items, self_.plain_publications.items, self_.call_publications.items, self_.call_reads.items, self_.summary_reads.items, self_.summary_publications.items , ..});
}
fn withRecorder<C,F>(session: const blot_eval_core_eval::Session&,context: C&) -> Error { var owner,error=initRecorderOwner(session); if error!=blot_error::Error.none { return error; } let recorder=owner.borrow(); assert(recorder); let result=F(context,recorder); let allocation_error=recorder.failure(); owner.deinit(); if result!=blot_error::Error.none { return result; } return allocation_error; }
// Shrinking a retained typed run releases its exact allocation extent.
fn shrinkCallPublications(self_: Key&, length: i64) {
    assert(length >= 0 && length <= self_.call_publications.len);
    if length == self_.call_publications.len { return; }
    let replacement = copyOwned(self_.call_publications[..length]);
    releaseOwned(self_.call_publications); self_.call_publications = replacement;
}
fn shrinkSummaryPublications(self_: Key&, length: i64) {
    assert(length >= 0 && length <= self_.summary_publications.len);
    if length == self_.summary_publications.len { return; }
    let replacement = copyOwned(self_.summary_publications[..length]);
    releaseOwned(self_.summary_publications); self_.summary_publications = replacement;
}

struct RecorderSourcesBuffer { storage: BindingRef[:]=default<BindingRef[:]>(),items: BindingRef[:]=default<BindingRef[:]>(),len: i64=0,failure: Error=blot_error::Error.none }
reusable[] var pool_RecorderSourcesBuffer: BindingRef[>..]=[];
fn ensure(self_: RecorderSourcesBuffer&,minimum: i64) -> Error { if self_.failure!=blot_error::Error.none { return self_.failure; } let error=blot_support_pooled_buffer::ensure(self_,minimum,pool_RecorderSourcesBuffer); if error!=blot_error::Error.none { self_.failure=error; } return error; }
fn push(self_: RecorderSourcesBuffer&,value: BindingRef) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::push(self_,value,pool_RecorderSourcesBuffer); self_.len=self_.items.len; }
fn append(self_: RecorderSourcesBuffer&,values: const BindingRef[:]) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::append(self_,values,pool_RecorderSourcesBuffer); self_.len=self_.items.len; }
fn resize(self_: RecorderSourcesBuffer&,length: i64) { blot_support_pooled_buffer::resize(self_,length); self_.len=length; }
fn clear(self_: RecorderSourcesBuffer&) { blot_support_pooled_buffer::clear(self_); self_.len=0; self_.failure=blot_error::Error.none; }
fn deinit(self_: RecorderSourcesBuffer&) { blot_support_pooled_buffer::deinit(self_,pool_RecorderSourcesBuffer); self_.len=0; self_.failure=blot_error::Error.none; }
struct RecorderSourcesSeenMap { count: i64=0,slots: dictionary_slot<BindingRef,bool>[:]=default<dictionary_slot<BindingRef,bool>[:]>() }
reusable[] var pool_RecorderSourcesSeenMap: dictionary_slot<BindingRef,bool>[>..]=[];
fn get(self_: const RecorderSourcesSeenMap&,key: BindingRef) -> bool? { return blot_support_pooled_map::getSlots(self_.slots,key); }
fn contains(self_: const RecorderSourcesSeenMap&,key: BindingRef) -> bool { return self_.get(key)!=null; }
fn insert(self_: RecorderSourcesSeenMap&,key: BindingRef,value: bool) { var view=blot_support_pooled_map::Map<BindingRef,bool> {count:self_.count,slots:self_.slots, ..}; blot_support_pooled_map::insert(view,key,value,pool_RecorderSourcesSeenMap); self_.count=view.count; self_.slots=view.slots; }
fn remove(self_: RecorderSourcesSeenMap&,key: BindingRef) { var view=blot_support_pooled_map::Map<BindingRef,bool> {count:self_.count,slots:self_.slots, ..}; blot_support_pooled_map::remove(view,key); self_.count=view.count; self_.slots=view.slots; }
fn clear(self_: RecorderSourcesSeenMap&) { for &slot in self_.slots { slot.tag=0; } self_.count=0; }
fn release(self_: RecorderSourcesSeenMap&) { if self_.slots.len!=0 { pool_RecorderSourcesSeenMap.free_slice(self_.slots); } self_.slots=default<dictionary_slot<BindingRef,bool>[:]>(); self_.count=0; }
struct RecorderInterfacesBuffer { storage: BindingRef[:]=default<BindingRef[:]>(),items: BindingRef[:]=default<BindingRef[:]>(),len: i64=0,failure: Error=blot_error::Error.none }
reusable[] var pool_RecorderInterfacesBuffer: BindingRef[>..]=[];
fn ensure(self_: RecorderInterfacesBuffer&,minimum: i64) -> Error { if self_.failure!=blot_error::Error.none { return self_.failure; } let error=blot_support_pooled_buffer::ensure(self_,minimum,pool_RecorderInterfacesBuffer); if error!=blot_error::Error.none { self_.failure=error; } return error; }
fn push(self_: RecorderInterfacesBuffer&,value: BindingRef) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::push(self_,value,pool_RecorderInterfacesBuffer); self_.len=self_.items.len; }
fn append(self_: RecorderInterfacesBuffer&,values: const BindingRef[:]) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::append(self_,values,pool_RecorderInterfacesBuffer); self_.len=self_.items.len; }
fn resize(self_: RecorderInterfacesBuffer&,length: i64) { blot_support_pooled_buffer::resize(self_,length); self_.len=length; }
fn clear(self_: RecorderInterfacesBuffer&) { blot_support_pooled_buffer::clear(self_); self_.len=0; self_.failure=blot_error::Error.none; }
fn deinit(self_: RecorderInterfacesBuffer&) { blot_support_pooled_buffer::deinit(self_,pool_RecorderInterfacesBuffer); self_.len=0; self_.failure=blot_error::Error.none; }
struct RecorderInterfacesSeenMap { count: i64=0,slots: dictionary_slot<BindingRef,bool>[:]=default<dictionary_slot<BindingRef,bool>[:]>() }
reusable[] var pool_RecorderInterfacesSeenMap: dictionary_slot<BindingRef,bool>[>..]=[];
fn get(self_: const RecorderInterfacesSeenMap&,key: BindingRef) -> bool? { return blot_support_pooled_map::getSlots(self_.slots,key); }
fn contains(self_: const RecorderInterfacesSeenMap&,key: BindingRef) -> bool { return self_.get(key)!=null; }
fn insert(self_: RecorderInterfacesSeenMap&,key: BindingRef,value: bool) { var view=blot_support_pooled_map::Map<BindingRef,bool> {count:self_.count,slots:self_.slots, ..}; blot_support_pooled_map::insert(view,key,value,pool_RecorderInterfacesSeenMap); self_.count=view.count; self_.slots=view.slots; }
fn remove(self_: RecorderInterfacesSeenMap&,key: BindingRef) { var view=blot_support_pooled_map::Map<BindingRef,bool> {count:self_.count,slots:self_.slots, ..}; blot_support_pooled_map::remove(view,key); self_.count=view.count; self_.slots=view.slots; }
fn clear(self_: RecorderInterfacesSeenMap&) { for &slot in self_.slots { slot.tag=0; } self_.count=0; }
fn release(self_: RecorderInterfacesSeenMap&) { if self_.slots.len!=0 { pool_RecorderInterfacesSeenMap.free_slice(self_.slots); } self_.slots=default<dictionary_slot<BindingRef,bool>[:]>(); self_.count=0; }
struct RecorderSourceUnitsBuffer { storage: u32[:]=default<u32[:]>(),items: u32[:]=default<u32[:]>(),len: i64=0,failure: Error=blot_error::Error.none }
reusable[] var pool_RecorderSourceUnitsBuffer: u32[>..]=[];
fn ensure(self_: RecorderSourceUnitsBuffer&,minimum: i64) -> Error { if self_.failure!=blot_error::Error.none { return self_.failure; } let error=blot_support_pooled_buffer::ensure(self_,minimum,pool_RecorderSourceUnitsBuffer); if error!=blot_error::Error.none { self_.failure=error; } return error; }
fn push(self_: RecorderSourceUnitsBuffer&,value: u32) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::push(self_,value,pool_RecorderSourceUnitsBuffer); self_.len=self_.items.len; }
fn append(self_: RecorderSourceUnitsBuffer&,values: const u32[:]) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::append(self_,values,pool_RecorderSourceUnitsBuffer); self_.len=self_.items.len; }
fn resize(self_: RecorderSourceUnitsBuffer&,length: i64) { blot_support_pooled_buffer::resize(self_,length); self_.len=length; }
fn clear(self_: RecorderSourceUnitsBuffer&) { blot_support_pooled_buffer::clear(self_); self_.len=0; self_.failure=blot_error::Error.none; }
fn deinit(self_: RecorderSourceUnitsBuffer&) { blot_support_pooled_buffer::deinit(self_,pool_RecorderSourceUnitsBuffer); self_.len=0; self_.failure=blot_error::Error.none; }
struct RecorderSourceUnitsSeenMap { count: i64=0,slots: dictionary_slot<u32,bool>[:]=default<dictionary_slot<u32,bool>[:]>() }
reusable[] var pool_RecorderSourceUnitsSeenMap: dictionary_slot<u32,bool>[>..]=[];
fn get(self_: const RecorderSourceUnitsSeenMap&,key: u32) -> bool? { return blot_support_pooled_map::getSlots(self_.slots,key); }
fn contains(self_: const RecorderSourceUnitsSeenMap&,key: u32) -> bool { return self_.get(key)!=null; }
fn insert(self_: RecorderSourceUnitsSeenMap&,key: u32,value: bool) { var view=blot_support_pooled_map::Map<u32,bool> {count:self_.count,slots:self_.slots, ..}; blot_support_pooled_map::insert(view,key,value,pool_RecorderSourceUnitsSeenMap); self_.count=view.count; self_.slots=view.slots; }
fn remove(self_: RecorderSourceUnitsSeenMap&,key: u32) { var view=blot_support_pooled_map::Map<u32,bool> {count:self_.count,slots:self_.slots, ..}; blot_support_pooled_map::remove(view,key); self_.count=view.count; self_.slots=view.slots; }
fn clear(self_: RecorderSourceUnitsSeenMap&) { for &slot in self_.slots { slot.tag=0; } self_.count=0; }
fn release(self_: RecorderSourceUnitsSeenMap&) { if self_.slots.len!=0 { pool_RecorderSourceUnitsSeenMap.free_slice(self_.slots); } self_.slots=default<dictionary_slot<u32,bool>[:]>(); self_.count=0; }
struct RecorderReadsBuffer { storage: ScalarRead[:]=default<ScalarRead[:]>(),items: ScalarRead[:]=default<ScalarRead[:]>(),len: i64=0,failure: Error=blot_error::Error.none }
reusable[] var pool_RecorderReadsBuffer: ScalarRead[>..]=[];
fn ensure(self_: RecorderReadsBuffer&,minimum: i64) -> Error { if self_.failure!=blot_error::Error.none { return self_.failure; } let error=blot_support_pooled_buffer::ensure(self_,minimum,pool_RecorderReadsBuffer); if error!=blot_error::Error.none { self_.failure=error; } return error; }
fn push(self_: RecorderReadsBuffer&,value: ScalarRead) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::push(self_,value,pool_RecorderReadsBuffer); self_.len=self_.items.len; }
fn append(self_: RecorderReadsBuffer&,values: const ScalarRead[:]) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::append(self_,values,pool_RecorderReadsBuffer); self_.len=self_.items.len; }
fn resize(self_: RecorderReadsBuffer&,length: i64) { blot_support_pooled_buffer::resize(self_,length); self_.len=length; }
fn clear(self_: RecorderReadsBuffer&) { blot_support_pooled_buffer::clear(self_); self_.len=0; self_.failure=blot_error::Error.none; }
fn deinit(self_: RecorderReadsBuffer&) { blot_support_pooled_buffer::deinit(self_,pool_RecorderReadsBuffer); self_.len=0; self_.failure=blot_error::Error.none; }
struct RecorderSeenMap { count: i64=0,slots: dictionary_slot<u64,u32>[:]=default<dictionary_slot<u64,u32>[:]>() }
reusable[] var pool_RecorderSeenMap: dictionary_slot<u64,u32>[>..]=[];
fn get(self_: const RecorderSeenMap&,key: u64) -> u32? { return blot_support_pooled_map::getSlots(self_.slots,key); }
fn contains(self_: const RecorderSeenMap&,key: u64) -> bool { return self_.get(key)!=null; }
fn insert(self_: RecorderSeenMap&,key: u64,value: u32) { var view=blot_support_pooled_map::Map<u64,u32> {count:self_.count,slots:self_.slots, ..}; blot_support_pooled_map::insert(view,key,value,pool_RecorderSeenMap); self_.count=view.count; self_.slots=view.slots; }
fn remove(self_: RecorderSeenMap&,key: u64) { var view=blot_support_pooled_map::Map<u64,u32> {count:self_.count,slots:self_.slots, ..}; blot_support_pooled_map::remove(view,key); self_.count=view.count; self_.slots=view.slots; }
fn clear(self_: RecorderSeenMap&) { for &slot in self_.slots { slot.tag=0; } self_.count=0; }
fn release(self_: RecorderSeenMap&) { if self_.slots.len!=0 { pool_RecorderSeenMap.free_slice(self_.slots); } self_.slots=default<dictionary_slot<u64,u32>[:]>(); self_.count=0; }
struct RecorderPlainReadsBuffer { storage: PlainRead[:]=default<PlainRead[:]>(),items: PlainRead[:]=default<PlainRead[:]>(),len: i64=0,failure: Error=blot_error::Error.none }
reusable[] var pool_RecorderPlainReadsBuffer: PlainRead[>..]=[];
fn ensure(self_: RecorderPlainReadsBuffer&,minimum: i64) -> Error { if self_.failure!=blot_error::Error.none { return self_.failure; } let error=blot_support_pooled_buffer::ensure(self_,minimum,pool_RecorderPlainReadsBuffer); if error!=blot_error::Error.none { self_.failure=error; } return error; }
fn push(self_: RecorderPlainReadsBuffer&,value: PlainRead) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::push(self_,value,pool_RecorderPlainReadsBuffer); self_.len=self_.items.len; }
fn append(self_: RecorderPlainReadsBuffer&,values: const PlainRead[:]) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::append(self_,values,pool_RecorderPlainReadsBuffer); self_.len=self_.items.len; }
fn resize(self_: RecorderPlainReadsBuffer&,length: i64) { blot_support_pooled_buffer::resize(self_,length); self_.len=length; }
fn clear(self_: RecorderPlainReadsBuffer&) { blot_support_pooled_buffer::clear(self_); self_.len=0; self_.failure=blot_error::Error.none; }
fn deinit(self_: RecorderPlainReadsBuffer&) { blot_support_pooled_buffer::deinit(self_,pool_RecorderPlainReadsBuffer); self_.len=0; self_.failure=blot_error::Error.none; }
struct RecorderPlainPublicationsBuffer { storage: PlainPublication[:]=default<PlainPublication[:]>(),items: PlainPublication[:]=default<PlainPublication[:]>(),len: i64=0,failure: Error=blot_error::Error.none }
reusable[] var pool_RecorderPlainPublicationsBuffer: PlainPublication[>..]=[];
fn ensure(self_: RecorderPlainPublicationsBuffer&,minimum: i64) -> Error { if self_.failure!=blot_error::Error.none { return self_.failure; } let error=blot_support_pooled_buffer::ensure(self_,minimum,pool_RecorderPlainPublicationsBuffer); if error!=blot_error::Error.none { self_.failure=error; } return error; }
fn push(self_: RecorderPlainPublicationsBuffer&,value: PlainPublication) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::push(self_,value,pool_RecorderPlainPublicationsBuffer); self_.len=self_.items.len; }
fn append(self_: RecorderPlainPublicationsBuffer&,values: const PlainPublication[:]) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::append(self_,values,pool_RecorderPlainPublicationsBuffer); self_.len=self_.items.len; }
fn resize(self_: RecorderPlainPublicationsBuffer&,length: i64) { blot_support_pooled_buffer::resize(self_,length); self_.len=length; }
fn clear(self_: RecorderPlainPublicationsBuffer&) { blot_support_pooled_buffer::clear(self_); self_.len=0; self_.failure=blot_error::Error.none; }
fn deinit(self_: RecorderPlainPublicationsBuffer&) { blot_support_pooled_buffer::deinit(self_,pool_RecorderPlainPublicationsBuffer); self_.len=0; self_.failure=blot_error::Error.none; }
struct RecorderPlainSeenMap { count: i64=0,slots: dictionary_slot<u64,PlainSeen>[:]=default<dictionary_slot<u64,PlainSeen>[:]>() }
reusable[] var pool_RecorderPlainSeenMap: dictionary_slot<u64,PlainSeen>[>..]=[];
fn get(self_: const RecorderPlainSeenMap&,key: u64) -> PlainSeen? { return blot_support_pooled_map::getSlots(self_.slots,key); }
fn contains(self_: const RecorderPlainSeenMap&,key: u64) -> bool { return self_.get(key)!=null; }
fn insert(self_: RecorderPlainSeenMap&,key: u64,value: PlainSeen) { var view=blot_support_pooled_map::Map<u64,PlainSeen> {count:self_.count,slots:self_.slots, ..}; blot_support_pooled_map::insert(view,key,value,pool_RecorderPlainSeenMap); self_.count=view.count; self_.slots=view.slots; }
fn remove(self_: RecorderPlainSeenMap&,key: u64) { var view=blot_support_pooled_map::Map<u64,PlainSeen> {count:self_.count,slots:self_.slots, ..}; blot_support_pooled_map::remove(view,key); self_.count=view.count; self_.slots=view.slots; }
fn clear(self_: RecorderPlainSeenMap&) { for &slot in self_.slots { slot.tag=0; } self_.count=0; }
fn release(self_: RecorderPlainSeenMap&) { if self_.slots.len!=0 { pool_RecorderPlainSeenMap.free_slice(self_.slots); } self_.slots=default<dictionary_slot<u64,PlainSeen>[:]>(); self_.count=0; }
struct RecorderCallPublicationsBuffer { storage: CallPublication[:]=default<CallPublication[:]>(),items: CallPublication[:]=default<CallPublication[:]>(),len: i64=0,failure: Error=blot_error::Error.none }
reusable[] var pool_RecorderCallPublicationsBuffer: CallPublication[>..]=[];
fn ensure(self_: RecorderCallPublicationsBuffer&,minimum: i64) -> Error { if self_.failure!=blot_error::Error.none { return self_.failure; } let error=blot_support_pooled_buffer::ensure(self_,minimum,pool_RecorderCallPublicationsBuffer); if error!=blot_error::Error.none { self_.failure=error; } return error; }
fn push(self_: RecorderCallPublicationsBuffer&,value: CallPublication) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::push(self_,value,pool_RecorderCallPublicationsBuffer); self_.len=self_.items.len; }
fn append(self_: RecorderCallPublicationsBuffer&,values: const CallPublication[:]) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::append(self_,values,pool_RecorderCallPublicationsBuffer); self_.len=self_.items.len; }
fn resize(self_: RecorderCallPublicationsBuffer&,length: i64) { blot_support_pooled_buffer::resize(self_,length); self_.len=length; }
fn clear(self_: RecorderCallPublicationsBuffer&) { blot_support_pooled_buffer::clear(self_); self_.len=0; self_.failure=blot_error::Error.none; }
fn deinit(self_: RecorderCallPublicationsBuffer&) { blot_support_pooled_buffer::deinit(self_,pool_RecorderCallPublicationsBuffer); self_.len=0; self_.failure=blot_error::Error.none; }
struct RecorderCallsSeenMap { count: i64=0,slots: dictionary_slot<CallPublication,bool>[:]=default<dictionary_slot<CallPublication,bool>[:]>() }
reusable[] var pool_RecorderCallsSeenMap: dictionary_slot<CallPublication,bool>[>..]=[];
fn get(self_: const RecorderCallsSeenMap&,key: CallPublication) -> bool? { return blot_support_pooled_map::getSlots(self_.slots,key); }
fn contains(self_: const RecorderCallsSeenMap&,key: CallPublication) -> bool { return self_.get(key)!=null; }
fn insert(self_: RecorderCallsSeenMap&,key: CallPublication,value: bool) { var view=blot_support_pooled_map::Map<CallPublication,bool> {count:self_.count,slots:self_.slots, ..}; blot_support_pooled_map::insert(view,key,value,pool_RecorderCallsSeenMap); self_.count=view.count; self_.slots=view.slots; }
fn remove(self_: RecorderCallsSeenMap&,key: CallPublication) { var view=blot_support_pooled_map::Map<CallPublication,bool> {count:self_.count,slots:self_.slots, ..}; blot_support_pooled_map::remove(view,key); self_.count=view.count; self_.slots=view.slots; }
fn clear(self_: RecorderCallsSeenMap&) { for &slot in self_.slots { slot.tag=0; } self_.count=0; }
fn release(self_: RecorderCallsSeenMap&) { if self_.slots.len!=0 { pool_RecorderCallsSeenMap.free_slice(self_.slots); } self_.slots=default<dictionary_slot<CallPublication,bool>[:]>(); self_.count=0; }
struct RecorderCallReadsBuffer { storage: CallRead[:]=default<CallRead[:]>(),items: CallRead[:]=default<CallRead[:]>(),len: i64=0,failure: Error=blot_error::Error.none }
reusable[] var pool_RecorderCallReadsBuffer: CallRead[>..]=[];
fn ensure(self_: RecorderCallReadsBuffer&,minimum: i64) -> Error { if self_.failure!=blot_error::Error.none { return self_.failure; } let error=blot_support_pooled_buffer::ensure(self_,minimum,pool_RecorderCallReadsBuffer); if error!=blot_error::Error.none { self_.failure=error; } return error; }
fn push(self_: RecorderCallReadsBuffer&,value: CallRead) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::push(self_,value,pool_RecorderCallReadsBuffer); self_.len=self_.items.len; }
fn append(self_: RecorderCallReadsBuffer&,values: const CallRead[:]) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::append(self_,values,pool_RecorderCallReadsBuffer); self_.len=self_.items.len; }
fn resize(self_: RecorderCallReadsBuffer&,length: i64) { blot_support_pooled_buffer::resize(self_,length); self_.len=length; }
fn clear(self_: RecorderCallReadsBuffer&) { blot_support_pooled_buffer::clear(self_); self_.len=0; self_.failure=blot_error::Error.none; }
fn deinit(self_: RecorderCallReadsBuffer&) { blot_support_pooled_buffer::deinit(self_,pool_RecorderCallReadsBuffer); self_.len=0; self_.failure=blot_error::Error.none; }
struct RecorderCallReadsSeenMap { count: i64=0,slots: dictionary_slot<CallPublication,bool>[:]=default<dictionary_slot<CallPublication,bool>[:]>() }
reusable[] var pool_RecorderCallReadsSeenMap: dictionary_slot<CallPublication,bool>[>..]=[];
fn get(self_: const RecorderCallReadsSeenMap&,key: CallPublication) -> bool? { return blot_support_pooled_map::getSlots(self_.slots,key); }
fn contains(self_: const RecorderCallReadsSeenMap&,key: CallPublication) -> bool { return self_.get(key)!=null; }
fn insert(self_: RecorderCallReadsSeenMap&,key: CallPublication,value: bool) { var view=blot_support_pooled_map::Map<CallPublication,bool> {count:self_.count,slots:self_.slots, ..}; blot_support_pooled_map::insert(view,key,value,pool_RecorderCallReadsSeenMap); self_.count=view.count; self_.slots=view.slots; }
fn remove(self_: RecorderCallReadsSeenMap&,key: CallPublication) { var view=blot_support_pooled_map::Map<CallPublication,bool> {count:self_.count,slots:self_.slots, ..}; blot_support_pooled_map::remove(view,key); self_.count=view.count; self_.slots=view.slots; }
fn clear(self_: RecorderCallReadsSeenMap&) { for &slot in self_.slots { slot.tag=0; } self_.count=0; }
fn release(self_: RecorderCallReadsSeenMap&) { if self_.slots.len!=0 { pool_RecorderCallReadsSeenMap.free_slice(self_.slots); } self_.slots=default<dictionary_slot<CallPublication,bool>[:]>(); self_.count=0; }
struct RecorderSummaryReadsBuffer { storage: Summary[:]=default<Summary[:]>(),items: Summary[:]=default<Summary[:]>(),len: i64=0,failure: Error=blot_error::Error.none }
reusable[] var pool_RecorderSummaryReadsBuffer: Summary[>..]=[];
fn ensure(self_: RecorderSummaryReadsBuffer&,minimum: i64) -> Error { if self_.failure!=blot_error::Error.none { return self_.failure; } let error=blot_support_pooled_buffer::ensure(self_,minimum,pool_RecorderSummaryReadsBuffer); if error!=blot_error::Error.none { self_.failure=error; } return error; }
fn push(self_: RecorderSummaryReadsBuffer&,value: Summary) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::push(self_,value,pool_RecorderSummaryReadsBuffer); self_.len=self_.items.len; }
fn append(self_: RecorderSummaryReadsBuffer&,values: const Summary[:]) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::append(self_,values,pool_RecorderSummaryReadsBuffer); self_.len=self_.items.len; }
fn resize(self_: RecorderSummaryReadsBuffer&,length: i64) { blot_support_pooled_buffer::resize(self_,length); self_.len=length; }
fn clear(self_: RecorderSummaryReadsBuffer&) { blot_support_pooled_buffer::clear(self_); self_.len=0; self_.failure=blot_error::Error.none; }
fn deinit(self_: RecorderSummaryReadsBuffer&) { blot_support_pooled_buffer::deinit(self_,pool_RecorderSummaryReadsBuffer); self_.len=0; self_.failure=blot_error::Error.none; }
struct RecorderSummaryPublicationsBuffer { storage: Summary[:]=default<Summary[:]>(),items: Summary[:]=default<Summary[:]>(),len: i64=0,failure: Error=blot_error::Error.none }
reusable[] var pool_RecorderSummaryPublicationsBuffer: Summary[>..]=[];
fn ensure(self_: RecorderSummaryPublicationsBuffer&,minimum: i64) -> Error { if self_.failure!=blot_error::Error.none { return self_.failure; } let error=blot_support_pooled_buffer::ensure(self_,minimum,pool_RecorderSummaryPublicationsBuffer); if error!=blot_error::Error.none { self_.failure=error; } return error; }
fn push(self_: RecorderSummaryPublicationsBuffer&,value: Summary) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::push(self_,value,pool_RecorderSummaryPublicationsBuffer); self_.len=self_.items.len; }
fn append(self_: RecorderSummaryPublicationsBuffer&,values: const Summary[:]) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::append(self_,values,pool_RecorderSummaryPublicationsBuffer); self_.len=self_.items.len; }
fn resize(self_: RecorderSummaryPublicationsBuffer&,length: i64) { blot_support_pooled_buffer::resize(self_,length); self_.len=length; }
fn clear(self_: RecorderSummaryPublicationsBuffer&) { blot_support_pooled_buffer::clear(self_); self_.len=0; self_.failure=blot_error::Error.none; }
fn deinit(self_: RecorderSummaryPublicationsBuffer&) { blot_support_pooled_buffer::deinit(self_,pool_RecorderSummaryPublicationsBuffer); self_.len=0; self_.failure=blot_error::Error.none; }
struct RecorderSummariesSeenMap { count: i64=0,slots: dictionary_slot<SummaryKey,u32>[:]=default<dictionary_slot<SummaryKey,u32>[:]>() }
reusable[] var pool_RecorderSummariesSeenMap: dictionary_slot<SummaryKey,u32>[>..]=[];
fn get(self_: const RecorderSummariesSeenMap&,key: SummaryKey) -> u32? { return blot_support_pooled_map::getSlots(self_.slots,key); }
fn contains(self_: const RecorderSummariesSeenMap&,key: SummaryKey) -> bool { return self_.get(key)!=null; }
fn insert(self_: RecorderSummariesSeenMap&,key: SummaryKey,value: u32) { var view=blot_support_pooled_map::Map<SummaryKey,u32> {count:self_.count,slots:self_.slots, ..}; blot_support_pooled_map::insert(view,key,value,pool_RecorderSummariesSeenMap); self_.count=view.count; self_.slots=view.slots; }
fn remove(self_: RecorderSummariesSeenMap&,key: SummaryKey) { var view=blot_support_pooled_map::Map<SummaryKey,u32> {count:self_.count,slots:self_.slots, ..}; blot_support_pooled_map::remove(view,key); self_.count=view.count; self_.slots=view.slots; }
fn clear(self_: RecorderSummariesSeenMap&) { for &slot in self_.slots { slot.tag=0; } self_.count=0; }
fn release(self_: RecorderSummariesSeenMap&) { if self_.slots.len!=0 { pool_RecorderSummariesSeenMap.free_slice(self_.slots); } self_.slots=default<dictionary_slot<SummaryKey,u32>[:]>(); self_.count=0; }
struct RecorderSummaryReadsSeenMap { count: i64=0,slots: dictionary_slot<SummaryKey,u32>[:]=default<dictionary_slot<SummaryKey,u32>[:]>() }
reusable[] var pool_RecorderSummaryReadsSeenMap: dictionary_slot<SummaryKey,u32>[>..]=[];
fn get(self_: const RecorderSummaryReadsSeenMap&,key: SummaryKey) -> u32? { return blot_support_pooled_map::getSlots(self_.slots,key); }
fn contains(self_: const RecorderSummaryReadsSeenMap&,key: SummaryKey) -> bool { return self_.get(key)!=null; }
fn insert(self_: RecorderSummaryReadsSeenMap&,key: SummaryKey,value: u32) { var view=blot_support_pooled_map::Map<SummaryKey,u32> {count:self_.count,slots:self_.slots, ..}; blot_support_pooled_map::insert(view,key,value,pool_RecorderSummaryReadsSeenMap); self_.count=view.count; self_.slots=view.slots; }
fn remove(self_: RecorderSummaryReadsSeenMap&,key: SummaryKey) { var view=blot_support_pooled_map::Map<SummaryKey,u32> {count:self_.count,slots:self_.slots, ..}; blot_support_pooled_map::remove(view,key); self_.count=view.count; self_.slots=view.slots; }
fn clear(self_: RecorderSummaryReadsSeenMap&) { for &slot in self_.slots { slot.tag=0; } self_.count=0; }
fn release(self_: RecorderSummaryReadsSeenMap&) { if self_.slots.len!=0 { pool_RecorderSummaryReadsSeenMap.free_slice(self_.slots); } self_.slots=default<dictionary_slot<SummaryKey,u32>[:]>(); self_.count=0; }

struct RecorderBacking { sources: RecorderSourcesBuffer=RecorderSourcesBuffer {..},sources_seen: RecorderSourcesSeenMap=RecorderSourcesSeenMap {..},interfaces: RecorderInterfacesBuffer=RecorderInterfacesBuffer {..},interfaces_seen: RecorderInterfacesSeenMap=RecorderInterfacesSeenMap {..},source_units: RecorderSourceUnitsBuffer=RecorderSourceUnitsBuffer {..},source_units_seen: RecorderSourceUnitsSeenMap=RecorderSourceUnitsSeenMap {..},reads: RecorderReadsBuffer=RecorderReadsBuffer {..},seen: RecorderSeenMap=RecorderSeenMap {..},plain_reads: RecorderPlainReadsBuffer=RecorderPlainReadsBuffer {..},plain_publications: RecorderPlainPublicationsBuffer=RecorderPlainPublicationsBuffer {..},plain_seen: RecorderPlainSeenMap=RecorderPlainSeenMap {..},call_publications: RecorderCallPublicationsBuffer=RecorderCallPublicationsBuffer {..},calls_seen: RecorderCallsSeenMap=RecorderCallsSeenMap {..},call_reads: RecorderCallReadsBuffer=RecorderCallReadsBuffer {..},call_reads_seen: RecorderCallReadsSeenMap=RecorderCallReadsSeenMap {..},summary_reads: RecorderSummaryReadsBuffer=RecorderSummaryReadsBuffer {..},summary_publications: RecorderSummaryPublicationsBuffer=RecorderSummaryPublicationsBuffer {..},summaries_seen: RecorderSummariesSeenMap=RecorderSummariesSeenMap {..},summary_reads_seen: RecorderSummaryReadsSeenMap=RecorderSummaryReadsSeenMap {..} }
reusable var recorder_backings: RecorderBacking[>..]=[];
struct RecorderOwnerState { value: Recorder,backing: u32,generation: u64,live: bool=true }
struct RecorderOwner { lease: u32=0,generation: u64=0 }
reusable var recorder_owners: RecorderOwnerState[>..]=[];
var next_recorder_generation: u64=1;
fn initRecorderOwner(session: const blot_eval_core_eval::Session&) -> RecorderOwner,Error { if next_recorder_generation==0xffffffffffffffff||recorder_owners.len>=0xffffffff||recorder_backings.len>=0xffffffff { return RecorderOwner {..},blot_error::Error.out_of_memory; } let generation=next_recorder_generation; next_recorder_generation++; let at=recorder_backings.alloc_index(RecorderBacking {..}); let backing: RecorderBacking& =recorder_backings[at]; let tables=RecorderTables {sources:backing.sources,sources_seen:backing.sources_seen,interfaces:backing.interfaces,interfaces_seen:backing.interfaces_seen,source_units:backing.source_units,source_units_seen:backing.source_units_seen,reads:backing.reads,seen:backing.seen,plain_reads:backing.plain_reads,plain_publications:backing.plain_publications,plain_seen:backing.plain_seen,call_publications:backing.call_publications,calls_seen:backing.calls_seen,call_reads:backing.call_reads,call_reads_seen:backing.call_reads_seen,summary_reads:backing.summary_reads,summary_publications:backing.summary_publications,summaries_seen:backing.summaries_seen,summary_reads_seen:backing.summary_reads_seen, ..}; var value=init(tables,true,session.options.max_values); value.empty_call_inputs=session.specializations.validated_calls.count==0; value.serial=session.principal_recordings; let owner=recorder_owners.alloc_index(RecorderOwnerState {value,at as u32,generation,true, ..}); return RecorderOwner {(owner+1) as u32,generation, ..},blot_error::Error.none; }
fn borrow(self_: RecorderOwner) -> Recorder? { if self_.lease==0||self_.lease-1>=recorder_owners.len { return null; } let owner: RecorderOwnerState& =recorder_owners[self_.lease-1]; if !owner.live||owner.generation!=self_.generation { return null; } return owner.value; }
fn deinit(self_: RecorderOwner&) { if self_.lease==0 { return; } let at=self_.lease-1; assert(at<recorder_owners.len&&recorder_owners[at].live&&recorder_owners[at].generation==self_.generation); let owner: RecorderOwnerState& =recorder_owners[at]; owner.value.deinit(); let backing: RecorderBacking& =recorder_backings[owner.backing]; backing.sources.deinit(); release(backing.sources_seen); backing.interfaces.deinit(); release(backing.interfaces_seen); backing.source_units.deinit(); release(backing.source_units_seen); backing.reads.deinit(); release(backing.seen); backing.plain_reads.deinit(); backing.plain_publications.deinit(); release(backing.plain_seen); backing.call_publications.deinit(); release(backing.calls_seen); backing.call_reads.deinit(); release(backing.call_reads_seen); backing.summary_reads.deinit(); backing.summary_publications.deinit(); release(backing.summaries_seen); release(backing.summary_reads_seen); recorder_backings.free(owner.backing); owner.live=false; recorder_owners.free(at); self_=RecorderOwner {..}; }
fn failure(self_: const Recorder&) -> Error { if self_.sources.failure!=blot_error::Error.none { return self_.sources.failure; } if self_.interfaces.failure!=blot_error::Error.none { return self_.interfaces.failure; } if self_.source_units.failure!=blot_error::Error.none { return self_.source_units.failure; } if self_.reads.failure!=blot_error::Error.none { return self_.reads.failure; } if self_.plain_reads.failure!=blot_error::Error.none { return self_.plain_reads.failure; } if self_.plain_publications.failure!=blot_error::Error.none { return self_.plain_publications.failure; } if self_.call_publications.failure!=blot_error::Error.none { return self_.call_publications.failure; } if self_.call_reads.failure!=blot_error::Error.none { return self_.call_reads.failure; } if self_.summary_reads.failure!=blot_error::Error.none { return self_.summary_reads.failure; } if self_.summary_publications.failure!=blot_error::Error.none { return self_.summary_publications.failure; } return blot_error::Error.none; }

fn hash(key:CallPublication)->u64 {return ::hash_combine(::hash_combine(::hash(key.target.unit),::hash(key.target.binding)),::hash(key.evidence));}
fn hash(key:SummaryKey)->u64 {return ::hash_combine(::hash_combine(::hash_combine(::hash(key.target.unit),::hash(key.target.binding)),::hash(key.inputs)),::hash(key.deferred_member));}
