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
    sources: const BindingRef[:] = [], interfaces: const BindingRef[:] = [],
    source_units: const u32[:] = [], scalar_reads: const ScalarRead[:],
    plain_reads: const PlainRead[:] = [], plain_publications: const PlainPublication[:] = [],
    call_publications: CallPublication[:] = [], call_reads: CallRead[:] = [],
    summary_reads: Summary[:] = [], summary_publications: Summary[:] = [],
}
reusable[] var owned_binding: BindingRef[>..] = [];
fn copyOwned(source: const BindingRef[:]) -> BindingRef[:] {
    if source.len == 0 { return []; } let out = owned_binding.alloc_slice(source.len);
    for value, index in source { out[index] = value; } return out;
}
fn releaseOwned(source: const BindingRef[:]) {
    if source.len == 0 { return; } let first: const BindingRef& = source[0];
    let at = owned_binding.index_of(first); assert(at >= 0); owned_binding.free_slice(owned_binding[at..at + source.len]);
}
reusable[] var owned_units: u32[>..] = [];
fn copyOwned(source: const u32[:]) -> u32[:] {
    if source.len == 0 { return []; } let out = owned_units.alloc_slice(source.len);
    for value, index in source { out[index] = value; } return out;
}
fn releaseOwned(source: const u32[:]) {
    if source.len == 0 { return; } let first: const u32& = source[0];
    let at = owned_units.index_of(first); assert(at >= 0); owned_units.free_slice(owned_units[at..at + source.len]);
}
reusable[] var owned_scalar: ScalarRead[>..] = [];
fn copyOwned(source: const ScalarRead[:]) -> ScalarRead[:] {
    if source.len == 0 { return []; } let out = owned_scalar.alloc_slice(source.len);
    for value, index in source { out[index] = value; } return out;
}
fn releaseOwned(source: const ScalarRead[:]) {
    if source.len == 0 { return; } let first: const ScalarRead& = source[0];
    let at = owned_scalar.index_of(first); assert(at >= 0); owned_scalar.free_slice(owned_scalar[at..at + source.len]);
}
reusable[] var owned_plain_reads: PlainRead[>..] = [];
fn copyOwned(source: const PlainRead[:]) -> PlainRead[:] {
    if source.len == 0 { return []; } let out = owned_plain_reads.alloc_slice(source.len);
    for value, index in source { out[index] = value; } return out;
}
fn releaseOwned(source: const PlainRead[:]) {
    if source.len == 0 { return; } let first: const PlainRead& = source[0];
    let at = owned_plain_reads.index_of(first); assert(at >= 0); owned_plain_reads.free_slice(owned_plain_reads[at..at + source.len]);
}
reusable[] var owned_plain_publications: PlainPublication[>..] = [];
fn copyOwned(source: const PlainPublication[:]) -> PlainPublication[:] {
    if source.len == 0 { return []; } let out = owned_plain_publications.alloc_slice(source.len);
    for value, index in source { out[index] = value; } return out;
}
fn releaseOwned(source: const PlainPublication[:]) {
    if source.len == 0 { return; } let first: const PlainPublication& = source[0];
    let at = owned_plain_publications.index_of(first); assert(at >= 0); owned_plain_publications.free_slice(owned_plain_publications[at..at + source.len]);
}
reusable[] var owned_call_publications: CallPublication[>..] = [];
fn copyOwned(source: const CallPublication[:]) -> CallPublication[:] {
    if source.len == 0 { return []; } let out = owned_call_publications.alloc_slice(source.len);
    for value, index in source { out[index] = value; } return out;
}
fn releaseOwned(source: const CallPublication[:]) {
    if source.len == 0 { return; } let first: const CallPublication& = source[0];
    let at = owned_call_publications.index_of(first); assert(at >= 0); owned_call_publications.free_slice(owned_call_publications[at..at + source.len]);
}
reusable[] var owned_call_reads: CallRead[>..] = [];
fn copyOwned(source: const CallRead[:]) -> CallRead[:] {
    if source.len == 0 { return []; } let out = owned_call_reads.alloc_slice(source.len);
    for value, index in source { out[index] = value; } return out;
}
fn releaseOwned(source: const CallRead[:]) {
    if source.len == 0 { return; } let first: const CallRead& = source[0];
    let at = owned_call_reads.index_of(first); assert(at >= 0); owned_call_reads.free_slice(owned_call_reads[at..at + source.len]);
}
reusable[] var owned_summaries: Summary[>..] = [];
fn copyOwned(source: const Summary[:]) -> Summary[:] {
    if source.len == 0 { return []; } let out = owned_summaries.alloc_slice(source.len);
    for value, index in source { out[index] = value; } return out;
}
fn releaseOwned(source: const Summary[:]) {
    if source.len == 0 { return; } let first: const Summary& = source[0];
    let at = owned_summaries.index_of(first); assert(at >= 0); owned_summaries.free_slice(owned_summaries[at..at + source.len]);
}
fn clone(self: Key) -> Key, Error {
    var result = self;
    result.sources = copyOwned(self.sources);
    result.interfaces = copyOwned(self.interfaces);
    result.source_units = copyOwned(self.source_units);
    result.scalar_reads = copyOwned(self.scalar_reads);
    result.plain_reads = copyOwned(self.plain_reads);
    result.plain_publications = copyOwned(self.plain_publications);
    result.call_publications = copyOwned(self.call_publications);
    result.call_reads = copyOwned(self.call_reads);
    result.summary_reads = copyOwned(self.summary_reads);
    result.summary_publications = copyOwned(self.summary_publications);
    return result, Error.none;
}
fn deinit(self: Key&) {
    releaseOwned(self.sources); self.sources = [];
    releaseOwned(self.interfaces); self.interfaces = [];
    releaseOwned(self.source_units); self.source_units = [];
    releaseOwned(self.scalar_reads); self.scalar_reads = [];
    releaseOwned(self.plain_reads); self.plain_reads = [];
    releaseOwned(self.plain_publications); self.plain_publications = [];
    releaseOwned(self.call_publications); self.call_publications = [];
    releaseOwned(self.call_reads); self.call_reads = [];
    releaseOwned(self.summary_reads); self.summary_reads = [];
    releaseOwned(self.summary_publications); self.summary_publications = [];
}
fn proofKey(target: BindingRef, evidence: u32) -> blot_eval_core_eval::CallProofKey {
    return blot_eval_core_eval::CallProofKey { target: BindingRef { target.unit - 1, target.binding }, evidence: evidence };
}
fn matches<S>(self: Key, session: const S&) -> bool {
    if !self.matchesBase(session) { return false; }
    for read in self.call_reads {
        if read.target.unit == 0 || read.target.unit > session.units.len || read.target.binding == 0 || read.target.binding >= session.units[read.target.unit - 1].bindings.len { return false; }
        if session.specializations.validated_calls.contains(proofKey(read.target, read.evidence)) != read.present { return false; }
    }
    for read in self.summary_reads { if !session.principalSummaryMatches(read) { return false; } } return true;
}
fn matchesBase<S>(self: Key, session: const S&) -> bool {
    if self.empty_call_inputs && session.specializations.validated_calls.count != 0 { return false; }
    let tags = [blot_eval_type_evidence::Tag.absent, blot_eval_type_evidence::Tag.unit,
        blot_eval_type_evidence::Tag.boolean, blot_eval_type_evidence::Tag.unsigned32,
        blot_eval_type_evidence::Tag.floating32, blot_eval_type_evidence::Tag.never];
    if session.storage.evidence.nodes.len < tags.len { return false; }
    for tag, index in tags { if session.storage.evidence.nodes.items[index] != blot_eval_type_evidence::Node { tag: tag } { return false; } }
    for read in self.scalar_reads {
        if read.evidence > 5 || read.target.unit == 0 || read.target.unit > session.units.len { return false; }
        let module = session.units[read.target.unit - 1];
        if read.target.binding == 0 || read.target.binding >= module.bindings.len { return false; }
        let body = module.body(read.target.binding); if body == null { return false; }
        let slot = session.slots[session.binding_offsets[read.target.unit - 1] + read.target.binding];
        var actual: u32 = 0;
        if !body.runtime && slot.state == blot_eval_core_eval::State.complete && session.valueInfo(slot.value).kind == blot_eval_core_eval::ValueKind.scalar {
            actual = session.valueEvidence(slot.value);
        }
        if actual != read.evidence { return false; }
    }
    for read in self.plain_reads {
        let actual = session.specializations.plain_nominals.get(read.key);
        if read.value.present { { let optional_source_41 .= actual; if optional_source_41 { let found .= optional_source_41; if found != read.value.value { return false; }  } else { return false; } } }
        else if actual != null { return false; }
    }
    return true;
}
fn publish<S>(self: Key, session: S&) -> Error {
    session.specializations.plain_nominals.reserve(session.specializations.plain_nominals.count + self.plain_publications.len);
    session.specializations.validated_calls.reserve(session.specializations.validated_calls.count + self.call_publications.len);
    let error = session.reservePrincipalSummaries(self.summary_publications.len); if error != Error.none { return error; }
    for fact in self.plain_publications { session.specializations.plain_nominals.insert(fact.key, fact.value); }
    for call in self.call_publications {
        let key = proofKey(call.target, call.evidence);
        if !session.specializations.validated_calls.contains(key) { session.proofs.proof_published++; }
        session.specializations.validated_calls.insert(key, true);
    }
    for summary in self.summary_publications { session.publishPrincipalSummary(summary); } return Error.none;
}
enum Reason { unsupported, runtime_source, call_read, call_publication, evaluate, specialize, scalar_domain, changed_input, read_limit }
fn reasonCode(value: Reason) -> u32 {
    match value { Reason.unsupported => 0, Reason.runtime_source => 1, Reason.call_read => 2, Reason.call_publication => 3,
        Reason.evaluate => 4, Reason.specialize => 5, Reason.scalar_domain => 6, Reason.changed_input => 7, Reason.read_limit => 8 }
}
struct PlainSeen { initial: blot_support::Option<bool>, publication: blot_support::Option<i64> }
struct Recorder {
    rejected: u16 = 0, eligible: bool, empty_call_inputs: bool = true, source_complete: bool = true,
    root: BindingRef = BindingRef { 0, 0 }, serial: u64 = 0, max_reads: i64,
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
    };
}
fn deinit(self: Recorder&) {
    self.sources.clear();
    self.sources_seen.clear();
    self.interfaces.clear();
    self.interfaces_seen.clear();
    self.source_units.clear();
    self.source_units_seen.clear();
    self.reads.clear();
    self.seen.clear();
    self.plain_reads.clear();
    self.plain_publications.clear();
    self.plain_seen.clear();
    self.call_publications.clear();
    self.calls_seen.clear();
    self.call_reads.clear();
    self.call_reads_seen.clear();
    self.summary_reads.clear();
    self.summary_publications.clear();
    self.summaries_seen.clear();
    self.summary_reads_seen.clear();
}
fn invalidate(self: Recorder&, reason: Reason) { self.eligible = false; self.rejected |= (1 as u16) << reasonCode(reason); }
fn scalar(self: Recorder&, target: BindingRef, actual: u32) -> Error {
    if !self.eligible { return Error.none; }
    let error = self.source(target); if error != Error.none { return error; }
    if actual > 5 || target.unit == 0 || target.binding == 0 { self.invalidate(Reason.scalar_domain); return Error.none; }
    let id = (target.unit as u64 << 32) | target.binding;
    { let optional_source_40 .= self.seen.get(id); if optional_source_40 { let previous = optional_source_40; if previous != actual { self.invalidate(Reason.changed_input); } return Error.none;  } }
    if self.plain_reads.len >= self.max_reads || self.reads.len >= self.max_reads - self.plain_reads.len { self.invalidate(Reason.read_limit); return Error.none; }
    self.seen.insert(id, actual); self.reads.push(ScalarRead { target, actual }); return Error.none;
}
fn plainRead(self: Recorder&, key: u64, actual: blot_support::Option<bool>) -> Error {
    if !self.eligible { return Error.none; }
    { let optional_source_39 .= self.plain_seen.get(key); if optional_source_39 { let previous .= optional_source_39;
        var expected = previous.initial;
        if previous.publication.present { expected = blot_support::some(self.plain_publications.items[previous.publication.value].value); }
        if expected != actual { self.invalidate(Reason.changed_input); } return Error.none;
     } }
    if self.plain_reads.len >= self.max_reads || self.reads.len >= self.max_reads - self.plain_reads.len { self.invalidate(Reason.read_limit); return Error.none; }
    self.plain_seen.insert(key, PlainSeen { initial: actual }); self.plain_reads.push(PlainRead { key, actual }); return Error.none;
}
fn plainRead(self: Recorder&, key: u64, actual: const bool?) -> Error {
    { let optional_source_38 .= actual; if optional_source_38 { let value .= optional_source_38; return self.plainRead(key, blot_support::some(value));  } } return self.plainRead(key, blot_support::none<bool>());
}
fn plainPublish(self: Recorder&, key: u64, value: bool) -> Error {
    if !self.eligible { return Error.none; }
    { let optional_source_37 .= self.plain_seen.get(key); if optional_source_37 { let observed .= optional_source_37;
        if observed.publication.present { self.plain_publications.items[observed.publication.value].value = value; }
        else {
            let at = self.plain_publications.len; self.plain_publications.push(PlainPublication { key, value });
            observed.publication = blot_support::some(at);
        }
     } else { self.invalidate(Reason.changed_input); } }
    return Error.none;
}
fn callPublish(self: Recorder&, target: BindingRef, actual: u32) -> Error {
    if !self.eligible { return Error.none; } let call = CallPublication { target, actual };
    if self.calls_seen.contains(call) { return Error.none; }
    if self.call_publications.len >= self.max_reads { self.invalidate(Reason.read_limit); return Error.none; }
    self.calls_seen.insert(call, true); self.call_publications.push(call); return Error.none;
}
fn callRead(self: Recorder&, target: BindingRef, actual: u32, present: bool) -> Error {
    if !self.eligible { return Error.none; } let call = CallPublication { target, actual };
    if self.calls_seen.contains(call) { if !present { self.invalidate(Reason.changed_input); } return Error.none; }
    if self.empty_call_inputs { if present { self.invalidate(Reason.call_read); } return Error.none; }
    { let optional_source_36 .= self.call_reads_seen.get(call); if optional_source_36 { let previous = optional_source_36; if previous != present { self.invalidate(Reason.changed_input); } return Error.none;  } }
    if self.call_reads.len >= self.max_reads { self.invalidate(Reason.read_limit); return Error.none; }
    self.call_reads_seen.insert(call, present); self.call_reads.push(CallRead { target, actual, present }); return Error.none;
}
fn summaryRead(self: Recorder&, value: Summary) -> Error {
    if !self.eligible { return Error.none; }
    { let optional_source_35 .= self.summaries_seen.get(value.key); if optional_source_35 { let previous = optional_source_35; if previous != value.result { self.invalidate(Reason.changed_input); } return Error.none;  } }
    { let optional_source_34 .= self.summary_reads_seen.get(value.key); if optional_source_34 { let previous = optional_source_34; if previous != value.result { self.invalidate(Reason.changed_input); } return Error.none;  } }
    if self.summary_reads.len >= self.max_reads { self.invalidate(Reason.read_limit); return Error.none; }
    self.summary_reads_seen.insert(value.key, value.result); self.summary_reads.push(value); return Error.none;
}
fn summaryPublish(self: Recorder&, value: Summary) -> Error {
    if !self.eligible { return Error.none; }
    { let optional_source_33 .= self.summaries_seen.get(value.key); if optional_source_33 { let previous = optional_source_33; if previous != value.result { self.invalidate(Reason.changed_input); } return Error.none;  } }
    if self.summary_publications.len >= self.max_reads { self.invalidate(Reason.read_limit); return Error.none; }
    self.summaries_seen.insert(value.key, value.result); self.summary_publications.push(value); return Error.none;
}
fn sourceRoom(self: const Recorder&) -> bool { return self.sources.len + self.source_units.len + self.interfaces.len < self.max_reads; }
fn source(self: Recorder&, target: BindingRef) -> Error {
    if !self.eligible || !self.source_complete || self.sources_seen.contains(target) { return Error.none; }
    if target.unit == 0 || target.binding == 0 || !self.sourceRoom() { self.source_complete = false; return Error.none; }
    self.sources_seen.insert(target, true); self.sources.push(target); return Error.none;
}
fn interface(self: Recorder&, target: BindingRef) -> Error {
    if !self.eligible || !self.source_complete || self.interfaces_seen.contains(target) { return Error.none; }
    if target.unit == 0 || target.binding == 0 || !self.sourceRoom() { self.source_complete = false; return Error.none; }
    self.interfaces_seen.insert(target, true); self.interfaces.push(target); return Error.none;
}
fn sourceUnit(self: Recorder&, unit: u32) -> Error {
    if !self.eligible || !self.source_complete || self.source_units_seen.contains(unit) { return Error.none; }
    if unit == 0 || !self.sourceRoom() { self.source_complete = false; return Error.none; }
    self.source_units_seen.insert(unit, true); self.source_units.push(unit); return Error.none;
}
fn key(self: const Recorder&) -> blot_support::Option<Key> { if self.failure()!=Error.none { return blot_support::none<Key>(); }
    if !self.eligible { return blot_support::none<Key>(); }
    return blot_support::some(Key { self.empty_call_inputs, self.source_complete, self.sources.items, self.interfaces.items, self.source_units.items,
        self.reads.items, self.plain_reads.items, self.plain_publications.items, self.call_publications.items, self.call_reads.items, self.summary_reads.items, self.summary_publications.items });
}
fn withRecorder<C,F>(session: const blot_eval_core_eval::Session&,context: C&) -> Error { var owner,error=initRecorderOwner(session); if error!=Error.none { return error; } let recorder=owner.borrow(); assert(recorder); let result=F(context,recorder); let allocation_error=recorder.failure(); owner.deinit(); if result!=Error.none { return result; } return allocation_error; }
// Shrinking a retained typed run releases its exact allocation extent.
fn shrinkCallPublications(self: Key&, length: i64) {
    assert(length >= 0 && length <= self.call_publications.len);
    if length == self.call_publications.len { return; }
    let replacement = copyOwned(self.call_publications[..length]);
    releaseOwned(self.call_publications); self.call_publications = replacement;
}
fn shrinkSummaryPublications(self: Key&, length: i64) {
    assert(length >= 0 && length <= self.summary_publications.len);
    if length == self.summary_publications.len { return; }
    let replacement = copyOwned(self.summary_publications[..length]);
    releaseOwned(self.summary_publications); self.summary_publications = replacement;
}

struct RecorderSourcesBuffer { storage: BindingRef[:]=[],items: BindingRef[:]=[],len: i64=0,failure: Error=Error.none }
reusable[] var pool_RecorderSourcesBuffer: BindingRef[>..]=[];
fn ensure(self: RecorderSourcesBuffer&,minimum: i64) -> Error { if self.failure!=Error.none { return self.failure; } let error=blot_support_pooled_buffer::ensure(self,minimum,pool_RecorderSourcesBuffer); if error!=Error.none { self.failure=error; } return error; }
fn push(self: RecorderSourcesBuffer&,value: BindingRef) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::push(self,value,pool_RecorderSourcesBuffer); self.len=self.items.len; }
fn append(self: RecorderSourcesBuffer&,values: const BindingRef[:]) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::append(self,values,pool_RecorderSourcesBuffer); self.len=self.items.len; }
fn resize(self: RecorderSourcesBuffer&,length: i64) { blot_support_pooled_buffer::resize(self,length); self.len=length; }
fn clear(self: RecorderSourcesBuffer&) { blot_support_pooled_buffer::clear(self); self.len=0; self.failure=Error.none; }
fn deinit(self: RecorderSourcesBuffer&) { blot_support_pooled_buffer::deinit(self,pool_RecorderSourcesBuffer); self.len=0; self.failure=Error.none; }
struct RecorderSourcesSeenMap { count: i64=0,slots: dictionary_slot<BindingRef,bool>[:]=[] }
reusable[] var pool_RecorderSourcesSeenMap: dictionary_slot<BindingRef,bool>[>..]=[];
fn get(self: const RecorderSourcesSeenMap&,key: BindingRef) -> bool? { let view=blot_support_pooled_map::Map<BindingRef,bool> {count:self.count,slots:self.slots}; return blot_support_pooled_map::get(view,key); }
fn contains(self: const RecorderSourcesSeenMap&,key: BindingRef) -> bool { return self.get(key)!=null; }
fn insert(self: RecorderSourcesSeenMap&,key: BindingRef,value: bool) { var view=blot_support_pooled_map::Map<BindingRef,bool> {count:self.count,slots:self.slots}; blot_support_pooled_map::insert(view,key,value,pool_RecorderSourcesSeenMap); self.count=view.count; self.slots=view.slots; }
fn remove(self: RecorderSourcesSeenMap&,key: BindingRef) { var view=blot_support_pooled_map::Map<BindingRef,bool> {count:self.count,slots:self.slots}; blot_support_pooled_map::remove(view,key); self.count=view.count; self.slots=view.slots; }
fn clear(self: RecorderSourcesSeenMap&) { for &slot in self.slots { slot.tag=0; } self.count=0; }
fn release(self: RecorderSourcesSeenMap&) { if self.slots.len!=0 { pool_RecorderSourcesSeenMap.free_slice(self.slots); } self.slots=[]; self.count=0; }
struct RecorderInterfacesBuffer { storage: BindingRef[:]=[],items: BindingRef[:]=[],len: i64=0,failure: Error=Error.none }
reusable[] var pool_RecorderInterfacesBuffer: BindingRef[>..]=[];
fn ensure(self: RecorderInterfacesBuffer&,minimum: i64) -> Error { if self.failure!=Error.none { return self.failure; } let error=blot_support_pooled_buffer::ensure(self,minimum,pool_RecorderInterfacesBuffer); if error!=Error.none { self.failure=error; } return error; }
fn push(self: RecorderInterfacesBuffer&,value: BindingRef) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::push(self,value,pool_RecorderInterfacesBuffer); self.len=self.items.len; }
fn append(self: RecorderInterfacesBuffer&,values: const BindingRef[:]) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::append(self,values,pool_RecorderInterfacesBuffer); self.len=self.items.len; }
fn resize(self: RecorderInterfacesBuffer&,length: i64) { blot_support_pooled_buffer::resize(self,length); self.len=length; }
fn clear(self: RecorderInterfacesBuffer&) { blot_support_pooled_buffer::clear(self); self.len=0; self.failure=Error.none; }
fn deinit(self: RecorderInterfacesBuffer&) { blot_support_pooled_buffer::deinit(self,pool_RecorderInterfacesBuffer); self.len=0; self.failure=Error.none; }
struct RecorderInterfacesSeenMap { count: i64=0,slots: dictionary_slot<BindingRef,bool>[:]=[] }
reusable[] var pool_RecorderInterfacesSeenMap: dictionary_slot<BindingRef,bool>[>..]=[];
fn get(self: const RecorderInterfacesSeenMap&,key: BindingRef) -> bool? { let view=blot_support_pooled_map::Map<BindingRef,bool> {count:self.count,slots:self.slots}; return blot_support_pooled_map::get(view,key); }
fn contains(self: const RecorderInterfacesSeenMap&,key: BindingRef) -> bool { return self.get(key)!=null; }
fn insert(self: RecorderInterfacesSeenMap&,key: BindingRef,value: bool) { var view=blot_support_pooled_map::Map<BindingRef,bool> {count:self.count,slots:self.slots}; blot_support_pooled_map::insert(view,key,value,pool_RecorderInterfacesSeenMap); self.count=view.count; self.slots=view.slots; }
fn remove(self: RecorderInterfacesSeenMap&,key: BindingRef) { var view=blot_support_pooled_map::Map<BindingRef,bool> {count:self.count,slots:self.slots}; blot_support_pooled_map::remove(view,key); self.count=view.count; self.slots=view.slots; }
fn clear(self: RecorderInterfacesSeenMap&) { for &slot in self.slots { slot.tag=0; } self.count=0; }
fn release(self: RecorderInterfacesSeenMap&) { if self.slots.len!=0 { pool_RecorderInterfacesSeenMap.free_slice(self.slots); } self.slots=[]; self.count=0; }
struct RecorderSourceUnitsBuffer { storage: u32[:]=[],items: u32[:]=[],len: i64=0,failure: Error=Error.none }
reusable[] var pool_RecorderSourceUnitsBuffer: u32[>..]=[];
fn ensure(self: RecorderSourceUnitsBuffer&,minimum: i64) -> Error { if self.failure!=Error.none { return self.failure; } let error=blot_support_pooled_buffer::ensure(self,minimum,pool_RecorderSourceUnitsBuffer); if error!=Error.none { self.failure=error; } return error; }
fn push(self: RecorderSourceUnitsBuffer&,value: u32) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::push(self,value,pool_RecorderSourceUnitsBuffer); self.len=self.items.len; }
fn append(self: RecorderSourceUnitsBuffer&,values: const u32[:]) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::append(self,values,pool_RecorderSourceUnitsBuffer); self.len=self.items.len; }
fn resize(self: RecorderSourceUnitsBuffer&,length: i64) { blot_support_pooled_buffer::resize(self,length); self.len=length; }
fn clear(self: RecorderSourceUnitsBuffer&) { blot_support_pooled_buffer::clear(self); self.len=0; self.failure=Error.none; }
fn deinit(self: RecorderSourceUnitsBuffer&) { blot_support_pooled_buffer::deinit(self,pool_RecorderSourceUnitsBuffer); self.len=0; self.failure=Error.none; }
struct RecorderSourceUnitsSeenMap { count: i64=0,slots: dictionary_slot<u32,bool>[:]=[] }
reusable[] var pool_RecorderSourceUnitsSeenMap: dictionary_slot<u32,bool>[>..]=[];
fn get(self: const RecorderSourceUnitsSeenMap&,key: u32) -> bool? { let view=blot_support_pooled_map::Map<u32,bool> {count:self.count,slots:self.slots}; return blot_support_pooled_map::get(view,key); }
fn contains(self: const RecorderSourceUnitsSeenMap&,key: u32) -> bool { return self.get(key)!=null; }
fn insert(self: RecorderSourceUnitsSeenMap&,key: u32,value: bool) { var view=blot_support_pooled_map::Map<u32,bool> {count:self.count,slots:self.slots}; blot_support_pooled_map::insert(view,key,value,pool_RecorderSourceUnitsSeenMap); self.count=view.count; self.slots=view.slots; }
fn remove(self: RecorderSourceUnitsSeenMap&,key: u32) { var view=blot_support_pooled_map::Map<u32,bool> {count:self.count,slots:self.slots}; blot_support_pooled_map::remove(view,key); self.count=view.count; self.slots=view.slots; }
fn clear(self: RecorderSourceUnitsSeenMap&) { for &slot in self.slots { slot.tag=0; } self.count=0; }
fn release(self: RecorderSourceUnitsSeenMap&) { if self.slots.len!=0 { pool_RecorderSourceUnitsSeenMap.free_slice(self.slots); } self.slots=[]; self.count=0; }
struct RecorderReadsBuffer { storage: ScalarRead[:]=[],items: ScalarRead[:]=[],len: i64=0,failure: Error=Error.none }
reusable[] var pool_RecorderReadsBuffer: ScalarRead[>..]=[];
fn ensure(self: RecorderReadsBuffer&,minimum: i64) -> Error { if self.failure!=Error.none { return self.failure; } let error=blot_support_pooled_buffer::ensure(self,minimum,pool_RecorderReadsBuffer); if error!=Error.none { self.failure=error; } return error; }
fn push(self: RecorderReadsBuffer&,value: ScalarRead) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::push(self,value,pool_RecorderReadsBuffer); self.len=self.items.len; }
fn append(self: RecorderReadsBuffer&,values: const ScalarRead[:]) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::append(self,values,pool_RecorderReadsBuffer); self.len=self.items.len; }
fn resize(self: RecorderReadsBuffer&,length: i64) { blot_support_pooled_buffer::resize(self,length); self.len=length; }
fn clear(self: RecorderReadsBuffer&) { blot_support_pooled_buffer::clear(self); self.len=0; self.failure=Error.none; }
fn deinit(self: RecorderReadsBuffer&) { blot_support_pooled_buffer::deinit(self,pool_RecorderReadsBuffer); self.len=0; self.failure=Error.none; }
struct RecorderSeenMap { count: i64=0,slots: dictionary_slot<u64,u32>[:]=[] }
reusable[] var pool_RecorderSeenMap: dictionary_slot<u64,u32>[>..]=[];
fn get(self: const RecorderSeenMap&,key: u64) -> u32? { let view=blot_support_pooled_map::Map<u64,u32> {count:self.count,slots:self.slots}; return blot_support_pooled_map::get(view,key); }
fn contains(self: const RecorderSeenMap&,key: u64) -> bool { return self.get(key)!=null; }
fn insert(self: RecorderSeenMap&,key: u64,value: u32) { var view=blot_support_pooled_map::Map<u64,u32> {count:self.count,slots:self.slots}; blot_support_pooled_map::insert(view,key,value,pool_RecorderSeenMap); self.count=view.count; self.slots=view.slots; }
fn remove(self: RecorderSeenMap&,key: u64) { var view=blot_support_pooled_map::Map<u64,u32> {count:self.count,slots:self.slots}; blot_support_pooled_map::remove(view,key); self.count=view.count; self.slots=view.slots; }
fn clear(self: RecorderSeenMap&) { for &slot in self.slots { slot.tag=0; } self.count=0; }
fn release(self: RecorderSeenMap&) { if self.slots.len!=0 { pool_RecorderSeenMap.free_slice(self.slots); } self.slots=[]; self.count=0; }
struct RecorderPlainReadsBuffer { storage: PlainRead[:]=[],items: PlainRead[:]=[],len: i64=0,failure: Error=Error.none }
reusable[] var pool_RecorderPlainReadsBuffer: PlainRead[>..]=[];
fn ensure(self: RecorderPlainReadsBuffer&,minimum: i64) -> Error { if self.failure!=Error.none { return self.failure; } let error=blot_support_pooled_buffer::ensure(self,minimum,pool_RecorderPlainReadsBuffer); if error!=Error.none { self.failure=error; } return error; }
fn push(self: RecorderPlainReadsBuffer&,value: PlainRead) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::push(self,value,pool_RecorderPlainReadsBuffer); self.len=self.items.len; }
fn append(self: RecorderPlainReadsBuffer&,values: const PlainRead[:]) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::append(self,values,pool_RecorderPlainReadsBuffer); self.len=self.items.len; }
fn resize(self: RecorderPlainReadsBuffer&,length: i64) { blot_support_pooled_buffer::resize(self,length); self.len=length; }
fn clear(self: RecorderPlainReadsBuffer&) { blot_support_pooled_buffer::clear(self); self.len=0; self.failure=Error.none; }
fn deinit(self: RecorderPlainReadsBuffer&) { blot_support_pooled_buffer::deinit(self,pool_RecorderPlainReadsBuffer); self.len=0; self.failure=Error.none; }
struct RecorderPlainPublicationsBuffer { storage: PlainPublication[:]=[],items: PlainPublication[:]=[],len: i64=0,failure: Error=Error.none }
reusable[] var pool_RecorderPlainPublicationsBuffer: PlainPublication[>..]=[];
fn ensure(self: RecorderPlainPublicationsBuffer&,minimum: i64) -> Error { if self.failure!=Error.none { return self.failure; } let error=blot_support_pooled_buffer::ensure(self,minimum,pool_RecorderPlainPublicationsBuffer); if error!=Error.none { self.failure=error; } return error; }
fn push(self: RecorderPlainPublicationsBuffer&,value: PlainPublication) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::push(self,value,pool_RecorderPlainPublicationsBuffer); self.len=self.items.len; }
fn append(self: RecorderPlainPublicationsBuffer&,values: const PlainPublication[:]) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::append(self,values,pool_RecorderPlainPublicationsBuffer); self.len=self.items.len; }
fn resize(self: RecorderPlainPublicationsBuffer&,length: i64) { blot_support_pooled_buffer::resize(self,length); self.len=length; }
fn clear(self: RecorderPlainPublicationsBuffer&) { blot_support_pooled_buffer::clear(self); self.len=0; self.failure=Error.none; }
fn deinit(self: RecorderPlainPublicationsBuffer&) { blot_support_pooled_buffer::deinit(self,pool_RecorderPlainPublicationsBuffer); self.len=0; self.failure=Error.none; }
struct RecorderPlainSeenMap { count: i64=0,slots: dictionary_slot<u64,PlainSeen>[:]=[] }
reusable[] var pool_RecorderPlainSeenMap: dictionary_slot<u64,PlainSeen>[>..]=[];
fn get(self: const RecorderPlainSeenMap&,key: u64) -> PlainSeen? { let view=blot_support_pooled_map::Map<u64,PlainSeen> {count:self.count,slots:self.slots}; return blot_support_pooled_map::get(view,key); }
fn contains(self: const RecorderPlainSeenMap&,key: u64) -> bool { return self.get(key)!=null; }
fn insert(self: RecorderPlainSeenMap&,key: u64,value: PlainSeen) { var view=blot_support_pooled_map::Map<u64,PlainSeen> {count:self.count,slots:self.slots}; blot_support_pooled_map::insert(view,key,value,pool_RecorderPlainSeenMap); self.count=view.count; self.slots=view.slots; }
fn remove(self: RecorderPlainSeenMap&,key: u64) { var view=blot_support_pooled_map::Map<u64,PlainSeen> {count:self.count,slots:self.slots}; blot_support_pooled_map::remove(view,key); self.count=view.count; self.slots=view.slots; }
fn clear(self: RecorderPlainSeenMap&) { for &slot in self.slots { slot.tag=0; } self.count=0; }
fn release(self: RecorderPlainSeenMap&) { if self.slots.len!=0 { pool_RecorderPlainSeenMap.free_slice(self.slots); } self.slots=[]; self.count=0; }
struct RecorderCallPublicationsBuffer { storage: CallPublication[:]=[],items: CallPublication[:]=[],len: i64=0,failure: Error=Error.none }
reusable[] var pool_RecorderCallPublicationsBuffer: CallPublication[>..]=[];
fn ensure(self: RecorderCallPublicationsBuffer&,minimum: i64) -> Error { if self.failure!=Error.none { return self.failure; } let error=blot_support_pooled_buffer::ensure(self,minimum,pool_RecorderCallPublicationsBuffer); if error!=Error.none { self.failure=error; } return error; }
fn push(self: RecorderCallPublicationsBuffer&,value: CallPublication) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::push(self,value,pool_RecorderCallPublicationsBuffer); self.len=self.items.len; }
fn append(self: RecorderCallPublicationsBuffer&,values: const CallPublication[:]) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::append(self,values,pool_RecorderCallPublicationsBuffer); self.len=self.items.len; }
fn resize(self: RecorderCallPublicationsBuffer&,length: i64) { blot_support_pooled_buffer::resize(self,length); self.len=length; }
fn clear(self: RecorderCallPublicationsBuffer&) { blot_support_pooled_buffer::clear(self); self.len=0; self.failure=Error.none; }
fn deinit(self: RecorderCallPublicationsBuffer&) { blot_support_pooled_buffer::deinit(self,pool_RecorderCallPublicationsBuffer); self.len=0; self.failure=Error.none; }
struct RecorderCallsSeenMap { count: i64=0,slots: dictionary_slot<CallPublication,bool>[:]=[] }
reusable[] var pool_RecorderCallsSeenMap: dictionary_slot<CallPublication,bool>[>..]=[];
fn get(self: const RecorderCallsSeenMap&,key: CallPublication) -> bool? { let view=blot_support_pooled_map::Map<CallPublication,bool> {count:self.count,slots:self.slots}; return blot_support_pooled_map::get(view,key); }
fn contains(self: const RecorderCallsSeenMap&,key: CallPublication) -> bool { return self.get(key)!=null; }
fn insert(self: RecorderCallsSeenMap&,key: CallPublication,value: bool) { var view=blot_support_pooled_map::Map<CallPublication,bool> {count:self.count,slots:self.slots}; blot_support_pooled_map::insert(view,key,value,pool_RecorderCallsSeenMap); self.count=view.count; self.slots=view.slots; }
fn remove(self: RecorderCallsSeenMap&,key: CallPublication) { var view=blot_support_pooled_map::Map<CallPublication,bool> {count:self.count,slots:self.slots}; blot_support_pooled_map::remove(view,key); self.count=view.count; self.slots=view.slots; }
fn clear(self: RecorderCallsSeenMap&) { for &slot in self.slots { slot.tag=0; } self.count=0; }
fn release(self: RecorderCallsSeenMap&) { if self.slots.len!=0 { pool_RecorderCallsSeenMap.free_slice(self.slots); } self.slots=[]; self.count=0; }
struct RecorderCallReadsBuffer { storage: CallRead[:]=[],items: CallRead[:]=[],len: i64=0,failure: Error=Error.none }
reusable[] var pool_RecorderCallReadsBuffer: CallRead[>..]=[];
fn ensure(self: RecorderCallReadsBuffer&,minimum: i64) -> Error { if self.failure!=Error.none { return self.failure; } let error=blot_support_pooled_buffer::ensure(self,minimum,pool_RecorderCallReadsBuffer); if error!=Error.none { self.failure=error; } return error; }
fn push(self: RecorderCallReadsBuffer&,value: CallRead) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::push(self,value,pool_RecorderCallReadsBuffer); self.len=self.items.len; }
fn append(self: RecorderCallReadsBuffer&,values: const CallRead[:]) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::append(self,values,pool_RecorderCallReadsBuffer); self.len=self.items.len; }
fn resize(self: RecorderCallReadsBuffer&,length: i64) { blot_support_pooled_buffer::resize(self,length); self.len=length; }
fn clear(self: RecorderCallReadsBuffer&) { blot_support_pooled_buffer::clear(self); self.len=0; self.failure=Error.none; }
fn deinit(self: RecorderCallReadsBuffer&) { blot_support_pooled_buffer::deinit(self,pool_RecorderCallReadsBuffer); self.len=0; self.failure=Error.none; }
struct RecorderCallReadsSeenMap { count: i64=0,slots: dictionary_slot<CallPublication,bool>[:]=[] }
reusable[] var pool_RecorderCallReadsSeenMap: dictionary_slot<CallPublication,bool>[>..]=[];
fn get(self: const RecorderCallReadsSeenMap&,key: CallPublication) -> bool? { let view=blot_support_pooled_map::Map<CallPublication,bool> {count:self.count,slots:self.slots}; return blot_support_pooled_map::get(view,key); }
fn contains(self: const RecorderCallReadsSeenMap&,key: CallPublication) -> bool { return self.get(key)!=null; }
fn insert(self: RecorderCallReadsSeenMap&,key: CallPublication,value: bool) { var view=blot_support_pooled_map::Map<CallPublication,bool> {count:self.count,slots:self.slots}; blot_support_pooled_map::insert(view,key,value,pool_RecorderCallReadsSeenMap); self.count=view.count; self.slots=view.slots; }
fn remove(self: RecorderCallReadsSeenMap&,key: CallPublication) { var view=blot_support_pooled_map::Map<CallPublication,bool> {count:self.count,slots:self.slots}; blot_support_pooled_map::remove(view,key); self.count=view.count; self.slots=view.slots; }
fn clear(self: RecorderCallReadsSeenMap&) { for &slot in self.slots { slot.tag=0; } self.count=0; }
fn release(self: RecorderCallReadsSeenMap&) { if self.slots.len!=0 { pool_RecorderCallReadsSeenMap.free_slice(self.slots); } self.slots=[]; self.count=0; }
struct RecorderSummaryReadsBuffer { storage: Summary[:]=[],items: Summary[:]=[],len: i64=0,failure: Error=Error.none }
reusable[] var pool_RecorderSummaryReadsBuffer: Summary[>..]=[];
fn ensure(self: RecorderSummaryReadsBuffer&,minimum: i64) -> Error { if self.failure!=Error.none { return self.failure; } let error=blot_support_pooled_buffer::ensure(self,minimum,pool_RecorderSummaryReadsBuffer); if error!=Error.none { self.failure=error; } return error; }
fn push(self: RecorderSummaryReadsBuffer&,value: Summary) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::push(self,value,pool_RecorderSummaryReadsBuffer); self.len=self.items.len; }
fn append(self: RecorderSummaryReadsBuffer&,values: const Summary[:]) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::append(self,values,pool_RecorderSummaryReadsBuffer); self.len=self.items.len; }
fn resize(self: RecorderSummaryReadsBuffer&,length: i64) { blot_support_pooled_buffer::resize(self,length); self.len=length; }
fn clear(self: RecorderSummaryReadsBuffer&) { blot_support_pooled_buffer::clear(self); self.len=0; self.failure=Error.none; }
fn deinit(self: RecorderSummaryReadsBuffer&) { blot_support_pooled_buffer::deinit(self,pool_RecorderSummaryReadsBuffer); self.len=0; self.failure=Error.none; }
struct RecorderSummaryPublicationsBuffer { storage: Summary[:]=[],items: Summary[:]=[],len: i64=0,failure: Error=Error.none }
reusable[] var pool_RecorderSummaryPublicationsBuffer: Summary[>..]=[];
fn ensure(self: RecorderSummaryPublicationsBuffer&,minimum: i64) -> Error { if self.failure!=Error.none { return self.failure; } let error=blot_support_pooled_buffer::ensure(self,minimum,pool_RecorderSummaryPublicationsBuffer); if error!=Error.none { self.failure=error; } return error; }
fn push(self: RecorderSummaryPublicationsBuffer&,value: Summary) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::push(self,value,pool_RecorderSummaryPublicationsBuffer); self.len=self.items.len; }
fn append(self: RecorderSummaryPublicationsBuffer&,values: const Summary[:]) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::append(self,values,pool_RecorderSummaryPublicationsBuffer); self.len=self.items.len; }
fn resize(self: RecorderSummaryPublicationsBuffer&,length: i64) { blot_support_pooled_buffer::resize(self,length); self.len=length; }
fn clear(self: RecorderSummaryPublicationsBuffer&) { blot_support_pooled_buffer::clear(self); self.len=0; self.failure=Error.none; }
fn deinit(self: RecorderSummaryPublicationsBuffer&) { blot_support_pooled_buffer::deinit(self,pool_RecorderSummaryPublicationsBuffer); self.len=0; self.failure=Error.none; }
struct RecorderSummariesSeenMap { count: i64=0,slots: dictionary_slot<SummaryKey,u32>[:]=[] }
reusable[] var pool_RecorderSummariesSeenMap: dictionary_slot<SummaryKey,u32>[>..]=[];
fn get(self: const RecorderSummariesSeenMap&,key: SummaryKey) -> u32? { let view=blot_support_pooled_map::Map<SummaryKey,u32> {count:self.count,slots:self.slots}; return blot_support_pooled_map::get(view,key); }
fn contains(self: const RecorderSummariesSeenMap&,key: SummaryKey) -> bool { return self.get(key)!=null; }
fn insert(self: RecorderSummariesSeenMap&,key: SummaryKey,value: u32) { var view=blot_support_pooled_map::Map<SummaryKey,u32> {count:self.count,slots:self.slots}; blot_support_pooled_map::insert(view,key,value,pool_RecorderSummariesSeenMap); self.count=view.count; self.slots=view.slots; }
fn remove(self: RecorderSummariesSeenMap&,key: SummaryKey) { var view=blot_support_pooled_map::Map<SummaryKey,u32> {count:self.count,slots:self.slots}; blot_support_pooled_map::remove(view,key); self.count=view.count; self.slots=view.slots; }
fn clear(self: RecorderSummariesSeenMap&) { for &slot in self.slots { slot.tag=0; } self.count=0; }
fn release(self: RecorderSummariesSeenMap&) { if self.slots.len!=0 { pool_RecorderSummariesSeenMap.free_slice(self.slots); } self.slots=[]; self.count=0; }
struct RecorderSummaryReadsSeenMap { count: i64=0,slots: dictionary_slot<SummaryKey,u32>[:]=[] }
reusable[] var pool_RecorderSummaryReadsSeenMap: dictionary_slot<SummaryKey,u32>[>..]=[];
fn get(self: const RecorderSummaryReadsSeenMap&,key: SummaryKey) -> u32? { let view=blot_support_pooled_map::Map<SummaryKey,u32> {count:self.count,slots:self.slots}; return blot_support_pooled_map::get(view,key); }
fn contains(self: const RecorderSummaryReadsSeenMap&,key: SummaryKey) -> bool { return self.get(key)!=null; }
fn insert(self: RecorderSummaryReadsSeenMap&,key: SummaryKey,value: u32) { var view=blot_support_pooled_map::Map<SummaryKey,u32> {count:self.count,slots:self.slots}; blot_support_pooled_map::insert(view,key,value,pool_RecorderSummaryReadsSeenMap); self.count=view.count; self.slots=view.slots; }
fn remove(self: RecorderSummaryReadsSeenMap&,key: SummaryKey) { var view=blot_support_pooled_map::Map<SummaryKey,u32> {count:self.count,slots:self.slots}; blot_support_pooled_map::remove(view,key); self.count=view.count; self.slots=view.slots; }
fn clear(self: RecorderSummaryReadsSeenMap&) { for &slot in self.slots { slot.tag=0; } self.count=0; }
fn release(self: RecorderSummaryReadsSeenMap&) { if self.slots.len!=0 { pool_RecorderSummaryReadsSeenMap.free_slice(self.slots); } self.slots=[]; self.count=0; }

struct RecorderBacking { sources: RecorderSourcesBuffer=RecorderSourcesBuffer {},sources_seen: RecorderSourcesSeenMap=RecorderSourcesSeenMap {},interfaces: RecorderInterfacesBuffer=RecorderInterfacesBuffer {},interfaces_seen: RecorderInterfacesSeenMap=RecorderInterfacesSeenMap {},source_units: RecorderSourceUnitsBuffer=RecorderSourceUnitsBuffer {},source_units_seen: RecorderSourceUnitsSeenMap=RecorderSourceUnitsSeenMap {},reads: RecorderReadsBuffer=RecorderReadsBuffer {},seen: RecorderSeenMap=RecorderSeenMap {},plain_reads: RecorderPlainReadsBuffer=RecorderPlainReadsBuffer {},plain_publications: RecorderPlainPublicationsBuffer=RecorderPlainPublicationsBuffer {},plain_seen: RecorderPlainSeenMap=RecorderPlainSeenMap {},call_publications: RecorderCallPublicationsBuffer=RecorderCallPublicationsBuffer {},calls_seen: RecorderCallsSeenMap=RecorderCallsSeenMap {},call_reads: RecorderCallReadsBuffer=RecorderCallReadsBuffer {},call_reads_seen: RecorderCallReadsSeenMap=RecorderCallReadsSeenMap {},summary_reads: RecorderSummaryReadsBuffer=RecorderSummaryReadsBuffer {},summary_publications: RecorderSummaryPublicationsBuffer=RecorderSummaryPublicationsBuffer {},summaries_seen: RecorderSummariesSeenMap=RecorderSummariesSeenMap {},summary_reads_seen: RecorderSummaryReadsSeenMap=RecorderSummaryReadsSeenMap {} }
reusable var recorder_backings: RecorderBacking[>..]=[];
struct RecorderOwnerState { value: Recorder,backing: u32,generation: u64,live: bool=true }
struct RecorderOwner { lease: u32=0,generation: u64=0 }
reusable var recorder_owners: RecorderOwnerState[>..]=[];
var next_recorder_generation: u64=1;
fn initRecorderOwner(session: const blot_eval_core_eval::Session&) -> RecorderOwner,Error { if next_recorder_generation==0xffffffffffffffff||recorder_owners.len>=0xffffffff||recorder_backings.len>=0xffffffff { return RecorderOwner {},Error.out_of_memory; } let generation=next_recorder_generation; next_recorder_generation++; let at=recorder_backings.alloc_index(RecorderBacking {}); let backing: RecorderBacking&=recorder_backings[at]; let tables=RecorderTables {sources:backing.sources,sources_seen:backing.sources_seen,interfaces:backing.interfaces,interfaces_seen:backing.interfaces_seen,source_units:backing.source_units,source_units_seen:backing.source_units_seen,reads:backing.reads,seen:backing.seen,plain_reads:backing.plain_reads,plain_publications:backing.plain_publications,plain_seen:backing.plain_seen,call_publications:backing.call_publications,calls_seen:backing.calls_seen,call_reads:backing.call_reads,call_reads_seen:backing.call_reads_seen,summary_reads:backing.summary_reads,summary_publications:backing.summary_publications,summaries_seen:backing.summaries_seen,summary_reads_seen:backing.summary_reads_seen}; var value=init(tables,true,session.options.max_values); value.empty_call_inputs=session.specializations.validated_calls.count==0; value.serial=session.principal_recordings; let owner=recorder_owners.alloc_index(RecorderOwnerState {value,at as u32,generation,true}); return RecorderOwner {(owner+1) as u32,generation},Error.none; }
fn borrow(self: RecorderOwner) -> Recorder? { if self.lease==0||self.lease-1>=recorder_owners.len { return null; } let owner: RecorderOwnerState&=recorder_owners[self.lease-1]; if !owner.live||owner.generation!=self.generation { return null; } return owner.value; }
fn deinit(self: RecorderOwner&) { if self.lease==0 { return; } let at=self.lease-1; assert(at<recorder_owners.len&&recorder_owners[at].live&&recorder_owners[at].generation==self.generation); let owner: RecorderOwnerState&=recorder_owners[at]; owner.value.deinit(); let backing: RecorderBacking&=recorder_backings[owner.backing]; backing.sources.deinit(); release(backing.sources_seen); backing.interfaces.deinit(); release(backing.interfaces_seen); backing.source_units.deinit(); release(backing.source_units_seen); backing.reads.deinit(); release(backing.seen); backing.plain_reads.deinit(); backing.plain_publications.deinit(); release(backing.plain_seen); backing.call_publications.deinit(); release(backing.calls_seen); backing.call_reads.deinit(); release(backing.call_reads_seen); backing.summary_reads.deinit(); backing.summary_publications.deinit(); release(backing.summaries_seen); release(backing.summary_reads_seen); recorder_backings.free(owner.backing); owner.live=false; recorder_owners.free(at); self=RecorderOwner {}; }
fn failure(self: const Recorder&) -> Error { if self.sources.failure!=Error.none { return self.sources.failure; } if self.interfaces.failure!=Error.none { return self.interfaces.failure; } if self.source_units.failure!=Error.none { return self.source_units.failure; } if self.reads.failure!=Error.none { return self.reads.failure; } if self.plain_reads.failure!=Error.none { return self.plain_reads.failure; } if self.plain_publications.failure!=Error.none { return self.plain_publications.failure; } if self.call_publications.failure!=Error.none { return self.call_publications.failure; } if self.call_reads.failure!=Error.none { return self.call_reads.failure; } if self.summary_reads.failure!=Error.none { return self.summary_reads.failure; } if self.summary_publications.failure!=Error.none { return self.summary_publications.failure; } return Error.none; }
